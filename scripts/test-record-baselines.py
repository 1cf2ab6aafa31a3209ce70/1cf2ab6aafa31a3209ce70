#!/usr/bin/env python3
"""Check record-baselines.py with mocked commands, and compile its probe for real.

The recorder is not a pass/fail gate on numbers, but it must never write a
baseline from missing data. This proves that it:
  - writes the documented JSON format (source identity, toolchain, runtime,
    host, instrumentation, per-title package size and per-geometry launch,
    scene-update and memory observations) from scripted probe rows;
  - keeps update gaps of a second or more out of the interval statistics and
    lists them;
  - fails, after deleting its owned simulator, when the gameplay test fails
    (with its N06/N09 classification) or the probe reports no launch, no
    scene updates or no memory samples;
  - injects the probe only into the UI target app through the xctestrun.
The probe library itself is compiled for the iOS Simulator and must link
nothing beyond Foundation, libobjc and libSystem, so loading it into other
simulator processes is harmless.
"""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parent
ROOT = SCRIPTS.parent
INTERACTION_PID = 7000


def load_recorder():
    spec = importlib.util.spec_from_file_location("record_baselines_under_test", SCRIPTS / "record-baselines.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def row(pid, message):
    return json.dumps({"processID": pid, "subsystem": "gamecore.baseline-probe", "category": "probe",
                       "eventMessage": message})


class Harness:
    def __init__(self, root, scenario):
        self.root, self.scenario = root, scenario
        self.calls, self.created, self.launches = [], [], []
        self.xctestrun = None

    def run(self, command, *, log=None, timeout=300):
        self.calls.append(list(command))
        text = ""
        if command[:2] == ["git", "rev-parse"]:
            text = "mock-checkout"
        elif "runtimes" in command:
            text = json.dumps({"runtimes": [{"isAvailable": True, "version": "26.5", "buildversion": "23F",
                                             "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5"}]})
        elif command[:2] == ["xcodebuild", "-version"]:
            text = "Xcode 26.6\nBuild version 17F113"
        elif command[:3] == ["xcrun", "swift", "--version"]:
            text = "swift-driver version: 1.0\nApple Swift version 6.3 (swiftlang-6.3)\nTarget: arm64-apple-macosx26.0"
        elif "--show-sdk-version" in command:
            text = "26.5"
        elif command[0] in ("sysctl", "sw_vers"):
            text = {"hw.model": "Mac16,10", "machdep.cpu.brand_string": "Apple M4", "hw.memsize": "17179869184",
                    "-productVersion": "26.4", "-buildVersion": "25E"}[command[-1]]
        elif "-dynamiclib" in command:
            Path(command[command.index("-o") + 1]).write_bytes(b"probe")
        elif "build-for-testing" in command:
            self.build_for_testing(command)
        elif "-configuration" in command and command[command.index("-configuration") + 1] == "Release":
            target = command[command.index("-scheme") + 1]
            app = Path(command[command.index("-derivedDataPath") + 1]) / f"Build/Products/Release-iphoneos/{target}.app"
            (app / "Assets").mkdir(parents=True)
            with (app / "Info.plist").open("wb") as stream:
                plistlib.dump({"CFBundleExecutable": target}, stream)
            (app / target).write_bytes(b"\0" * 4096)
            (app / "Assets/data.bin").write_bytes(b"A" * 10000)
        elif command[:3] == ["xcrun", "simctl", "create"]:
            text = f"OWNED-{len(self.created) + 1}"
            self.created.append(text)
        elif command[0] == "env" and "launch" in command:
            pid = 6000 + len(self.launches)
            self.launches.append(pid)
            text = f"{command[-1]}: {pid}"
        elif "-xctestrun" in command:
            self.xctestrun = Path(command[command.index("-xctestrun") + 1])
            Path(command[command.index("-resultBundlePath") + 1]).mkdir()
            if self.scenario == "interaction-failure":
                raise RuntimeError("Command failed (65): xcodebuild test-without-building")
        elif "log" in command and "show" in command:
            log.write_text(self.probe_rows() + "\n")
            return ""
        if log:
            log.write_text(text)
            return ""
        return text

    def build_for_testing(self, command):
        target = command[command.index("-scheme") + 1]
        products = Path(command[command.index("-derivedDataPath") + 1]) / "Build/Products"
        app = products / f"Debug-iphonesimulator/{target}.app"
        app.mkdir(parents=True)
        with (app / "Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleExecutable": target, "CFBundleIdentifier": f"local.gamecore.{target}"}, stream)
        plan = {"__xctestrun_metadata__": {"FormatVersion": 1},
                f"{target}Tests": {"EnvironmentVariables": {}, "TestingEnvironmentVariables": {}},
                f"{target}UITests": {"EnvironmentVariables": {}, "UITargetAppEnvironmentVariables": {"XCODE_SCHEME_NAME": target}}}
        with (products / f"{target}_iphonesimulator26.5-arm64.xctestrun").open("wb") as stream:
            plistlib.dump(plan, stream)

    def probe_rows(self):
        rows = []
        for index, pid in enumerate(self.launches):
            rows.append(row(pid, "loaded pid=%d bundle=local.gamecore.BlockTitle" % pid))
            if not (self.scenario == "missing-launch" and index == 1):
                rows.append(row(pid, f"launch pid={pid} processStart=1.0 activeMs={400 + index} "
                                     f"firstFrameMs={(900 if index == 0 else 450 + 10 * index)} "
                                     f"footprintBytes={20 * 1048576} peakBytes={20 * 1048576}"))
            rows.append(row(pid, "update hooked classes=1"))
        rows.append(row(INTERACTION_PID, "update hooked classes=1"))
        if self.scenario != "missing-updates":
            rows.append(row(INTERACTION_PID, "update seq=1 ms=16.60,16.70,16.70,40.00 gapsMs="))
            rows.append(row(INTERACTION_PID, "update seq=2 ms=16.65 gapsMs=1500.00"))
        if self.scenario != "missing-memory":
            rows.append(row(INTERACTION_PID, "memory footprintBytes=62914560 peakBytes=67108864"))
            rows.append(row(INTERACTION_PID, "memory footprintBytes=60817408 peakBytes=68157440"))
        rows.append("Filtering the log data using \"subsystem == \\\"gamecore.baseline-probe\\\"\"")
        return "\n".join(rows)


