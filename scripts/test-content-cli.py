#!/usr/bin/env python3
"""Exercise real authoring CLI rejection using disposable mutated sample directories."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SAMPLES = ROOT / "Games/DevelopmentContent/Sources/DevelopmentContent/Resources"


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: test-content-cli.py /absolute/path/to/content-validator")
    binary = str(Path(sys.argv[1]).resolve())
    cases = [("duplicate IDs", "catalog.json", "duplicate level ID"),
             ("missing asset", None, "marker.svg"),
             ("missing notice", None, "SplitMix64-NOTICE.txt"),
             ("unknown reference", "Levels/block.json", "next-level reference"),
             ("future version", "Levels/block.json", "unsupported schema version 99"),
             ("malformed block", "Levels/block.json", "unique"),
             ("malformed tile", "Levels/tile.json", "exactly two"),
             ("malformed unscrew", "Levels/unscrew.json", "existing panels"),
             ("malformed dig", "Levels/dig.json", "dig spawn"),
             ("undeclared trace", None, "undeclared bundled resource: input-trace.json"),
             ("symbolic link", None, "symbolic links are not bundled resources: marker.svg")]
    good = subprocess.run([binary, str(SAMPLES)], text=True, capture_output=True, timeout=30)
    if good.returncode:
        raise SystemExit(f"Valid samples rejected: {good.stderr}")
    print(good.stdout.strip())
    with tempfile.TemporaryDirectory(prefix="gamecore-valid-content-") as temporary:
        copied = Path(temporary) / "Resources"
        shutil.copytree(SAMPLES, copied)
        result = subprocess.run([binary, str(copied)], text=True, capture_output=True, timeout=30)
        if result.returncode:
            raise SystemExit(f"Copied valid samples rejected: {result.stderr}")
        print("Copied valid authoring directory passed")
    for name, file, expected in cases:
        with tempfile.TemporaryDirectory(prefix="gamecore-invalid-content-") as temporary:
            directory = Path(temporary) / "Resources"
            shutil.copytree(SAMPLES, directory)
            baseline = subprocess.run([binary, str(directory)], text=True, capture_output=True, timeout=30)
            if baseline.returncode:
                raise SystemExit(f"{name}: unmodified copied baseline rejected: {baseline.stderr}")
            if file:
                path = directory / file
                data = json.loads(path.read_text())
                if name == "duplicate IDs": data["levels"].append(data["levels"][0])
                elif name == "unknown reference": data["payload"]["nextLevelIDs"] = ["absent-level"]
                elif name == "future version": data = {"schemaVersion": 99, "future": True}
                elif name == "malformed block": data["payload"]["occupiedCells"] = [0,0]
                elif name == "malformed tile": data["payload"]["tokens"] = ["a","b","c","d"]
                elif name == "malformed unscrew": data["payload"]["screws"][0]["panelIDs"] = ["missing-panel"]
                elif name == "malformed dig": data["payload"]["spawnCell"] = 99
                path.write_text(json.dumps(data))
            elif name == "missing asset": (directory / "marker.svg").unlink()
            elif name == "missing notice": (directory / "SplitMix64-NOTICE.txt").unlink()
            elif name == "symbolic link":
                (directory / "marker.svg").unlink()
                (directory / "marker.svg").symlink_to(directory / "catalog.json")
            else: (directory / "input-trace.json").write_text("[]")
            result = subprocess.run([binary, str(directory)], text=True, capture_output=True, timeout=30)
            if result.returncode != 1 or expected not in result.stderr:
                raise SystemExit(f"{name}: expected rejection containing {expected!r}; got {result.returncode}: {result.stderr}")
            print(f"Rejected {name}: {result.stderr.strip()}")
    print(f"CLI rejection checks passed: {len(cases)} adversarial fixture cases")


if __name__ == "__main__":
    main()
