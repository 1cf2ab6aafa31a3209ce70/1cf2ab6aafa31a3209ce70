#!/usr/bin/env python3
"""Observe an owned simulator's app process for network activity during tests.

A simulator app is a host process, so two host-side channels watch it while
the app-hosted and UI tests run:

1. Socket samples. Every SAMPLE_INTERVAL seconds, find the app's host PIDs by
   their executable path inside the owned device's data directory and list
   their internet sockets with `lsof -nP -a -i -p`. Any socket held at a sample
   is a finding. A connection that opens and closes between two samples can
   be missed, so the report records the largest gap between samples. A
   sample whose ps or lsof times out on a loaded host is such a gap: it is
   counted and widens the gap, and more than MAX_TIMEOUT_SHARE of them fails
   the gate. Any other sampler error fails it.
2. The device's unified log. After the run, read the app process's entries
   from Apple's networking subsystems (Network.framework, CFNetwork, URL
   sessions). These name connections however briefly they lived, but only
   for traffic that goes through Apple's networking stacks.

Nothing is excluded silently: an entry that Apple's frameworks attribute to
the app without opening a connection is listed under `systemOwned` with its
reason, and anything that matches no listed reason fails the gate.
"""
import json
from pathlib import Path
import re
import subprocess
import threading
import time

SAMPLE_INTERVAL = 0.25
# A hosted runner once stalled ps -axo for over 30 s three times in 782 samples
# while booting simulators; beyond this share the socket channel is too thin to trust.
MAX_TIMEOUT_SHARE = 0.1
LOG_PREDICATE = ('(subsystem BEGINSWITH "com.apple.network" OR subsystem BEGINSWITH "com.apple.CFNetwork" '
                 'OR subsystem BEGINSWITH "com.apple.nsurlsession")')

# Each rule names something Apple's frameworks attribute to the app process
# that is not an app-originated connection, and why. Nothing else is excused.
SYSTEM_OWNED_LOG = (
    {"subsystem": "com.apple.network", "category": "activity",
     "reason": "nw_activity telemetry objects handed to the app over XPC with its launch request; "
               "creating, parenting and completing an activity opens no socket or flow"},
)
# No socket has been seen attributed to an app process without the app
# opening it, so no socket is excused. Add a rule here only with evidence.
SYSTEM_OWNED_SOCKETS = ()


def _run(command, timeout=30):
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    return result.returncode, result.stdout, result.stderr


def app_path_pattern(device, executable):
    """The host path of an app installed on one owned device, as ps prints it."""
    return re.compile(r"/Devices/" + re.escape(device)
                      + r"/data/Containers/Bundle/Application/[0-9A-Fa-f-]+/"
                      + re.escape(executable) + r"\.app/" + re.escape(executable) + r"(?:\s|$)")


def find_app_pids(ps_output, device, executable):
    """PIDs whose command is this app's executable on this device only."""
    pattern = app_path_pattern(device, executable)
    pids = []
    for line in ps_output.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and fields[0].isdigit() and pattern.search(fields[1]):
            pids.append(int(fields[0]))
    return sorted(pids)


def parse_lsof(output):
    """Parse `lsof -F pcfPtTn` field output into one record per socket."""
    sockets, pid, command, current = [], None, None, None
    for line in output.splitlines():
        if not line:
            continue
        key, value = line[0], line[1:]
        if key == "p":
            pid, command, current = int(value), None, None
        elif key == "c":
            command = value
        elif key == "f":
            current = {"pid": pid, "command": command, "fd": value, "type": None,
                       "protocol": None, "name": None, "state": None}
            sockets.append(current)
        elif current is not None:
            if key == "t":
                current["type"] = value
            elif key == "P":
                current["protocol"] = value
            elif key == "n":
                current["name"] = value
            elif key == "T" and value.startswith("ST="):
                current["state"] = value[3:]
    return sockets


def classify_socket(socket):
    for rule in SYSTEM_OWNED_SOCKETS:
        if all(socket.get(key) == value for key, value in rule.items() if key != "reason"):
            return rule["reason"]
    return None