class Stream:
    """Stands in for `log stream`: the harness's probe answers each launch at once."""
    scenario = None

    def __init__(self, device, path):
        path.write_text("")

    def wait_for_launch(self, pid, timeout):
        return not (Stream.scenario == "missing-launch" and pid == 6001)

    def close(self):
        pass


def run_scenario(scenario):
    with tempfile.TemporaryDirectory(prefix="gamecore-baseline-harness-") as temporary:
        root = Path(temporary)
        output = root / "evidence"
        harness = Harness(root, scenario)
        recorder = load_recorder()
        recorder.run = harness.run
        recorder.runner.run = harness.run
        Stream.scenario = scenario
        error = None
        environment = {key: value for key, value in os.environ.items() if key != "GAMECORE_SIM_RUNTIME_VERSION"}
        with patch.object(recorder, "ProbeStream", Stream), \
                patch.object(recorder.runner, "scan_input_faults", lambda bundle: {"archives": 1, "faults": []}), patch.object(recorder.time, "sleep", lambda seconds: None), \
                patch.dict(os.environ, environment, clear=True), \
                patch.object(sys, "argv", ["record-baselines.py", str(output), "--title", "BlockTitle",
                                           "--model", "iphone12", "--launches", "3"]), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            try:
                recorder.main()
            except (RuntimeError, ValueError, OSError, KeyError) as exception:
                error = str(exception)
        baseline = json.loads((output / "baselines.json").read_text()) if (output / "baselines.json").exists() else None
        plan = None
        if harness.xctestrun and harness.xctestrun.exists():
            with harness.xctestrun.open("rb") as stream:
                plan = plistlib.load(stream)
        for action in ("shutdown", "delete"):
            cleaned = {call[-1] for call in harness.calls if call[:3] == ["xcrun", "simctl", action]}
            assert set(harness.created) <= cleaned, (scenario, action)
        return harness, error, baseline, plan


