#!/usr/bin/env python3
"""Scan a built app's code for network, web, commerce, ads, tracking, cloud, game-service and push APIs.

Uses the scanning approach of check-required-reason-apis.py on every Mach-O
file in the bundle: imported symbols (C functions and Objective-C classes),
referenced selectors and demangled Swift references. It adds the binary's own
defined symbols and Objective-C class names, so a statically linked analytics
or ads SDK is found by its class prefix or Swift module, and C strings, so a
class or framework named for dynamic lookup is found too. Any match fails:
the privacy contract allows none of these capabilities.

Limits: Swift string literals of 15 bytes or fewer are stored inline in code,
so a short class name built for NSClassFromString is not in __cstring; code
that assembles names at run time, or reaches an API through a system framework
on the app's behalf, is outside a static scan. Runtime traffic observation is
the release checklist's job.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import macho  # noqa: E402
import release_policy as policy  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "required_reason", Path(__file__).resolve().with_name("check-required-reason-apis.py"))
required_reason = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(required_reason)


def swift_module(*modules):
    return re.compile(r"(?<![\w.])(?:%s)\." % "|".join(modules))


# classes: Objective-C class names, matched as referenced (_OBJC_CLASS_$_X),
# defined or named in a C string. symbols: imported C symbols; a trailing *
# matches a prefix. swift: patterns over demangled Swift references.
CAPABILITIES = {
    "network": {
        "classes": {"NSURLSession", "NSURLSessionConfiguration", "NSURLSessionTask", "NSURLSessionDataTask",
                    "NSURLSessionDownloadTask", "NSURLSessionUploadTask", "NSURLSessionStreamTask",
                    "NSURLSessionWebSocketTask", "NSURLConnection", "NSURLDownload", "NWPathMonitor"},
        "symbols": {"_nw_*", "_CFStreamCreatePairWithSocketToHost", "_CFSocketCreate", "_CFSocketConnectToAddress",
                    "_CFReadStreamCreateForHTTPRequest", "_CFHTTPMessageCreateRequest", "_CFNetworkCopySystemProxySettings",
                    "_SCNetworkReachabilityCreateWithName", "_socket", "_connect", "_getaddrinfo", "_gethostbyname",
                    "__swift_FORCE_LOAD_$_swiftNetwork"},
        "selectors": {"sharedSession", "sessionWithConfiguration:", "sessionWithConfiguration:delegate:delegateQueue:",
                      "dataTaskWithURL:", "dataTaskWithRequest:", "dataTaskWithURL:completionHandler:",
                      "dataTaskWithRequest:completionHandler:", "downloadTaskWithURL:", "uploadTaskWithRequest:fromData:",
                      "webSocketTaskWithURL:", "sendSynchronousRequest:returningResponse:error:",
                      "sendAsynchronousRequest:queue:completionHandler:", "connectionWithRequest:delegate:"},
        "swift": [re.compile(r"NSURLSession|NSURLConnection|URLSessionConfiguration|URLSessionTask"),
                  swift_module("Network", "FoundationNetworking", "CFNetwork")],
    },
    "web view": {
        "classes": {"WKWebView", "WKWebViewConfiguration", "WKWebsiteDataStore", "SFSafariViewController",
                    "SFAuthenticationSession", "ASWebAuthenticationSession", "UIWebView"},
        "symbols": {"__swift_FORCE_LOAD_$_swiftWebKit"},
        "selectors": {"loadHTMLString:baseURL:", "loadFileURL:allowingReadAccessToURL:"},
        "swift": [swift_module("WebKit", "SafariServices", "AuthenticationServices")],
    },
    "in-app purchase": {
        "classes": {"SKPaymentQueue", "SKPayment", "SKMutablePayment", "SKProductsRequest", "SKProduct",
                    "SKReceiptRefreshRequest", "SKStoreReviewController", "SKStoreProductViewController",
                    "SKAdNetwork", "SKOverlay", "SKCloudServiceController"},
        "symbols": {"__swift_FORCE_LOAD_$_swiftStoreKit"},
        "selectors": {"addPayment:", "restoreCompletedTransactions", "finishTransaction:"},
        "swift": [swift_module("StoreKit", "_StoreKit_SwiftUI")],
    },
    "advertising and attribution": {
        "classes": {"ASIdentifierManager", "AAAttribution"},
        "symbols": set(),
        "selectors": {"advertisingIdentifier", "isAdvertisingTrackingEnabled", "attributionTokenWithError:"},
        "swift": [swift_module("AdSupport", "AdServices", "iAd")],
    },
    "tracking permission": {
        "classes": {"ATTrackingManager"},
        "symbols": set(),
        "selectors": {"requestTrackingAuthorizationWithCompletionHandler:", "trackingAuthorizationStatus"},
        "swift": [swift_module("AppTrackingTransparency")],
    },
    "cloud": {
        "classes": {"CKContainer", "CKDatabase", "CKRecord", "CKRecordZone", "CKSyncEngine", "CKShare",
                    "NSUbiquitousKeyValueStore"},
        "symbols": {"_NSUbiquitousKeyValueStoreDidChangeExternallyNotification", "__swift_FORCE_LOAD_$_swiftCloudKit"},
        "selectors": {"URLForUbiquityContainerIdentifier:", "ubiquityIdentityToken"},
        "swift": [swift_module("CloudKit")],
    },
    "game services": {
        "classes": {"GKLocalPlayer", "GKPlayer", "GKGameCenterViewController", "GKLeaderboard", "GKLeaderboardSet",
                    "GKAchievement", "GKAchievementDescription", "GKAccessPoint", "GKMatchmaker", "GKMatch",
                    "GKMatchRequest", "GKTurnBasedMatch", "GKScore", "GKSavedGame", "GKVoiceChat", "GKChallenge"},
        "symbols": {"__swift_FORCE_LOAD_$_swiftGameKit"},
        "selectors": {"setAuthenticateHandler:"},
        "swift": [swift_module("GameKit")],
    },
    "push and notifications": {
        "classes": {"UNUserNotificationCenter", "UNNotificationRequest", "UNMutableNotificationContent", "PKPushRegistry"},
        "symbols": {"__swift_FORCE_LOAD_$_swiftUserNotifications"},
        "selectors": {"registerForRemoteNotifications", "registerForRemoteNotificationTypes:",
                      "registerUserNotificationSettings:", "requestAuthorizationWithOptions:completionHandler:"},
        "swift": [swift_module("UserNotifications", "PushKit"), re.compile(r"registerForRemoteNotifications")],
    },
}
FRAMEWORK_PATH = re.compile(r"/System/Library/Frameworks/(%s)\.framework" % "|".join(policy.BLOCKED_FRAMEWORKS))


def section_strings(binary, segment, section):
    """Strings listed by otool -v -s for a C-string section; empty when absent."""
    output = required_reason.tool(["otool", "-v", "-s", segment, section, str(binary)])
    values = []
    for line in output.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and all(c in "0123456789abcdef" for c in parts[0]):
            values.append(parts[1])
    return values


def demangle(names):
    """Full Swift demangling, which keeps module names (--simplified drops them)."""
    mangled = "\n".join(sorted(name for name in names if name.startswith(("_$s", "$s"))))
    return required_reason.tool(["swift-demangle"], stdin=mangled).splitlines() if mangled else []


def defined_references(binary):
    """Demangled defined Swift symbols and the Objective-C classes the binary defines."""
    names = [line.strip() for line in required_reason.tool(["nm", "-U", "-j", str(binary)]).splitlines() if line.strip()]
    classes = set(section_strings(binary, "__TEXT", "__objc_classname"))
    classes |= {name.split("_OBJC_CLASS_$_", 1)[1] for name in names if "_OBJC_CLASS_$_" in name}
    return demangle(names), classes


def scan(binary):
    imports, selectors, _ = required_reason.references(binary)
    swift_imports = demangle(imports)
    swift_defined, defined_classes = defined_references(binary)
    referenced_classes = {name.split("_OBJC_CLASS_$_", 1)[1] for name in imports if name.startswith("_OBJC_CLASS_$_")}
    cstrings = set(section_strings(binary, "__TEXT", "__cstring"))
    swift = swift_imports + swift_defined
    found = {}
    for capability, rules in CAPABILITIES.items():
        evidence = set()
        evidence |= {f"class {name}" for name in (referenced_classes | defined_classes) & rules["classes"]}
        evidence |= {f"string {name}" for name in cstrings & rules["classes"]}
        for symbol in rules["symbols"]:
            if symbol.endswith("*"):
                evidence |= {f"symbol {name}" for name in imports if name.startswith(symbol[:-1])}
            elif symbol in imports:
                evidence.add(f"symbol {symbol}")
        evidence |= {f"selector {name}" for name in selectors & rules["selectors"]}
        for pattern in rules["swift"]:
            evidence |= {f"swift {line.strip()[:160]}" for line in swift if pattern.search(line)}
        if evidence:
            found[capability] = sorted(evidence)
    sdk = {f"class {name}" for name in referenced_classes | defined_classes if policy.SDK_CLASS_PATTERN.match(name)}
    sdk |= {f"swift {line.strip()[:160]}" for line in swift if policy.SDK_MODULE_PATTERN.search(line)}
    if sdk:
        found["analytics, ads or crash-reporting SDK"] = sorted(sdk)
    paths = {f"string {value}" for value in cstrings if FRAMEWORK_PATH.search(value)}
    if paths:
        found["dynamic loading of a blocked framework"] = sorted(paths)
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("app", type=Path, help="Built .app bundle (Release, as shipped)")
    args = parser.parse_args()
    app = args.app.resolve()
    if not app.is_dir() or app.suffix != ".app":
        parser.error("expected a built .app directory")
    binaries = macho.files(app)
    report = {"app": app.name, "binaries": {}, "problems": []}
    if not binaries:
        report["problems"].append(f"{app.name}: no Mach-O files to scan")
    for binary in binaries:
        name = str(binary.relative_to(app.parent))
        found = scan(binary)
        report["binaries"][name] = found
        for capability, evidence in sorted(found.items()):
            shown = ", ".join(evidence[:4]) + (f" and {len(evidence) - 4} more" if len(evidence) > 4 else "")
            report["problems"].append(f"{name}: {capability}: {shown}")
    print(json.dumps(report, indent=2, sort_keys=True))
    if report["problems"]:
        print("App capability scan failed:\n  " + "\n  ".join(report["problems"]), file=sys.stderr)
        return 1
    print(f"App capability scan passed for {app.name}: {len(binaries)} Mach-O file(s), no network, web view, "
          "commerce, ads, attribution, tracking, cloud, game-service, push or analytics SDK references")
    return 0


if __name__ == "__main__":
    sys.exit(main())
