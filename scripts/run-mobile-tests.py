#!/usr/bin/env python3
"""Run mobile app and UI tests on owned disposable simulators; never touch other devices."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
MODELS = (
    ("iphone12", "com.apple.CoreSimulator.SimDeviceType.iPhone-12"),
    ("ipad9", "com.apple.CoreSimulator.SimDeviceType.iPad-9th-generation"),
)


def stop_owned_group(process):
    """Stop the detached command group, including descendants after leader exit."""
    def group_exists():
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            return False
        except PermissionError:
            # macOS can report EPERM while an orphaned/zombie group is being
            # reaped. Keep the bounded retry instead of claiming it is gone.
            return True
        return True

    for sig, grace in ((signal.SIGINT, 10), (signal.SIGTERM, 10), (signal.SIGKILL, 5)):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            break
        except PermissionError:
            pass
        deadline = time.monotonic() + grace
        while time.monotonic() < deadline:
            # Reap the leader, but do not use its exit as proof that descendants
            # are gone. With stdout redirected to a log they can outlive it.
            try:
                process.communicate(timeout=min(0.1, max(0.001, deadline - time.monotonic())))
            except subprocess.TimeoutExpired:
                pass
            if not group_exists():
                break
            time.sleep(0.05)
        if not group_exists():
            break
    try:
        process.communicate(timeout=5)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"Could not reap owned command {process.pid}") from error
    if group_exists():
        raise RuntimeError(f"Could not stop owned process group {process.pid}")


def run(command, *, log=None, timeout=300):
    stream = log.open("w") if log else subprocess.PIPE
    try:
        process = subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                   text=True, start_new_session=True)
    except BaseException:
        if log:
            stream.close()
        raise
    try:
        stdout, _ = process.communicate(timeout=timeout)
    except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        # Only this command's process group is interrupted, never unrelated Xcode sessions.
        stop_owned_group(process)
        if isinstance(error, KeyboardInterrupt):
            raise
        raise RuntimeError(f"Timed out: {command[0]}; evidence: {log}") from error
    finally:
        if log:
            stream.close()
    if process.returncode:
        detail = "\n".join(log.read_text().splitlines()[-50:]) if log else stdout
        raise RuntimeError(f"Command failed ({process.returncode}): {' '.join(command)}\n{detail}")
    return (stdout or "").strip()


def version(value):
    return tuple(int(part) for part in value.split("."))


def collect_boot_diagnostics(device, model, output):
    """Best-effort evidence for one owned device, without masking boot failure."""
    log = output / f"{model}-diagnose.log"
    try:
        inventory = json.loads(run(["xcrun", "simctl", "list", "devices", "--json"], timeout=30))
        owned = next((item for devices in inventory.get("devices", {}).values()
                      for item in devices if item.get("udid") == device), None)
        state = owned.get("state") if owned else None
        if state != "Booted":
            # Apple documents implicit --all-logs when no device is booted,
            # which overrides --udid. Never enter that broad collection path.
            log.write_text(f"Skipped diagnostics for owned simulator {device}: state {state or 'unknown'}\n")
            return
        directory = output / f"{model}-diagnostics"
        directory.mkdir()
        run(["xcrun", "simctl", "diagnose", "-b", "--timeout=60", f"--udid={device}",
             f"--output={directory}"], log=log, timeout=90)
    except Exception as error:
        # Diagnostics are optional evidence; the caller retains the original
        # readiness error even if collection or the state query fails.
        message = f"Diagnostic collection failed for owned simulator {device}: {error}"
        try:
            with log.open("a") as stream:
                stream.write(message + "\n")
        except OSError:
            pass
        print(message, file=sys.stderr)


def source_identity():
    # HEAD alone does not identify an uncommitted implementation. Hash the actual
    # build and verification inputs, using paths relative to the repository.
    sources = {}
    for directory in ("Packages", "Games", "Tests", "GameCore.xcodeproj",
                      "GameCore.xcworkspace", "scripts", ".github"):
        for path in sorted((ROOT / directory).rglob("*")):
            if not path.is_file() or any(part in (".build", "__pycache__", "xcuserdata", ".swiftpm")
                                         for part in path.relative_to(ROOT).parts):
                continue
            sources[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return {"sourceRevision": run(["git", "rev-parse", "HEAD"]),
            "worktreeDirty": bool(run(["git", "status", "--porcelain", "--untracked-files=all"])),
            "sourceSHA256": sources}


def verify_restart(xcode, device, model, output, runtime_identifier):
    """Validate test-reported paths; never delete an inferred sandbox location."""
    restart_test = "DevelopmentTitleTests/SavePersistenceTests/testSimulatorRestartPersistence"
    receipt_prefix = "GAMECORE_RESTART_RECEIPT "

    def invoke(label):
        log = output / f"{model}-restart-{label}.log"
        run(xcode + ["-destination", f"platform=iOS Simulator,id={device}",
                     "-only-testing:" + restart_test,
                     "-resultBundlePath", str(output / f"{model}-restart-{label}.xcresult"),
                     "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
                     "-maximum-test-execution-time-allowance", "120", "test-without-building"],
            log=log, timeout=600)
        lines = log.read_text().splitlines()
        if not any("testSimulatorRestartPersistence" in line and "passed" in line for line in lines):
            raise RuntimeError(f"Restart {label} invocation did not pass the selected test")
        receipts = [json.loads(line.split(receipt_prefix, 1)[1])
                    for line in lines if receipt_prefix in line]
        if len(receipts) != 1:
            raise RuntimeError(f"Restart {label} must emit exactly one fixture receipt")
        receipt = receipts[0]
        try:
            uuid.UUID(receipt["token"])
        except (ValueError, KeyError, TypeError) as error:
            raise RuntimeError("Restart receipt lacks a valid fixture token") from error
        # xcodebuild can refresh a data container. Discover it after the test,
        # then validate the exact Foundation path emitted by that known test.
        container = Path(run(["xcrun", "simctl", "get_app_container", device,
                              "local.gamecore.DevelopmentTitle", "data"])).resolve()
        root = Path(receipt["root"])
        sandbox = Path(receipt["sandboxRoot"])
        if (not root.is_absolute() or not sandbox.is_absolute()
                or sandbox.resolve() != container
                or not root.resolve().is_relative_to(container)
                or root.name != "epic04-restart-proof" or root.parent.name != "GameCoreSaves"
                or receipt["phase"] not in {"prepared", "restored"}):
            raise RuntimeError(f"Restart {label} receipt is outside its owned fixture sandbox: {receipt}")
        return receipt, root.resolve()

    receipt, restart_root = invoke("prepare")
    initial_phase = receipt["phase"]
    if initial_phase == "restored":
        # The full suite may have seeded the marker. Consume it safely in the
        # known test, then make one bounded invocation to prepare fresh state.
        receipt, restart_root = invoke("prepare-fresh")
    if receipt["phase"] != "prepared":
        raise RuntimeError("Restart preparation did not report a prepared fixture")
    snapshot = restart_root / "restart-proof/save.json"
    marker = restart_root / "prepared.marker"
    if not snapshot.is_file() or not marker.is_file():
        raise RuntimeError("Restart preparation did not retain its reported fixture")
    if marker.read_text() != receipt["token"]:
        raise RuntimeError("Restart marker does not identify the prepared fixture")
    before = hashlib.sha256(snapshot.read_bytes()).hexdigest()
    run(["xcrun", "simctl", "shutdown", device], timeout=90)
    run(["xcrun", "simctl", "boot", device])
    run(["xcrun", "simctl", "bootstatus", device, "-b"],
        log=output / f"{model}-restart-boot.log", timeout=600)
    if hashlib.sha256(snapshot.read_bytes()).hexdigest() != before:
        raise RuntimeError("Save bytes changed during simulator restart")
    restored, restored_root = invoke("restore")
    if (restored["phase"] != "restored" or restored["token"] != receipt["token"]
            or restored_root.exists()):
        raise RuntimeError("Restart restore did not validate and remove the prepared fixture")
    (output / f"{model}-restart.json").write_text(json.dumps({
        "fixtureSHA256": before, "saveBytesPreserved": True,
        "device": device, "runtime": runtime_identifier,
        "preparedRoot": str(restart_root), "restoredRoot": str(restored_root),
        "fixtureToken": receipt["token"], "initialPhase": initial_phase,
        "restoredPhase": restored["phase"], "fixtureRemoved": True,
        "scope": "Simulator shutdown/boot; restore test reads settings and progress"
    }, indent=2) + "\n")
    print(f"PASS {model}: settings/progress restored after simulator restart", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", help="New absolute output directory (default: temporary)")
    args = parser.parse_args()
    if args.output:
        output = Path(args.output)
        if not output.is_absolute():
            parser.error("Output directory must be absolute")
        output.mkdir(parents=True, exist_ok=False)
    else:
        output = Path(tempfile.mkdtemp(prefix="gamecore-mobile-tests-"))
    print(f"Mobile test evidence: {output}", flush=True)
    inventory = json.loads(run(["xcrun", "simctl", "list", "runtimes", "--json"]))
    available = [r for r in inventory["runtimes"] if r.get("isAvailable")
                 and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
                 and version(r["version"]) >= (18,)]
    requested = os.environ.get("GAMECORE_SIM_RUNTIME_VERSION")
    if requested:
        available = [r for r in available if r["version"] == requested]
    if not available:
        raise RuntimeError(f"No available iOS simulator runtime >=18 matching {requested or 'installed inventory'}")
    runtime = max(available, key=lambda item: version(item["version"]))
    print(f"Selected iOS {runtime['version']} ({runtime['identifier']}); minimum-OS coverage is separate", flush=True)
    metadata = {"xcode": run(["xcodebuild", "-version"]), "runtime": runtime["identifier"],
                "runtimeVersion": runtime["version"], "runtimeBuild": runtime.get("buildversion"),
                **source_identity(), "devices": []}
    (output / "inventory.json").write_text(json.dumps(metadata, indent=2) + "\n")
    run(["python3", "scripts/generate-project.py", "--check"])
    xcode = ["xcodebuild", "-workspace", "GameCore.xcworkspace", "-scheme", "DevelopmentTitle",
             "-derivedDataPath", str(output / "build"), "CODE_SIGNING_ALLOWED=NO"]
    run(xcode + ["-configuration", "Debug", "-destination", "generic/platform=iOS Simulator",
                 "build-for-testing"], log=output / "build.log", timeout=600)
    for model, device_type in MODELS:
        device = None
        try:
            device = run(["xcrun", "simctl", "create", f"GameCore Mobile {model} {uuid.uuid4().hex[:8]}",
                          device_type, runtime["identifier"]])
            metadata["devices"].append({"model": model, "type": device_type, "id": device})
            (output / "inventory.json").write_text(json.dumps(metadata, indent=2) + "\n")
            run(["xcrun", "simctl", "boot", device])
            try:
                run(["xcrun", "simctl", "bootstatus", device, "-b"],
                    log=output / f"{model}-boot.log", timeout=600)
            except RuntimeError:
                collect_boot_diagnostics(device, model, output)
                raise
            run(xcode + ["-destination", f"platform=iOS Simulator,id={device}",
                         "-resultBundlePath", str(output / f"{model}.xcresult"),
                         "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
                         "-maximum-test-execution-time-allowance", "120", "test-without-building"],
                log=output / f"{model}.log", timeout=600)
            print(f"PASS {model}: {output / (model + '.xcresult')}", flush=True)
            verify_restart(xcode, device, model, output, runtime["identifier"])
        finally:
            if device:
                # Only UUIDs returned by create in this invocation are cleaned up.
                for operation in ("shutdown", "delete"):
                    try:
                        run(["xcrun", "simctl", operation, device],
                            log=output / f"{model}-{operation}.log", timeout=90)
                    except RuntimeError as error:
                        print(f"Cleanup warning ({model}): {error}", file=sys.stderr)
    print("Mobile app and UI tests passed; no physical performance claim", flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Interrupted; owned command and simulator cleanup completed.", file=sys.stderr)
        sys.exit(130)
    except (RuntimeError, OSError, ValueError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