def check_probe_build():
    with tempfile.TemporaryDirectory(prefix="gamecore-baseline-probe-") as temporary:
        binary = Path(temporary) / "BaselineProbe.dylib"
        subprocess.run(["xcrun", "--sdk", "iphonesimulator", "clang", "-dynamiclib", "-fobjc-arc", "-O2", "-Werror",
                        "-Wall", "-target", f"{os.uname().machine}-apple-ios18.0-simulator", "-framework", "Foundation",
                        str(SCRIPTS / "baseline-probe/BaselineProbe.m"), "-o", str(binary)], check=True, capture_output=True)
        linked = subprocess.run(["otool", "-L", str(binary)], check=True, capture_output=True, text=True).stdout
        libraries = {line.split(" (")[0].strip() for line in linked.splitlines()[1:]} - {str(binary)}
        allowed = {"/System/Library/Frameworks/Foundation.framework/Foundation",
                   "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
                   "/usr/lib/libobjc.A.dylib", "/usr/lib/libSystem.B.dylib"}
        assert libraries <= allowed, sorted(libraries - allowed)
    print("PASS probe compiles for the iOS Simulator and links only Foundation, libobjc and libSystem")


def main():
    harness, error, baseline, plan = run_scenario("pass")
    assert error is None, error
    for key in ("schemaVersion", "kind", "notice", "recordedAt", "source", "toolchain", "runtime", "host",
                "instrumentation", "titles"):
        assert key in baseline, key
    assert baseline["source"]["revision"] == "mock-checkout" and len(baseline["source"]["inputsSHA256"]) == 64
    assert baseline["runtime"]["version"] == "26.5" and baseline["host"]["model"] == "Mac16,10"
    assert baseline["toolchain"]["swift"].startswith("Apple Swift version 6.3"), baseline["toolchain"]
    assert "not physical-device budgets" in baseline["notice"]
    title = baseline["titles"]["BlockTitle"]
    package = title["package"]
    assert package["executableBytes"] == 4096 and package["appBundleBytes"] > 14096 and 0 < package["zipBytes"] < 14096, package
    geometry = title["geometries"]["iphone12"]
    launch = geometry["coldLaunch"]
    assert launch["firstLaunchAfterInstallMs"] == 900 and launch["samplesMs"] == [460, 470, 480], launch
    assert launch["medianMs"] == 470, launch
    updates = geometry["sceneUpdates"]
    assert updates["count"] == 5 and updates["maxMs"] == 40.0 and updates["over33Ms"] == 1, updates
    assert updates["gapsAtLeast1sMs"] == [1500.0] and "SKScene update" in updates["signal"], updates
    memory = geometry["memory"]
    assert memory["interactionPeakMiB"] == 65.0 and memory["interactionLastMiB"] == 58.0, memory
    assert memory["launchFootprintMedianMiB"] == 20.0, memory
    environment = plan["BlockTitleUITests"]["UITargetAppEnvironmentVariables"]
    assert environment["DYLD_INSERT_LIBRARIES"].endswith("BaselineProbe.dylib"), environment
    assert environment["GAMECORE_BASELINE_PROBE_BUNDLE"] == "local.gamecore.BlockTitle", environment
    assert "DYLD_INSERT_LIBRARIES" not in plan["BlockTitleTests"]["EnvironmentVariables"], "Unit test host stays uninstrumented"
    launches = [call for call in harness.calls if call[0] == "env"]
    assert len(launches) == 4 and all("SIMCTL_CHILD_GAMECORE_BASELINE_PROBE_BUNDLE=local.gamecore.BlockTitle" in call
                                      for call in launches)
    print("PASS baseline JSON records source, toolchain, runtime, host, package size, launch, updates and memory")

    for scenario, needle in (("interaction-failure", 'failed, so no baseline; simulator input faults: {"archives": 1'),
                             ("missing-launch", "no first frame from PID 6001"),
                             ("missing-updates", "no scene-update intervals"),
                             ("missing-memory", "no footprint samples")):
        _, error, baseline, _ = run_scenario(scenario)
        assert error and needle in error and baseline is None, (scenario, error)
        print(f"PASS {scenario}: no baseline written, owned simulator deleted ({needle})")
    check_probe_build()
    print("Baseline recorder writes only complete observations and deletes its simulators")


if __name__ == "__main__":
    main()
