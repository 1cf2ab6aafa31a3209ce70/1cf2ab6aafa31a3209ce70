#!/usr/bin/env python3
"""Check the current foundation's package boundaries and static privacy surface.

Requires the selected Swift toolchain and macOS plutil. This is a structural
review aid, not a runtime traffic audit or a general Swift source parser.
"""
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def command_json(arguments):
    result = subprocess.run(arguments, cwd=ROOT, text=True, capture_output=True)
    require(result.returncode == 0,
            f"{' '.join(arguments)} failed:\n{result.stderr.strip()}")
    return json.loads(result.stdout)


def target_dependencies(target):
    """Accept only the dependency encodings used by this foundation."""
    dependencies = []
    for entry in target.get("dependencies", []):
        require(len(entry) == 1, f"Unsupported dependency in {target['name']}: {entry}")
        kind, values = next(iter(entry.items()))
        require(isinstance(values, list), f"Unsupported {kind} dependency encoding")
        if kind in {"byName", "target"}:
            require(len(values) == 2 and values[1] is None,
                    f"Conditional/unsupported {kind} dependency: {entry}")
            dependencies.append(("target", values[0]))
        elif kind == "product":
            require(len(values) in {3, 4} and all(v is None for v in values[2:]),
                    f"Conditional/unsupported product dependency: {entry}")
            dependencies.append(("product", values[0], values[1].lower()))
        else:
            raise ValueError(f"Unsupported target dependency kind {kind!r}; review checker before adopting it")
    return dependencies


def check_packages():
    core = command_json(["swift", "package", "--package-path", "Packages/GameCore", "dump-package"])
    platform = command_json(["swift", "package", "--package-path", "Packages/GamePlatform", "dump-package"])
    require(core["name"] == "GameCore" and not core["dependencies"],
            "GameCore must have no package dependencies")
    core_targets = {target["name"]: target for target in core["targets"]}
    require(set(core_targets) == {"GameCore", "GameCoreTests"}, "Review changes to GameCore target inventory")
    require(core_targets["GameCore"]["type"] == "regular" and not target_dependencies(core_targets["GameCore"]),
            "GameCore must not depend on platform or title modules")
    require(core_targets["GameCoreTests"]["type"] == "test"
            and target_dependencies(core_targets["GameCoreTests"]) == [("target", "GameCore")],
            "GameCoreTests must depend only on GameCore")
    dependencies = platform["dependencies"]
    require(platform["name"] == "GamePlatform" and len(dependencies) == 1,
            "GamePlatform must have exactly one local GameCore package dependency")
    require(set(dependencies[0]) == {"fileSystem"} and len(dependencies[0]["fileSystem"]) == 1,
            "GamePlatform dependency must be a local filesystem package")
    local = dependencies[0]["fileSystem"][0]
    require(Path(local["path"]).resolve() == ROOT / "Packages/GameCore",
            "GamePlatform local package must resolve to Packages/GameCore")
    platform_targets = {target["name"]: target for target in platform["targets"]}
    require(set(platform_targets) == {"GamePlatform", "GamePlatformTests"}
            and platform_targets["GamePlatform"]["type"] == "regular",
            "Expected platform implementation and its test target")
    require(target_dependencies(platform_targets["GamePlatform"]) == [("product", "GameCore", "gamecore")],
            "GamePlatform target must depend only on the GameCore product")
    require(platform_targets["GamePlatformTests"]["type"] == "test"
            and target_dependencies(platform_targets["GamePlatformTests"]) == [("target", "GamePlatform")],
            "GamePlatformTests must depend only on GamePlatform")


