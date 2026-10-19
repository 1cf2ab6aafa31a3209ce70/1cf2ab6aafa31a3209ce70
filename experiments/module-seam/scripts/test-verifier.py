#!/usr/bin/env python3
"""Check failure and cleanup orchestration without starting native processes."""
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
from unittest.mock import patch

script = Path(__file__).with_name('verify.py')
results = []
for scenario in ['pass', 'retried-pass', 'restore-failure', 'boot-failure', 'skipped-test', 'test-timeout']:
    with tempfile.TemporaryDirectory(prefix='gamecore-s06-harness-') as temp:
        out = Path(temp)/'evidence'
        calls = []
        def fake(command, **kwargs):
            calls.append(command)
            code, content = 0, ''
            if command[:2] == ['git', 'rev-parse']: content = 'mock-checkout\n'
            if 'runtimes' in command:
                content = json.dumps({'runtimes':[{'isAvailable':True, 'identifier':'com.apple.CoreSimulator.SimRuntime.iOS-26-0', 'version':'26.0', 'buildversion':'mock'}]})
            if 'create' in command: content = 'FAKE-OWNED-' + command[-2].rsplit('.', 1)[-1] + '\n'
            if 'summary' in command:
                content = json.dumps({'totalTestCount':7, 'passedTests':7, 'failedTests':0, 'skippedTests':1 if scenario == 'skipped-test' else 0, 'runtimeWarnings':[], 'expectedFailures':0})
            if 'tests' in command and 'test-results' in command:
                repetitions = [{'nodeType':'Repetition', 'name':'First Run', 'result':'Failed'}, {'nodeType':'Repetition', 'name':'Retry 1', 'result':'Passed'}]
                case = {'nodeType':'Test Case', 'name':'testSample()', 'result':'Passed', 'children':repetitions if scenario == 'retried-pass' else []}
                content = json.dumps({'testNodes':[{'nodeType':'Test Plan', 'children':[case]}]})
            if scenario == 'test-timeout' and 'test-without-building' in command:
                raise subprocess.TimeoutExpired(command, kwargs['timeout'])
            if scenario == 'boot-failure' and 'boot' in command: code = 1
            if scenario == 'restore-failure' and len(command) == 2 and command[-1].endswith('generate-project.py'): code = 1
            kwargs['stdout'].write(content)
            return subprocess.CompletedProcess(command, code)
        error = None
        # The input-fault scan uses Popen; refuse it so a retry is classified without native processes.
        with patch('subprocess.run', side_effect=fake), patch('subprocess.Popen', side_effect=OSError('mocked')), \
                patch.object(sys, 'argv', [str(script), str(out)]):
            try: runpy.run_path(str(script), run_name='__main__')
            except (RuntimeError, SystemExit) as exception: error = type(exception).__name__
        receipt = json.loads((out/'receipt.json').read_text())
        assert receipt['status'] == ('passed' if scenario.endswith('pass') else 'failed'), scenario
        assert bool(error) == (not scenario.endswith('pass')), scenario
        created = {'FAKE-OWNED-' + c[-2].rsplit('.', 1)[-1] for c in calls if 'simctl' in c and 'create' in c}
        assert created
        for action in ['shutdown', 'delete']:
            assert {c[-1] for c in calls if 'simctl' in c and action in c} >= created, (scenario, action)
        if scenario.endswith('pass'):
            assert set(receipt['geometries']) == {'iphone12', 'ipad9'}
        timed_out = [c for c in receipt['commands'] if c.get('timedOut')]
        assert len(timed_out) == (scenario == 'test-timeout') and all('test-without-building' in c['command'] for c in timed_out), scenario
        retried = [m['retries']['cases'] for g in receipt['geometries'].values() for m in g['modules'].values() if 'retries' in m]
        assert any(retried) == (scenario == 'retried-pass'), scenario
        results.append({'scenario':scenario, 'status':receipt['status'], 'exception':error, 'ownedCleanupAttempted':True})
print(json.dumps(results, indent=2))
