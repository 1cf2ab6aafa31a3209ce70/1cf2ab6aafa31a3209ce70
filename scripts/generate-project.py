#!/usr/bin/env python3
"""Generate the mobile foundation's Xcode project using the Python standard library.

Every title manifest (Games/<Target>/title.json) yields an app target, its
app-hosted unit tests, its UI tests and a shared scheme of the same name.
"""
import argparse
from hashlib import sha1
import json
from pathlib import Path

import titles as title_manifests

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "GameCore.xcodeproj"
WORKSPACE = ROOT / "GameCore.xcworkspace"
objects = {}
outputs = {}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true", help="Check generated files without modifying them")
args = parser.parse_args()
TITLES = title_manifests.load()


def ident(name):
    return sha1(name.encode()).hexdigest()[:24].upper()


def quoted(value):
    return json.dumps(str(value))


def add(name, body):
    key = ident(name)
    objects[key] = body
    return key


def array(values):
    return "(" + ", ".join(values) + ",)" if values else "()"


def settings(values):
    return "{ " + " ".join(f"{quoted(k)} = {quoted(v)};" for k, v in values.items()) + " }"


def configs(name, extra):
    ids = []
    for config in ["Debug", "Release"]:
        values = {
            "SWIFT_VERSION": "5.0",
            "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
            "SDKROOT": "iphoneos",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "TARGETED_DEVICE_FAMILY": "1,2",
            "SUPPORTS_MACCATALYST": "NO",
            "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
            "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
            "CLANG_ENABLE_MODULES": "YES",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
            "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if config == "Debug" else "",
            "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO",
            "CODE_SIGN_STYLE": "Automatic",
        }
        values.update(extra)
        ids.append(add(f"{name}-{config}", f"isa = XCBuildConfiguration; name = {config}; buildSettings = {settings(values)};"))
    return add(f"{name}-config-list", f"isa = XCConfigurationList; buildConfigurations = {array(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")


# Shared foundation packages first, then each title's own content package.
package_paths = {"GameCore": "Packages/GameCore", "GamePlatform": "Packages/GamePlatform"}
for title in TITLES:
    package_paths[title.content_product] = title.content_package
package_refs = []
package_products = {}
for name, package_path in package_paths.items():
    ref = add(f"package-{name}", f"isa = XCLocalSwiftPackageReference; relativePath = {quoted(package_path)};")
    package_refs.append(ref)
    package_products[name] = add(f"package-product-{name}", f"isa = XCSwiftPackageProductDependency; package = {ref}; productName = {name};")

