#!/usr/bin/env python3
"""Generate the mobile foundation's Xcode project using the Python standard library."""
import argparse
from hashlib import sha1
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "GameCore.xcodeproj"
WORKSPACE = ROOT / "GameCore.xcworkspace"
objects = {}
outputs = {}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true", help="Check generated files without modifying them")
args = parser.parse_args()


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


app_ref = add("app-product", "isa = PBXFileReference; explicitFileType = wrapper.application; path = DevelopmentTitle.app; sourceTree = BUILT_PRODUCTS_DIR;")
test_ref = add("test-product", "isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = DevelopmentTitleUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;")
package_refs = []
package_products = []
package_builds = []
for name in ["GameCore", "GamePlatform"]:
    ref = add(f"package-{name}", f"isa = XCLocalSwiftPackageReference; relativePath = {quoted(f'Packages/{name}')};")
    product = add(f"package-product-{name}", f"isa = XCSwiftPackageProductDependency; package = {ref}; productName = {name};")
    package_refs.append(ref)
    package_products.append(product)
    package_builds.append(add(f"link-{name}", f"isa = PBXBuildFile; productRef = {product};"))

refs = []
phases = {}
for name, directory in [("app", "Games/DevelopmentTitle"), ("ui", "Tests/DevelopmentTitleUITests")]:
    builds = []
    for file in sorted((ROOT / directory).rglob("*.swift")):
        path = str(file.relative_to(ROOT))
        ref = add(f"ref-{path}", f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(path)}; sourceTree = SOURCE_ROOT;")
        refs.append(ref)
        builds.append(add(f"build-{path}", f"isa = PBXBuildFile; fileRef = {ref};"))
    phases[name] = add(f"{name}-sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;")
    framework_builds = package_builds if name == "app" else []
    phases[f"{name}-frameworks"] = add(f"{name}-frameworks", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {array(framework_builds)}; runOnlyForDeploymentPostprocessing = 0;")
    phases[f"{name}-resources"] = add(f"{name}-resources", "isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")

products = add("products", f"isa = PBXGroup; name = Products; sourceTree = {quoted('<group>')}; children = {array([app_ref, test_ref])};")
group = add("main-group", f"isa = PBXGroup; sourceTree = {quoted('<group>')}; children = {array(refs + [products])};")
app_config = configs("app", {
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "PRODUCT_BUNDLE_IDENTIFIER": "local.gamecore.DevelopmentTitle",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "Development Title",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "MARKETING_VERSION": "0.0.1",
    "CURRENT_PROJECT_VERSION": "1",
})
app = add("app-target", f"isa = PBXNativeTarget; name = DevelopmentTitle; productName = DevelopmentTitle; productReference = {app_ref}; productType = {quoted('com.apple.product-type.application')}; buildConfigurationList = {app_config}; buildPhases = {array([phases['app'], phases['app-frameworks'], phases['app-resources']])}; buildRules = (); dependencies = (); packageProductDependencies = {array(package_products)};")
project_id = ident("project")
proxy = add("app-proxy", f"isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {app}; remoteInfo = DevelopmentTitle;")
dependency = add("app-dependency", f"isa = PBXTargetDependency; target = {app}; targetProxy = {proxy};")
ui_config = configs("ui", {
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "PRODUCT_BUNDLE_IDENTIFIER": "local.gamecore.DevelopmentTitleUITests",
    "GENERATE_INFOPLIST_FILE": "YES",
    "TEST_TARGET_NAME": "DevelopmentTitle",
})
ui = add("ui-target", f"isa = PBXNativeTarget; name = DevelopmentTitleUITests; productName = DevelopmentTitleUITests; productReference = {test_ref}; productType = {quoted('com.apple.product-type.bundle.ui-testing')}; buildConfigurationList = {ui_config}; buildPhases = {array([phases['ui'], phases['ui-frameworks'], phases['ui-resources']])}; buildRules = (); dependencies = {array([dependency])};")
project_config = configs("project", {})
add("project", f"isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; TargetAttributes = {{ {ui} = {{ TestTargetID = {app}; }}; }}; }}; buildConfigurationList = {project_config}; compatibilityVersion = {quoted('Xcode 14.0')}; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = {quoted('')}; projectRoot = {quoted('')}; packageReferences = {array(package_refs)}; targets = {array([app, ui])};")
body = "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n"
body += "\n".join(f"{key} = {{ {value} }};" for key, value in sorted(objects.items()))
body += f"\n}}; rootObject = {project_id}; }}\n"
outputs[PROJECT / "project.pbxproj"] = body
scheme_dir = PROJECT / "xcshareddata" / "xcschemes"


def buildable(target, name, product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:GameCore.xcodeproj"/>'


app_xml = buildable(app, "DevelopmentTitle", "DevelopmentTitle.app")
ui_xml = buildable(ui, "DevelopmentTitleUITests", "DevelopmentTitleUITests.xctest")
outputs[scheme_dir / "DevelopmentTitle.xcscheme"] = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_xml}</BuildActionEntry>
    <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{ui_xml}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ui_xml}</TestableReference></Testables></TestAction>
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
if args.check:
    stale = [path for path, content in outputs.items() if not path.is_file() or path.read_bytes() != content.encode("utf-8")]
    if stale:
        for path in stale:
            print(f"Missing or stale generated file: {path.relative_to(ROOT)}")
        print("Run python3 scripts/generate-project.py to regenerate the project.")
        raise SystemExit(1)
    print("Generated project, scheme, and workspace are current")
else:
    for path, content in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content.encode("utf-8"))
    print(f"Generated {PROJECT.name} and {WORKSPACE.name} with {len(refs)} app/test sources and two local package products")
