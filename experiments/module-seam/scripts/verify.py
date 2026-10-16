#!/usr/bin/env python3
"""Focused serial spike checks, one disposable iPhone 12; no foundation matrix."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('evidence', type=Path)
parser.add_argument('--derived-data', type=Path, help='Reuse only this experiment build cache')
args = parser.parse_args()
out = args.evidence.resolve()
out.mkdir(parents=True, exist_ok=False)
receipt = {'scope': 'one iPhone 12, serial module-only focused tests', 'models': {}, 'commands': []}
device = None

def run(command, name, timeout=360):
    path = out / (name + '.log')
    start = time.monotonic()
    with path.open('w') as log:
        result = subprocess.run(command, cwd=REPO, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
    receipt['commands'].append({'command': command, 'log': path.name, 'exitCode': result.returncode, 'seconds': round(time.monotonic()-start, 3)})
    (out/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    if result.returncode: raise RuntimeError(name + ' failed; see ' + str(path))
    return path.read_text()

def source_hashes():
    directories = [ROOT, REPO/'Packages/GameCore/Sources', REPO/'Packages/GamePlatform/Sources', REPO/'Games/DevelopmentContent/Sources']
    files = {p for directory in directories for p in directory.rglob('*')
             if p.is_file() and '.xcodeproj' not in str(p) and '__pycache__' not in str(p)
             and p.suffix in ['.swift', '.py', '.json', '.svg']}
    files.update(REPO/p for p in ['Packages/GameCore/Package.swift', 'Packages/GamePlatform/Package.swift', 'Games/DevelopmentContent/Package.swift'])
    return {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}

try:
    receipt['checkout'] = run(['git','rev-parse','HEAD'], 'checkout').strip()
    receipt['workingTree'] = run(['git','status','--short'], 'working-tree').strip()
    receipt['inputsBefore'] = source_hashes()
    receipt['toolchain'] = run(['xcodebuild','-version'], 'toolchain').strip()
    runtimes = json.loads(run(['xcrun','simctl','list','runtimes','-j'], 'runtimes'))
    available = [r for r in runtimes['runtimes'] if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-') and int(r['version'].split('.')[0]) >= 18]
    runtime = max(available, key=lambda r: tuple(int(i) for i in r['version'].split('.')))
    receipt['runtime'] = {k:runtime[k] for k in ['identifier','version','buildversion']}
    device = run(['xcrun','simctl','create','GameCore Spike06 owned','com.apple.CoreSimulator.SimDeviceType.iPhone-12',runtime['identifier']], 'create').strip()
    receipt['deviceUUID'] = device
    run(['xcrun','simctl','boot',device], 'boot')
    run(['xcrun','simctl','bootstatus',device,'-b'], 'bootstatus')
    for module in ['grid','terrain']:
        scheme = module.title()+'Seam'
        run([sys.executable,str(ROOT/'scripts/generate-project.py'),'--modules',module], module+'-generate')
        receipt['models'][module] = {'projectSHA256':hashlib.sha256((ROOT/'ModuleSeam.xcodeproj/project.pbxproj').read_bytes()).hexdigest()}
        common = ['xcodebuild','-project',str(ROOT/'ModuleSeam.xcodeproj'),'-scheme',scheme,'-derivedDataPath',str((args.derived_data or out/'build').resolve()),'-jobs','2','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','CODE_SIGNING_ALLOWED=NO']
        run(common+['-destination','generic/platform=iOS Simulator','build-for-testing'], module+'-build')
        run(common+['-destination','platform=iOS Simulator,id='+device,'-resultBundlePath',str(out/(module+'.xcresult')),'-parallel-testing-enabled','NO','-test-timeouts-enabled','YES','-maximum-test-execution-time-allowance','90','-collect-test-diagnostics','never','test-without-building'], module+'-tests', timeout=420)
        summary = json.loads(run(['xcrun','xcresulttool','get','test-results','summary','--path',str(out/(module+'.xcresult'))], module+'-summary'))
        receipt['models'][module]['summary'] = summary
        if summary.get('totalTestCount') != 7 or summary.get('passedTests') != 7 or summary.get('failedTests', 0) or summary.get('skippedTests', 0) or summary.get('testFailures') or summary.get('runtimeWarnings') or summary.get('expectedFailures', 0):
            raise RuntimeError(module + ' summary did not confirm seven passing tests without skips/failures/runtime warnings')
    receipt['status'] = 'passed'
except Exception as error:
    receipt['status'] = 'failed'
    receipt['error'] = str(error)
    raise
finally:
    try:
        run([sys.executable,str(ROOT/'scripts/generate-project.py')], 'restore-project')
    except Exception as error:
        receipt['restorationError'] = str(error)
        receipt['status'] = 'failed'
    if device:
        for action in ['shutdown','delete']:
            try: run(['xcrun','simctl',action,device], action)
            except Exception as error:
                receipt['cleanupError'] = str(error)
                receipt['status'] = 'failed'
    receipt['inputsAfter'] = source_hashes()
    if receipt.get('inputsBefore') != receipt['inputsAfter']:
        receipt['sourceIdentityError'] = 'Inputs changed during verification'
        receipt['status'] = 'failed'
    (out/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')

if receipt.get('status') != 'passed':
    raise SystemExit(1)
