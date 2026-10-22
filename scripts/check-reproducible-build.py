#!/usr/bin/env python3
"""Compare two app bundles built from the same source in separate clean derived-data directories.

Reports whether the bundles are bit-identical and, when they are not, which
Mach-O regions differ and the strings that differ there. Fails when:

- the bundles hold different files, or any non-Mach-O file differs;
- an executable's LC_UUID differs;
- the executables still differ once the code signature is removed and the
  debug map is stripped (`strip -S`, which drops only the N_SO/N_OSO stab
  entries that record build-directory paths of object files for dsymutil).

Observed with Xcode 27.1 (27A9275), iOS 27.1 SDK, unsigned generic iOS
Release builds of both titles on 2026-10-20: the executable keeps its debug
map, whose object-file paths name the derived-data directory, so two clean
builds are not bit-identical. With derived-data paths of equal length they
differ only in the LINKEDIT string table; LC_UUID and every section match and
the stripped executables are identical. With paths of different lengths the
linker's LC_UUID also changes, though nothing else differs after strip -S, so
scripts/verify.sh rebuilds into a directory whose path has the same length.
Every resource, Assets.car and Info.plist is identical. Archive builds strip
the debug map (STRIP_INSTALLED_PRODUCT); that path is not exercised here.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import macho  # noqa: E402


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inventory(app):
    return {path.relative_to(app).as_posix(): path for path in sorted(app.rglob("*")) if path.is_file() and not path.is_symlink()}


def normalized(path, scratch):
    """Bytes of the executable without its code signature and debug map."""
    copy = scratch / f"{len(list(scratch.iterdir()))}-{path.name}"
    shutil.copy2(path, copy)
    _, slices = macho.parse(copy)
    if any(item["signature"] for item in slices):
        subprocess.run(["codesign", "--remove-signature", str(copy)], check=True, capture_output=True)
    stripped = copy.with_suffix(".stripped")
    subprocess.run(["xcrun", "strip", "-S", "-o", str(stripped), str(copy)], check=True, capture_output=True)
    return stripped.read_bytes()


def without_uuid(data):
    """The same bytes with every slice's LC_UUID zeroed."""
    copy = bytearray(data)
    for item in macho.parse_bytes(data):
        if item["uuid_offset"] is not None:
            copy[item["uuid_offset"]:item["uuid_offset"] + 16] = bytes(16)
    return bytes(copy)


def differences(first, second):
    """Differing regions of two Mach-O files of equal size, with sample differing strings."""
    data_a, slices_a = macho.parse(first)
    data_b, slices_b = macho.parse(second)
    regions, strings = {}, set()
    if len(data_a) != len(data_b):
        return {"size": [len(data_a), len(data_b)]}, []
    for offset in (i for i in range(len(data_a)) if data_a[i] != data_b[i]):
        region = macho.region_at(slices_a, offset)
        regions[region] = regions.get(region, 0) + 1
        if region == "string table":
            table = next(item["symtab"][2] for item in slices_a if item["symtab"])
            strings.add((macho.string_at(data_a, table, offset), macho.string_at(data_b, table, offset)))
    return regions, sorted(strings)[:5]


def compare(first, second):
    report = {"first": str(first), "second": str(second), "bitIdentical": True, "files": {}, "problems": []}
    problems = report["problems"]
    files_a, files_b = inventory(first), inventory(second)
    for name in sorted(set(files_a) ^ set(files_b)):
        problems.append(f"{name}: present in only one build")
    with tempfile.TemporaryDirectory(prefix="gamecore-reproducible-") as temporary:
        scratch = Path(temporary)
        for name in sorted(set(files_a) & set(files_b)):
            a, b = files_a[name].read_bytes(), files_b[name].read_bytes()
            if a == b:
                continue
            report["bitIdentical"] = False
            if not macho.is_macho(files_a[name]):
                problems.append(f"{name}: differs between builds ({digest(a)[:12]} vs {digest(b)[:12]})")
                continue
            entry = {}
            _, slices_a = macho.parse(files_a[name])
            _, slices_b = macho.parse(files_b[name])
            entry["uuid"] = [[item["uuid"] for item in slices_a], [item["uuid"] for item in slices_b]]
            entry["regions"], samples = differences(files_a[name], files_b[name])
            entry["differingStrings"] = [list(pair) for pair in samples]
            stripped_a, stripped_b = normalized(files_a[name], scratch), normalized(files_b[name], scratch)
            entry["normalizedIdentical"] = stripped_a == stripped_b
            entry["normalizedSHA256"] = [digest(stripped_a), digest(stripped_b)]
            entry["identicalApartFromUUID"] = without_uuid(stripped_a) == without_uuid(stripped_b)
            if entry["uuid"][0] != entry["uuid"][1]:
                cause = (" and nothing else differs after strip -S: the debug-map paths had different lengths, which "
                         "changes the linker's UUID; build both copies from derived-data paths of equal length"
                         if entry["identicalApartFromUUID"] else "")
                problems.append(f"{name}: LC_UUID differs ({entry['uuid'][0]} vs {entry['uuid'][1]}){cause}")
            if not entry["identicalApartFromUUID"]:
                problems.append(f"{name}: executables differ beyond the debug map and signature "
                                f"(regions: {', '.join(sorted(entry['regions']))})")
            report["files"][name] = entry
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("first", type=Path, help="App bundle from the first clean build")
    parser.add_argument("second", type=Path, help="App bundle from the second clean build")
    args = parser.parse_args()
    first, second = args.first.resolve(), args.second.resolve()
    for app in (first, second):
        if not app.is_dir() or app.suffix != ".app":
            parser.error(f"expected a built .app directory: {app}")
    report = compare(first, second)
    print(json.dumps(report, indent=2, sort_keys=True))
    if report["problems"]:
        print("Reproducible build check failed:\n  " + "\n  ".join(report["problems"]), file=sys.stderr)
        return 1
    if report["bitIdentical"]:
        print(f"Reproducible build check passed for {first.name}: bit-identical")
    else:
        regions = sorted({region for entry in report["files"].values() for region in entry["regions"]})
        print(f"Reproducible build check passed for {first.name}: not bit-identical; differences confined to "
              f"{', '.join(regions)} (debug-map paths); LC_UUID equal and executables identical after strip -S")
    return 0


if __name__ == "__main__":
    sys.exit(main())
