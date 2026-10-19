#!/usr/bin/env python3
"""Run mobile app and UI tests on owned disposable simulators; never touch other devices."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid

# The seam verifier loads this file by path to reuse its input-fault scan.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import titles as title_manifests  # noqa: E402

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


def collect_action_journals(device, model, output, bundle_identifier):
    """Copy only bounded diagnostic journals from this owned app's UUID fixtures."""
    destination = output / "action-journals" / model
    # Each journal caps itself at 128 KiB, and a retried case adds a journal.
    receipt = {"device": device, "model": model, "byteLimit": 1024 * 1024,
               "files": [], "missing": False, "truncated": False, "errors": []}
    try:
        destination.mkdir(parents=True, exist_ok=True)
        container = Path(run(["xcrun", "simctl", "get_app_container", device,
                              bundle_identifier, "data"], timeout=30))
        if not container.is_absolute() or container.resolve() != container:
            raise ValueError("App container is not an absolute path without symlinks")
        fixtures = container / "Library/Application Support/GameCoreSaves/UIAutomationFixtures"
        # Walk only the known subtree. Reject symlinks at every component before
        # opening child paths; never recursively inspect or copy save envelopes.
        current = container
        for part in fixtures.relative_to(container).parts:
            current = current / part
            if current.is_symlink():
                raise ValueError("Symlink in fixture root")
            if not current.exists():
                receipt["missing"] = True
                break
            if not current.is_dir() or not current.resolve().is_relative_to(container):
                raise ValueError("Fixture root escapes the owned app container")
        if not receipt["missing"]:
            remaining = receipt["byteLimit"]
            entries = []
            with os.scandir(fixtures) as iterator:
                for entry in iterator:
                    entries.append(Path(entry.path))
                    if len(entries) == 65:
                        break
            entries.sort(key=lambda path: path.name)
            if len(entries) > 64:
                receipt["errors"].append("More than 64 fixture entries; collection bounded to 64")
                receipt["truncated"] = True
            for fixture in entries[:64]:
                try:
                    identity = uuid.UUID(fixture.name)
                    if str(identity).upper() != fixture.name:
                        raise ValueError("Noncanonical fixture UUID")
                    journal = fixture / "diagnostics/action-state.jsonl"
                    for candidate in (fixture, fixture / "diagnostics", journal):
                        if candidate.is_symlink():
                            raise ValueError("Symlink in journal path")
                        if not candidate.resolve().is_relative_to(fixtures):
                            raise ValueError("Journal path escapes fixture root")
                    if not journal.exists():
                        receipt["files"].append({"fixture": fixture.name, "missing": True})
                        continue
                    # O_NOFOLLOW plus regular-file verification refuses a final
                    # symlink/device. Read at most the shared collection budget.
                    directory_descriptor = os.open(container, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
                    try:
                        # Open every component relative to the previously opened
                        # directory, so a replaced symlink cannot redirect reads.
                        for part in journal.parent.relative_to(container).parts:
                            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                            dir_fd=directory_descriptor)
                            os.close(directory_descriptor)
                            directory_descriptor = child
                        descriptor = os.open(journal.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                                             dir_fd=directory_descriptor)
                        try:
                            attributes = os.fstat(descriptor)
                            if not stat.S_ISREG(attributes.st_mode):
                                raise ValueError("Journal is not a regular file")
                            data = os.read(descriptor, remaining)
                        finally:
                            os.close(descriptor)
                    finally:
                        os.close(directory_descriptor)
                    truncated = attributes.st_size > len(data)
                    partial = bool(data and not data.endswith(b"\n"))
                    parse_errors = []
                    for line_number, line in enumerate(data.splitlines(), 1):
                        try:
                            if not isinstance(json.loads(line), dict):
                                raise ValueError("Journal row is not an object")
                        except (ValueError, UnicodeError):
                            parse_errors.append(line_number)
                    target = destination / fixture.name / "action-state.jsonl"
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(data)
                    receipt["files"].append({"fixture": fixture.name, "path": str(target.relative_to(output)),
                        "bytes": len(data), "observedBytes": attributes.st_size,
                        "sha256": hashlib.sha256(data).hexdigest(), "missing": False,
                        "truncated": truncated, "parsePartial": partial,
                        "parseErrorLines": parse_errors})
                    remaining -= len(data)
                    receipt["truncated"] |= truncated
                    if remaining == 0:
                        receipt["truncated"] |= len(entries) > len(receipt["files"])
                        break
                except (OSError, ValueError) as error:
                    receipt["errors"].append({"fixture": fixture.name, "error": str(error)})
            receipt["missing"] = not any(not item["missing"] for item in receipt["files"])
    except Exception as error:
        receipt["errors"].append(str(error))
    finally:
        # Optional diagnostic errors must never replace the native failure or
        # prevent shutdown/deletion of the simulator owned by this invocation.
        try:
            destination.mkdir(parents=True, exist_ok=True)
            (destination / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        except OSError as error:
            print(f"Action journal receipt warning ({model}): {error}", file=sys.stderr)


def scan_input_faults(result_bundle):
    """Find simulator input-injection faults in the bundle's failure diagnostics.

    N06: XCTest plays each synthesized gesture through a new virtual digitizer,
    and backboardd registers it while the first events arrive. Under load it
    either builds a second touch state for the same digitizer, so the touch-up
    is skipped and the contact is canceled ("unknown digitizer"), or
    initializes the state late and replays the queued gesture compressed.

    N09: a synthesized hardware button press reaches SpringBoard with its
    release seconds late, so a click reads as a hold, and testmanagerd times
    out waiting for ButtonEventsCompleted.
    """
    faults = []
    archives = 0
    with tempfile.TemporaryDirectory(prefix="gamecore-diagnostics-") as directory:
        run(["xcrun", "xcresulttool", "export", "diagnostics", "--path", str(result_bundle),
             "--output-path", directory], timeout=300)
        for archive in sorted(Path(directory).rglob("system.logarchive")):
            archives += 1
            lines = run(["/usr/bin/log", "show", "--archive", str(archive), "--info", "--debug",
                         "--style", "compact", "--predicate",
                         '(process == "backboardd" AND category == "TouchEvents") OR '
                         '(process == "testmanagerd" AND eventMessage CONTAINS "Timed out" '
                         'AND eventMessage CONTAINS "ButtonEventsCompleted")'], timeout=300).splitlines()
            attached = {}
            for line in lines:
                stamp = line[:23]
                if "ButtonEventsCompleted" in line:
                    faults.append({"time": stamp, "kind": "button release delivered late; press read as a hold"})
                    continue
                sender = re.search(r"sender(?:ID)?:? (?:0x)?([0-9A-Fa-f]+)", line)
                sender = sender.group(1).upper() if sender else None
                if "digitizer attached" in line and sender:
                    attached[sender] = stamp
                elif "unknown digitizer" in line:
                    faults.append({"time": stamp, "kind": "duplicate touch state; touch-up skipped"})
                elif "init: <BKDirectTouchState" in line and sender in attached:
                    delay = (datetime.strptime(stamp, "%Y-%m-%d %H:%M:%S.%f")
                             - datetime.strptime(attached.pop(sender), "%Y-%m-%d %H:%M:%S.%f")).total_seconds()
                    # Normal registration takes 2-10 ms; the observed fault took 357 ms.
                    if delay > 0.1:
                        faults.append({"time": stamp, "kind": "late touch state; gesture replayed compressed",
                                       "delaySeconds": round(delay, 3)})
    return {"archives": archives, "faults": faults}


def report_retries(model, output):
    """Name every case that failed before passing or failing again; never hide a retry."""
    result_bundle = output / f"{model}.xcresult"
    report = {"model": model, "cases": [], "inputFaults": None, "errors": []}
    try:
        if not result_bundle.exists():
            raise ValueError("No result bundle")
        tree = json.loads(run(["xcrun", "xcresulttool", "get", "test-results", "tests",
                               "--path", str(result_bundle)], timeout=120))

        def visit(node):
            repetitions = [child for child in node.get("children", [])
                           if child.get("nodeType") == "Repetition"]
            if node.get("nodeType") == "Test Case" and any(r.get("result") == "Failed" for r in repetitions):
                report["cases"].append({
                    "test": node.get("nodeIdentifier") or node.get("name"),
                    "result": node.get("result"),
                    "repetitions": [{"name": r.get("name"), "result": r.get("result"),
                                     "failures": [c.get("name") for c in r.get("children", [])
                                                  if c.get("nodeType") == "Failure Message"]}
                                    for r in repetitions]})
            for child in node.get("children", []):
                visit(child)

        for node in tree.get("testNodes", []):
            visit(node)
        if report["cases"]:
            report["inputFaults"] = scan_input_faults(result_bundle)
    except Exception as error:
        report["errors"].append(str(error))
        print(f"Retry report warning ({model}): {error}", file=sys.stderr)
    try:
        (output / f"{model}-retries.json").write_text(json.dumps(report, indent=2) + "\n")
    except OSError as error:
        print(f"Retry report warning ({model}): {error}", file=sys.stderr)
    failed_runs = sum(r["result"] == "Failed" for case in report["cases"] for r in case["repetitions"])
    faults = len((report["inputFaults"] or {}).get("faults", []))
    for case in report["cases"]:
        first = next((r for r in case["repetitions"] if r["result"] == "Failed"), {})
        failures = "; ".join(first.get("failures", [])).replace("\n", " ")
        message = f"{model} {case['test']} {case['result']} after retry; first failure: {failures}"
        print(f"RETRIED {message}", flush=True)
        if os.environ.get("GITHUB_ACTIONS") == "true":
            print(f"::warning title=UI test retried::{message}", flush=True)
    if report["cases"]:
        # A failure without a matching injection fault may be an app defect.
        if not (report["inputFaults"] or {}).get("archives"):
            verdict = "no simulator log in the result bundle; cannot classify, investigate"
        elif faults >= failed_runs:
            verdict = "each failed run has a matching simulator input fault"
        else:
            verdict = f"{failed_runs - faults} failed run(s) lack a simulator input fault; investigate"
        print(f"INPUT FAULTS {model}: {faults} for {failed_runs} failed run(s); {verdict}", flush=True)
        if faults < failed_runs and os.environ.get("GITHUB_ACTIONS") == "true":
            print(f"::warning title=Unexplained UI failure::{model}: {verdict}", flush=True)


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


def verify_restart(xcode, device, model, output, runtime_identifier, title):
    """Validate test-reported paths; never delete an inferred sandbox location."""
    restart_test = title.restart_proof
    receipt_prefix = "GAMECORE_RESTART_RECEIPT "

    def invoke(label):
        log = output / f"{model}-restart-{label}.log"
        run(xcode + ["-destination", f"platform=iOS Simulator,id={device}",
                     "-only-testing:" + restart_test,
                     "-resultBundlePath", str(output / f"{model}-restart-{label}.xcresult"),
                     "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
                     "-maximum-test-execution-time-allowance", "180", "test-without-building"],
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
                              title.bundle_identifier, "data"])).resolve()
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


