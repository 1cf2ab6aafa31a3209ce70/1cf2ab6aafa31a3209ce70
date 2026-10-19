#!/usr/bin/env python3
"""Check a built app's privacy manifests against the required-reason APIs its code references.

Apple requires each executable or dynamic library that uses a required-reason
API to ship in a bundle whose PrivacyInfo.xcprivacy declares that API's
category with an approved reason. This scans every Mach-O file in the app for
the APIs Apple lists (imported symbols, Objective-C selectors and demangled
Swift references) and compares the categories found with the categories the
enclosing bundle declares. A missing declaration fails, and so does a declared
category the code does not use: the privacy contract allows no speculative
declarations.

The API list follows Apple's NSPrivacyAccessedAPIType documentation, rechecked
2026-10-19. Static references are what App Store Connect's scan reports; code
reached only through dynamic lookup is outside this check.
"""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import sys

CATEGORIES = {
    "NSPrivacyAccessedAPICategoryFileTimestamp": {
        "symbols": {"_getattrlist", "_getattrlistbulk", "_fgetattrlist", "_getattrlistat", "_stat", "_fstat",
                    "_fstatat", "_lstat", "_NSFileCreationDate", "_NSFileModificationDate",
                    "_NSURLContentModificationDateKey", "_NSURLCreationDateKey"},
        "selectors": {"creationDate", "modificationDate", "fileModificationDate", "contentModificationDate"},
        "swift": [".creationDate", ".modificationDate", ".fileModificationDate", ".contentModificationDate"],
    },
    "NSPrivacyAccessedAPICategorySystemBootTime": {
        "symbols": {"_mach_absolute_time"},
        "selectors": {"systemUptime"},
        "swift": [".systemUptime"],
    },
    "NSPrivacyAccessedAPICategoryDiskSpace": {
        "symbols": {"_statfs", "_statvfs", "_fstatfs", "_fstatvfs", "_getattrlist", "_fgetattrlist", "_getattrlistat",
                    "_NSURLVolumeAvailableCapacityKey", "_NSURLVolumeAvailableCapacityForImportantUsageKey",
                    "_NSURLVolumeAvailableCapacityForOpportunisticUsageKey", "_NSURLVolumeTotalCapacityKey",
                    "_NSFileSystemFreeSize", "_NSFileSystemSize"},
        "selectors": {"volumeAvailableCapacity", "volumeTotalCapacity"},
        "swift": [".volumeAvailableCapacity", ".volumeTotalCapacity"],
    },
    "NSPrivacyAccessedAPICategoryActiveKeyboards": {
        "symbols": set(),
        "selectors": {"activeInputModes"},
        "swift": [".activeInputModes"],
    },
    "NSPrivacyAccessedAPICategoryUserDefaults": {
        "symbols": {"_OBJC_CLASS_$_NSUserDefaults"},
        "selectors": {"standardUserDefaults"},
        "swift": ["UserDefaults"],
    },
}
MACH_O_MAGIC = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce",
                b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}
BUNDLE_SUFFIXES = (".app", ".framework", ".appex", ".bundle", ".xctest")


def tool(arguments, stdin=None):
    result = subprocess.run(["xcrun"] + arguments, input=stdin, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"xcrun {' '.join(arguments)} failed: {result.stderr.strip()}")
    return result.stdout


def symbol(name):
    """C symbols may carry a variant suffix such as `$INODE64`; Swift and class symbols keep theirs."""
    return name if name.startswith(("_$s", "_OBJC_")) else name.split("$", 1)[0]


def references(binary):
    """Imported symbols, referenced selectors and demangled Swift imports."""
    imports = {symbol(line.strip()) for line in tool(["nm", "-u", "-j", str(binary)]).splitlines() if line.strip()}
    selectors = set()
    for line in tool(["otool", "-v", "-s", "__TEXT", "__objc_methname", str(binary)]).splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and all(c in "0123456789abcdef" for c in parts[0]):
            selectors.add(parts[1].split(":", 1)[0])
    mangled = "\n".join(sorted(name for name in imports if name.startswith("_$s")))
    swift = tool(["swift-demangle", "--simplified"], stdin=mangled).splitlines() if mangled else []
    return imports, selectors, swift


def detected_categories(binary):
    imports, selectors, swift = references(binary)
    found = {}
    for category, apis in CATEGORIES.items():
        evidence = sorted(imports & apis["symbols"]) + sorted(f"selector {s}" for s in selectors & apis["selectors"])
        evidence += sorted({f"swift {line.strip()}" for line in swift for name in apis["swift"] if name in line})
        if evidence:
            found[category] = evidence
    return found


def enclosing_bundle(path, app):
    for parent in [path.parent, *path.parent.parents]:
        if parent.name.endswith(BUNDLE_SUFFIXES):
            return parent
        if parent == app:
            break
    return app


def declared_categories(bundle):
    manifest = bundle / "PrivacyInfo.xcprivacy"
    if not manifest.is_file():
        return None
    values = plistlib.loads(manifest.read_bytes())
    declared = {}
    for entry in values.get("NSPrivacyAccessedAPITypes", []):
        declared[entry["NSPrivacyAccessedAPIType"]] = entry.get("NSPrivacyAccessedAPITypeReasons", [])
    return declared


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="Built .app bundle (Release, as shipped)")
    args = parser.parse_args()
    app = args.app.resolve()
    if not app.is_dir() or app.suffix != ".app":
        parser.error("expected a built .app directory")
    binaries = sorted(path for path in app.rglob("*")
                      if path.is_file() and not path.is_symlink() and path.open("rb").read(4) in MACH_O_MAGIC)
    report = {"app": app.name, "bundles": {}, "problems": []}
    by_bundle = {}
    for binary in binaries:
        found = detected_categories(binary)
        bundle = enclosing_bundle(binary, app)
        entry = by_bundle.setdefault(bundle, {"binaries": {}, "used": set()})
        entry["binaries"][str(binary.relative_to(app.parent))] = found
        entry["used"].update(found)
    for bundle, entry in sorted(by_bundle.items()):
        declared = declared_categories(bundle)
        name = str(bundle.relative_to(app.parent))
        report["bundles"][name] = {"binaries": entry["binaries"], "declared": declared}
        if declared is None:
            if entry["used"]:
                report["problems"].append(f"{name}: uses {sorted(entry['used'])} but has no PrivacyInfo.xcprivacy")
            elif bundle == app:
                report["problems"].append(f"{name}: the app bundle has no PrivacyInfo.xcprivacy")
            continue
        for category in sorted(entry["used"] - set(declared)):
            report["problems"].append(f"{name}: uses {category} without declaring it")
        for category in sorted(set(declared) - entry["used"]):
            report["problems"].append(f"{name}: declares {category}, which its code does not reference")
        for category in sorted(set(declared) & entry["used"]):
            if not declared[category]:
                report["problems"].append(f"{name}: declares {category} without a reason")
    print(json.dumps(report, indent=2, sort_keys=True))
    if report["problems"]:
        print("Required-reason API check failed:\n  " + "\n  ".join(report["problems"]), file=sys.stderr)
        return 1
    used = sorted({c for entry in by_bundle.values() for c in entry["used"]})
    print(f"Required-reason APIs match the privacy manifests in {app.name}: {', '.join(used) or 'none referenced'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
