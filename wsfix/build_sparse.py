"""Build a sparse (WebClips-only) nullify backup from a full backup.

Reads the full backup's Manifest.db, keeps ONLY rows inside
Library/WebClips/*.webclip/ that are regular files, and rewrites every
file row's content file as a ZERO-BYTE file (the "nullify" trick used by
Nugget-family tools to invalidate delivered files on next restore).

Info.plist of each webclip becomes 0 bytes -> SpringBoard can no longer
register the web clip -> the ghost icon disappears on next reboot.

Usage:
  python -I build_sparse.py <full_backup_dir> <sparse_out_dir>

(full_backup_dir contains the <UDID> subdirectory, e.g. E:/ws_backup)
"""
import hashlib
import os
import plistlib
import shutil
import sqlite3
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src_root, dst_root = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    udid_dirs = [d for d in os.listdir(src_root)
                 if os.path.isdir(os.path.join(src_root, d)) and len(d) >= 25]
    if len(udid_dirs) != 1:
        print("Cannot find exactly one UDID dir in", src_root, ":", udid_dirs)
        return 2
    udid = udid_dirs[0]
    src = os.path.join(src_root, udid)
    dst = os.path.join(dst_root, udid)

    src_db = os.path.join(src, "Manifest.db")
    if not os.path.isfile(src_db):
        print("Manifest.db missing (backup incomplete?) at", src_db)
        return 2

    con = sqlite3.connect(src_db)
    rows = con.execute(
        "SELECT fileID, domain, relativePath, flags, file FROM Files "
        "WHERE relativePath LIKE 'Library/WebClips/%' ORDER BY relativePath"
    ).fetchall()
    con.close()
    if not rows:
        print("No WebClips rows found in Manifest.db - nothing to do.")
        return 1

    print(f"UDID: {udid}")
    webclip_files = [r for r in rows if r[3] == 1]
    webclip_dirs = [r for r in rows if r[3] != 1]
    folders = sorted({r[2].split("/")[2] for r in rows if r[2].count("/") >= 2})
    print(f"WebClip folders ({len(folders)}):")
    for f in folders:
        print("  ", f)
    print(f"file rows: {len(webclip_files)}, dir rows: {len(webclip_dirs)}")

    targets = [r for r in webclip_files if r[2].endswith("/Info.plist")]
    print(f"Will nullify {len(targets)} Info.plist files:")
    for r in targets:
        print("  ", r[2])

    if os.path.isdir(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)

    empty_digest = hashlib.sha256(b"").digest()

    # New Manifest.db with only the Info.plist rows, patched for 0-byte content.
    out_db = os.path.join(dst, "Manifest.db")
    out = sqlite3.connect(out_db)
    out.execute("CREATE TABLE Files (fileID TEXT PRIMARY KEY, domain TEXT, "
                "relativePath TEXT, flags INTEGER, file BLOB)")
    for fileID, domain, rel, flags, blob in targets:
        meta = plistlib.loads(blob) if blob else {}
        meta["Size"] = 0
        meta["Digest"] = empty_digest
        if "Length" in meta:
            meta["Length"] = 0
        out.execute("INSERT INTO Files VALUES (?,?,?,?,?)",
                    (fileID, domain, rel, flags, plistlib.dumps(meta)))
    out.commit()
    out.close()

    # Zero-byte content files at the device-expected hash paths.
    for fileID, domain, rel, flags, blob in targets:
        p = os.path.join(dst, fileID[:2], fileID)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").close()

    # Metadata files for the restore session.
    for name in ("Status.plist", "Info.plist", "Manifest.plist"):
        s = os.path.join(src, name)
        d = os.path.join(dst, name)
        if os.path.isfile(s) and os.path.getsize(s) > 0:
            shutil.copyfile(s, d)
        else:
            print(f"WARNING: {name} missing/empty in source backup")
    if not os.path.isfile(os.path.join(dst, "Manifest.plist")):
        with open(os.path.join(dst, "Manifest.plist"), "wb") as fd:
            plistlib.dump({"IsEncrypted": False}, fd)
        print("Wrote minimal Manifest.plist (source was empty)")

    print("Sparse backup built at", dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
