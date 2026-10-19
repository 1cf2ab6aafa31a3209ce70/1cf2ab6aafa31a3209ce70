#!/usr/bin/env python3
"""Focused serial spike checks on owned iPhone 12 and iPad (9th generation) simulators; no foundation matrix."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
MODELS = {'iphone12': 'com.apple.CoreSimulator.SimDeviceType.iPhone-12',
          'ipad9': 'com.apple.CoreSimulator.SimDeviceType.iPad-9th-generation'}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('evidence', type=Path)
parser.add_argument('--model', action='append', choices=list(MODELS), help='Repeat to select geometries (default: both)')
parser.add_argument('--derived-data', type=Path, help='Reuse only this experiment build cache')
args = parser.parse_args()
models = args.model or list(MODELS)
out = args.evidence.resolve()
out.mkdir(parents=True, exist_ok=False)
receipt = {'scope': 'serial module-only focused tests, one owned simulator at a time', 'geometries': {}, 'commands': []}
devices = []

def run(command, name, timeout=360):
    path = out / (name + '.log')
    start = time.monotonic()
    entry = {'command': command, 'log': path.name}
    receipt['commands'].append(entry)
    try:
        with path.open('w') as log:
            result = subprocess.run(command, cwd=REPO, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired:
        # A timed-out command stays in the receipt; its log shows how far it got.
        entry.update(timedOut=True, seconds=round(time.monotonic()-start, 3))
        (out/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
        raise RuntimeError(name + ' timed out after ' + str(timeout) + ' seconds; see ' + str(path))
    entry.update(exitCode=result.returncode, seconds=round(time.monotonic()-start, 3))
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

def retries(bundle, name):
    """A retried case passes in the summary, so read repetitions from the test tree and never hide one."""
    tree = json.loads(run(['xcrun','xcresulttool','get','test-results','tests','--path',str(bundle)], name+'-tests-tree'))
    cases = []
    def visit(node):
        repetitions = [c for c in node.get('children', []) if c.get('nodeType') == 'Repetition']
        if node.get('nodeType') == 'Test Case' and any(r.get('result') == 'Failed' for r in repetitions):
            cases.append({'test': node.get('nodeIdentifier') or node.get('name'), 'result': node.get('result'),
                          'repetitions': [{'name': r.get('name'), 'result': r.get('result')} for r in repetitions]})
        for child in node.get('children', []): visit(child)
    for node in tree.get('testNodes', []): visit(node)
    report = {'cases': cases, 'inputFaults': None}
    if cases:
        # Classify against the simulator input fault behind N06 with the collector's own scan.
        try:
            spec = importlib.util.spec_from_file_location('collector', REPO/'scripts/run-mobile-tests.py')
            collector = importlib.util.module_from_spec(spec); spec.loader.exec_module(collector)
            report['inputFaults'] = collector.scan_input_faults(bundle)
        except Exception as error:
            report['inputFaults'] = {'error': str(error)}
        for case in cases:
            message = name + ' ' + case['test'] + ' ' + str(case['result']) + ' after retry'
            print('RETRIED ' + message, flush=True)
            if os.environ.get('GITHUB_ACTIONS') == 'true': print('::warning title=Seam test retried::' + message, flush=True)
    return report

try:
    receipt['checkout'] = run(['git','rev-parse','HEAD'], 'checkout').strip()
    receipt['workingTree'] = run(['git','status','--short'], 'working-tree').strip()
    receipt['inputsBefore'] = source_hashes()
    receipt['toolchain'] = run(['xcodebuild','-version'], 'toolchain').strip()
    runtimes = json.loads(run(['xcrun','simctl','list','runtimes','-j'], 'runtimes'))
    available = [r for r in runtimes['runtimes'] if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-') and int(r['version'].split('.')[0]) >= 18]
    requested = os.environ.get('GAMECORE_SIM_RUNTIME_VERSION')
    if requested: available = [r for r in available if r['version'] == requested]
    if not available: raise RuntimeError('No available iOS simulator runtime >=18 matching ' + (requested or 'installed inventory'))
    runtime = max(available, key=lambda r: tuple(int(i) for i in r['version'].split('.')))
    receipt['runtime'] = {k:runtime[k] for k in ['identifier','version','buildversion']}
    for model in models:
        device = run(['xcrun','simctl','create','GameCore Spike06 owned '+model,MODELS[model],runtime['identifier']], model+'-create').strip()
        devices.append(device)
        geometry = receipt['geometries'][model] = {'deviceUUID': device, 'modules': {}}
        run(['xcrun','simctl','boot',device], model+'-boot')
        run(['xcrun','simctl','bootstatus',device,'-b'], model+'-bootstatus')
        for module in ['grid','terrain']:
            scheme, name = module.title()+'Seam', model+'-'+module
            run([sys.executable,str(ROOT/'scripts/generate-project.py'),'--modules',module], name+'-generate')
            result = geometry['modules'][module] = {'projectSHA256':hashlib.sha256((ROOT/'ModuleSeam.xcodeproj/project.pbxproj').read_bytes()).hexdigest()}
            common = ['xcodebuild','-project',str(ROOT/'ModuleSeam.xcodeproj'),'-scheme',scheme,'-derivedDataPath',str((args.derived_data or out/'build').resolve()),'-jobs','2','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','CODE_SIGNING_ALLOWED=NO']
            run(common+['-destination','generic/platform=iOS Simulator','build-for-testing'], name+'-build')
            bundle = out/(name+'.xcresult')
            run(common+['-destination','platform=iOS Simulator,id='+device,'-resultBundlePath',str(bundle),'-parallel-testing-enabled','NO','-test-timeouts-enabled','YES','-maximum-test-execution-time-allowance','90','-retry-tests-on-failure','-test-iterations','2','test-without-building'], name+'-tests', timeout=600)
            summary = result['summary'] = json.loads(run(['xcrun','xcresulttool','get','test-results','summary','--path',str(bundle)], name+'-summary'))
            if summary.get('totalTestCount') != 7 or summary.get('passedTests') != 7 or summary.get('failedTests', 0) or summary.get('skippedTests', 0) or summary.get('testFailures') or summary.get('runtimeWarnings') or summary.get('expectedFailures', 0):
                raise RuntimeError(name + ' summary did not confirm seven passing tests without skips/failures/runtime warnings')
            result['retries'] = retries(bundle, name)
        for action in ['shutdown','delete']: run(['xcrun','simctl',action,device], model+'-'+action)
        devices.remove(device)
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
    for device in devices:
        for action in ['shutdown','delete']:
            try: run(['xcrun','simctl',action,device], 'cleanup-'+action+'-'+device)
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
