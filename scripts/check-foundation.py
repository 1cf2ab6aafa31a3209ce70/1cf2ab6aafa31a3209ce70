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

import titles as title_manifests

ROOT = Path(__file__).resolve().parents[1]
TITLES = []


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

    for title in TITLES:
        check_content_package(title)


def check_content_package(title):
    """Each title's content depends only on GameCore and ships one reviewed Resources copy."""
    name = title.content_product
    content = command_json(["swift", "package", "--package-path", title.content_package, "dump-package"])
    require(content["name"] == name and len(content["dependencies"]) == 1,
            f"{name}: title content must have one local core dependency")
    dep = content["dependencies"][0]
    require(set(dep) == {"fileSystem"} and Path(dep["fileSystem"][0]["path"]).resolve() == ROOT / "Packages/GameCore",
            f"{name}: title content may depend only on local GameCore")
    products = {product["name"]: product for product in content["products"]}
    require(set(products) == {name, "content-validator"},
            f"{name}: expected the title library and the content-validator executable")
    targets = {t["name"]: t for t in content["targets"]}
    require(set(targets) == {name, "ContentValidatorCLI", f"{name}Tests"},
            f"{name}: review title content target inventory")
    require(targets[name]["type"] == "regular" and target_dependencies(targets[name]) == [("product", "GameCore", "gamecore")],
            f"{name}: title content library must depend only on GameCore")
    require(targets[name].get("resources") == [{"path": "Resources", "rule": {"copy": {}}}],
            f"{name}: title package must copy the reviewed Resources directory")
    require(targets["ContentValidatorCLI"]["type"] == "executable" and target_dependencies(targets["ContentValidatorCLI"]) == [("target", name)],
            f"{name}: host validator must use the same title content library")
    require(targets[f"{name}Tests"]["type"] == "test" and target_dependencies(targets[f"{name}Tests"]) == [("target", name)],
            f"{name}: content tests must exercise the title content library")
    catalog = json.loads((ROOT / title.content_resources / "catalog.json").read_text())
    require(catalog.get("titleID") == title.title_id,
            f"{name}: catalog titleID must match the {title.target} manifest's titleID")