def test_title(title, selected_models, output, runtime, record_device, navigation_only):
    """Build one title's scheme, then run its app-hosted and UI tests on each owned device."""
    xcode = ["xcodebuild", "-workspace", "GameCore.xcworkspace", "-scheme", title.target,
             "-derivedDataPath", str(output / "build"), "CODE_SIGNING_ALLOWED=NO"]
    run(xcode + ["-configuration", "Debug", "-destination", "generic/platform=iOS Simulator",
                 "build-for-testing"], log=output / "build.log", timeout=600)
    for model, device_type in selected_models:
        device = None
        journal_collected = False
        try:
            device = run(["xcrun", "simctl", "create", f"GameCore Mobile {model} {uuid.uuid4().hex[:8]}",
                          device_type, runtime["identifier"]])
            record_device({"title": title.target, "model": model, "type": device_type, "id": device})
            run(["xcrun", "simctl", "boot", device])
            try:
                run(["xcrun", "simctl", "bootstatus", device, "-b"],
                    log=output / f"{model}-boot.log", timeout=600)
            except RuntimeError:
                collect_boot_diagnostics(device, model, output)
                raise
            # Hosted accessibility queries can exceed 120 seconds for a passing
            # multi-step UI case. Each case gets 180 seconds; the separate
            # 900-second whole-suite cap remains the aggregate failure bound.
            # A failed case runs once more (N06 in the navigation-contact audit:
            # XCTest's synthesized touches race backboardd on loaded simulators).
            # Every retry is reported by name, and a second failure still fails.
            selectors = []
            if navigation_only:
                selectors = ["-only-testing:DevelopmentTitleUITests/DevelopmentTitleUITests/" + name
                             for name in ("testNavigationSuccessFailureResumeAndRestart",
                                          "testForegroundRequiresExplicitResumeAndRotationPreservesPlay",
                                          "testLargeTextAndReducedMotionKeepControlsReachable")]
            try:
                run(xcode + ["-destination", f"platform=iOS Simulator,id={device}",
                             "-resultBundlePath", str(output / f"{model}.xcresult"),
                             "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
                             "-maximum-test-execution-time-allowance", "180",
                             "-retry-tests-on-failure", "-test-iterations", "2"] + selectors + ["test-without-building"],
                    log=output / f"{model}.log", timeout=900)
            finally:
                collect_action_journals(device, model, output, title.bundle_identifier)
                journal_collected = True
                report_retries(model, output)
            print(f"PASS {title.target} {model}: {output / (model + '.xcresult')}", flush=True)
            if not navigation_only and title.restart_proof:
                verify_restart(xcode, device, model, output, runtime["identifier"], title)
        finally:
            if device:
                if not journal_collected:
                    collect_action_journals(device, model, output, title.bundle_identifier)
                # Only UUIDs returned by create in this invocation are cleaned up.
                for operation in ("shutdown", "delete"):
                    try:
                        run(["xcrun", "simctl", operation, device],
                            log=output / f"{model}-{operation}.log", timeout=90)
                    except RuntimeError as error:
                        print(f"Cleanup warning ({title.target} {model}): {error}", file=sys.stderr)


