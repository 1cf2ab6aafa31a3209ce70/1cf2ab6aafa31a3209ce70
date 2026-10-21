#!/usr/bin/env python3
"""Spike 11 dig-feasibility verification on owned iPhone 12 and iPad (9th generation) simulators.

Serial: pure DigCore tests on the host, Debug and Release builds, then per geometry the
app-hosted and behaviour UI tests once and each candidate's timing run (two UI cases)
`--runs` times. Copies each run's JSON report out of the simulator, evaluates it against
the research budgets, writes measurements.json and receipt.json, and deletes the owned
simulators even on failure. Simulator numbers are host diagnostics, not device results.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
BUNDLE = 'local.gamecore.DigFeasibility'
MODELS = {'iphone12': 'com.apple.CoreSimulator.SimDeviceType.iPhone-12',
          'ipad9': 'com.apple.CoreSimulator.SimDeviceType.iPad-9th-generation'}
CANDIDATES = ['heightfield', 'lowlevel', 'voxel', 'sprite']
CLASS = {'heightfield': 'Heightfield', 'lowlevel': 'LowLevel', 'voxel': 'Voxel', 'sprite': 'Sprite'}
BEHAVIOUR_TESTS = {'heightfield': 5, 'lowlevel': 2, 'voxel': 5, 'sprite': 7}
UNIT_TESTS = 5
# Research budgets (iOS 26.0 simulator on the recorded host; they rank candidates only).
BUDGET = {'intervalP95': 20.0, 'intervalP99': 25.0, 'over33Share': 0.5, 'worstFlag': 100.0,
          'meshP95': 4.0, 'collisionChunkP95': 25.0, 'collisionLagP95': 100.0, 'collisionLagMax': 250.0,
          'visualLagP95': 33.4, 'footprintGrowth': 8.0, 'footprintStep': 1.0, 'footprintFlag': 133.0,
          'reloadMax': 500.0}


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--model', action='append', choices=list(MODELS), help='Repeat to select geometries (default: both)')
    parser.add_argument('--candidate', action='append', choices=CANDIDATES, help='Repeat to select candidates (default: all)')
    parser.add_argument('--runs', type=int, default=2, help='Timing runs per geometry and candidate (default 2)')
    parser.add_argument('--derived-data', type=Path, help='Reuse only this experiment build cache')
    parser.add_argument('--summarize-only', action='store_true',
                        help='Recompute verdicts from an existing evidence directory; starts no native process')
    return parser.parse_args(argv)


# ---------------------------------------------------------------- budget evaluation

def row(name, value, budget, ok, note=None):
    result = {'row': name, 'value': value, 'budget': budget, 'pass': ok}
    if note: result['note'] = note
    return result


def interval_rows(window, stats):
    if not stats or not stats.get('count'):
        return [row(window + ' intervals', None, 'samples', False, 'no samples')]
    return [row(window + ' p95 ms', stats['p95'], '<= 20.0', stats['p95'] <= BUDGET['intervalP95']),
            row(window + ' p99 ms', stats['p99'], '<= 25.0', stats['p99'] <= BUDGET['intervalP99']),
            row(window + ' share > 33.3 ms %', stats['over33Share'], '<= 0.5', stats['over33Share'] <= BUDGET['over33Share']),
            row(window + ' worst ms (reported)', stats['max'], 'flag > 100', True,
                'flagged' if stats['max'] > BUDGET['worstFlag'] else None)]


def evaluate_timing(report):
    """Rows 1-9 for the sustained case of one run. Returns (rows, void)."""
    candidate = report['candidate']
    windows = report.get('windows', {})
    idle = interval_rows('I', windows.get('I'))
    void = not all(r['pass'] for r in idle)
    rows = idle + interval_rows('S', windows.get('S'))
    mesh = report.get('mesh', {}).get('S', {})
    total = mesh.get('totalMs', {})
    rows.append(row('mesh total p95 ms (S)', total.get('p95'), '<= 4.0',
                    bool(mesh.get('jobs')) and total.get('p95', 1e9) <= BUDGET['meshP95'],
                    'main actor p95 %s ms, extraction p95 %s ms, %s jobs, max %s chunks' % (
                        mesh.get('mainActorMs', {}).get('p95'), mesh.get('extractMs', {}).get('p95'),
                        mesh.get('jobs'), mesh.get('chunksMax'))))
    lag = report.get('lag', {}).get('S', {})
    if candidate == 'sprite':
        visual = lag.get('meshLagMs', {})
        rows.append(row('collision', None, 'none (2D)', True, 'no collision lane; rules look up cells'))
        rows.append(row('visual lag p95 ms (S)', visual.get('p95'), '<= 33.4',
                        bool(visual.get('count')) and visual['p95'] <= BUDGET['visualLagP95'] and lag.get('meshUnresolved', 1) == 0))
    else:
        chunk = report.get('collision', {}).get('S', {}).get('chunkMs', {})
        rows.append(row('collision per chunk p95 ms (S)', chunk.get('p95'), '<= 25',
                        bool(chunk.get('count')) and chunk['p95'] <= BUDGET['collisionChunkP95'],
                        'max %s ms over %s chunk jobs' % (chunk.get('max'), chunk.get('count'))))
        clag = lag.get('collisionLagMs', {})
        rows.append(row('collision lag p95 ms (S)', clag.get('p95'), '<= 100',
                        bool(clag.get('count')) and clag['p95'] <= BUDGET['collisionLagP95'] and lag.get('collisionUnresolved', 1) == 0))
        rows.append(row('collision lag max ms (S)', clag.get('max'), '<= 250',
                        bool(clag.get('count')) and clag['max'] <= BUDGET['collisionLagMax']))
    summary = report.get('summary', {})
    rows.append(row('score after S / B', [summary.get('scoreAfterS'), summary.get('scoreAfterB')], '24 / 28, controls untouched',
                    summary.get('meetsFixture') is True,
                    'controls collected %s; live matches headless replay: %s' % (
                        summary.get('controlsCollected'), summary.get('matchesReplay'))))
    rows.append(row('no accepted command lost', summary.get('refused'), '0 refused, replay match',
                    summary.get('refused') == 0 and summary.get('matchesReplay') is True))
    return rows, void


def evaluate_cycles(report):
    """Rows 10-12 from the restart-cycle case."""
    cycles = report.get('cycles', [])
    if len(cycles) < 5:
        return [row('restart cycles', len(cycles), '5 cycles', False)]
    footprints = [c['footprintMiB'] for c in cycles]
    growth = round(footprints[-1] - footprints[0], 3)
    deltas = [footprints[i + 1] - footprints[i] for i in range(len(footprints) - 1)]
    streak = longest = 0
    for delta in deltas:
        streak = streak + 1 if delta > BUDGET['footprintStep'] else 0
        longest = max(longest, streak)
    peak = max(c.get('peakMiB', 0) for c in cycles)
    reloads = [c['reloadMs'] for c in cycles]
    return [
        row('footprint growth cycle 1 to 5 MiB', growth, '<= 8', growth <= BUDGET['footprintGrowth'],
            'snapshots %s; peak %s MiB%s' % (footprints, peak, '; flagged > 133 MiB' if max(footprints) > BUDGET['footprintFlag'] else '')),
        row('consecutive deltas > 1 MiB', longest, '< 4', longest < 4),
        row('entities and subscriptions equal to cycle 1',
            [[c['entities'], c['subscriptions']] for c in cycles], 'equal',
            all(c['entities'] == cycles[0]['entities'] and c['subscriptions'] == cycles[0]['subscriptions'] for c in cycles)),
        row('restored initial rule state each cycle', [c['restoredInitialState'] for c in cycles], 'all true',
            all(c['restoredInitialState'] and c['matchesReplay'] for c in cycles)),
        row('reload ms each cycle', reloads, '<= 500', all(0 <= r <= BUDGET['reloadMax'] for r in reloads)),
    ]


def summarize(results, expected_runs=2):
    """Candidate verdicts. A run whose idle window stayed void after its repeats measured a
    noisy host, not the candidate: it is excluded and reported. A candidate passes only when
    every budgeted row passes in `expected_runs` counted runs on every geometry; it fails on
    any failed row in a counted run; otherwise it is inconclusive."""
    verdicts = {}
    for candidate in CANDIDATES:
        runs = [run for geometry in results.values() for run in geometry.get(candidate, [])]
        if not runs: continue
        counted = [run for run in runs if not run.get('void')]
        failed = sorted({'%s: %s' % (run['geometry'], r['row']) for run in counted for r in run['rows'] if not r['pass']})
        missing = [run for run in runs if run.get('missing')]
        complete = not missing and all(
            len([run for run in counted if run['geometry'] == geometry]) >= expected_runs for geometry in results)
        status = 'fail' if failed else ('pass' if complete else 'inconclusive')
        verdicts[candidate] = {'runs': len(runs), 'countedRuns': len(counted),
                               'voidRuns': sorted('%s run %d' % (run['geometry'], run['run']) for run in runs if run.get('void')),
                               'status': status, 'pass': status == 'pass', 'failedRows': failed, 'missingReports': len(missing)}
    return verdicts


# ---------------------------------------------------------------- orchestration

def main(argv=None):
    args = parse_args(argv)
    if args.summarize_only:
        path = args.evidence.resolve() / 'measurements.json'
        measurements = json.loads(path.read_text())
        measurements['verdicts'] = summarize(measurements['results'], args.runs)
        path.write_text(json.dumps(measurements, indent=2) + '\n')
        print(json.dumps(measurements['verdicts'], indent=2))
        return
    models = args.model or list(MODELS)
    candidates = args.candidate or CANDIDATES
    out = args.evidence.resolve()
    out.mkdir(parents=True, exist_ok=False)
    derived = (args.derived_data or out / 'build').resolve()
    receipt = {'scope': 'Spike 11 dig feasibility: serial, one owned simulator at a time; simulator diagnostics, not device performance',
               'models': models, 'candidates': candidates, 'runs': args.runs, 'geometries': {}, 'commands': []}
    devices = []
    results = {}

    def save():
        (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')

    def run(command, name, timeout=600, check=True, env=None):
        path = out / (name + '.log')
        start = time.monotonic()
        entry = {'command': command, 'log': path.name}
        receipt['commands'].append(entry)
        try:
            with path.open('w') as log:
                result = subprocess.run(command, cwd=REPO, stdout=log, stderr=subprocess.STDOUT, timeout=timeout,
                                        env=None if env is None else {**os.environ, **env})
        except subprocess.TimeoutExpired:
            entry.update(timedOut=True, seconds=round(time.monotonic() - start, 3))
            save()
            raise RuntimeError(name + ' timed out after ' + str(timeout) + ' seconds; see ' + str(path))
        entry.update(exitCode=result.returncode, seconds=round(time.monotonic() - start, 3))
        save()
        if result.returncode and check: raise RuntimeError(name + ' failed; see ' + str(path))
        return path.read_text()

    def source_identity():
        directories = [ROOT, REPO / 'Packages/GameCore', REPO / 'Packages/GamePlatform', REPO / 'Games/DevelopmentContent']
        files = sorted(p for d in directories for p in d.rglob('*') if p.is_file()
                       and '.build' not in p.parts and '__pycache__' not in p.parts and 'evidence' not in p.relative_to(d).parts[:1]
                       and p.suffix in ['.swift', '.py', '.json', '.svg', '.pbxproj', '.xcscheme'])
        hashes = {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
        aggregate = hashlib.sha256(''.join(k + v for k, v in sorted(hashes.items()) if k.startswith('experiments/')).encode()).hexdigest()
        return aggregate, hashes

    def retries(bundle, name):
        """A retried case passes in the summary; read repetitions from the test tree and never hide one."""
        tree = json.loads(run(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(bundle)], name + '-tests-tree'))
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
            try:
                spec = importlib.util.spec_from_file_location('collector', REPO / 'scripts/run-mobile-tests.py')
                collector = importlib.util.module_from_spec(spec); spec.loader.exec_module(collector)
                report['inputFaults'] = collector.scan_input_faults(bundle)
            except Exception as error:
                report['inputFaults'] = {'error': str(error)}
            for case in cases:
                message = name + ' ' + case['test'] + ' ' + str(case['result']) + ' after retry'
                print('RETRIED ' + message, flush=True)
                if os.environ.get('GITHUB_ACTIONS') == 'true': print('::warning title=Dig test retried::' + message, flush=True)
        return report

    def test(device, name, only, expected, timeout, label=None):
        bundle = out / (name + '.xcresult')
        command = ['xcodebuild', '-project', str(ROOT / 'DigFeasibility.xcodeproj'), '-scheme', 'DigFeasibility',
                   '-derivedDataPath', str(derived), 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO',
                   'SWIFT_OPTIMIZATION_LEVEL=-O', '-destination', 'platform=iOS Simulator,id=' + device,
                   '-resultBundlePath', str(bundle), '-parallel-testing-enabled', 'NO', '-test-timeouts-enabled', 'YES',
                   '-maximum-test-execution-time-allowance', '180', '-retry-tests-on-failure', '-test-iterations', '2']
        command += ['-only-testing:' + o for o in only] + ['test-without-building']
        run(command, name, timeout=timeout, check=False, env={'TEST_RUNNER_DIG_RUN_LABEL': label} if label else None)
        result = {'bundle': bundle.name}
        try:
            summary = result['summary'] = json.loads(run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)], name + '-summary'))
            result['passed'] = (summary.get('totalTestCount') == expected and summary.get('passedTests') == expected
                                and not summary.get('failedTests', 0) and not summary.get('skippedTests', 0))
            result['retries'] = retries(bundle, name)
        except Exception as error:
            result.update(passed=False, error=str(error))
        return result

    def fetch(device, label, model):
        """Copies this label's JSON reports out of the app's data container."""
        container = Path(run(['xcrun', 'simctl', 'get_app_container', device, BUNDLE, 'data'], model + '-' + label + '-container').strip())
        target = out / model
        target.mkdir(exist_ok=True)
        copied = {}
        for path in sorted((container / 'Documents').glob('dig-*-' + label + '-*.json')):
            shutil.copy2(path, target / path.name)
            copied[path.name] = json.loads(path.read_text())
        return copied

    try:
        receipt['checkout'] = run(['git', 'rev-parse', 'HEAD'], 'checkout').strip()
        status = run(['git', 'status', '--porcelain', '--untracked-files=all'], 'working-tree')
        aggregate, hashes = source_identity()
        receipt['sourceIdentity'] = {'head': receipt['checkout'], 'dirty': bool(status.strip()),
                                     'experimentSourcesSHA256': aggregate, 'files': len(hashes)}
        receipt['workingTree'] = status.strip().splitlines()
        receipt['inputsBefore'] = hashes
        receipt['toolchain'] = run(['xcodebuild', '-version'], 'toolchain').strip()
        receipt['host'] = {'model': run(['sysctl', '-n', 'hw.model'], 'host-model').strip(),
                           'cpu': run(['sysctl', '-n', 'machdep.cpu.brand_string'], 'host-cpu').strip(),
                           'os': run(['sw_vers'], 'host-os').strip()}
        runtimes = json.loads(run(['xcrun', 'simctl', 'list', 'runtimes', '-j'], 'runtimes'))
        available = [r for r in runtimes['runtimes'] if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')
                     and int(r['version'].split('.')[0]) >= 18]
        requested = os.environ.get('GAMECORE_SIM_RUNTIME_VERSION')
        if requested: available = [r for r in available if r['version'] == requested]
        if not available: raise RuntimeError('No available iOS simulator runtime >=18 matching ' + (requested or 'installed inventory'))
        runtime = max(available, key=lambda r: tuple(int(i) for i in r['version'].split('.')))
        receipt['runtime'] = {k: runtime[k] for k in ['identifier', 'version', 'buildversion']}
        run([sys.executable, str(ROOT / 'scripts/generate-project.py'), '--check'], 'project-check')
        pure = run(['swift', 'test', '--package-path', str(ROOT)], 'pure-tests', timeout=900)
        receipt['pureTests'] = [line.strip() for line in pure.splitlines() if 'Executed' in line][-1:]
        common = ['xcodebuild', '-project', str(ROOT / 'DigFeasibility.xcodeproj'), '-scheme', 'DigFeasibility', '-derivedDataPath', str(derived),
                  '-jobs', '4', 'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO', '-destination', 'generic/platform=iOS Simulator']
        run(common + ['-configuration', 'Release', 'build'], 'build-release', timeout=1200)
        run(common + ['SWIFT_OPTIMIZATION_LEVEL=-O', 'build-for-testing'], 'build-debug', timeout=1200)
        receipt['configuration'] = 'Debug (DEBUG instrumentation) with SWIFT_OPTIMIZATION_LEVEL=-O for every target, including packages; Release built separately'
        for model in models:
            device = run(['xcrun', 'simctl', 'create', 'GameCore Spike11 owned ' + model, MODELS[model], runtime['identifier']], model + '-create').strip()
            devices.append(device)
            geometry = receipt['geometries'][model] = {'deviceUUID': device, 'tests': {}}
            run(['xcrun', 'simctl', 'boot', device], model + '-boot')
            run(['xcrun', 'simctl', 'bootstatus', device, '-b'], model + '-bootstatus')
            only = ['DigFeasibilityTests'] + ['DigFeasibilityUITests/' + CLASS[c] + 'BehaviourTests' for c in candidates]
            geometry['tests']['behaviour'] = test(device, model + '-behaviour', only,
                                                  UNIT_TESTS + sum(BEHAVIOUR_TESTS[c] for c in candidates), 3600,
                                                  label=model + '-behaviour')
            geometry['behaviourReports'] = sorted(fetch(device, model + '-behaviour', model))
            results[model] = {}
            for index in range(1, args.runs + 1):
                for candidate in candidates:
                    attempts = []
                    for attempt in range(1, 4):
                        label = '%s-run%d-a%d' % (model, index, attempt)
                        name = '%s-%s-run%d-a%d' % (model, candidate, index, attempt)
                        outcome = test(device, name, ['DigFeasibilityUITests/' + CLASS[candidate] + 'TimingTests'], 2, 900, label=label)
                        reports = fetch(device, label, model)
                        found = {r['kind']: (name, r) for name, r in reports.items() if r.get('candidate') == candidate}
                        timing = found.get('timing', (None, None))[1]
                        cycles = found.get('prefix', (None, None))[1]
                        rows, void = evaluate_timing(timing) if timing else ([row('timing report', None, 'present', False)], False)
                        rows += evaluate_cycles(cycles) if cycles else [row('restart cycle report', None, 'present', False)]
                        attempts.append({'attempt': attempt, 'test': outcome, 'void': void})
                        if not void: break
                    geometry['tests']['%s-run%d' % (candidate, index)] = attempts
                    results[model].setdefault(candidate, []).append(
                        {'geometry': model, 'run': index, 'attempts': len(attempts), 'void': void, 'testsPassed': outcome['passed'],
                         'missing': timing is None or cycles is None, 'rows': rows,
                         'reports': sorted(name for name, _ in found.values())})
                    (out / 'measurements.json').write_text(json.dumps({'budgets': BUDGET, 'results': results}, indent=2) + '\n')
            for action in ['shutdown', 'delete']: run(['xcrun', 'simctl', action, device], model + '-' + action)
            devices.remove(device)
        verdicts = summarize(results, args.runs)
        receipt['verdicts'] = verdicts
        tests_ok = all(t['passed'] if isinstance(t, dict) else all(a['test']['passed'] for a in t)
                       for g in receipt['geometries'].values() for t in g['tests'].values())
        receipt['testsPassed'] = tests_ok
        receipt['status'] = 'passed' if tests_ok else 'failed'
    except Exception as error:
        receipt['status'] = 'failed'
        receipt['error'] = str(error)
        raise
    finally:
        for device in list(devices):
            for action in ['shutdown', 'delete']:
                try: run(['xcrun', 'simctl', action, device], 'cleanup-' + action + '-' + device)
                except Exception as error:
                    receipt['cleanupError'] = str(error)
                    receipt['status'] = 'failed'
        try:
            receipt['inputsAfter'] = source_identity()[1]
            if receipt.get('inputsBefore') != receipt['inputsAfter']:
                receipt['sourceIdentityError'] = 'Inputs changed during verification'
                receipt['status'] = 'failed'
        except Exception as error:
            receipt['sourceIdentityError'] = str(error)
        (out / 'measurements.json').write_text(json.dumps({'budgets': BUDGET, 'results': results,
                                                           'verdicts': summarize(results, args.runs)}, indent=2) + '\n')
        save()
    print(json.dumps({'status': receipt['status'], 'verdicts': receipt.get('verdicts')}, indent=2))
    if receipt.get('status') != 'passed':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
