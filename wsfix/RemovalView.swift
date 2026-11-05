import SwiftUI

// Sweep — original UI for the removal flow. Deliberately NOT the upstream
// look: near-black console aesthetic, one accent, a hold-to-confirm sweep
// control (no accidental taps on a destructive action), and the exact file
// manifest shown before and during the run.

struct RemovalView: View {
    // MARK: - State

    @State private var findMyOff = false
    @State private var riskAccepted = false
    @State private var backupPassword = ""
    @State private var holdProgress: CGFloat = 0
    @State private var holding = false
    @State private var running = false
    @State private var cancelling = false
    @State private var result: String?
    @State private var failed = false
    @State private var progress: RestoreProgress?
    @State private var logLines: [String] = []
    @State private var applyTask: Task<Void, Never>?
    @State private var showManifest = false

    private let planner: RemovalPlanner.Result = RemovalPlanner.build()

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.05).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if running { runStatus } else { preflight }
                    log
                }
                .padding(20)
            }
        }
        .navigationTitle("Sweep")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REMOVE ALL TWEAKS")
                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color(red: 0.35, green: 0.95, blue: 0.7))
            Text("iOS \(DeviceInfoEx.fullVersion) (\(DeviceInfoEx.buildNumber ?? "?")) · \(planner.files.count) files · \(planner.webClipFolders.count / 2) icon themes")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var preflight: some View {
        VStack(alignment: .leading, spacing: 14) {
            consoleCard {
                Toggle("Find My iPhone is OFF", isOn: $findMyOff)
                Toggle("I understand: this rewrites \(planner.files.count) system files back to stock", isOn: $riskAccepted)
            }
            consoleCard {
                SecureField("Backup password (only if backups are encrypted)", text: $backupPassword)
                    .font(.system(size: 12, design: .monospaced))
            }
            if !planner.warnings.isEmpty {
                consoleCard {
                    ForEach(planner.warnings, id: \.self) { w in
                        Text("! \(w)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }
            }
            Button { showManifest = true } label: {
                Label("Show file manifest (\(planner.files.count))", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 12, design: .monospaced))
            }
            .sheet(isPresented: $showManifest) { manifestSheet }

            holdToSweep
        }
    }

    private var runStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let p = progress {
                ProgressView(value: p.fraction)
                    .tint(Color(red: 0.35, green: 0.95, blue: 0.7))
                Text("[\(Int(p.fraction * 100))%] \(p.phase.displayName): \(p.message)")
                    .font(.system(size: 11, design: .monospaced))
            }
            if !cancelling {
                Button("CANCEL", role: .destructive) {
                    cancelling = true
                    applyTask?.cancel()
                    Task { await RestoreEngine.shared.cancel() }
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
            } else {
                Text("cancelling…").font(.system(size: 11, design: .monospaced))
            }
        }
    }

    private var log: some View {
        Group {
            if !logLines.isEmpty {
                consoleCard {
                    ForEach(Array(logLines.suffix(40).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.8))
                    }
                }
            }
            if let result, !running {
                Text(result)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(failed ? Color.red : Color(red: 0.35, green: 0.95, blue: 0.7))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // Hold 1.5 s to fire. Both attestations required before the gesture arms.
    private var holdToSweep: some View {
        let armed = findMyOff && riskAccepted
        return ZStack {
            Circle()
                .stroke(armed ? Color(red: 0.35, green: 0.95, blue: 0.7).opacity(0.25) : .gray.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(Color(red: 0.35, green: 0.95, blue: 0.7), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.05), value: holdProgress)
            Text(armed ? "HOLD TO SWEEP" : "DISABLE FIND MY + CONFIRM")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(armed ? .white : .secondary)
        }
        .frame(width: 170, height: 170)
        .frame(maxWidth: .infinity)
        .contentShape(Circle())
        .gesture(LongPressGesture(minimumDuration: 1.5)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard armed, !running else { return }
                switch value {
                case .first(let strength):
                    holdProgress = CGFloat(strength)
                case .second:
                    holdProgress = 1.0
                }
            }
            .onEnded { _ in
                holdProgress = 0
                if armed, !running { startSweep() }
            }
        )
    }

    private var manifestSheet: some View {
        NavigationStack {
            List(planner.touchedPaths, id: \.self) { path in
                Text(path).font(.system(size: 11, design: .monospaced))
            }
            .navigationTitle("Manifest")
            .toolbar { Button("Done") { showManifest = false } }
        }
        .preferredColorScheme(.dark)
    }

    private func consoleCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Run

    private func startSweep() {
        guard let version = DeviceVersion(DeviceInfoEx.fullVersion) else {
            failed = true
            result = "Could not read this device's iOS version - refusing to guess."
            return
        }
        running = true
        failed = false
        result = nil
        progress = nil
        logLines = ["[sweep] payload: \(planner.files.count) files, \(planner.webClipFolders.count) webclip paths"]
        let request = RestoreRequest(
            deviceVersion: version,
            stagedFeatureIDs: ["remove-all"],
            findMyDisabledAttested: findMyOff,
            deviceLabel: "device",
            backupPassword: backupPassword.isEmpty ? nil : backupPassword,
            deviceBuild: DeviceInfoEx.buildNumber,
            riskWarningAccepted: riskAccepted
        )
        applyTask = Task {
            do {
                try await RestoreEngine.shared.start(request: request, onProgress: { @MainActor p in
                    self.progress = p
                    let pct = Int(p.fraction * 100)
                    logLines.append("[\(pct)%] \(p.phase.displayName): \(p.message)")
                })
                await MainActor.run {
                    running = false
                    result = "SWEEP COMPLETE. Reboot the phone now — ghost icons will not come back."
                    logLines.append("[done] success")
                }
            } catch is CancellationError {
                await MainActor.run { running = false; result = "Cancelled."; logLines.append("[done] cancelled") }
            } catch {
                await MainActor.run {
                    running = false
                    failed = true
                    result = "FAILED: \(error.localizedDescription)"
                    logLines.append("[done] error: \(error.localizedDescription)")
                }
            }
        }
    }
}