def main():
    titles = title_manifests.load()
    targets = [title.target for title in titles]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", help="New absolute output directory (default: temporary)")
    parser.add_argument("--model", choices=[model for model, _ in MODELS],
                        help="Run only this simulator geometry (default: both)")
    parser.add_argument("--title", action="append", choices=targets,
                        help="Run only this title; repeat to select several (default: every title)")
    parser.add_argument("--navigation-only", action="store_true",
                        help="Run three DevelopmentTitle navigation UI diagnostics only; omit restart proof")
    args = parser.parse_args()
    selected_models = tuple(item for item in MODELS if args.model is None or item[0] == args.model)
    selected_titles = [title for title in titles if args.title is None or title.target in args.title]
    if args.navigation_only:
        if any(title.target != "DevelopmentTitle" for title in selected_titles if args.title):
            parser.error("--navigation-only applies to DevelopmentTitle only")
        selected_titles = [title for title in selected_titles if title.target == "DevelopmentTitle"]
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
                "selectedModels": [model for model, _ in selected_models],
                "selectedTitles": [title.target for title in selected_titles],
                "navigationOnly": args.navigation_only,
                **source_identity(), "devices": []}

    def record_device(device):
        metadata["devices"].append(device)
        (output / "inventory.json").write_text(json.dumps(metadata, indent=2) + "\n")

    (output / "inventory.json").write_text(json.dumps(metadata, indent=2) + "\n")
    run(["python3", "scripts/generate-project.py", "--check"])
    for title in selected_titles:
        # One title keeps the established flat layout; several get one directory each.
        title_output = output if len(selected_titles) == 1 else output / title.target
        title_output.mkdir(exist_ok=True)
        test_title(title, selected_models, title_output, runtime, record_device, args.navigation_only)
    scope = "Navigation diagnostics" if args.navigation_only else "Mobile app and UI tests"
    print(f"{scope} passed for {', '.join(title.target for title in selected_titles)}; no physical performance claim", flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Interrupted; owned command and simulator cleanup completed.", file=sys.stderr)
        sys.exit(130)
    except (RuntimeError, OSError, ValueError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
