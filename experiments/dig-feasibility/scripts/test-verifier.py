#!/usr/bin/env python3
"""Check verify.py orchestration, budget evaluation and cleanup with mocked commands (no native processes)."""
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
from unittest.mock import patch

script = Path(__file__).with_name('verify.py')
for key in ['GAMECORE_SIM_RUNTIME_VERSION', 'GITHUB_ACTIONS']: os.environ.pop(key, None)


def stats(p95, p99=None, maximum=None, count=600, share=0.0):
    return {'count': count, 'p50': p95 / 2, 'p95': p95, 'p99': p99 or p95, 'max': maximum or p95, 'over33': 0, 'over33Share': share}


def timing_report(candidate, idle_p95=17.0, mesh_p95=2.0):
    lag = {'commands': 600, 'changing': 600, 'meshLagMs': stats(15), 'meshUnresolved': 0}
    if candidate != 'sprite': lag.update(collisionLagMs=stats(70, maximum=90), collisionUnresolved=0)
    fixture = candidate != 'voxel'
    return {'candidate': candidate, 'kind': 'timing',
            'windows': {'I': stats(idle_p95, 20), 'S': stats(18, 22, count=3600)},
            'mesh': {'S': {'jobs': 600, 'totalMs': stats(mesh_p95), 'mainActorMs': stats(mesh_p95), 'extractMs': stats(0.1), 'chunksMax': 4}},
            'collision': {'S': {'chunkMs': stats(18)}}, 'lag': {'S': lag},
            'summary': {'scoreAfterS': 24 if fixture else 26, 'scoreAfterB': 28 if fixture else 30, 'meetsFixture': fixture,
                        'matchesReplay': True, 'refused': 0, 'controlsCollected': [] if fixture else [32, 35]}}


def prefix_report(candidate):
    return {'candidate': candidate, 'kind': 'prefix',
            'cycles': [{'cycle': i, 'footprintMiB': 70 + 0.2 * i, 'peakMiB': 72, 'entities': 60, 'subscriptions': 2,
                        'restoredInitialState': True, 'matchesReplay': True, 'reloadMs': 300} for i in range(1, 6)]}


