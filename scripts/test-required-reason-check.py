#!/usr/bin/env python3
"""Prove check-required-reason-apis.py finds every API category and refuses mismatched manifests.

Compiles a disposable iOS Simulator executable that references one listed API
from each category, places it in temporary app bundles with different privacy
manifests and checks the scanner's verdicts. Nothing is installed or run.
"""
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).resolve().with_name("check-required-reason-apis.py")
SOURCE = """
import Darwin
import Foundation
import UIKit

@inline(never) func touch(_ values: Any...) { print(values.count) }

var info = stat()
_ = stat("/", &info)
let attributes = try? FileManager.default.attributesOfItem(atPath: "/")
touch(attributes?[.modificationDate] as Any)
touch(mach_absolute_time(), ProcessInfo.processInfo.systemUptime)
var volume = statfs()
_ = statfs("/", &volume)
touch(UserDefaults.standard.bool(forKey: "fixture"))
touch(UITextInputMode.activeInputModes.count)
"""
ALL = {"NSPrivacyAccessedAPICategoryFileTimestamp", "NSPrivacyAccessedAPICategorySystemBootTime",
       "NSPrivacyAccessedAPICategoryDiskSpace", "NSPrivacyAccessedAPICategoryActiveKeyboards",
       "NSPrivacyAccessedAPICategoryUserDefaults"}


def manifest(categories):
    return plistlib.dumps({"NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": [],
                           "NSPrivacyAccessedAPITypes": [{"NSPrivacyAccessedAPIType": c,
                                                          "NSPrivacyAccessedAPITypeReasons": ["FIXTURE.1"]}
                                                         for c in sorted(categories)]})


def check(app):
    result = subprocess.run([sys.executable, str(SCRIPT), str(app)], capture_output=True, text=True)
    report = json.loads(result.stdout[:result.stdout.rindex("}") + 1])
    return result.returncode, report


def main():
    with tempfile.TemporaryDirectory(prefix="gamecore-required-reason-") as temporary:
        root = Path(temporary)
        (root / "main.swift").write_text(SOURCE)
        binary = root / "Fixture"
        subprocess.run(["xcrun", "--sdk", "iphonesimulator", "swiftc", "-target", "arm64-apple-ios18.0-simulator",
                        "-O", str(root / "main.swift"), "-o", str(binary)], check=True, capture_output=True)
        cases = [("complete manifest", ALL, 0, set()),
                 ("missing declarations", {"NSPrivacyAccessedAPICategoryUserDefaults"}, 1, ALL - {"NSPrivacyAccessedAPICategoryUserDefaults"}),
                 ("no manifest", None, 1, ALL)]
        for name, declared, expected_code, expected_problems in cases:
            app = root / name.replace(" ", "-") / "Fixture.app"
            app.mkdir(parents=True)
            (app / "Fixture").write_bytes(binary.read_bytes())
            if declared is not None:
                (app / "PrivacyInfo.xcprivacy").write_bytes(manifest(declared))
            code, report = check(app)
            found = set(report["bundles"]["Fixture.app"]["binaries"]["Fixture.app/Fixture"])
            assert found == ALL, (name, sorted(found))
            assert code == expected_code, (name, code, report["problems"])
            assert all(any(c in problem for problem in report["problems"]) for c in expected_problems), (name, report["problems"])
            print(f"PASS {name}: found {len(found)} categories, exit {code}")
        # A declaration the code does not use is speculative and refused.
        app = root / "speculative" / "Fixture.app"
        app.mkdir(parents=True)
        (app / "Fixture").write_bytes(binary.read_bytes())
        (app / "PrivacyInfo.xcprivacy").write_bytes(manifest(ALL | {"NSPrivacyAccessedAPICategoryUnlisted"}))
        code, report = check(app)
        assert code == 1 and any("NSPrivacyAccessedAPICategoryUnlisted" in p for p in report["problems"]), report["problems"]
        print("PASS speculative declaration: refused")
    print("Required-reason API check detects every category and refuses mismatched manifests")


if __name__ == "__main__":
    main()
