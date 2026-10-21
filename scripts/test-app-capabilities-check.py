#!/usr/bin/env python3
"""Prove check-app-capabilities.py finds each forbidden capability and passes a clean app.

Compiles disposable iOS Simulator executables: one that references an API from
every capability the scan covers, one per capability for the single-category
cases that matter most (networking and an SDK linked in as a Swift module), and
a clean one that uses only the frameworks the titles use. Each goes into a
temporary app bundle; nothing is installed or run.
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).resolve().with_name("check-app-capabilities.py")
CLEAN = """
import Foundation
import SpriteKit
import UIKit

@inline(never) func touch(_ values: Any...) { print(values.count) }
touch(SKScene(size: CGSize(width: 1, height: 1)), UIColor.red, Bundle.main.bundleURL)
"""
EVERYTHING = """
import AdServices
import AdSupport
import AppTrackingTransparency
import AuthenticationServices
import CloudKit
import Darwin
import Foundation
import GameKit
import Network
import SafariServices
import StoreKit
import UIKit
import UserNotifications
import WebKit

@inline(never) func touch(_ values: Any...) { print(values.count) }

touch(URLSession.shared, NWConnection(host: "example.invalid", port: 1, using: .tcp))
touch(WKWebView(), SFSafariViewController(url: URL(fileURLWithPath: "/")))
touch(ASWebAuthenticationSession(url: URL(fileURLWithPath: "/"), callbackURLScheme: nil) { _, _ in })
touch(SKPaymentQueue.default())
touch(ASIdentifierManager.shared().advertisingIdentifier, try? AAAttribution.attributionToken())
touch(ATTrackingManager.trackingAuthorizationStatus)
touch(CKContainer.default())
touch(GKLocalPlayer.local)
touch(UNUserNotificationCenter.current())
UIApplication.shared.registerForRemoteNotifications()
touch(dlopen("/System/Library/Frameworks/AdSupport.framework/AdSupport", RTLD_LAZY) as Any)

@objc(FIRAnalyticsFixture) final class AnalyticsFixture: NSObject {}
touch(AnalyticsFixture())
"""
NETWORK_ONLY = """
import Foundation
@inline(never) func touch(_ values: Any...) { print(values.count) }
touch(URLSession.shared.dataTask(with: URL(fileURLWithPath: "/")))
"""
STOREKIT2_ONLY = """
import StoreKit
@inline(never) func touch(_ values: Any...) { print(values.count) }
Task { touch((try? await Product.products(for: ["fixture"])) as Any) }
"""
SDK_MODULE = """
public final class Tracker {
    public init() {}
    public func record(_ event: String) { print(event) }
}
"""
SDK_CLIENT = """
import Mixpanel
Tracker().record("fixture")
"""
ALL = {"network", "web view", "in-app purchase", "advertising and attribution", "tracking permission", "cloud",
       "game services", "push and notifications", "analytics, ads or crash-reporting SDK",
       "dynamic loading of a blocked framework"}
TARGET = ["-target", "arm64-apple-ios18.0-simulator"]


def swiftc(root, arguments):
    subprocess.run(["xcrun", "--sdk", "iphonesimulator", "swiftc"] + TARGET + arguments,
                   cwd=root, check=True, capture_output=True)


def compile_app(root, name, source):
    (root / f"{name}.swift").write_text(source)
    app = root / name / "Fixture.app"
    app.mkdir(parents=True)
    swiftc(root, ["-O", f"{name}.swift", "-o", str(app / "Fixture")])
    return app


def check(app):
    result = subprocess.run([sys.executable, str(SCRIPT), str(app)], capture_output=True, text=True)
    report = json.loads(result.stdout[:result.stdout.rindex("}") + 1])
    return result.returncode, set(report["binaries"].get("Fixture.app/Fixture", {})), report["problems"]


def main():
    with tempfile.TemporaryDirectory(prefix="gamecore-capabilities-") as temporary:
        root = Path(temporary)
        code, found, problems = check(compile_app(root, "clean", CLEAN))
        assert code == 0 and not found, ("clean", code, problems)
        print("PASS clean app: no capabilities, exit 0")

        code, found, problems = check(compile_app(root, "everything", EVERYTHING))
        assert code == 1 and found >= ALL, ("everything", code, sorted(ALL - found))
        print(f"PASS every capability: found {len(found)} categories, exit {code}")

        code, found, problems = check(compile_app(root, "network", NETWORK_ONLY))
        assert code == 1 and found == {"network"}, ("network only", code, sorted(found))
        print("PASS URLSession alone: refused as network")

        code, found, problems = check(compile_app(root, "storekit2", STOREKIT2_ONLY))
        assert code == 1 and found == {"in-app purchase"}, ("StoreKit 2 only", code, sorted(found), problems)
        print("PASS Swift-only StoreKit 2: refused as in-app purchase")

        # A statically linked SDK shows up as a Swift module in the app's own symbols.
        (root / "Mixpanel.swift").write_text(SDK_MODULE)
        swiftc(root, ["-parse-as-library", "-emit-library", "-static", "-emit-module", "-module-name", "Mixpanel",
                      "Mixpanel.swift", "-o", "libMixpanel.a"])
        (root / "client.swift").write_text(SDK_CLIENT)
        app = root / "sdk" / "Fixture.app"
        app.mkdir(parents=True)
        swiftc(root, ["-I", ".", "-L", ".", "-lMixpanel", "client.swift", "-o", str(app / "Fixture")])
        code, found, problems = check(app)
        assert code == 1 and "analytics, ads or crash-reporting SDK" in found, ("static SDK", code, problems)
        print("PASS statically linked analytics module: refused")
    print("App capability scan detects every forbidden capability and passes a clean app")


if __name__ == "__main__":
    main()
