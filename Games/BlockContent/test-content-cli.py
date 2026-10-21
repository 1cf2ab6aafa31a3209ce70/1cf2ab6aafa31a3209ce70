#!/usr/bin/env python3
"""Exercise the real authoring CLI: the level plan regenerates the bundled
levels byte for byte, and mutated copies of them are rejected."""
import filecmp
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

PACKAGE = Path(__file__).resolve().parent
LEVELS = PACKAGE / "Sources/BlockContent/Resources"
PLAN = PACKAGE / "level-plan.json"


def payload(change):
    def mutate(level):
        change(level["payload"])
        return level
    return mutate


CASES = [
    ("broken clearing sequence", "Levels/intro-01.json", payload(lambda p: p.update(solution=[3, 4])), "leaves blocks"),
    ("illegal clearing move", "Levels/intro-02.json", payload(lambda p: p.update(solution=[0])), "selects no group at 0"),
    ("kind outside the chapter", "Levels/intro-03.json",
     payload(lambda p: p.update(cells=[3 if cell == 1 else cell for cell in p["cells"]])), "kind 1...2"),
    ("board outside the chapter", "Levels/final-01.json", payload(lambda p: p.update(chapter=1)), "chapter 1 boards must be 3...5"),
    ("broken unlock chain", "Levels/intro-05.json", payload(lambda p: p.update(nextLevelIDs=["intro-07"])), "unlock exactly the next level"),
    ("shared seed", "Levels/intro-04.json", lambda level: {**level, "seed": 201}, "two levels share a seed"),
    ("floating block", "Levels/intro-01.json", payload(lambda p: p.update(cells=[1, 0, 0, 0, 2, 1, 1, 2, 1])), "rest on the floor"),
]


def run(binary, *args):
    return subprocess.run([binary, *map(str, args)], text=True, capture_output=True, timeout=120)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: test-content-cli.py /absolute/path/to/BlockContentValidator")
    binary = str(Path(sys.argv[1]).resolve())
    good = run(binary, LEVELS)
    if good.returncode:
        raise SystemExit(f"Bundled levels rejected: {good.stderr}")
    print(good.stdout.splitlines()[0])

    with tempfile.TemporaryDirectory(prefix="gamecore-generated-content-") as temporary:
        directory = Path(temporary) / "Resources"
        directory.mkdir()
        shutil.copy(LEVELS / "SplitMix64-NOTICE.txt", directory)
        generated = run(binary, "generate", PLAN, directory)
        if generated.returncode:
            raise SystemExit(f"Level plan did not generate: {generated.stderr}")
        comparison = filecmp.dircmp(LEVELS, directory)
        differing = comparison.left_only + comparison.right_only + comparison.diff_files
        differing += [f"Levels/{name}" for name in (comparison.subdirs["Levels"].left_only
                      + comparison.subdirs["Levels"].right_only + comparison.subdirs["Levels"].diff_files)]
        if differing:
            raise SystemExit(f"Level plan does not reproduce the bundled levels: {sorted(differing)}")
        print(f"Level plan reproduces all {len(list((LEVELS / 'Levels').glob('*.json')))} bundled levels")

    for name, file, change, expected in CASES:
        with tempfile.TemporaryDirectory(prefix="gamecore-invalid-content-") as temporary:
            directory = Path(temporary) / "Resources"
            shutil.copytree(LEVELS, directory)
            path = directory / file
            path.write_text(json.dumps(change(json.loads(path.read_text()))))
            result = run(binary, directory)
            if result.returncode != 1 or expected not in result.stderr:
                raise SystemExit(f"{name}: expected rejection containing {expected!r}; got {result.returncode}: {result.stderr}")
            print(f"Rejected {name}: {result.stderr.strip()}")
    print(f"CLI checks passed: plan reproduction and {len(CASES)} adversarial fixture cases")


if __name__ == "__main__":
    main()