def classify_log_entry(entry):
    for rule in SYSTEM_OWNED_LOG:
        if entry.get("subsystem") == rule["subsystem"] and entry.get("category") == rule["category"]:
            return rule["reason"]
    return None


def parse_log(output):
    """Parse `log show --style ndjson` output, keeping only event rows."""
    entries = []
    for line in output.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            row = json.loads(line)
        except ValueError:
            continue
        if isinstance(row, dict) and row.get("eventMessage") is not None:
            entries.append({key: row.get(key) for key in ("timestamp", "processID", "processImagePath",
                                                          "subsystem", "category", "messageType", "eventMessage")})
    return entries


class Observer:
    """Sample one app's sockets on one owned device on a background thread."""

    def __init__(self, device, executable, output, label, *, interval=SAMPLE_INTERVAL,
                 runner=None, clock=time.time):
        self.device, self.executable, self.label = device, executable, label
        self.output, self.interval, self.clock = Path(output), interval, clock
        self.runner = runner or _run
        self.samples_path = self.output / f"{label}-network-samples.jsonl"
        self.report_path = self.output / f"{label}-network.json"
        self.started = None
        self.attempts = 0
        self.samples = 0
        self.samples_with_app = 0
        self.timeouts = []
        self.max_gap = 0.0
        self.pids = set()
        self.sockets = []
        self.errors = []
        self._stop = threading.Event()
        self._thread = None
        self._previous = None

    def start(self):
        self.started = self.clock()
        self.samples_path.write_text("")
        self._thread = threading.Thread(target=self._loop, name=f"network-observer-{self.label}", daemon=True)
        self._thread.start()
        return self

    def sample_once(self):
        now = self.clock()
        code, ps_output, error = self.runner(["ps", "-axo", "pid=,command="])
        if code:
            raise RuntimeError(f"ps failed ({code}): {error.strip()}")
        pids = find_app_pids(ps_output, self.device, self.executable)
        sockets = []
        if pids:
            # lsof exits 1 when it finds nothing; that is a clean sample.
            code, lsof_output, error = self.runner(["lsof", "-nP", "-a", "-i", "-p", ",".join(map(str, pids)),
                                                    "-F", "pcfPtTn"])
            if code not in (0, 1):
                raise RuntimeError(f"lsof failed ({code}): {error.strip()}")
            sockets = parse_lsof(lsof_output)
        record = {"time": round(now, 3), "pids": pids, "sockets": sockets}
        with self.samples_path.open("a") as stream:
            stream.write(json.dumps(record) + "\n")
        self.samples += 1
        self.samples_with_app += bool(pids)
        self.pids.update(pids)
        for socket in sockets:
            self.sockets.append(dict(socket, time=record["time"]))
        return record

    def sample(self):
        """One sample; an error is recorded and fails the gate but never ends observation early."""
        self.attempts += 1
        try:
            record = self.sample_once()
        except subprocess.TimeoutExpired as error:
            self.timeouts.append(f"{round(self.clock(), 3)}: {error}")
            return
        except Exception as error:
            self.errors.append(f"{type(error).__name__}: {error}")
            return
        if self._previous is not None:
            self.max_gap = max(self.max_gap, record["time"] - self._previous)
        self._previous = record["time"]

    def _loop(self):
        while not self._stop.is_set():
            self.sample()
            self._stop.wait(self.interval)

    def stop(self):
        if self._thread:
            self._stop.set()
            self._thread.join(timeout=60)
            if self._thread.is_alive():
                self.errors.append("Sampler thread did not stop")
            self._thread = None

    def read_log(self):
        start = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(self.started - 1))
        predicate = f'process == "{self.executable}" AND {LOG_PREDICATE}'
        code, output, error = self.runner(["xcrun", "simctl", "spawn", self.device, "log", "show", "--start", start,
                                           "--info", "--debug", "--style", "ndjson", "--predicate", predicate],
                                          timeout=300)
        (self.output / f"{self.label}-network-log.ndjson").write_text(output)
        if code:
            raise RuntimeError(f"Device log read failed ({code}): {error.strip()[-500:]}")
        return parse_log(output)

    def finish(self, read_log=True):
        """Stop sampling, read the log channel and write the report. Returns it."""
        self.stop()
        log_entries = []
        if read_log:
            try:
                log_entries = self.read_log()
            except Exception as error:
                self.errors.append(f"{type(error).__name__}: {error}")
        report = evaluate(self, log_entries, log_read=read_log)
        self.report_path.write_text(json.dumps(report, indent=2) + "\n")
        return report