def check_project():
    project = command_json(["plutil", "-convert", "json", "-o", "-", "GameCore.xcodeproj/project.pbxproj"])
    objects = project["objects"]
    expected = {"Packages/GameCore": "GameCore", "Packages/GamePlatform": "GamePlatform"}
    local_refs = {}
    products = {}
    for identifier, item in objects.items():
        kind = item["isa"]
        require(kind != "XCRemoteSwiftPackageReference", "Remote Xcode package dependencies are not allowed")
        if kind == "XCLocalSwiftPackageReference":
            path = item.get("relativePath")
            require(path in expected, f"Unexpected or non-relative Xcode package path: {path}")
            local_refs[identifier] = path
        if kind == "XCSwiftPackageProductDependency":
            products[identifier] = item
    require(len(local_refs) == 2 and set(local_refs.values()) == set(expected),
            "Project must reference exactly the two foundation packages")
    require(len(products) == 2, "Project must declare exactly the two foundation package products")
    for product in products.values():
        require(product.get("package") in local_refs
                and product["productName"] == expected[local_refs[product["package"]]],
                "Package product must match its local package reference")
    project_root = objects[project["rootObject"]]
    require(set(project_root.get("packageReferences", [])) == set(local_refs),
            "Project packageReferences must include both local packages")
    apps = [item for item in objects.values()
            if item["isa"] == "PBXNativeTarget" and item.get("productType") == "com.apple.product-type.application"]
    require(len(apps) == 1 and apps[0]["name"] == "DevelopmentTitle", "Expected one DevelopmentTitle app target")
    app = apps[0]
    require(set(app.get("packageProductDependencies", [])) == set(products),
            "DevelopmentTitle must depend on both package products")
    linked = []
    for phase_id in app["buildPhases"]:
        phase = objects[phase_id]
        if phase["isa"] == "PBXFrameworksBuildPhase":
            for build_id in phase["files"]:
                build = objects[build_id]
                require(build.get("productRef") in products,
                        "Unexpected linked framework; review foundation dependency policy")
                linked.append(build["productRef"])
    require(len(linked) == 2 and set(linked) == set(products), "Both foundation products must be linked by the app")
    allowed_info = {
        "CFBundleDisplayName", "UIApplicationSceneManifest_Generation", "UILaunchScreen_Generation",
        "UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations_iPad",
    }
    for item in objects.values():
        if item["isa"] != "XCBuildConfiguration":
            continue
        settings = item["buildSettings"]
        require(not settings.get("CODE_SIGN_ENTITLEMENTS"), "Foundation must not add signing entitlements")
        require(not settings.get("INFOPLIST_FILE"), "Review custom Info.plist before adding it to the foundation")
        for key in settings:
            if key.startswith("INFOPLIST_KEY_"):
                require(key.removeprefix("INFOPLIST_KEY_") in allowed_info,
                        f"Review new generated Info.plist key: {key}")
    attributes = project_root.get("attributes", {}).get("TargetAttributes", {})
    for target in attributes.values():
        require(not target.get("SystemCapabilities"), "Review added project capabilities")


def source_without_comments(source):
    # Deliberately limited: catches direct imports/API spellings; compilation and
    # manual review still cover aliases, dynamic calls, and obfuscated behavior.
    # Preserve string contents so a URL containing // cannot hide code that
    # follows the literal on the same line. This does not evaluate Swift syntax.
    tokens = r'""".*?"""|"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*'
    return re.sub(tokens, lambda match: "" if match.group().startswith(("//", "/*"))
                  else match.group(), source, flags=re.DOTALL)


def check_sources():
    blocked_imports = {
        "Network", "FoundationNetworking", "CloudKit", "GameKit", "StoreKit",
        "AdSupport", "AppTrackingTransparency", "WebKit", "SafariServices",
        "MetricKit", "UserNotifications", "Firebase", "Amplitude", "Sentry",
        "Segment", "Mixpanel", "GoogleMobileAds", "FBSDKCoreKit", "AppsFlyerLib",
    }
    blocked_apis = re.compile(r"\b(?:URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|"
                              r"CFNetwork|CKContainer|GKLocalPlayer|SKPaymentQueue|ASIdentifierManager|"
                              r"ATTrackingManager|UserDefaults|FileManager|NSUbiquitousKeyValueStore)\b")
    title_imports = set()
    for directory in [ROOT / "Packages", ROOT / "Games"]:
        for path in sorted(directory.rglob("*.swift")):
            if ".build" in path.parts or path.name == "Package.swift":
                continue
            source = source_without_comments(path.read_text())
            imports = set(re.findall(r"\bimport\s+(?:(?:class|struct|enum|protocol|func|var|let)\s+)?([A-Za-z_][A-Za-z_0-9]*)", source))
            require(not any(module in blocked_imports or module.startswith("Firebase") for module in imports),
                    f"Disallowed privacy-related import in {path.relative_to(ROOT)}")
            match = blocked_apis.search(source)
            require(match is None, f"Disallowed network/cloud/commerce/storage API in {path.relative_to(ROOT)}: {match.group() if match else ''}")
            if path.is_relative_to(ROOT / "Packages/GameCore/Sources"):
                require(imports <= {"Foundation", "Swift", "_Concurrency"},
                        f"GameCore imports outside Foundation/standard library: {sorted(imports)}")
            if path.is_relative_to(ROOT / "Games/DevelopmentTitle"):
                title_imports.update(imports)
        for path in sorted(directory.rglob("*.entitlements")):
            if ".build" in path.parts:
                continue
            require(not plistlib.loads(path.read_bytes()), f"Review nonempty entitlements: {path.relative_to(ROOT)}")
        for path in sorted(directory.rglob("*.plist")):
            if ".build" in path.parts:
                continue
            info = plistlib.loads(path.read_bytes())
            require(not any(key.endswith("UsageDescription") or key in {"UIBackgroundModes", "NSAppTransportSecurity"}
                            for key in info), f"Review permission/background/network keys in {path.relative_to(ROOT)}")
    require({"GameCore", "GamePlatform"} <= title_imports, "DevelopmentTitle must import both foundation products")


def main():
    try:
        check_packages()
        check_project()
        check_sources()
    except (ValueError, KeyError, TypeError, OSError, json.JSONDecodeError, plistlib.InvalidFileException) as error:
        print(f"Foundation check failed: {error}", file=sys.stderr)
        return 1
    print("Foundation checks passed: local package boundaries, app links, imports and static privacy surface.")
    print("Static checks do not establish runtime network behavior or distribution privacy compliance.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
