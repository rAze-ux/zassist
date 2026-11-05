import Foundation

// Sweep — Remove ALL Tweaks planner.
//
// Fork addition (Sweep), not present upstream: builds the undo payload the
// apply engine never could. Semantics ported from desktop
// device_manager.reset_tweaks (AGPL, same project family), scoped to what
// this app's own catalog can deliver:
//
// - Managed/system override plists  -> valid EMPTY plist (<dict/>).
//   NEVER zero bytes (desktop Wave 10 P0: a truncated
//   com.apple.springboard.plist can crash SpringBoard at boot on iOS 26.2+,
//   and iOS 26.x is unsigned — there is no way back from a bootloop).
// - disabledDaemons (launchd disabled.plist) -> stock seed dict
//   (desktop UPSTREAM_DEFAULT_DAEMONS): daemons Apple ships disabled stay
//   disabled, daemons this app disabled come back.
// - ScreenTimeAgent plist -> zero bytes ("nullify + rebuild", same
//   semantics as the existing dm-clear-screentime feature).
// - statusBarOverrides -> zero bytes: SpringBoard ignores an invalid
//   override struct and renders the stock status bar (desktop analysis of
//   the 3,944-byte struct; a zeroed file makes every override "off").
// - WebClips (icon themes) -> Info.plist replaced with an EMPTY plist:
//   the clip loses ApplicationBundleIdentifier/Title, so SpringBoard
//   cannot register it on the next boot and the ghost icon disappears.
//   Covers every entry this app knows (CustomIconStore) plus the legacy
//   Cowabunga_ folder twins of the same names.
// - PosterBoard -> the existing pb-reset spec (empty descriptor files;
//   PosterBoard rebuilds stock).
//
// Everything flows through the normal engine (staged featureID "remove-all"),
// so pairing, version gating, journaling and progress reporting are the
// tested code paths, not new ones.
enum RemovalPlanner {
    struct Result {
        let files: [BuiltFile]
        let warnings: [String]
        /// Human-readable summary of what the payload touches.
        let touchedPaths: [String]
        let webClipFolders: [String]
    }

    static func build() -> Result {
        build(iconEntries: CustomIconStore.load())
    }

    static func build(iconEntries: [CustomIconEntry]) -> Result {
        var warnings: [String] = []
        var files: [BuiltFile] = []
        var touched: [String] = []

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RemovalPreview", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let emptyPlist = plistData([:])

        // Stage one file. Mirrors PayloadBuilder's staging conventions
        // (safeName replace "/" with "_", atomic write).
        func stage(domain: String, restorePath: String, data: Data, keys: [String]) {
            let safeName = restorePath.replacingOccurrences(of: "/", with: "_")
            let url = dir.appendingPathComponent(safeName)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                warnings.append("\(restorePath): staging failed (\(error.localizedDescription))")
                return
            }
            files.append(BuiltFile(domain: domain, restorePath: restorePath, keys: keys, url: url))
            touched.append(restorePath)
        }

        // 1. Every unique concrete write target in the catalog -> empty plist.
        //    (Override plists are whole-file layers: empty = stock. Keys the
        //    app or other tools wrote there are wiped by design — that is
        //    what "remove all tweaks" means. User data lives elsewhere.)
        var seen = Set<String>()
        for spec in PayloadSpecCatalog.all {
            for write in spec.writes {
                if write.fileTarget != nil { continue }          // dedicated blocks below
                if write.restorePath.contains("<") { continue }  // parameterized webclips
                let path = write.restorePath
                guard seen.insert(path).inserted else { continue }
                if path.contains("ScreenTimeAgent") {
                    stage(domain: write.domain.rawValue, restorePath: path,
                          data: Data(), keys: ["<empty file, 0 bytes>"])
                } else if path.hasSuffix("statusBarOverrides") {
                    // Binary struct, not a plist — zero it.
                    stage(domain: write.domain.rawValue, restorePath: path,
                          data: Data(), keys: ["<zeroed override struct>"])
                } else {
                    stage(domain: write.domain.rawValue, restorePath: path,
                          data: emptyPlist, keys: ["<empty plist>"])
                }
            }
        }

        // 2. Launchd disabled.plist -> stock seed (desktop UPSTREAM_DEFAULT_DAEMONS).
        let stockDisabled: [String: Bool] = [
            "com.apple.magicswitchd.companion": true,
            "com.apple.security.otpaird": true,
            "com.apple.dhcp6d": true,
            "com.apple.bootpd": true,
            "com.apple.ftp-proxy-embedded": false,
            "com.apple.relevanced": true,
        ]
        stage(domain: PayloadDomain.databaseDomain.rawValue,
              restorePath: "com.apple.xpc.launchd/disabled.plist",
              data: plistData(stockDisabled),
              keys: ["stock disabled.plist seed"])

        // 3. WebClip folders (icon themes): Info.plist -> empty plist.
        //    Folder name formula identical to the apply path (PayloadBuilder):
        //    WorkSlop_<bundleID>,<safeName>.webclip, legacy prefix Cowabunga_.
        var folders: [String] = []
        var byBundle: [String: CustomIconEntry] = [:]
        var order: [String] = []
        for entry in iconEntries where !entry.bundleID.isEmpty {
            if byBundle[entry.bundleID] == nil { order.append(entry.bundleID) }
            byBundle[entry.bundleID] = entry
        }
        for bundle in order {
            let entry = byBundle[bundle]!
            let safeName = entry.appName
                .replacingOccurrences(of: ",", with: " ")
                .replacingOccurrences(of: "/", with: " ")
            for prefix in ["WorkSlop", "Cowabunga"] {
                let folder = "Library/WebClips/\(prefix)_\(entry.bundleID),\(safeName).webclip"
                stage(domain: PayloadDomain.homeDomain.rawValue,
                      restorePath: folder + "/Info.plist",
                      data: emptyPlist, keys: ["<empty plist>"])
                folders.append(folder)
            }
        }

        // 4. PosterBoard reset: reuse the existing pb-reset spec verbatim
        //    (empty files for the descriptor folders + GalleryCache).
        if let resetSpec = PayloadSpecCatalog.all.first(where: { $0.featureID == "pb-reset" }) {
            for write in resetSpec.writes {
                stage(domain: write.domain.rawValue, restorePath: write.restorePath,
                      data: Data(), keys: ["<empty file, 0 bytes>"])
            }
        } else {
            warnings.append("pb-reset: spec not found in catalog — PosterBoard reset skipped.")
        }

        if files.isEmpty {
            warnings.append("Removal payload is empty — nothing would change.")
        }
        return Result(files: files, warnings: warnings,
                      touchedPaths: touched.sorted(), webClipFolders: folders.sorted())
    }

    private static func plistData(_ object: Any) -> Data {
        (try? PropertyListSerialization.data(
            fromPropertyList: object, format: .xml, options: 0)) ?? Data()
    }
}
