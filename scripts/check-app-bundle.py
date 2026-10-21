#!/usr/bin/env python3
"""Audit a built Release app bundle against the release policy.

Checks the bundle that ships, not the sources:

- Every Mach-O load command (otool -L) names a reviewed first-party system
  framework or runtime library. No third-party, private or blocked framework
  (see scripts/release_policy.py) is linked.
- The bundle embeds no framework, dylib, extension or second executable.
  Resource bundles are allowed only when named (by default, the title's own
  content package bundle) and must hold no code.
- Entitlements, read with codesign and from an embedded __entitlements
  section, are empty or limited to identifiers signing adds by itself. An
  unsigned build has none.
- No Info.plist in the bundle declares permission prompts, background modes,
  App Transport Security exceptions, URL schemes, cloud containers or ad
  attribution.
- The app ships PrivacyInfo.xcprivacy declaring no tracking, no tracking
  domains and no collected data; every other manifest in the bundle agrees.

scripts/check-app-capabilities.py scans the code for API references. Neither
check establishes runtime network behavior.
"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import macho  # noqa: E402
import release_policy as policy  # noqa: E402
import titles as title_manifests  # noqa: E402

EMBEDDED_CODE_SUFFIXES = (".framework", ".dylib", ".appex", ".xpc", ".app", ".so")
EMBEDDED_CODE_DIRECTORIES = {"Frameworks", "PlugIns", "Extensions", "Watch", "SystemExtensions", "AppClips"}


def xcrun(arguments):
    return subprocess.run(["xcrun"] + arguments, capture_output=True, text=True)


def linked_libraries(binary):
    """Install names from otool -L, without the file's own LC_ID_DYLIB."""
    result = xcrun(["otool", "-L", str(binary)])
    if result.returncode:
        raise RuntimeError(f"otool -L {binary} failed: {result.stderr.strip()}")
    names = [line.strip().split(" (compatibility", 1)[0] for line in result.stdout.splitlines()[1:] if line.strip()]
    own = xcrun(["otool", "-D", str(binary)]).stdout.splitlines()[1:]
    return [name for name in names if name not in {line.strip() for line in own}]


def classify_library(name):
    """None when the install name is reviewed; otherwise the reason it is refused."""
    framework = re.fullmatch(r"/System/Library/Frameworks/([^/]+)\.framework/.+", name)
    if framework:
        module = framework.group(1)
        if module in policy.BLOCKED_FRAMEWORKS:
            return f"blocked system framework {module} ({policy.BLOCKED_FRAMEWORKS[module]})"
        if module not in policy.ALLOWED_SYSTEM_FRAMEWORKS:
            return f"system framework {module} is not in the reviewed allowlist"
        return None
    overlay = re.fullmatch(r"/usr/lib/swift/libswift(.+)\.dylib", name)
    if overlay:
        module = overlay.group(1)
        if module in policy.BLOCKED_FRAMEWORKS:
            return f"Swift overlay for blocked framework {module} ({policy.BLOCKED_FRAMEWORKS[module]})"
        return None
    if re.fullmatch(r"/usr/lib/[^/]+\.dylib", name):
        return None if Path(name).name in policy.ALLOWED_SYSTEM_LIBRARIES else "system library is not in the reviewed allowlist"
    if name.startswith("/System/Library/PrivateFrameworks/"):
        return "private framework"
    if policy.SDK_LIBRARY_PATTERN.search(name):
        return "third-party analytics, ads or crash-reporting library"
    return "not a first-party system library"


def entitlements(app, executable):
    """Entitlements from the signature and from an embedded section; {} when unsigned."""
    found, sources = {}, []
    result = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(app)], capture_output=True)
    if result.returncode == 0 and result.stdout.strip():
        found.update(plistlib.loads(result.stdout))
        sources.append("code signature")
    elif result.returncode and b"not signed at all" not in result.stderr:
        raise RuntimeError(f"codesign -d {app} failed: {result.stderr.decode().strip()}")
    data, slices = macho.parse(executable)
    for item in slices:
        for name, start, size in item["regions"]:
            if name == "__TEXT,__entitlements" and size:
                found.update(plistlib.loads(data[start:start + size]))
                sources.append(name)
    return found, sources