results = []
scenarios = ['pass', 'retried-pass', 'void-then-pass', 'always-void', 'budget-miss', 'boot-failure', 'test-timeout', 'missing-runtime']
for scenario in scenarios:
    with tempfile.TemporaryDirectory(prefix='gamecore-s11-harness-') as temp:
        out = Path(temp) / 'evidence'
        container = Path(temp) / 'container'
        (container / 'Documents').mkdir(parents=True)
        calls = []
        voided = set()

        def fake(command, **kwargs):
            calls.append(command)
            code, content = 0, ''
            env = kwargs.get('env') or {}
            if command[:2] == ['git', 'rev-parse']: content = 'mock-checkout\n'
            if 'runtimes' in command:
                content = json.dumps({'runtimes': [{'isAvailable': True, 'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-26-0',
                                                    'version': '26.0', 'buildversion': 'mock'}]})
            if command[:2] == ['swift', 'test']: content = 'Executed 33 tests, with 0 failures (0 unexpected)\n'
            if 'create' in command: content = 'FAKE-OWNED-' + command[-2].rsplit('.', 1)[-1] + '\n'
            if 'get_app_container' in command: content = str(container) + '\n'
            if scenario == 'boot-failure' and 'boot' in command: code = 1
            if 'test-without-building' in command:
                if scenario == 'test-timeout': raise subprocess.TimeoutExpired(command, kwargs['timeout'])
                label = env.get('TEST_RUNNER_DIG_RUN_LABEL', 'none')
                for option in command:
                    if option.endswith('TimingTests'):
                        candidate = {'Heightfield': 'heightfield', 'LowLevel': 'lowlevel', 'Voxel': 'voxel', 'Sprite': 'sprite'}[
                            option.split('/')[-1][:-len('TimingTests')]]
                        idle = 30.0 if scenario == 'always-void' and candidate == 'sprite' else 17.0
                        if scenario == 'void-then-pass' and (candidate, label.split('-a')[0]) not in voided:
                            voided.add((candidate, label.split('-a')[0]))
                            idle = 30.0
                        mesh = 10.0 if scenario == 'budget-miss' and candidate == 'voxel' else 2.0
                        for kind, report in [('timing', timing_report(candidate, idle, mesh)), ('prefix', prefix_report(candidate))]:
                            (container / 'Documents' / ('dig-%s-%s-%s-%s.json' % (candidate, label, kind, kind))).write_text(json.dumps(report))
            if 'summary' in command and 'test-results' in command:
                bundle = command[command.index('--path') + 1]
                timing = any(c for c in calls if 'test-without-building' in c and bundle in c and any(o.endswith('TimingTests') for o in c))
                total = 2 if timing else 5 + 5 + 2 + 5 + 7
                content = json.dumps({'totalTestCount': total, 'passedTests': total, 'failedTests': 0, 'skippedTests': 0})
            if 'tests' in command and 'test-results' in command:
                repetitions = [{'nodeType': 'Repetition', 'name': 'First Run', 'result': 'Failed'}, {'nodeType': 'Repetition', 'name': 'Retry 1', 'result': 'Passed'}]
                case = {'nodeType': 'Test Case', 'name': 'testSample()', 'result': 'Passed', 'children': repetitions if scenario == 'retried-pass' else []}
                content = json.dumps({'testNodes': [{'nodeType': 'Test Plan', 'children': [case]}]})
            kwargs['stdout'].write(content)
            return subprocess.CompletedProcess(command, code)

        error = None
        pin = {'GAMECORE_SIM_RUNTIME_VERSION': '18.0'} if scenario == 'missing-runtime' else {}
        with patch('subprocess.run', side_effect=fake), patch('subprocess.Popen', side_effect=OSError('mocked')), \
                patch.dict(os.environ, pin), patch.object(sys, 'argv', [str(script), str(out)]):
            try: runpy.run_path(str(script), run_name='__main__')
            except (RuntimeError, SystemExit) as exception: error = type(exception).__name__
        receipt = json.loads((out / 'receipt.json').read_text())
        passing = scenario in {'pass', 'retried-pass', 'void-then-pass', 'always-void', 'budget-miss'}
        assert receipt['status'] == ('passed' if passing else 'failed'), (scenario, receipt.get('error'))
        assert bool(error) == (not passing), scenario
        created = {'FAKE-OWNED-' + c[-2].rsplit('.', 1)[-1] for c in calls if 'simctl' in c and 'create' in c}
        assert bool(created) == (scenario != 'missing-runtime'), scenario
        for action in ['shutdown', 'delete']:
            assert {c[-1] for c in calls if 'simctl' in c and action in c} >= created, (scenario, action)
        assert receipt['sourceIdentity']['head'] == 'mock-checkout' and len(receipt['sourceIdentity']['experimentSourcesSHA256']) == 64
        if passing:
            assert set(receipt['geometries']) == {'iphone12', 'ipad9'}, scenario
            measurements = json.loads((out / 'measurements.json').read_text())
            verdicts = measurements['verdicts']
            assert verdicts['heightfield']['pass'] and verdicts['lowlevel']['pass'], (scenario, verdicts)
            # A run void after three attempts is excluded, never a candidate failure.
            assert verdicts['sprite']['status'] == ('inconclusive' if scenario == 'always-void' else 'pass'), (scenario, verdicts['sprite'])
            assert len(verdicts['sprite']['voidRuns']) == (4 if scenario == 'always-void' else 0), scenario
            # The voxel fixture deviation fails the correctness row; a budget miss adds the mesh row.
            assert not verdicts['voxel']['pass'] and any('score after S / B' in r for r in verdicts['voxel']['failedRows']), scenario
            assert any('mesh total' in r for r in verdicts['voxel']['failedRows']) == (scenario == 'budget-miss'), scenario
            attempts = [len(a) for g in receipt['geometries'].values() for k, a in g['tests'].items() if k != 'behaviour']
            assert max(attempts) == {'void-then-pass': 2, 'always-void': 3}.get(scenario, 1), (scenario, attempts)
            assert len(list((out / 'iphone12').glob('dig-*.json'))) > 0
        timed_out = [c for c in receipt['commands'] if c.get('timedOut')]
        assert len(timed_out) == (scenario == 'test-timeout'), scenario
        retried = [g['tests']['behaviour']['retries']['cases'] for g in receipt['geometries'].values() if 'retries' in g['tests'].get('behaviour', {})]
        assert any(retried) == (scenario == 'retried-pass'), scenario
        if scenario == 'pass':
            # Offline re-evaluation reads only measurements.json and starts nothing.
            calls.clear()
            with patch('subprocess.run', side_effect=fake), patch.object(sys, 'argv', [str(script), str(out), '--summarize-only']):
                runpy.run_path(str(script), run_name='__main__')
            assert not calls and json.loads((out / 'measurements.json').read_text())['verdicts']['heightfield']['status'] == 'pass'
        results.append({'scenario': scenario, 'status': receipt['status'], 'exception': error, 'ownedCleanupAttempted': True})
print(json.dumps(results, indent=2))
