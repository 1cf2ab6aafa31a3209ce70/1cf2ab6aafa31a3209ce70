#!/usr/bin/env python3
"""Check run-mobile-tests.py orchestration with mocked commands (no simulator, no build).

Covers the minimum-runtime job's contract and the network gate:
  - with GAMECORE_SIM_RUNTIME_VERSION=18.0 and --model ipad9 (and iphone12)
    every title runs on an owned iOS 18.0 device of that geometry, with the
    retry flags, and every owned device is shut down and deleted;
  - a retried case whose first run hit the N10 launch timeout is reported and
    classified as explained;
  - the network gate fails the run on an app-originated socket or networking
    log entry, keeps its evidence when tests fail first, and passes a clean run;
  - a missing iOS 18.0 runtime fails before any device is created, and a full
    disk cannot skip owned simulator cleanup;
  - the workflow runs the minimum-runtime job on both geometries with iOS 18.0.
"""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import sys
import tempfile
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parent
ROOT = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))
import network_observation  # noqa: E402
import titles as title_manifests  # noqa: E402

LAUNCH_TIMEOUT = "Timed out while launching application via Xcode"
OUTBOUND = "p{pid}\ncApp\nf9\ntIPv4\nPTCP\nn10.0.0.2:50000->93.184.215.14:443\nTST=ESTABLISHED\n"
CFNETWORK = json.dumps({"processID": 4242, "subsystem": "com.apple.CFNetwork", "category": "Summary",
                        "eventMessage": "Task <1>.<1> summary for task success"})
ACTIVITY = json.dumps({"processID": 4242, "subsystem": "com.apple.network", "category": "activity",
                       "eventMessage": "Create activity from XPC object <nw_activity 50:1>"})
RUNTIMES = {"runtimes": [
    {"isAvailable": True, "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5", "version": "26.5", "buildversion": "23F"},
    {"isAvailable": True, "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-0", "version": "18.0", "buildversion": "22A3354"},
    {"isAvailable": True, "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-17-4", "version": "17.4", "buildversion": "21E"}]}


