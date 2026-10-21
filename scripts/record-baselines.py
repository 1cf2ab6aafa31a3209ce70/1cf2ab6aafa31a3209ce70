#!/usr/bin/env python3
"""Record simulator regression baselines for every title on owned disposable simulators.

These are simulator observations for spotting regressions between runs on a
comparable host. They are not physical-device budgets (ADR-003), and nothing
here passes or fails a title on a number.

For each selected title this records:
  - package size from an unsigned Release iphoneos build: app bundle bytes,
    executable bytes and a deflate zip of Payload/<App>.app (IPA-equivalent);
and on each selected geometry, with a test-only probe library injected into
the Debug app (scripts/baseline-probe/BaselineProbe.m):
  - cold launch: process start to the first display-link frame after the app
    becomes active, over repeated `simctl launch` runs after `simctl terminate`
    (process cold, file cache warm; the first launch after install apart);
  - scene-update intervals: time between successive -[SKScene update:] calls
    while the title's fixed gameplay UI test runs;
  - process memory: phys_footprint of the simulated app's host process at
    first frame, and its lifetime peak during the gameplay test.
The titles have no per-title frame diagnostics; the DEBUG action journal
records shell actions, not frames, so the probe supplies the update signal.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import statistics
import subprocess
import sys
import time
import uuid
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import titles as title_manifests  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
PROBE_SOURCE = ROOT / "scripts/baseline-probe/BaselineProbe.m"
PROBE_SUBSYSTEM = "gamecore.baseline-probe"
SCHEMA_VERSION = 1
# One existing UI test per title is its fixed gameplay interaction. A new
# title needs an entry before it can be baselined.
INTERACTIONS = {
    "BlockTitle": "BlockTitleUITests/BlockTitleUITests/testClearFirstBoardThenRelaunchContinuesWithTheSecond",
    "DevelopmentTitle": "DevelopmentTitleUITests/DevelopmentTitleUITests/testNavigationSuccessFailureResumeAndRestart",
}
GAP_MS = 1000.0
NOTICE = ("Simulator observations on the recorded host, runtime and geometry, measured with an injected test-only "
          "probe in a Debug build. They are regression baselines for comparable hosts, not physical-device budgets.")

spec = importlib.util.spec_from_file_location("mobile_runner", ROOT / "scripts/run-mobile-tests.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
run = runner.run


def percentile(values, fraction):
    ordered = sorted(values)
    if not ordered:
        return None
    index = min(len(ordered) - 1, max(0, round(fraction * (len(ordered) - 1))))
    return round(ordered[index], 2)


def describe(values):
    if not values:
        return {"count": 0}
    return {"count": len(values), "meanMs": round(statistics.fmean(values), 2), "p50Ms": percentile(values, 0.5),
            "p95Ms": percentile(values, 0.95), "p99Ms": percentile(values, 0.99), "maxMs": round(max(values), 2),
            "over20Ms": sum(value > 20 for value in values), "over33Ms": sum(value > 33.4 for value in values)}


def mib(value):
    return None if value is None else round(value / (1024 * 1024), 2)


def parse_fields(message):
    return dict(re.findall(r"(\w+)=(\S*)", message))


def parse_probe(ndjson):
    """Probe rows from `log show --style ndjson`, grouped by app process."""
    processes = {}
    for line in ndjson.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            row = json.loads(line)
        except ValueError:
            continue
        message = row.get("eventMessage") or ""
        if row.get("subsystem") != PROBE_SUBSYSTEM:
            continue
        pid = row.get("processID")
        entry = processes.setdefault(pid, {"launch": None, "intervals": [], "gaps": [], "footprints": [],
                                           "peaks": [], "hooked": None, "unavailable": None})
        kind, fields = message.split(" ", 1)[0], parse_fields(message)
        if kind == "launch":
            entry["launch"] = {"activeMs": float(fields["activeMs"]), "firstFrameMs": float(fields["firstFrameMs"]),
                               "footprintBytes": int(fields["footprintBytes"])}
        elif kind == "update" and "seq" in fields:
            entry["intervals"] += [float(value) for value in fields.get("ms", "").split(",") if value]
            entry["gaps"] += [float(value) for value in fields.get("gapsMs", "").split(",") if value]
        elif kind == "update" and "classes" in fields:
            entry["hooked"] = int(fields["classes"])
            if not entry["hooked"]:
                entry["unavailable"] = "no SKScene class implements update:"
        elif kind == "update" and "reason" in fields:
            entry["unavailable"] = message
        elif kind == "memory":
            entry["footprints"].append(int(fields["footprintBytes"]))
            if int(fields["peakBytes"]) >= 0:
                entry["peaks"].append(int(fields["peakBytes"]))
    return processes


def package_size(app, output):
    """Bytes of an unsigned Release app bundle and of its IPA-equivalent zip."""
    with (app / "Info.plist").open("rb") as stream:
        executable = plistlib.load(stream)["CFBundleExecutable"]
    files = sorted(path for path in app.rglob("*") if path.is_file() and not path.is_symlink())
    archive = output / f"{app.stem}-Payload.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for path in files:
            # Fixed timestamps keep the archive size independent of build time.
            info = zipfile.ZipInfo(str(Path("Payload") / app.name / path.relative_to(app)), (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (path.stat().st_mode & 0o777) << 16
            bundle.writestr(info, path.read_bytes(), compresslevel=9)
    return {"configuration": "Release", "sdk": "iphoneos", "signed": False,
            "appBundleBytes": sum(path.stat().st_size for path in files), "files": len(files),
            "executableBytes": (app / executable).stat().st_size, "zipBytes": archive.stat().st_size,
            "zipMethod": "Payload/<App>.app, deflate level 9, sorted entries, fixed timestamps (Python zipfile)"}


def build_probe(output):
    architecture = platform.machine()
    binary = output / "BaselineProbe.dylib"
    run(["xcrun", "--sdk", "iphonesimulator", "clang", "-dynamiclib", "-fobjc-arc", "-O2",
         "-target", f"{architecture}-apple-ios18.0-simulator", "-framework", "Foundation",
         str(PROBE_SOURCE), "-o", str(binary)], log=output / "probe-build.log", timeout=300)
    run(["codesign", "--force", "--sign", "-", str(binary)], timeout=60)
    return binary


def probe_xctestrun(products, title, probe, bundle_identifier):
    """A copy of the built xctestrun whose UI target app loads the probe."""
    candidates = sorted(products.glob(f"{title.target}_*.xctestrun"))
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one {title.target} xctestrun in {products}, found {len(candidates)}")
    with candidates[0].open("rb") as stream:
        plan = plistlib.load(stream)
    bundle = Path(title.ui_tests).name
    if bundle not in plan or "UITargetAppEnvironmentVariables" not in plan[bundle]:
        raise RuntimeError(f"{candidates[0].name} has no UI target environment for {bundle}")
    plan[bundle]["UITargetAppEnvironmentVariables"].update(
        {"DYLD_INSERT_LIBRARIES": str(probe), "GAMECORE_BASELINE_PROBE_BUNDLE": bundle_identifier})
    path = products / f"{title.target}-baseline-probe.xctestrun"
    with path.open("wb") as stream:
        plistlib.dump(plan, stream)
    return path


class ProbeStream:
    """Follow the probe's log rows on one owned device, so each launch is awaited, not slept on."""

    def __init__(self, device, path):
        self.path = path
        self.stream = path.open("w")
        self.process = subprocess.Popen(["xcrun", "simctl", "spawn", device, "log", "stream", "--style", "ndjson",
                                         "--predicate", f'subsystem == "{PROBE_SUBSYSTEM}"'],
                                        stdout=self.stream, stderr=subprocess.STDOUT, text=True,
                                        start_new_session=True)

    def wait_for_launch(self, pid, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if (parse_probe(self.path.read_text()).get(pid) or {}).get("launch"):
                return True
            if self.process.poll() is not None:
                raise RuntimeError(f"Probe log stream exited ({self.process.returncode}); see {self.path}")
            time.sleep(0.5)
        return False

    def close(self):
        try:
            runner.stop_owned_group(self.process)
        finally:
            self.stream.close()


def read_probe_log(device, since, path):
    run(["xcrun", "simctl", "spawn", device, "log", "show", "--start", since, "--info", "--style", "ndjson",
         "--predicate", f'subsystem == "{PROBE_SUBSYSTEM}"'], log=path, timeout=300)
    return parse_probe(path.read_text())


def measure_geometry(title, model, device_type, runtime, app, xctestrun, probe, bundle_identifier,
                     launches, output, owner):
    device = None
    since = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - 1))
    try:
        name = " ".join(filter(None, ["GameCore Baseline", model, owner, uuid.uuid4().hex[:8]]))
        device = run(["xcrun", "simctl", "create", name, device_type, runtime["identifier"]])
        run(["xcrun", "simctl", "boot", device])
        run(["xcrun", "simctl", "bootstatus", device, "-b"], log=output / f"{model}-boot.log", timeout=600)
        run(["xcrun", "simctl", "install", device, str(app)], timeout=300)
        environment = [f"SIMCTL_CHILD_DYLD_INSERT_LIBRARIES={probe}",
                       f"SIMCTL_CHILD_GAMECORE_BASELINE_PROBE_BUNDLE={bundle_identifier}"]
        launch_pids = []
        stream = ProbeStream(device, output / f"{model}-launch-stream.ndjson")
        try:
            for _ in range(launches + 1):
                launched = run(["env"] + environment + ["xcrun", "simctl", "launch", device, bundle_identifier],
                               timeout=300)
                match = re.search(r":\s*(\d+)\s*$", launched)
                if not match:
                    raise RuntimeError(f"simctl launch did not report a PID: {launched!r}")
                launch_pids.append(int(match.group(1)))
                if not stream.wait_for_launch(launch_pids[-1], 120):
                    raise RuntimeError(f"{title.target} {model}: no first frame from PID {launch_pids[-1]} in 120 s")
                time.sleep(2)  # Let the launch settle so termination never overlaps first-frame work.
                run(["xcrun", "simctl", "terminate", device, bundle_identifier], timeout=120)
                time.sleep(1)
        finally:
            stream.close()
        interaction = INTERACTIONS[title.target]
        result_bundle = output / f"{model}-interaction.xcresult"
        try:
            run(["xcodebuild", "-xctestrun", str(xctestrun), "-destination", f"platform=iOS Simulator,id={device}",
                 "-resultBundlePath", str(result_bundle), "-only-testing:" + interaction,
                 "-parallel-testing-enabled", "NO", "test-without-building"],
                log=output / f"{model}-interaction.log", timeout=900)
        except RuntimeError as error:
            # No retry: a baseline mixes no attempts. Classify against N06/N09 first (CONTRIBUTING.md).
            try:
                faults = runner.scan_input_faults(result_bundle) if result_bundle.exists() else None
            except Exception as scan_error:
                faults = {"error": str(scan_error)}
            raise RuntimeError(f"{title.target} {model}: gameplay test {interaction} failed, so no baseline; "
                               f"simulator input faults: {json.dumps(faults)}; record on a quiet host. "
                               f"{str(error).splitlines()[0]}") from error
        processes = read_probe_log(device, since, output / f"{model}-probe.ndjson")
    finally:
        if device:
            for operation in ("shutdown", "delete"):
                runner.cleanup_device(device, operation, output / f"{model}-{operation}.log", f"{title.target} {model}")

    measured = []
    for pid in launch_pids:
        launch = (processes.get(pid) or {}).get("launch")
        if not launch:
            raise RuntimeError(f"{title.target} {model}: no probe launch record for simctl launch PID {pid}")
        measured.append(launch)
    first, repeated = measured[0], measured[1:]
    interaction_processes = [entry for pid, entry in processes.items() if pid not in launch_pids]
    intervals = [value for entry in interaction_processes for value in entry["intervals"]]
    gaps = [value for entry in interaction_processes for value in entry["gaps"]]
    peaks = [value for entry in interaction_processes for value in entry["peaks"]]
    if not interaction_processes:
        raise RuntimeError(f"{title.target} {model}: no probe records from the gameplay test's app process")
    if not intervals:
        detail = next((entry["unavailable"] for entry in interaction_processes if entry["unavailable"]), "none recorded")
        raise RuntimeError(f"{title.target} {model}: no scene-update intervals during {interaction} ({detail})")
    if not peaks:
        raise RuntimeError(f"{title.target} {model}: no footprint samples during {interaction}")
    first_frame = [item["firstFrameMs"] for item in repeated]
    return {
        "deviceType": device_type,
        "coldLaunch": {
            "definition": "process start (kern.proc p_starttime) to the first display-link frame after "
                          "UIApplicationDidBecomeActive; simctl launch after simctl terminate",
            "firstLaunchAfterInstallMs": first["firstFrameMs"],
            "samplesMs": first_frame, "medianMs": round(statistics.median(first_frame), 2),
            "minMs": min(first_frame), "maxMs": max(first_frame),
            "becameActiveMedianMs": round(statistics.median(item["activeMs"] for item in repeated), 2)},
        "sceneUpdates": {
            "signal": "intervals between successive -[SKScene update:] calls (injected probe); recorded only "
                      "while a SpriteKit scene is shown and unpaused",
            "interaction": interaction, "appProcesses": len(interaction_processes),
            **describe(intervals), "gapsAtLeast1sMs": [round(value, 1) for value in gaps]},
        "memory": {
            "signal": "phys_footprint of the simulated app's host process (task_info TASK_VM_INFO)",
            "launchFootprintMedianMiB": mib(statistics.median(item["footprintBytes"] for item in repeated)),
            "interactionPeakMiB": mib(max(peaks)),
            "interactionLastMiB": mib(next(entry["footprints"][-1] for entry in reversed(interaction_processes)
                                           if entry["footprints"]))},
    }


