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
for scenario in ['pass', 'restore-failure', 'boot-failure', 'skipped-test']:
    with tempfile.TemporaryDirectory(prefix='gamecore-s06-harness-') as temp:
        out = Path(temp)/'evidence'
        calls = []
        def fake(command, **kwargs):
            calls.append(command)
            code, content = 0, ''
            if command[:2] == ['git', 'rev-parse']: content = 'mock-checkout\n'
            if 'runtimes' in command:
                content = json.dumps({'runtimes':[{'isAvailable':True, 'identifier':'com.apple.CoreSimulator.SimRuntime.iOS-26-0', 'version':'26.0', 'buildversion':'mock'}]})
            if 'create' in command: content = 'FAKE-OWNED-UUID\n'
            if 'summary' in command:
                content = json.dumps({'totalTestCount':7, 'passedTests':7, 'failedTests':0, 'skippedTests':1 if scenario == 'skipped-test' else 0, 'runtimeWarnings':[], 'expectedFailures':0})
            if scenario == 'boot-failure' and 'boot' in command: code = 1
            if scenario == 'restore-failure' and len(command) == 2 and command[-1].endswith('generate-project.py'): code = 1
            kwargs['stdout'].write(content)
            return subprocess.CompletedProcess(command, code)
        error = None
        with patch('subprocess.run', side_effect=fake), patch.object(sys, 'argv', [str(script), str(out)]):
            try: runpy.run_path(str(script), run_name='__main__')
            except (RuntimeError, SystemExit) as exception: error = type(exception).__name__
        receipt = json.loads((out/'receipt.json').read_text())
        assert receipt['status'] == ('passed' if scenario == 'pass' else 'failed')
        assert bool(error) == (scenario != 'pass')
        assert any('shutdown' in c for c in calls) and any('delete' in c for c in calls)
        results.append({'scenario':scenario, 'status':receipt['status'], 'exception':error, 'ownedCleanupAttempted':True})
print(json.dumps(results, indent=2))