def evaluate(observer, log_entries, log_read=True):
    violations, system_owned = [], []
    # A socket held across many samples is one finding with its sample count.
    grouped = {}
    for socket in observer.sockets:
        key = tuple(socket.get(field) for field in ("pid", "fd", "type", "protocol", "name", "state"))
        if key not in grouped:
            grouped[key] = dict(socket, channel="socket", firstSeen=socket["time"], samples=0)
            grouped[key].pop("time")
        grouped[key]["lastSeen"] = socket["time"]
        grouped[key]["samples"] += 1
    for socket in grouped.values():
        reason = classify_socket(socket)
        (system_owned if reason else violations).append(dict(socket, **({"reason": reason} if reason else {})))
    log_system = {}
    for entry in log_entries:
        reason = classify_log_entry(entry)
        if reason:
            key = (entry.get("subsystem"), entry.get("category"))
            log_system.setdefault(key, {"channel": "log", "subsystem": key[0], "category": key[1],
                                        "reason": reason, "entries": 0, "examples": []})
            log_system[key]["entries"] += 1
            if len(log_system[key]["examples"]) < 3:
                log_system[key]["examples"].append(entry.get("eventMessage"))
        else:
            violations.append(dict(entry, channel="log"))
    system_owned.extend(log_system.values())
    problems = list(observer.errors)
    if len(observer.timeouts) > MAX_TIMEOUT_SHARE * max(observer.attempts, 1):
        problems.append(f"{len(observer.timeouts)} of {observer.attempts} samples timed out, more than "
                        f"{MAX_TIMEOUT_SHARE:.0%}; the socket channel was not watching (first: {observer.timeouts[0]})")
    if not observer.samples_with_app:
        problems.append(f"No sample saw {observer.executable}; the observer cannot claim the app made no connection")
    if not log_read:
        problems.append("Device log was not read")
    passed = not violations and not problems
    return {
        "device": observer.device, "executable": observer.executable,
        "method": {"sockets": f"ps -axo pid=,command= matched to the app path on this device, then "
                              f"lsof -nP -a -i -p <pids> every {observer.interval}s",
                   "log": f"xcrun simctl spawn <device> log show --predicate 'process == \"{observer.executable}\" "
                          f"AND {LOG_PREDICATE}'",
                   "limits": "A socket opened and closed between two samples is visible only through the log "
                             "channel, which covers Apple's networking stacks, not raw BSD sockets."},
        "samples": observer.samples, "samplesWithApp": observer.samples_with_app,
        "maxSampleGapSeconds": round(observer.max_gap, 3), "samplerTimeouts": observer.timeouts,
        "pids": sorted(observer.pids),
        "logEntries": len(log_entries), "violations": violations, "systemOwned": system_owned,
        "problems": problems, "passed": passed,
    }


def summary(report):
    if report["passed"]:
        excused = sum(item.get("entries", 1) for item in report["systemOwned"])
        timeouts = f", {len(report['samplerTimeouts'])} timed out" if report["samplerTimeouts"] else ""
        return (f"no app-originated network activity in {report['samples']} samples "
                f"({report['samplesWithApp']} with the app running{timeouts}; max gap {report['maxSampleGapSeconds']}s) "
                f"and {report['logEntries']} networking log entries ({excused} system-owned, listed with reasons)")
    details = [f"{v['channel']}: " + (f"{v.get('protocol')} {v.get('name')} {v.get('state') or ''} pid {v.get('pid')}"
                                       if v["channel"] == "socket" else
                                       f"[{v.get('subsystem')}:{v.get('category')}] {v.get('eventMessage')}")
               for v in report["violations"][:10]]
    return "; ".join(details + report["problems"])
