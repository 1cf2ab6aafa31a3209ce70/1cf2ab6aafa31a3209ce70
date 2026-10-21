#!/usr/bin/env python3
"""Prove check-app-bundle.py passes a reviewed bundle and refuses each seeded violation.

Builds disposable iOS Simulator app bundles in a temporary directory: a clean
one (unsigned, then ad-hoc signed with an allowed entitlement) and one per
violation: an embedded third-party framework, a blocked system framework, an
unreviewed system library, service entitlements, forbidden Info.plist keys,
missing or tracking privacy manifests and an unreviewed resource bundle.
Nothing is installed or run.
"""
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).resolve().with_name("check-app-bundle.py")
CLEAN = """
import Foundation
import SpriteKit
import UIKit
@inline(never) func touch(_ values: Any...) { print(values.count) }
touch(SKScene(size: CGSize(width: 1, height: 1)), UIColor.red)
"""
WEB = """
import WebKit
@inline(never) func touch(_ values: Any...) { print(values.count) }
touch(WKWebView())
"""
SQLITE = """
import Foundation
import SQLite3
var handle: OpaquePointer?
print(sqlite3_open(":memory:", &handle))
"""
TRACKER = """
public func track(_ event: String) { print(event) }
"""
TRACKER_CLIENT = """
import Tracker
track("launch")
"""
PRIVACY = {"NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": [],
           "NSPrivacyAccessedAPITypes": []}
TARGET = ["-target", "arm64-apple-ios18.0-simulator"]


def swiftc(root, arguments):
    subprocess.run(["xcrun", "--sdk", "iphonesimulator", "swiftc"] + TARGET + arguments,
                   cwd=root, check=True, capture_output=True)


def executable(root, name, source, extra=()):
    (root / f"{name}.swift").write_text(source)
    swiftc(root, [f"{name}.swift", "-o", f"{name}.bin", *extra])
    return root / f"{name}.bin"


def bundle(root, case, binary, info=None, privacy=PRIVACY):
    app = root / case / "Fixture.app"
    app.mkdir(parents=True)
    shutil.copy2(binary, app / "Fixture")
    values = {"CFBundleExecutable": "Fixture", "CFBundleIdentifier": "local.gamecore.Fixture",
              "CFBundlePackageType": "APPL"}
    values.update(info or {})
    (app / "Info.plist").write_bytes(plistlib.dumps(values))
    if privacy is not None:
        (app / "PrivacyInfo.xcprivacy").write_bytes(plistlib.dumps(privacy))
    content = app / "FixtureContent_FixtureContent.bundle"
    content.mkdir()
    (content / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "local.gamecore.FixtureContent"}))
    (content / "catalog.json").write_text("{}")
    return app


def check(app, *extra):
    result = subprocess.run([sys.executable, str(SCRIPT), "--no-title",
                             "--resource-bundle", "FixtureContent_FixtureContent.bundle", *extra, str(app)],
                            capture_output=True, text=True)
    report = json.loads(result.stdout[:result.stdout.rindex("}") + 1])
    return result.returncode, report["problems"]


def expect_refused(name, app, fragments, *extra):
    code, problems = check(app, *extra)
    missing = [fragment for fragment in fragments if not any(fragment in problem for problem in problems)]
    assert code == 1 and not missing, (name, code, missing, problems)
    print(f"PASS {name}: refused ({len(problems)} problem(s))")