def load_runner():
    spec = importlib.util.spec_from_file_location("mobile_runner_under_test", SCRIPTS / "run-mobile-tests.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Harness:
    """A scripted simulator host: every command the runner issues is answered here."""

    def __init__(self, root, scenario):
        self.root, self.scenario = root, scenario
        self.calls, self.created, self.devices = [], [], {}
        self.container = (root / "container").resolve()
        self.container.mkdir()
        self.counter = 0

    def run(self, command, *, log=None, timeout=300):
        if self.scenario == "unwritable-cleanup-log" and log and log.name.endswith(("-shutdown.log", "-delete.log")):
            raise OSError(28, "No space left on device", str(log))  # The real run opens its log first.
        self.calls.append(list(command))
        text = ""
        if command[:2] == ["git", "rev-parse"]:
            text = "mock-checkout"
        elif command[:2] == ["git", "status"]:
            text = ""
        elif command[:2] == ["xcodebuild", "-version"]:
            text = "Xcode 26.6\nBuild version 17F113"
        elif "runtimes" in command:
            inventory = json.loads(json.dumps(RUNTIMES))
            if self.scenario == "missing-runtime":
                inventory["runtimes"] = [r for r in inventory["runtimes"] if r["version"] != "18.0"]
            text = json.dumps(inventory)
        elif command[:3] == ["xcrun", "simctl", "create"]:
            self.counter += 1
            text = f"OWNED-{self.counter:04d}"
            self.created.append(text)
            self.devices[text] = {"type": command[-2], "runtime": command[-1], "name": command[3]}
        elif "build-for-testing" in command:
            target = command[command.index("-scheme") + 1]
            derived = Path(command[command.index("-derivedDataPath") + 1])
            info = derived / f"Build/Products/Debug-iphonesimulator/{target}.app/Info.plist"
            info.parent.mkdir(parents=True, exist_ok=True)
            with info.open("wb") as stream:
                plistlib.dump({"CFBundleExecutable": target, "CFBundleIdentifier": f"local.gamecore.{target}"}, stream)
        elif "test-without-building" in command:
            text = self.test(command, log)
        elif "get_app_container" in command:
            text = str(self.container)
        elif command[:5] == ["xcrun", "xcresulttool", "get", "test-results", "tests"]:
            repetitions = [{"nodeType": "Repetition", "name": "First Run", "result": "Failed",
                            "children": [{"nodeType": "Failure Message", "name": f"{LAUNCH_TIMEOUT} (Underlying Error)"}]},
                           {"nodeType": "Repetition", "name": "Retry 1", "result": "Passed"}]
            case = {"nodeType": "Test Case", "nodeIdentifier": "AppUITests/testFlow()", "result": "Passed",
                    "children": repetitions if self.scenario == "retried-launch-timeout" else []}
            text = json.dumps({"testNodes": [{"nodeType": "Test Plan", "children": [case]}]})
        if log:
            if text and not log.exists():
                log.write_text(text)
            elif not log.exists():
                log.write_text("")
            return ""
        return text

    def test(self, command, log):
        destination = command[command.index("-destination") + 1]
        device = destination.rsplit("=", 1)[1]
        bundle = Path(command[command.index("-resultBundlePath") + 1])
        bundle.mkdir(parents=True, exist_ok=True)
        if any("testSimulatorRestartPersistence" in part for part in command):
            self.restart(log)
            return ""
        self.devices[device]["tested"] = True
        if self.scenario == "test-failure":
            raise RuntimeError("Command failed (65): xcodebuild test-without-building")
        return "** TEST EXECUTE SUCCEEDED **"

    def restart(self, log):
        root = self.container / "Library/Application Support/GameCoreSaves/epic04-restart-proof"
        token = "6F9619FF-8B86-D011-B42D-00CF4FC964FF"
        label = log.stem.rsplit("-", 1)[-1]
        if label in ("prepare", "fresh"):
            (root / "restart-proof").mkdir(parents=True, exist_ok=True)
            (root / "restart-proof/save.json").write_text("{}")
            (root / "prepared.marker").write_text(token)
            phase = "prepared"
        else:
            shutil.rmtree(root)
            phase = "restored"
        receipt = {"token": token, "root": str(root), "sandboxRoot": str(self.container), "phase": phase}
        log.write_text("Test Case '-[SavePersistenceTests testSimulatorRestartPersistence]' passed (1.0 seconds).\n"
                       f"GAMECORE_RESTART_RECEIPT {json.dumps(receipt)}\n")

    def observer_run(self, command, timeout=30):
        """Answers for the network observer's own ps, lsof and log commands."""
        if command[0] == "ps":
            lines = ["1 /sbin/launchd"]
            for device in self.created:
                for title in title_manifests.load():
                    lines.append(f"4242 /Users/ci/Library/Developer/CoreSimulator/Devices/{device}/data/Containers/"
                                 f"Bundle/Application/0A0B0C0D-0000-1111-2222-333344445555/"
                                 f"{title.target}.app/{title.target}")
            return 0, "\n".join(lines), ""
        if command[0] == "lsof":
            if self.scenario == "network-socket":
                return 0, OUTBOUND.format(pid=4242), ""
            return 1, "", ""
        if "log" in command:
            rows = [ACTIVITY]
            if self.scenario == "network-log":
                rows.append(CFNETWORK)
            return 0, "\n".join(rows) + "\n", ""
        raise AssertionError(command)


def run_scenario(scenario, arguments, environment):
    with tempfile.TemporaryDirectory(prefix="gamecore-runner-harness-") as temporary:
        root = Path(temporary)
        output = root / "evidence"
        harness = Harness(root, scenario)
        runner = load_runner()
        runner.run = harness.run
        stdout, error = io.StringIO(), None
        environ = {key: value for key, value in os.environ.items() if key not in ("GITHUB_ACTIONS", "GAMECORE_SIM_OWNER")}
        environ.update(environment)
        with patch.object(network_observation, "_run", harness.observer_run), \
                patch.dict(os.environ, environ, clear=True), \
                patch.object(sys, "argv", ["run-mobile-tests.py", str(output)] + arguments), \
                contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(io.StringIO()):
            try:
                runner.main()
            except (RuntimeError, ValueError, OSError) as exception:
                error = str(exception)
        evidence = {path.relative_to(output).as_posix(): path for path in output.rglob("*") if path.is_file()} \
            if output.exists() else {}
        reports = {name: json.loads(path.read_text()) for name, path in evidence.items() if name.endswith("-network.json")}
        retries = {name: json.loads(path.read_text()) for name, path in evidence.items() if name.endswith("-retries.json")}
        return harness, error, stdout.getvalue(), reports, retries


def check_cleanup(harness, scenario):
    for action in ("shutdown", "delete"):
        cleaned = {call[-1] for call in harness.calls if call[:3] == ["xcrun", "simctl", action]}
        assert set(harness.created) <= cleaned, (scenario, action, harness.created, cleaned)


def main():
    targets = [title.target for title in title_manifests.load()]
    floor = {"GAMECORE_SIM_RUNTIME_VERSION": "18.0"}

    for model, device_type in (("ipad9", "iPad-9th-generation"), ("iphone12", "iPhone-12")):
        harness, error, stdout, reports, _ = run_scenario(f"minimum-runtime-{model}", ["--model", model], floor)
        assert error is None, (model, error)
        assert len(harness.created) == len(targets), (model, harness.created)
        for device, details in harness.devices.items():
            assert details["runtime"] == "com.apple.CoreSimulator.SimRuntime.iOS-18-0", details
            assert details["type"].endswith(device_type) and details.get("tested"), details
        tests = [call for call in harness.calls if "test-without-building" in call
                 and not any("testSimulatorRestartPersistence" in part for part in call)]
        assert len(tests) == len(targets) and all("-retry-tests-on-failure" in call
                                                  and call[call.index("-test-iterations") + 1] == "2" for call in tests)
        assert {call[call.index("-scheme") + 1] for call in tests} == set(targets)
        assert len(reports) == len(targets) and all(r["passed"] and r["systemOwned"] for r in reports.values()), reports
        assert stdout.count("NETWORK PASS") == len(targets) and "Selected iOS 18.0" in stdout, stdout
        check_cleanup(harness, model)
        print(f"PASS every title ({', '.join(targets)}) on {model} with iOS 18.0: retries on, network gate passed, "
              f"{len(harness.created)} owned devices deleted")

    harness, error, stdout, _, retries = run_scenario("retried-launch-timeout", ["--model", "ipad9", "--title", "BlockTitle"], floor)
    assert error is None, error
    report = retries["ipad9-retries.json"]
    assert report["launchTimeouts"] == 1 and report["cases"][0]["result"] == "Passed", report
    assert "RETRIED ipad9" in stdout and "INPUT FAULTS ipad9: 1 for 1 failed run(s); each failed run has a matching" in stdout, stdout
    check_cleanup(harness, "retried-launch-timeout")
    print("PASS N10 launch timeout on ipad9: retried case reported and classified as explained")

    for scenario, needle in (("network-socket", "93.184.215.14:443"), ("network-log", "CFNetwork:Summary")):
        harness, error, stdout, reports, _ = run_scenario(scenario, ["--model", "ipad9", "--title", "BlockTitle"], floor)
        assert error and "NETWORK FAIL BlockTitle ipad9" in error and needle in error, (scenario, error)
        assert not reports["ipad9-network.json"]["passed"], scenario
        assert "passed for" not in stdout, scenario
        check_cleanup(harness, scenario)
        print(f"PASS seeded {scenario} violation fails the run: {needle}")

    harness, error, stdout, reports, _ = run_scenario("test-failure", ["--model", "iphone12", "--title", "BlockTitle"], floor)
    assert error and "Command failed (65)" in error, error
    assert reports["iphone12-network.json"]["passed"] and "(after another failure)" in stdout, stdout
    check_cleanup(harness, "test-failure")
    print("PASS test failure keeps the network evidence without replacing the test error")

    harness, error, _, _, _ = run_scenario("unwritable-cleanup-log", ["--model", "ipad9", "--title", "BlockTitle"], floor)
    assert error is None, error
    check_cleanup(harness, "unwritable-cleanup-log")
    print("PASS a full disk cannot skip owned simulator shutdown and deletion")

    harness, error, _, _, _ = run_scenario("missing-runtime", ["--model", "ipad9"], floor)
    assert error and "No available iOS simulator runtime >=18 matching 18.0" in error and not harness.created, error
    print("PASS missing iOS 18.0 runtime fails before any device is created")

    workflow = (ROOT / ".github/workflows/mobile.yml").read_text()
    job = re.search(r"\n  minimum-runtime:\n(.*?)(?=\n  [A-Za-z0-9_-]+:\n|\Z)", workflow, re.S)
    assert job, "minimum-runtime job missing"
    body = job.group(1)
    assert re.search(r"matrix:\s*\n\s*model: \[iphone12, ipad9\]", body), "minimum-runtime must cover both geometries"
    assert "GAMECORE_SIM_RUNTIME_VERSION: '18.0'" in body, "minimum-runtime must pin iOS 18.0"
    assert re.search(r'test-mobile\.sh "\$RUNNER_TEMP/minimum-runtime-ui" --model "\$MODEL"', body) and "--title" not in body, \
        "minimum-runtime must run every title on the matrix geometry"
    assert "*-network.json" in body and "*-retries.json" in body, "minimum-runtime must retain network and retry evidence"
    print("PASS workflow runs every title on iphone12 and ipad9 with iOS 18.0 and keeps network evidence")
    print("Mobile runner orchestration, minimum-runtime coverage and network gate checked with mocked commands")


if __name__ == "__main__":
    main()
