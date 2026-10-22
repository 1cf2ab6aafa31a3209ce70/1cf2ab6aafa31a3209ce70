#!/usr/bin/env python3
"""Prove check-reproducible-build.py accepts debug-map-only differences and refuses real ones.

Compiles the same iOS Simulator source twice with debug info, each time in
its own build directory, so the two executables differ only in the
object-file paths of their debug maps, as two clean Xcode builds do (linked
with ZERO_AR_DATE=1 like Xcode). Seeded
violations change the code, a resource, or the file set. Nothing is installed
or run.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).resolve().with_name("check-reproducible-build.py")
SOURCE = 'print("fixture build %s")\n'


def build(root, directory, marker="one", resource="{}"):
    """Compile then link from a per-build object directory, as Xcode does."""
    work = root / directory
    work.mkdir(parents=True)
    (work / "main.swift").write_text(SOURCE % marker)
    target = ["xcrun", "--sdk", "iphonesimulator", "swiftc", "-target", "arm64-apple-ios18.0-simulator"]
    subprocess.run(target + ["-O", "-g", "-c", "main.swift", "-module-name", "Fixture", "-o", str(work / "main.o")],
                   cwd=work, check=True, capture_output=True)
    app = work / "Fixture.app"
    app.mkdir()
    # Xcode links with ZERO_AR_DATE=1, so debug-map entries carry no object modification time.
    subprocess.run(target + [str(work / "main.o"), "-o", str(app / "Fixture")], cwd=work, check=True, capture_output=True,
                   env=dict(os.environ, ZERO_AR_DATE="1"))
    (app / "catalog.json").write_text(resource)
    return app


def check(first, second):
    result = subprocess.run([sys.executable, str(SCRIPT), str(first), str(second)], capture_output=True, text=True)
    report = json.loads(result.stdout[:result.stdout.rindex("}") + 1])
    return result.returncode, report


def main():
    with tempfile.TemporaryDirectory(prefix="gamecore-reproducible-") as temporary:
        root = Path(temporary)
        first = build(root, "derived-a")
        second = build(root, "derived-b")
        code, report = check(first, second)
        entry = report["files"].get("Fixture", {})
        assert code == 0 and not report["bitIdentical"] and entry.get("normalizedIdentical"), (code, report)
        # The simulator linker signs ad hoc, so the signature covers the changed strings too.
        assert "string table" in entry["regions"] and set(entry["regions"]) <= {"string table", "code signature"}, entry["regions"]
        print(f"PASS same source in two build directories: not bit-identical, differs only in {sorted(entry['regions'])}")

        # A longer build path changes the linker's UUID even though nothing else differs after strip -S.
        longer = build(root, "derived-longer-path")
        code, report = check(first, longer)
        entry = report["files"]["Fixture"]
        assert code == 1 and entry["identicalApartFromUUID"] and len(report["problems"]) == 1, (code, report)
        assert "LC_UUID differs" in report["problems"][0] and "equal length" in report["problems"][0], report["problems"]
        print("PASS build directories of different lengths: refused for LC_UUID, identical otherwise after strip -S")

        copy = root / "copy" / "Fixture.app"
        shutil.copytree(first, copy)
        code, report = check(first, copy)
        assert code == 0 and report["bitIdentical"], (code, report)
        print("PASS identical bundles: bit-identical")

        code, report = check(first, build(root, "derived-c", marker="two"))
        assert code == 1 and any("Fixture: " in problem for problem in report["problems"]), report["problems"]
        print(f"PASS changed code: refused ({'; '.join(report['problems'])})")

        code, report = check(first, build(root, "derived-d", resource='{"changed": true}'))
        assert code == 1 and any("catalog.json: differs" in problem for problem in report["problems"]), report["problems"]
        print("PASS changed resource: refused")

        extra = build(root, "derived-e")
        (extra / "stray.txt").write_text("x")
        code, report = check(first, extra)
        assert code == 1 and any("stray.txt: present in only one build" in problem for problem in report["problems"])
        print("PASS extra file: refused")
    print("Reproducible build check accepts debug-map-only differences and refuses code, resource and file-set changes")


if __name__ == "__main__":
    main()