def resource_bundle_names(app, target, extra):
    """The title's own content bundle plus any named extras."""
    manifests = {item.target: item for item in title_manifests.load()}
    title = manifests.get(target or app.stem)
    if title is None:
        raise ValueError(f"no title manifest for {target or app.stem}; pass --no-title for a fixture bundle")
    return set(extra) | {f"{title.content_product}_{title.content_product}.bundle"}


def audit(app, allowed_bundles):
    report = {"app": app.name, "linked": {}, "entitlements": {}, "privacyManifests": [], "problems": []}
    problems = report["problems"]
    info_path = app / "Info.plist"
    if not info_path.is_file():
        problems.append(f"{app.name}: missing Info.plist")
        return report
    info = plistlib.loads(info_path.read_bytes())
    executable = app / info.get("CFBundleExecutable", app.stem)
    if not macho.is_macho(executable):
        problems.append(f"{app.name}: CFBundleExecutable {executable.name} is not a Mach-O file")
        return report

    for path in sorted(app.rglob("*")):
        relative = path.relative_to(app)
        if path.is_dir() and (path.suffix in EMBEDDED_CODE_SUFFIXES or str(relative) in EMBEDDED_CODE_DIRECTORIES):
            problems.append(f"{app.name}/{relative}: embedded code container")
        if path.is_dir() and path.suffix == ".bundle" and path.name not in allowed_bundles:
            problems.append(f"{app.name}/{relative}: unreviewed resource bundle")
    for binary in macho.files(app):
        relative = str(binary.relative_to(app.parent))
        if binary != executable:
            problems.append(f"{relative}: embedded Mach-O file (third-party or extra code is not allowed)")
        libraries = linked_libraries(binary)
        report["linked"][relative] = libraries
        for name in libraries:
            reason = classify_library(name)
            if reason:
                problems.append(f"{relative}: links {name}: {reason}")

    values, sources = entitlements(app, executable)
    report["entitlements"] = {"sources": sources, "keys": sorted(values)}
    for key in sorted(set(values) - policy.ALLOWED_ENTITLEMENTS):
        problems.append(f"{app.name}: entitlement {key} is not allowed")

    for plist in sorted(app.rglob("Info.plist")):
        problems += policy.info_plist_problems(plistlib.loads(plist.read_bytes()), str(plist.relative_to(app.parent)))

    manifests = sorted(app.rglob("PrivacyInfo.xcprivacy"))
    if app / "PrivacyInfo.xcprivacy" not in manifests:
        problems.append(f"{app.name}: missing PrivacyInfo.xcprivacy at the bundle root")
    for manifest in manifests:
        label = str(manifest.relative_to(app.parent))
        report["privacyManifests"].append(label)
        try:
            values = plistlib.loads(manifest.read_bytes())
        except plistlib.InvalidFileException as error:
            problems.append(f"{label}: unreadable privacy manifest ({error})")
            continue
        problems += policy.privacy_manifest_problems(values, label)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("app", type=Path, help="Built .app bundle (Release, as shipped)")
    parser.add_argument("--title", help="Title target whose content bundle is allowed (default: the app's name)")
    parser.add_argument("--resource-bundle", action="append", default=[],
                        help="Allow an additional code-free resource bundle by name")
    parser.add_argument("--no-title", action="store_true", help="Do not look up a title manifest (fixtures)")
    args = parser.parse_args()
    app = args.app.resolve()
    if not app.is_dir() or app.suffix != ".app":
        parser.error("expected a built .app directory")
    try:
        allowed = set(args.resource_bundle) if args.no_title else resource_bundle_names(app, args.title, args.resource_bundle)
    except ValueError as error:
        parser.error(str(error))
    report = audit(app, allowed)
    print(json.dumps(report, indent=2, sort_keys=True))
    if report["problems"]:
        print("App bundle audit failed:\n  " + "\n  ".join(report["problems"]), file=sys.stderr)
        return 1
    signed = ", ".join(report["entitlements"]["sources"]) or "unsigned, no entitlements"
    print(f"App bundle audit passed for {app.name}: {sum(len(v) for v in report['linked'].values())} reviewed "
          f"system libraries, no embedded code, entitlements {signed}, no forbidden Info.plist keys, "
          f"privacy manifest declares no tracking or collection")
    return 0


if __name__ == "__main__":
    sys.exit(main())
