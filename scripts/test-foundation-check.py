#!/usr/bin/env python3
"""Prove check-foundation.py refuses the source-level privacy violations release_policy.py lists.

Copies the repository's tracked and new files to a temporary directory, runs
the check on the unchanged copy, then seeds one violation at a time into the
first title (a blocked framework import, an analytics SDK import, a push
registration call, a URL scheme in its Info.plist and an ad-attribution key
in a package plist) and restores it after. A package plist whose top level is
an array, which declares no Info.plist keys, must pass.
The original checkout is never modified.
"""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import titles as title_manifests  # noqa: E402


def copy_repository(destination):
    """Tracked and new (unignored) files only, so build products never leak in."""
    files = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                           cwd=ROOT, capture_output=True, check=True).stdout.split(b"\0")
    for name in filter(None, files):
        source = ROOT / name.decode()
        if source.is_file() and not source.is_symlink():
            target = destination / name.decode()
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)


def run(copy):
    result = subprocess.run([sys.executable, "scripts/check-foundation.py"], cwd=copy, capture_output=True, text=True)
    return result.returncode, result.stderr.strip()


def main():
    title = title_manifests.load()[0]
    with tempfile.TemporaryDirectory(prefix="gamecore-foundation-check-") as temporary:
        copy = Path(temporary)
        copy_repository(copy)
        code, errors = run(copy)
        assert code == 0, ("unchanged copy", errors)
        print("PASS unchanged repository: exit 0")
        source = sorted((copy / title.source_directory).glob("*.swift"))[0]
        info = copy / title.source_directory / "Info.plist"
        values = plistlib.loads(info.read_bytes())
        cases = [
            ("blocked framework import", source, source.read_text() + "\nimport WebKit\n", "Disallowed privacy-related import"),
            ("analytics SDK import", source, source.read_text() + "\nimport FirebaseAnalytics\n", "FirebaseAnalytics"),
            ("push registration", source, source.read_text() + "\nfunc register() { UIApplication.shared.registerForRemoteNotifications() }\n",
             "registerForRemoteNotifications"),
            # The title Info.plist must match its reviewed content exactly.
            ("URL scheme in title Info.plist", info, plistlib.dumps(dict(values, CFBundleURLTypes=[{"CFBundleURLSchemes": ["fixture"]}])).decode(),
             "Info.plist must retain the reviewed"),
            # Any other committed plist is checked against release_policy.FORBIDDEN_INFO_KEYS.
            ("ad attribution in a package plist", copy / "Packages/GamePlatform/Sources/GamePlatform/Seeded.plist",
             plistlib.dumps({"SKAdNetworkItems": [{}]}).decode(), "SKAdNetworkItems"),
        ]
        for name, path, seeded, fragment in cases:
            original = path.read_bytes() if path.exists() else None
            path.write_text(seeded)
            try:
                code, errors = run(copy)
            finally:
                if original is None:
                    path.unlink()
                else:
                    path.write_bytes(original)
            assert code == 1 and fragment in errors, (name, code, errors)
            print(f"PASS {name}: refused")
        array_plist = copy / "Packages/GamePlatform/Sources/GamePlatform/Levels.plist"
        array_plist.write_bytes(plistlib.dumps(["level-1", "level-2"]))
        try:
            code, errors = run(copy)
        finally:
            array_plist.unlink()
        assert code == 0, ("top-level array plist", errors)
        print("PASS top-level array plist in a package: exit 0")
    print("Foundation check refuses each seeded source-level privacy violation")


if __name__ == "__main__":
    main()
