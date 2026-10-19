#!/usr/bin/env python3
"""Prove that titles are added and removed without touching another title.

Works in disposable copies of the repository's tracked and new files:

1. For each title, delete its directories, regenerate the project, run the
   foundation checks and the core and platform package tests, and build every
   remaining title.
2. Scaffold a third skeletal title with scripts/new-title.py, then run the
   checks and its content tests and build it, tests included.

Every step must succeed; the original checkout is never modified.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import titles as title_manifests  # noqa: E402


def run(command, cwd, log, timeout=1200):
    start = time.monotonic()
    with log.open("w") as stream:
        result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    if result.returncode:
        tail = "\n".join(log.read_text().splitlines()[-40:])
        raise RuntimeError(f"{' '.join(command)} failed ({result.returncode}); see {log}\n{tail}")
    return round(time.monotonic() - start, 1)


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


def build(copy, target, output, label, action="build"):
    return run(["xcodebuild", "-workspace", "GameCore.xcworkspace", "-scheme", target, "-configuration", "Debug",
                "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(output / f"{label}-derived"),
                "CODE_SIGNING_ALLOWED=NO", action], copy, output / f"{label}-{target}.log")


def shared_checks(copy, output, label):
    seconds = run([sys.executable, "scripts/generate-project.py"], copy, output / f"{label}-generate.log")
    seconds += run([sys.executable, "scripts/check-foundation.py"], copy, output / f"{label}-check.log")
    for package in ["GameCore", "GamePlatform"]:
        seconds += run(["swift", "test", "--package-path", f"Packages/{package}",
                        "--scratch-path", str(output / f"{label}-{package}")], copy, output / f"{label}-{package}-tests.log")
    return seconds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New absolute evidence directory")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    titles = title_manifests.load()
    receipt = {"source": subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip(),
               "worktreeDirty": bool(subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True).stdout.strip()),
               "steps": []}
    try:
        for removed in titles:
            with tempfile.TemporaryDirectory(prefix="gamecore-title-removal-") as temporary:
                copy = Path(temporary)
                copy_repository(copy)
                for path in removed.owned_paths:
                    shutil.rmtree(copy / path)
                label = f"without-{removed.target}"
                seconds = shared_checks(copy, output, label)
                remaining = [title.target for title in titles if title is not removed]
                for target in remaining:
                    seconds += build(copy, target, output, label)
                receipt["steps"].append({"step": label, "removedPaths": removed.owned_paths,
                                         "builtTitles": remaining, "seconds": seconds})
                print(f"PASS {label}: checks, core and platform tests, and {', '.join(remaining)} build", flush=True)
        with tempfile.TemporaryDirectory(prefix="gamecore-title-scaffold-") as temporary:
            copy = Path(temporary)
            copy_repository(copy)
            label = "scaffold-ExampleTitle"
            seconds = run([sys.executable, "scripts/new-title.py", "ExampleTitle", "--title-id", "example-title",
                           "--display-name", "Example", "--game-type", "tile"], copy, output / f"{label}-new-title.log")
            seconds += shared_checks(copy, output, label)
            seconds += run(["swift", "test", "--package-path", "Games/ExampleContent", "--scratch-path",
                            str(output / f"{label}-content")], copy, output / f"{label}-content-tests.log")
            seconds += build(copy, "ExampleTitle", output, label, action="build-for-testing")
            receipt["steps"].append({"step": label, "builtTitles": ["ExampleTitle"], "seconds": seconds})
            print(f"PASS {label}: scaffold, checks, content tests and a test build", flush=True)
        receipt["status"] = "passed"
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        receipt["status"] = "failed"
        receipt["error"] = str(error)
        print(error, file=sys.stderr)
    finally:
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return 0 if receipt["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
