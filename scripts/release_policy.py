"""Shared release policy for the source checks and the built-bundle gates.

scripts/check-foundation.py applies these lists to committed sources and
plists; scripts/check-app-bundle.py and scripts/check-app-capabilities.py apply
them to the Release app bundles that scripts/verify.sh builds. Keep one list so
the source and bundle checks cannot drift apart. A change here is a privacy
review (docs/privacy-contract.md), not a tooling tweak.
"""
import re

# Apple frameworks that provide a capability the privacy contract forbids:
# networking, web content and web sign-in, commerce, advertising, attribution,
# tracking permission, cloud, game services and push notifications.
BLOCKED_FRAMEWORKS = {
    "Network": "network", "CFNetwork": "network", "FoundationNetworking": "network",
    "WebKit": "web view", "SafariServices": "web view", "AuthenticationServices": "web sign-in",
    "StoreKit": "in-app purchase", "AdSupport": "advertising identifier", "AdServices": "ad attribution",
    "iAd": "advertising", "AppTrackingTransparency": "tracking permission", "CloudKit": "cloud",
    "GameKit": "game services", "UserNotifications": "notifications", "PushKit": "push",
    "MetricKit": "diagnostics collection",
}

# First-party system frameworks a reviewed title may link. The first group is
# what the titles link today; the second is what the Swift and SwiftUI
# toolchains link automatically on some SDKs. Anything else, including any
# BLOCKED_FRAMEWORKS entry, needs a privacy review before it is added.
ALLOWED_SYSTEM_FRAMEWORKS = {
    "AVFAudio", "Combine", "CoreFoundation", "CoreGraphics", "CoreHaptics", "Foundation",
    "SpriteKit", "SwiftUI", "UIKit", "_SpriteKit_SwiftUI",
    "AVFoundation", "Accessibility", "AudioToolbox", "CoreAudio", "CoreImage", "CoreMedia",
    "CoreServices", "CoreText", "CoreVideo", "DeveloperToolsSupport", "ImageIO", "Metal",
    "Observation", "OSLog", "QuartzCore", "Symbols", "UniformTypeIdentifiers",
}
# Runtime libraries under /usr/lib outside /usr/lib/swift.
ALLOWED_SYSTEM_LIBRARIES = {"libobjc.A.dylib", "libSystem.B.dylib", "libc++.1.dylib"}

# Info.plist keys that declare permissions, background execution, network
# policy, URL schemes, cloud containers or ad attribution. Any key ending in
# UsageDescription (NSUserTrackingUsageDescription included) is refused too.
FORBIDDEN_INFO_KEYS = {
    "UIBackgroundModes": "background modes, including remote-notification",
    "NSAppTransportSecurity": "App Transport Security exceptions",
    "CFBundleURLTypes": "URL schemes",
    "LSApplicationQueriesSchemes": "queried URL schemes",
    "NSUbiquitousContainers": "iCloud containers",
    "SKAdNetworkItems": "ad network attribution",
    "NSAdvertisingAttributionReportEndpoint": "ad attribution reports",
    "NSBonjourServices": "local network services",
    "NSUserActivityTypes": "handoff and activity continuation",
}

# Entitlements that signing adds by itself and that grant no service. Any other
# entitlement (aps-environment, iCloud, Game Center, in-app payments, networking,
# associated domains) fails the bundle audit.
ALLOWED_ENTITLEMENTS = {
    "application-identifier", "com.apple.developer.team-identifier", "get-task-allow",
    "beta-reports-active", "keychain-access-groups",
}

# Analytics, attribution, advertising and crash-reporting SDKs. A class
# prefix matches the start of an Objective-C class name followed by an
# uppercase letter. A name matches a Swift module (`Name.` at the start of a
# demangled path), the start of an Objective-C class name, or a framework or
# library name. Short prefixes that Apple also uses (CLS, AMP, MP) are left out.
SDK_CLASS_PREFIXES = ("FIR", "GAD", "GUL", "FBSDK", "FBAd", "ABK", "BNC", "NRMA", "ALSdk", "MAAd", "YMM",
                      "SEG", "UADS")
SDK_NAMES = (
    "Firebase", "Crashlytics", "GoogleMobileAds", "GoogleAnalytics", "GoogleAppMeasurement", "FBSDKCoreKit",
    "FacebookCore", "FBAudienceNetwork", "AppsFlyerLib", "AppsFlyer", "Adjust", "AdjustSdk", "Amplitude",
    "Mixpanel", "Segment", "Sentry", "Bugsnag", "Flurry", "Branch", "UnityAds", "AppLovinSDK", "AppLovin",
    "IronSource", "Braze", "BrazeKit", "Appboy", "OneSignal", "Instabug", "Kochava", "Chartboost", "Vungle",
    "VungleSDK", "MoPub", "Tapjoy", "Heap", "NewRelic", "Countly", "PostHog", "Smartlook", "UXCam",
    "Localytics", "Leanplum", "CleverTap", "Singular", "AppMetrica", "AdColony", "Datadog", "DatadogCore",
    "Embrace", "Instana", "Kochava", "Pendo", "FullStory", "LogRocket", "Qualtrics",
)
_SDK_ALTERNATION = "|".join(sorted(set(SDK_NAMES), key=len, reverse=True))
SDK_CLASS_PATTERN = re.compile(r"^(?:(?:%s)[A-Z]|(?:%s)(?![a-z0-9_]))" % ("|".join(SDK_CLASS_PREFIXES), _SDK_ALTERNATION))
SDK_MODULE_PATTERN = re.compile(r"(?<![\w.])(?:%s)\w*[.)]" % _SDK_ALTERNATION)
SDK_LIBRARY_PATTERN = re.compile(r"(?<![A-Za-z0-9])(?:%s)(?![a-z0-9])" % _SDK_ALTERNATION)


def info_plist_problems(info, label):
    """Forbidden keys in one Info.plist dictionary."""
    problems = []
    for key in sorted(info):
        if key.endswith("UsageDescription"):
            problems.append(f"{label}: permission prompt {key}")
        elif key in FORBIDDEN_INFO_KEYS:
            problems.append(f"{label}: {key} ({FORBIDDEN_INFO_KEYS[key]})")
    capabilities = info.get("UIRequiredDeviceCapabilities", [])
    if isinstance(capabilities, dict):
        capabilities = [name for name, required in capabilities.items() if required]
    for capability in sorted(set(capabilities) & {"gamekit", "location-services", "gps"}):
        problems.append(f"{label}: UIRequiredDeviceCapabilities {capability}")
    return problems


def privacy_manifest_problems(manifest, label):
    """A shipped privacy manifest must declare no tracking and no collected data."""
    problems = []
    if manifest.get("NSPrivacyTracking") is not False:
        problems.append(f"{label}: NSPrivacyTracking must be false")
    if manifest.get("NSPrivacyTrackingDomains", []) != []:
        problems.append(f"{label}: NSPrivacyTrackingDomains must be empty")
    if manifest.get("NSPrivacyCollectedDataTypes", []) != []:
        problems.append(f"{label}: NSPrivacyCollectedDataTypes must be empty")
    for key in ("NSPrivacyTrackingDomains", "NSPrivacyCollectedDataTypes"):
        if key not in manifest:
            problems.append(f"{label}: missing {key}")
    return problems
