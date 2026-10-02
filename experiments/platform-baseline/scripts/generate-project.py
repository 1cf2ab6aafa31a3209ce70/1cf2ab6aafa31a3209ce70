#!/usr/bin/env python3
"""Generate this disposable Xcode project using only Python's standard library."""
from pathlib import Path
from hashlib import sha1
import json

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "PlatformBaseline.xcodeproj"
objects = {}


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
            "SWIFT_VERSION": "5.0", "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
            "MACOSX_DEPLOYMENT_TARGET": "15.0", "SDKROOT": "auto",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx",
            "CLANG_ENABLE_MODULES": "YES", "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
            "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if config == "Debug" else "",
            "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO",
            "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "1,2",
        }
        values.update(extra)
        ids.append(add(f"{name}-{config}", f"isa = XCBuildConfiguration; name = {config}; buildSettings = {settings(values)};"))
    return add(f"{name}-config-list", f"isa = XCConfigurationList; buildConfigurations = {array(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")


app_ref = add("app-product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = PlatformBaseline.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_ref = add("test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = PlatformBaselineUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
refs = []
phases = {}
for name, directory in [("app", "Sources"), ("ui", "UITests")]:
    builds = []
    for file in sorted((ROOT / directory).rglob("*.swift")):
        path = str(file.relative_to(ROOT))
        ref = add(f"ref-{path}", f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(path)}; sourceTree = SOURCE_ROOT;")
        refs.append(ref)
        builds.append(add(f"build-{path}", f"isa = PBXBuildFile; fileRef = {ref};"))
    phases[name] = add(f"{name}-sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;")
    phases[f"{name}-frameworks"] = add(f"{name}-frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
    phases[f"{name}-resources"] = add(f"{name}-resources", "isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")

products = add("products", f"isa = PBXGroup; name = Products; sourceTree = {quoted('<group>')}; children = {array([app_ref, test_ref])};")
group = add("main-group", f"isa = PBXGroup; sourceTree = {quoted('<group>')}; children = {array(refs + [products])};")
app_config = configs("app", {
    "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "local.gamecore.PlatformBaseline",
    "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_CFBundleDisplayName": "Platform Baseline",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES", "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.games",
    "MARKETING_VERSION": "0.0.1", "CURRENT_PROJECT_VERSION": "1", "SUPPORTS_MACCATALYST": "NO",
})
app = add("app-target", f"isa = PBXNativeTarget; name = PlatformBaseline; productName = PlatformBaseline; productReference = {app_ref}; productType = {quoted('com.apple.product-type.application')}; buildConfigurationList = {app_config}; buildPhases = {array([phases['app'], phases['app-frameworks'], phases['app-resources']])}; buildRules = (); dependencies = ();")
project_id = ident("project")
proxy = add("app-proxy", f"isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {app}; remoteInfo = PlatformBaseline;")
dependency = add("app-dependency", f"isa = PBXTargetDependency; target = {app}; targetProxy = {proxy};")
ui_config = configs("ui", {"PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "local.gamecore.PlatformBaselineUITests", "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "PlatformBaseline"})
ui = add("ui-target", f"isa = PBXNativeTarget; name = PlatformBaselineUITests; productName = PlatformBaselineUITests; productReference = {test_ref}; productType = {quoted('com.apple.product-type.bundle.ui-testing')}; buildConfigurationList = {ui_config}; buildPhases = {array([phases['ui'], phases['ui-frameworks'], phases['ui-resources']])}; buildRules = (); dependencies = {array([dependency])};")
project_config = configs("project", {})
add("project", f"isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; TargetAttributes = {{ {ui} = {{ TestTargetID = {app}; }}; }}; }}; buildConfigurationList = {project_config}; compatibilityVersion = {quoted('Xcode 14.0')}; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = {quoted('')}; projectRoot = {quoted('')}; targets = {array([app, ui])};")
PROJECT.mkdir(exist_ok=True)
body = "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n"
body += "\n".join(f"{key} = {{ {value} }};" for key, value in sorted(objects.items()))
body += f"\n}}; rootObject = {project_id}; }}\n"
(PROJECT / "project.pbxproj").write_text(body)
scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
def buildable(target, name, product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:PlatformBaseline.xcodeproj"/>'
app_xml = buildable(app, "PlatformBaseline", "PlatformBaseline.app")
ui_xml = buildable(ui, "PlatformBaselineUITests", "PlatformBaselineUITests.xctest")
(scheme_dir / "PlatformBaseline.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
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
''')
print(f"Generated {PROJECT.relative_to(ROOT)} with {len(refs)} Swift source files")