def main():
    with tempfile.TemporaryDirectory(prefix="gamecore-bundle-audit-") as temporary:
        root = Path(temporary)
        clean = executable(root, "clean", CLEAN)

        app = bundle(root, "clean", clean)
        code, problems = check(app)
        assert code == 0, ("clean", problems)
        print("PASS clean unsigned bundle: exit 0")

        entitlements = root / "allowed.entitlements"
        entitlements.write_bytes(plistlib.dumps({"get-task-allow": True}))
        app = bundle(root, "signed-allowed", clean)
        subprocess.run(["codesign", "-s", "-", "--entitlements", str(entitlements), str(app)], check=True, capture_output=True)
        code, problems = check(app)
        assert code == 0, ("ad-hoc signed with get-task-allow", problems)
        print("PASS ad-hoc signed bundle with only get-task-allow: exit 0")

        entitlements = root / "services.entitlements"
        entitlements.write_bytes(plistlib.dumps({"aps-environment": "development",
                                                 "com.apple.developer.icloud-container-identifiers": ["iCloud.fixture"]}))
        app = bundle(root, "signed-services", clean)
        subprocess.run(["codesign", "-s", "-", "--entitlements", str(entitlements), str(app)], check=True, capture_output=True)
        expect_refused("push and iCloud entitlements", app,
                       ["entitlement aps-environment", "entitlement com.apple.developer.icloud-container-identifiers"])

        (root / "Tracker.swift").write_text(TRACKER)
        swiftc(root, ["-parse-as-library", "-emit-library", "-emit-module", "-module-name", "Tracker", "Tracker.swift",
                      "-o", "Tracker", "-Xlinker", "-install_name", "-Xlinker", "@rpath/Tracker.framework/Tracker"])
        client = executable(root, "client", TRACKER_CLIENT, ["-I", ".", "-L", ".", "-Xlinker", str(root / "Tracker"),
                                                              "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks"])
        app = bundle(root, "third-party-framework", client)
        framework = app / "Frameworks" / "Tracker.framework"
        framework.mkdir(parents=True)
        shutil.copy2(root / "Tracker", framework / "Tracker")
        expect_refused("embedded third-party framework", app,
                       ["Fixture.app/Frameworks: embedded code container", "Frameworks/Tracker.framework: embedded code container",
                        "embedded Mach-O file",
                        "links @rpath/Tracker.framework/Tracker: not a first-party system library"])

        expect_refused("blocked system framework", bundle(root, "webkit", executable(root, "web", WEB)),
                       ["links /System/Library/Frameworks/WebKit.framework/WebKit: blocked system framework WebKit"])
        expect_refused("unreviewed system library", bundle(root, "sqlite", executable(root, "sqlite", SQLITE, ["-lsqlite3"])),
                       ["libsqlite3.dylib: system library is not in the reviewed allowlist"])

        forbidden = {"NSCameraUsageDescription": "camera", "NSUserTrackingUsageDescription": "tracking",
                     "UIBackgroundModes": ["remote-notification"], "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True},
                     "CFBundleURLTypes": [{"CFBundleURLSchemes": ["fixture"]}], "SKAdNetworkItems": [{}]}
        expect_refused("forbidden Info.plist keys", bundle(root, "info", clean, info=forbidden),
                       ["permission prompt NSCameraUsageDescription", "permission prompt NSUserTrackingUsageDescription",
                        "UIBackgroundModes", "NSAppTransportSecurity", "CFBundleURLTypes", "SKAdNetworkItems"])

        expect_refused("missing privacy manifest", bundle(root, "no-privacy", clean, privacy=None),
                       ["missing PrivacyInfo.xcprivacy"])
        tracking = dict(PRIVACY, NSPrivacyTracking=True, NSPrivacyTrackingDomains=["tracker.example"],
                        NSPrivacyCollectedDataTypes=[{"NSPrivacyCollectedDataType": "NSPrivacyCollectedDataTypeDeviceID"}])
        expect_refused("tracking privacy manifest", bundle(root, "tracking", clean, privacy=tracking),
                       ["NSPrivacyTracking must be false", "NSPrivacyTrackingDomains must be empty",
                        "NSPrivacyCollectedDataTypes must be empty"])

        app = bundle(root, "extra-bundle", clean)
        (app / "Vendor_Vendor.bundle").mkdir()
        expect_refused("unreviewed resource bundle", app, ["Vendor_Vendor.bundle: unreviewed resource bundle"])
    print("App bundle audit passes a reviewed bundle and refuses every seeded violation")


if __name__ == "__main__":
    main()
