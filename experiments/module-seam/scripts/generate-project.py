#!/usr/bin/env python3
"""Generate independently removable mobile module experiment targets."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--modules', choices=['grid', 'terrain', 'both'], default='both')
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
objects = {}
outputs = {}
def key(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def q(s): return json.dumps(str(s))
def arr(values): return '(' + ', '.join(values) + (',' if values else '') + ')'
def add(s, body): objects[key(s)] = body; return key(s)
def configs(name, extra):
    refs = []
    for config in ['Debug', 'Release']:
        settings = dict(SWIFT_VERSION='5.0', IPHONEOS_DEPLOYMENT_TARGET='18.0', SDKROOT='iphoneos',
            SUPPORTED_PLATFORMS='iphoneos iphonesimulator', TARGETED_DEVICE_FAMILY='1,2',
            SUPPORTS_MACCATALYST='NO', CLANG_ENABLE_MODULES='YES', CODE_SIGN_STYLE='Automatic',
            SWIFT_OPTIMIZATION_LEVEL='-Onone' if config == 'Debug' else '-O',
            ENABLE_TESTABILITY='YES' if config == 'Debug' else 'NO',
            SWIFT_ACTIVE_COMPILATION_CONDITIONS=('DEBUG ' if config == 'Debug' else '') + '')
        settings.update(extra)
        if 'Grid' in name: settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] += ' GRID_MODULE'
        refs.append(add(name+config, 'isa = XCBuildConfiguration; name = '+config+'; buildSettings = { '+ ' '.join(q(k)+' = '+q(v)+';' for k,v in settings.items())+' };'))
    return add(name+'configs', 'isa = XCConfigurationList; buildConfigurations = '+arr(refs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
packages=[]; products=[]
for name,path in [('GameCore','../../Packages/GameCore'),('GamePlatform','../../Packages/GamePlatform'),('DevelopmentContent','../../Games/DevelopmentContent')]:
    ref=add(name+'package','isa = XCLocalSwiftPackageReference; relativePath = '+q(path)+';')
    packages.append(ref)
    products.append(add(name+'product','isa = XCSwiftPackageProductDependency; package = '+ref+'; productName = '+name+';'))
refs=[]; productrefs=[]; targets=[]; attributes=[]
project=key('project')
for module in (['grid','terrain'] if args.modules=='both' else [args.modules]):
    name=module.title()+'Seam'
    targetIDs={kind:key(name+kind) for kind in ['app','unit','ui']}
    for kind in ['app','unit','ui']:
        targetname=name if kind=='app' else name+('UITests' if kind=='ui' else 'Tests')
        extension='app' if kind=='app' else 'xctest'
        product=add(targetname+'ref','isa = PBXFileReference; explicitFileType = '+('wrapper.application' if kind=='app' else 'wrapper.cfbundle')+'; path = '+targetname+'.'+extension+'; sourceTree = BUILT_PRODUCTS_DIR;')
        productrefs.append(product)
        dirs=['Sources/App','Sources/Contract','Sources/'+module.title()] if kind=='app' else ['UITests' if kind=='ui' else 'Tests']
        builds=[]
        for file in sorted(f for d in dirs for f in (ROOT/d).rglob('*.swift')):
            path=str(file.relative_to(ROOT))
            ref=add(path+'ref','isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+q(path)+'; sourceTree = SOURCE_ROOT;')
            if ref not in refs: refs.append(ref)
            builds.append(add(targetname+path,'isa = PBXBuildFile; fileRef = '+ref+';'))
        sources=add(targetname+'sources','isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+arr(builds)+'; runOnlyForDeploymentPostprocessing = 0;')
        links=[add(targetname+p,'isa = PBXBuildFile; productRef = '+p+';') for p in (products if kind!='ui' else [])]
        frameworks=add(targetname+'frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = '+arr(links)+'; runOnlyForDeploymentPostprocessing = 0;')
        resources=add(targetname+'resources','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
        settings=dict(PRODUCT_NAME='$(TARGET_NAME)',PRODUCT_BUNDLE_IDENTIFIER='local.gamecore.'+targetname,GENERATE_INFOPLIST_FILE='YES')
        if kind=='app': settings.update(INFOPLIST_KEY_UIApplicationSceneManifest_Generation='YES',INFOPLIST_KEY_UILaunchScreen_Generation='YES',INFOPLIST_KEY_UISupportedInterfaceOrientations='UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',MARKETING_VERSION='0.0.1',CURRENT_PROJECT_VERSION='1')
        elif kind=='ui': settings.update(TEST_TARGET_NAME=name)
        else: settings.update(TEST_HOST='$(BUILT_PRODUCTS_DIR)/'+name+'.app/'+name,BUNDLE_LOADER='$(TEST_HOST)')
        config=configs(targetname,settings)
        deps=[]
        if kind!='app':
            proxy=add(name+'proxy','isa = PBXContainerItemProxy; containerPortal = '+project+'; proxyType = 1; remoteGlobalIDString = '+targetIDs['app']+'; remoteInfo = '+name+';')
            deps=[add(name+'dependency','isa = PBXTargetDependency; target = '+targetIDs['app']+'; targetProxy = '+proxy+';')]
            attributes.append(targetIDs[kind]+' = { TestTargetID = '+targetIDs['app']+'; };')
        target=add(name+kind,'isa = PBXNativeTarget; name = '+targetname+'; productName = '+targetname+'; productReference = '+product+'; productType = '+q('com.apple.product-type.application' if kind=='app' else ('com.apple.product-type.bundle.ui-testing' if kind=='ui' else 'com.apple.product-type.bundle.unit-test'))+'; buildConfigurationList = '+config+'; buildPhases = '+arr([sources,frameworks,resources])+'; buildRules = (); dependencies = '+arr(deps)+'; packageProductDependencies = '+arr(products if kind!='ui' else [])+';')
        targets.append(target)
    def buildable(kind):
        n=name if kind=='app' else name+('UITests' if kind=='ui' else 'Tests')
        return '<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="'+targetIDs[kind]+'" BuildableName="'+n+('.app' if kind=='app' else '.xctest')+'" BlueprintName="'+n+'" ReferencedContainer="container:ModuleSeam.xcodeproj"/>'
    outputs[ROOT/'ModuleSeam.xcodeproj/xcshareddata/xcschemes'/ (name+'.xcscheme')]='''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>'''+''.join('<BuildActionEntry buildForTesting="YES" buildForRunning="'+('YES' if k=='app' else 'NO')+'" buildForProfiling="NO" buildForArchiving="'+('YES' if k=='app' else 'NO')+'" buildForAnalyzing="YES">'+buildable(k)+'</BuildActionEntry>' for k in ['app','unit','ui'])+'''</BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">'''+buildable('unit')+'''</TestableReference><TestableReference skipped="NO">'''+buildable('ui')+'''</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">'''+buildable('app')+'''</BuildableProductRunnable></LaunchAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>
'''
group=add('group','isa = PBXGroup; sourceTree = "<group>"; children = '+arr(refs+[add('products','isa = PBXGroup; name = Products; sourceTree = "<group>"; children = '+arr(productrefs)+';')])+';')
add('project','isa = PBXProject; attributes = { LastUpgradeCheck = 2700; TargetAttributes = { '+ ' '.join(attributes)+' }; }; buildConfigurationList = '+configs('project',{})+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = '+group+'; productRefGroup = '+key('products')+'; projectDirPath = ""; projectRoot = ""; packageReferences = '+arr(packages)+'; targets = '+arr(targets)+';')
outputs[ROOT/'ModuleSeam.xcodeproj/project.pbxproj']='// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = { '+v+' };' for k,v in sorted(objects.items()))+'\n}; rootObject = '+project+'; }\n'
if args.check:
    stale=[str(p) for p,s in outputs.items() if not p.exists() or p.read_text()!=s]
    if stale: raise SystemExit('Stale generated files: '+', '.join(stale))
else:
    scheme_dir=ROOT/'ModuleSeam.xcodeproj/xcshareddata/xcschemes'
    if scheme_dir.exists():
        for p in scheme_dir.glob('*Seam.xcscheme'):
            if p not in outputs: p.unlink()
    for p,s in outputs.items(): p.parent.mkdir(parents=True,exist_ok=True); p.write_text(s)
print('Module project current: '+args.modules)