def host_identity():
    def sysctl(name):
        try:
            return run(["sysctl", "-n", name], timeout=10)
        except RuntimeError:
            return None
    return {"model": sysctl("hw.model"), "cpu": sysctl("machdep.cpu.brand_string"),
            "logicalCPUs": os.cpu_count(), "memoryBytes": int(sysctl("hw.memsize") or 0),
            "macOS": run(["sw_vers", "-productVersion"]), "macOSBuild": run(["sw_vers", "-buildVersion"]),
            "architecture": platform.machine(), "loadAverageAtStart": [round(v, 2) for v in os.getloadavg()],
            "githubActions": os.environ.get("GITHUB_ACTIONS") == "true",
            "runnerName": os.environ.get("RUNNER_NAME")}


def main():
    titles = title_manifests.load()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("output", help="New absolute output directory for evidence and baselines.json")
    parser.add_argument("--title", action="append", choices=[title.target for title in titles],
                        help="Record only this title; repeat to select several (default: every title)")
    parser.add_argument("--model", choices=[model for model, _ in runner.MODELS],
                        help="Record only this geometry (default: both)")
    parser.add_argument("--launches", type=int, default=5, help="Measured cold launches per geometry (default: 5)")
    args = parser.parse_args()
    output = Path(args.output)
    if not output.is_absolute():
        parser.error("Output directory must be absolute")
    if args.launches < 1:
        parser.error("--launches must be at least 1")
    selected = [title for title in titles if args.title is None or title.target in args.title]
    missing = [title.target for title in selected if title.target not in INTERACTIONS]
    if missing:
        parser.error(f"No gameplay interaction defined for {', '.join(missing)}; add one to INTERACTIONS")
    models = [item for item in runner.MODELS if args.model is None or item[0] == args.model]
    output.mkdir(parents=True, exist_ok=False)
    owner = re.sub(r"[^A-Za-z0-9-]", "", os.environ.get("GAMECORE_SIM_OWNER", ""))[:32]
    print(f"Baseline evidence: {output}", flush=True)
    runtime = runner.select_runtime()
    identity = runner.source_identity()
    (output / "source-identity.json").write_text(json.dumps(identity, indent=2) + "\n")
    digest = hashlib.sha256("".join(f"{path}\0{value}\n" for path, value in sorted(identity["sourceSHA256"].items()))
                            .encode()).hexdigest()
    run(["python3", "scripts/generate-project.py", "--check"])
    probe = build_probe(output)
    baseline = {
        "schemaVersion": SCHEMA_VERSION, "kind": "gamecore-simulator-regression-baseline", "notice": NOTICE,
        "recordedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source": {"revision": identity["sourceRevision"], "worktreeDirty": identity["worktreeDirty"],
                   "inputsSHA256": digest, "inputFiles": len(identity["sourceSHA256"])},
        "toolchain": {"xcode": run(["xcodebuild", "-version"]).replace("\n", " "),
                      "swift": next((line for line in run(["xcrun", "swift", "--version"]).splitlines()
                                     if "Swift version" in line), None),
                      "iphonesimulatorSDK": run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]),
                      "iphoneosSDK": run(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"])},
        "runtime": {"identifier": runtime["identifier"], "version": runtime["version"],
                    "build": runtime.get("buildversion")},
        "host": host_identity(),
        "instrumentation": {
            "probe": "scripts/baseline-probe/BaselineProbe.m, injected with DYLD_INSERT_LIBRARIES into the Debug app "
                     "(simctl launch environment and the xctestrun UITargetAppEnvironmentVariables)",
            "probeSourceSHA256": hashlib.sha256(PROBE_SOURCE.read_bytes()).hexdigest(),
            "buildConfiguration": {"runtime": "Debug (UI tests need DEBUG test hooks)", "package": "Release"},
            "launches": args.launches},
        "titles": {},
    }
    for title in selected:
        title_output = output / title.target
        title_output.mkdir()
        derived = title_output / "build"
        run(["xcodebuild", "-workspace", "GameCore.xcworkspace", "-scheme", title.target, "-configuration", "Debug",
             "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(derived),
             "CODE_SIGNING_ALLOWED=NO", "build-for-testing"], log=title_output / "build.log", timeout=900)
        run(["xcodebuild", "-workspace", "GameCore.xcworkspace", "-scheme", title.target, "-configuration", "Release",
             "-destination", "generic/platform=iOS", "-derivedDataPath", str(title_output / "release"),
             "CODE_SIGNING_ALLOWED=NO", "build"], log=title_output / "release-build.log", timeout=900)
        products = derived / "Build/Products"
        app = products / f"Debug-iphonesimulator/{title.target}.app"
        with (app / "Info.plist").open("rb") as stream:
            bundle_identifier = plistlib.load(stream)["CFBundleIdentifier"]
        xctestrun = probe_xctestrun(products, title, probe, bundle_identifier)
        entry = baseline["titles"][title.target] = {
            "bundleIdentifier": bundle_identifier,
            "package": package_size(title_output / f"release/Build/Products/Release-iphoneos/{title.target}.app",
                                    title_output),
            "geometries": {}}
        for model, device_type in models:
            entry["geometries"][model] = measure_geometry(title, model, device_type, runtime, app, xctestrun, probe,
                                                          bundle_identifier, args.launches, title_output, owner)
            geometry = entry["geometries"][model]
            print(f"RECORDED {title.target} {model}: launch median {geometry['coldLaunch']['medianMs']} ms, "
                  f"scene update p95 {geometry['sceneUpdates']['p95Ms']} ms over {geometry['sceneUpdates']['count']}, "
                  f"peak {geometry['memory']['interactionPeakMiB']} MiB (simulator observation)", flush=True)
        print(f"RECORDED {title.target} package: zip {entry['package']['zipBytes']} bytes, "
              f"executable {entry['package']['executableBytes']} bytes", flush=True)
    baseline["host"]["loadAverageAtEnd"] = [round(v, 2) for v in os.getloadavg()]
    (output / "baselines.json").write_text(json.dumps(baseline, indent=2) + "\n")
    print(f"Baselines written: {output / 'baselines.json'}; simulator observations, not physical budgets", flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Interrupted; owned command and simulator cleanup completed.", file=sys.stderr)
        sys.exit(130)
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