def check_project():
    project = command_json(["plutil", "-convert", "json", "-o", "-", "GameCore.xcodeproj/project.pbxproj"])
    objects = project["objects"]
    expected = {"Packages/GameCore": "GameCore", "Packages/GamePlatform": "GamePlatform"}
    expected.update({title.content_package: title.content_product for title in TITLES})
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
    require(len(local_refs) == len(expected) and set(local_refs.values()) == set(expected),
            "Project must reference exactly the two foundation packages and each title's content package")
    require(len(products) == len(expected), "Project must declare exactly the reviewed foundation and title package products")
    product_by_name = {}
    for identifier, product in products.items():
        require(product.get("package") in local_refs
                and product["productName"] == expected[local_refs[product["package"]]],
                "Package product must match its local package reference")
        product_by_name[product["productName"]] = identifier
    project_root = objects[project["rootObject"]]
    require(set(project_root.get("packageReferences", [])) == set(local_refs),
            "Project packageReferences must include all reviewed local packages")
    apps = {item["name"]: item for item in objects.values()
            if item["isa"] == "PBXNativeTarget" and item.get("productType") == "com.apple.product-type.application"}
    require(set(apps) == {title.target for title in TITLES}, "Expected exactly one app target per title manifest")
    reviewed_info = {f"{title.source_directory}/Info.plist" for title in TITLES}
    for title in TITLES:
        app = apps[title.target]
        # A title links the shared foundation and its own content, never another title's.
        own = {product_by_name["GameCore"], product_by_name["GamePlatform"], product_by_name[title.content_product]}
        require(set(app.get("packageProductDependencies", [])) == own,
                f"{title.target} must depend on the core, platform and its own content products only")
        validation = [index for index, phase_id in enumerate(app["buildPhases"])
                      if objects[phase_id]["isa"] == "PBXShellScriptBuildPhase"
                      and f"swift run --package-path {title.content_package} " in objects[phase_id].get("shellScript", "")
                      and f"content-validator {title.content_resources}" in objects[phase_id].get("shellScript", "")]
        require(validation == [0], f"{title.target}: native content validation must precede app compilation and packaging")
        linked = []
        for phase_id in app["buildPhases"]:
            phase = objects[phase_id]
            if phase["isa"] == "PBXFrameworksBuildPhase":
                for build_id in phase["files"]:
                    build = objects[build_id]
                    require(build.get("productRef") in products,
                            "Unexpected linked framework; review foundation dependency policy")
                    linked.append(build["productRef"])
        require(len(linked) == 3 and set(linked) == own, f"{title.target}: core, platform and its own content products must be linked")
        configurations = objects[app["buildConfigurationList"]]["buildConfigurations"]
        for configuration in configurations:
            settings = objects[configuration]["buildSettings"]
            require(settings.get("PRODUCT_BUNDLE_IDENTIFIER") == title.bundle_identifier,
                    f"{title.target}: bundle identifier must match its manifest")
    allowed_info = {
        "CFBundleDisplayName", "UIApplicationSceneManifest_Generation", "UILaunchScreen_Generation",
        "UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations_iPad",
    }
    for item in objects.values():
        if item["isa"] != "XCBuildConfiguration":
            continue
        settings = item["buildSettings"]
        require(not settings.get("CODE_SIGN_ENTITLEMENTS"), "Foundation must not add signing entitlements")
        require(settings.get("INFOPLIST_FILE") in {None} | reviewed_info,
                "Review any additional custom Info.plist")
        for key in settings:
            if key.startswith("INFOPLIST_KEY_"):
                require(key.removeprefix("INFOPLIST_KEY_") in allowed_info,
                        f"Review new generated Info.plist key: {key}")
    attributes = project_root.get("attributes", {}).get("TargetAttributes", {})
    for target in attributes.values():
        require(not target.get("SystemCapabilities"), "Review added project capabilities")
    for path in sorted(reviewed_info):
        if (ROOT / path).is_file():
            info = plistlib.loads((ROOT / path).read_bytes())
            require(info == {"UIApplicationSceneManifest": {
                "UIApplicationSupportsMultipleScenes": False, "UISceneConfigurations": {}}},
                f"{path} must retain the reviewed single-window scene configuration")


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
                              r"ATTrackingManager|UserDefaults|NSUbiquitousKeyValueStore)\b")
    # Epic 04 owns local filesystem access in a single reviewed adapter.
    # Package fixtures may use FileManager for isolated roots; core/title code cannot.
    filesystem_adapter = ROOT / "Packages/GamePlatform/Sources/GamePlatform/LocalSaveStore.swift"
    fixture_diagnostics = ROOT / "Packages/GamePlatform/Sources/GamePlatform/ShellActionJournal.swift"
    platform_test_root = ROOT / "Packages/GamePlatform/Tests"
    authoring_clis = {ROOT / title.content_package / "Sources/ContentValidatorCLI/main.swift" for title in TITLES}
    content_test_roots = [ROOT / title.content_package / "Tests" for title in TITLES]
    title_imports = {title.target: set() for title in TITLES}
    registrations = {title.target: set() for title in TITLES}
    content_products = {title.content_product for title in TITLES}
    for directory in [ROOT / "Packages", ROOT / "Games"]:
        for path in sorted(directory.rglob("*.swift")):
            if ".build" in path.parts or path.name == "Package.swift":
                continue
            source = source_without_comments(path.read_text())
            imports = set(re.findall(r"\bimport\s+(?:(?:class|struct|enum|protocol|func|var|let)\s+)?([A-Za-z_][A-Za-z_0-9]*)", source))
            require(not any(module in blocked_imports or module.startswith("Firebase") for module in imports),
                    f"Disallowed privacy-related import in {path.relative_to(ROOT)}")
            require(not re.search(r"\bFileManager\b", source)
                    or path in {filesystem_adapter, fixture_diagnostics} | authoring_clis
                    or any(path.is_relative_to(root) for root in content_test_roots + [platform_test_root]),
                    f"Filesystem access belongs in the reviewed save adapter or host authoring CLI: {path.relative_to(ROOT)}")
            match = blocked_apis.search(source)
            require(match is None, f"Disallowed network/cloud/commerce/storage API in {path.relative_to(ROOT)}: {match.group() if match else ''}")
            if path.is_relative_to(ROOT / "Packages/GameCore/Sources"):
                require(imports <= {"Foundation", "Swift", "_Concurrency"},
                        f"GameCore imports outside Foundation/standard library: {sorted(imports)}")
            for title in TITLES:
                if path.is_relative_to(title.directory):
                    title_imports[title.target].update(imports)
                    registrations[title.target].update(re.findall(r'TitleRegistration\(\s*id:\s*"([^"]*)"', source))
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
    for title in TITLES:
        imports = title_imports[title.target]
        require({"GameCore", "GamePlatform"} <= imports, f"{title.target} must import both foundation products")
        others = imports & (content_products - {title.content_product})
        require(not others, f"{title.target} must not import another title's content: {sorted(others)}")
        # The registered ID names the save namespace; it must be the manifest's.
        require(registrations[title.target] == {title.title_id},
                f"{title.target} must register only its manifest titleID {title.title_id!r}, found {sorted(registrations[title.target])}")


def main():
    global TITLES
    try:
        TITLES = title_manifests.load()
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