project_id = ident("project")
refs = []
product_refs = []
targets = []
target_attributes = []
for title in TITLES:
    name = title.target
    # A title links the shared foundation and only its own content.
    linked = [package_products["GameCore"], package_products["GamePlatform"], package_products[title.content_product]]
    app_ref = add(f"{name}-app-product", f"isa = PBXFileReference; explicitFileType = wrapper.application; path = {name}.app; sourceTree = BUILT_PRODUCTS_DIR;")
    ui_name = Path(title.ui_tests).name
    unit_name = Path(title.unit_tests).name
    ui_ref = add(f"{name}-ui-product", f"isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = {ui_name}.xctest; sourceTree = BUILT_PRODUCTS_DIR;")
    unit_ref = add(f"{name}-unit-product", f"isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = {unit_name}.xctest; sourceTree = BUILT_PRODUCTS_DIR;")
    product_refs += [app_ref, ui_ref, unit_ref]
    phases = {}
    for kind, directory in [("app", title.source_directory), ("ui", title.ui_tests), ("unit", title.unit_tests)]:
        builds = []
        for file in sorted((ROOT / directory).rglob("*.swift")):
            path = str(file.relative_to(ROOT))
            ref = add(f"ref-{path}", f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(path)}; sourceTree = SOURCE_ROOT;")
            refs.append(ref)
            builds.append(add(f"build-{path}", f"isa = PBXBuildFile; fileRef = {ref};"))
        phases[kind] = add(f"{name}-{kind}-sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;")
        framework_builds = [add(f"{name}-{kind}-link-{index}", f"isa = PBXBuildFile; productRef = {product};")
                            for index, product in enumerate(linked)] if kind != "ui" else []
        phases[f"{kind}-frameworks"] = add(f"{name}-{kind}-frameworks", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {array(framework_builds)}; runOnlyForDeploymentPostprocessing = 0;")
        phases[f"{kind}-resources"] = add(f"{name}-{kind}-resources", "isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")

    # Validate the exact copied SwiftPM resources before app compilation/packaging.
    # This is a host authoring tool; the app links only the title library product.
    validation_script = f'set -eu\ncd "$SRCROOT"\n/usr/bin/env -u SDK_NAME -u SDK_DIR -u PLATFORM_NAME -u SWIFT_EXEC SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)" /usr/bin/xcrun --sdk macosx swift run --package-path {title.content_package} --scratch-path "$DERIVED_FILE_DIR/ContentValidation" content-validator {title.content_resources}\n'
    validation_phase = add(f"{name}-content-validation", f"isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = (); outputPaths = (); runOnlyForDeploymentPostprocessing = 0; alwaysOutOfDate = 1; shellPath = /bin/sh; shellScript = {quoted(validation_script)};")

    app_settings = {
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "PRODUCT_BUNDLE_IDENTIFIER": title.bundle_identifier,
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_CFBundleDisplayName": title.app_display_name,
        "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
        "MARKETING_VERSION": "0.0.1",
        "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    }
    info_plist = title.directory / "Info.plist"
    if info_plist.is_file():
        info_path = str(info_plist.relative_to(ROOT))
        app_settings["INFOPLIST_FILE"] = info_path
        refs.append(add(f"{name}-app-info", f"isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {quoted(info_path)}; sourceTree = SOURCE_ROOT;"))
    app_config = configs(f"{name}-app", app_settings)
    app = add(f"{name}-app-target", f"isa = PBXNativeTarget; name = {name}; productName = {name}; productReference = {app_ref}; productType = {quoted('com.apple.product-type.application')}; buildConfigurationList = {app_config}; buildPhases = {array([validation_phase, phases['app'], phases['app-frameworks'], phases['app-resources']])}; buildRules = (); dependencies = (); packageProductDependencies = {array(linked)};")
    proxy = add(f"{name}-app-proxy", f"isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {app}; remoteInfo = {name};")
    dependency = add(f"{name}-app-dependency", f"isa = PBXTargetDependency; target = {app}; targetProxy = {proxy};")
    ui_config = configs(f"{name}-ui", {
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "PRODUCT_BUNDLE_IDENTIFIER": f"{title.bundle_identifier}UITests",
        "GENERATE_INFOPLIST_FILE": "YES",
        "TEST_TARGET_NAME": name,
    })
    ui = add(f"{name}-ui-target", f"isa = PBXNativeTarget; name = {ui_name}; productName = {ui_name}; productReference = {ui_ref}; productType = {quoted('com.apple.product-type.bundle.ui-testing')}; buildConfigurationList = {ui_config}; buildPhases = {array([phases['ui'], phases['ui-frameworks'], phases['ui-resources']])}; buildRules = (); dependencies = {array([dependency])};")
    unit_config = configs(f"{name}-unit", {
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "PRODUCT_BUNDLE_IDENTIFIER": f"{title.bundle_identifier}Tests",
        "GENERATE_INFOPLIST_FILE": "YES",
        "TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{name}.app/{name}",
        "BUNDLE_LOADER": "$(TEST_HOST)",
    })
    unit = add(f"{name}-unit-target", f"isa = PBXNativeTarget; name = {unit_name}; productName = {unit_name}; productReference = {unit_ref}; productType = {quoted('com.apple.product-type.bundle.unit-test')}; buildConfigurationList = {unit_config}; buildPhases = {array([phases['unit'], phases['unit-frameworks'], phases['unit-resources']])}; buildRules = (); dependencies = {array([dependency])}; packageProductDependencies = {array(linked)};")
    targets += [app, ui, unit]
    target_attributes += [f"{ui} = {{ TestTargetID = {app}; }};", f"{unit} = {{ TestTargetID = {app}; }};"]
    title.generated = {"app": app, "ui": ui, "unit": unit, "ui_name": ui_name, "unit_name": unit_name}

products = add("products", f"isa = PBXGroup; name = Products; sourceTree = {quoted('<group>')}; children = {array(product_refs)};")
group = add("main-group", f"isa = PBXGroup; sourceTree = {quoted('<group>')}; children = {array(refs + [products])};")
project_config = configs("project", {})
add("project", f"isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; TargetAttributes = {{ {' '.join(target_attributes)} }}; }}; buildConfigurationList = {project_config}; compatibilityVersion = {quoted('Xcode 14.0')}; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = {quoted('')}; projectRoot = {quoted('')}; packageReferences = {array(package_refs)}; targets = {array(targets)};")
body = "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n"
body += "\n".join(f"{key} = {{ {value} }};" for key, value in sorted(objects.items()))
body += f"\n}}; rootObject = {project_id}; }}\n"
outputs[PROJECT / "project.pbxproj"] = body
scheme_dir = PROJECT / "xcshareddata" / "xcschemes"


def buildable(target, name, product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:GameCore.xcodeproj"/>'


for title in TITLES:
    generated = title.generated
    app_xml = buildable(generated["app"], title.target, f"{title.target}.app")
    ui_xml = buildable(generated["ui"], generated["ui_name"], f"{generated['ui_name']}.xctest")
    unit_xml = buildable(generated["unit"], generated["unit_name"], f"{generated['unit_name']}.xctest")
    outputs[scheme_dir / f"{title.target}.xcscheme"] = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_xml}</BuildActionEntry>
    <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{ui_xml}</BuildActionEntry>
    <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{unit_xml}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{unit_xml}</TestableReference><TestableReference skipped="NO">{ui_xml}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_xml}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_xml}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
outputs[WORKSPACE / "contents.xcworkspacedata"] = '''<?xml version="1.0" encoding="UTF-8"?>
<Workspace version="1.0">
  <FileRef location="group:GameCore.xcodeproj"/>
</Workspace>
'''
# A removed title's scheme is stale too; the generator owns every shared scheme.
stale_schemes = [path for path in scheme_dir.glob("*.xcscheme") if path not in outputs] if scheme_dir.is_dir() else []
if args.check:
    stale = [path for path, content in outputs.items() if not path.is_file() or path.read_bytes() != content.encode("utf-8")]
    if stale or stale_schemes:
        for path in stale + stale_schemes:
            print(f"Missing, stale or orphaned generated file: {path.relative_to(ROOT)}")
        print("Run python3 scripts/generate-project.py to regenerate the project.")
        raise SystemExit(1)
    print("Generated project, schemes, and workspace are current")
else:
    for path in stale_schemes:
        path.unlink()
    for path, content in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content.encode("utf-8"))
    print(f"Generated {PROJECT.name} and {WORKSPACE.name}: {len(TITLES)} title(s), {len(refs)} app/test files and {len(package_paths)} local package products")
