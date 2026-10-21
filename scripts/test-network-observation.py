#!/usr/bin/env python3
"""Prove the network observation gate fails on app-originated traffic and passes a clean app.

Three layers, cheapest first:
  1. Mocked sampler and log input: an outbound TCP connection, an unexplained
     networking log entry, a missing app process and a sampler error each fail;
     a clean sample passes, and system-owned log entries pass only while listed
     with their reason. Another device's copy of the app is never attributed.
  2. Live host processes: a compiled fixture executable placed at a simulator
     app path connects to a loopback listener (fails) or stays idle (passes),
     observed with the real ps and lsof sampler.
  3. --simulator: a throwaway iOS app built here and installed on an owned
     simulator opens a Network.framework TCP connection to a loopback
     listener (fails on both channels) or launches idle (passes). The
     simulator is deleted even on failure.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import sys
import tempfile
import threading
import time
import uuid

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
import network_observation as observation  # noqa: E402

DEVICE = "11111111-2222-3333-4444-555555555555"
OTHER_DEVICE = "99999999-8888-7777-6666-555555555555"


def app_command(device, executable, container="0A0B0C0D-0000-1111-2222-333344445555"):
    return (f"/Users/ci/Library/Developer/CoreSimulator/Devices/{device}/data/Containers/Bundle/Application/"
            f"{container}/{executable}.app/{executable}")


PS = "\n".join([
    f"  101 {app_command(DEVICE, 'BlockTitle')}",
    f"  102 {app_command(OTHER_DEVICE, 'BlockTitle')}",
    f"  103 {app_command(DEVICE, 'BlockTitleUITests-Runner')}",
    f"  104 {app_command(DEVICE, 'BlockTitle')}Helper",
    "  105 /usr/libexec/nsurlsessiond",
])
OUTBOUND = "p101\ncBlockTitle\nf12\ntIPv4\nPTCP\nn10.0.0.2:51234->17.253.144.10:443\nTST=ESTABLISHED\nTQR=0\n"
CFNETWORK = json.dumps({"timestamp": "2026-10-20 19:00:00.000000-0700", "processID": 101, "subsystem": "com.apple.CFNetwork",
                        "category": "Summary", "messageType": "Default",
                        "eventMessage": "Task <1A2B>.<1> summary for task success {transaction_duration_ms=42}"})
ACTIVITY = json.dumps({"timestamp": "2026-10-20 19:00:00.000000-0700", "processID": 101, "subsystem": "com.apple.network",
                       "category": "activity", "messageType": "Default",
                       "eventMessage": "Create activity from XPC object <nw_activity 50:1 [C77A] (reporting strategy default)>"})


def scripted(ps=PS, lsof="", log="", lsof_code=None, log_code=0, ps_timeouts=0):
    calls = []

    def runner(command, timeout=30):
        calls.append(command)
        if command[0] == "ps":
            if sum(call[0] == "ps" for call in calls) <= ps_timeouts:
                raise subprocess.TimeoutExpired(command, timeout)
            return 0, ps, ""
        if command[0] == "lsof":
            return (lsof_code if lsof_code is not None else (0 if lsof else 1)), lsof, "lsof: fixture error"
        if "log" in command:
            return log_code, log, "log: fixture error"
        raise AssertionError(command)
    return runner, calls


def observe(directory, runner, samples=3):
    observer = observation.Observer(DEVICE, "BlockTitle", directory, "fixture", runner=runner)
    observer.started = time.time()
    observer.samples_path.write_text("")
    for _ in range(samples):
        observer.sample()
    return observer.finish()


def mocked_cases():
    with tempfile.TemporaryDirectory(prefix="gamecore-network-mock-") as temporary:
        root = Path(temporary)
        assert observation.find_app_pids(PS, DEVICE, "BlockTitle") == [101], "Only the owned device's app executable"
        cases = [
            ("clean sample", scripted(), True, None),
            ("outbound TCP connection", scripted(lsof=OUTBOUND), False, "17.253.144.10:443"),
            ("unexplained CFNetwork log entry", scripted(log=CFNETWORK + "\n"), False, "CFNetwork:Summary"),
            ("system-owned nw_activity listed with its reason", scripted(log=ACTIVITY + "\n"), True, None),
            ("app never observed", scripted(ps="  105 /usr/libexec/nsurlsessiond"), False, "No sample saw"),
            ("sampler failure", scripted(lsof_code=2), False, "lsof failed"),
            ("log read failure", scripted(log_code=1), False, "Device log read failed"),
            # A ps stalled on a loaded host is a counted gap; a sampler that mostly stalls fails.
            ("one timed-out sample in twenty", scripted(ps_timeouts=1), True, "1 timed out"),
            ("timed-out samples above the share", scripted(ps_timeouts=3), False, "3 of 20 samples timed out"),
        ]
        for index, (name, (runner, calls), passes, needle) in enumerate(cases):
            directory = root / str(index)
            directory.mkdir()
            report = observe(directory, runner, samples=20 if "timed-out" in name else 3)
            text = observation.summary(report)
            assert report["passed"] is passes, (name, report)
            if needle:
                assert needle in text, (name, text)
            assert (directory / "fixture-network.json").is_file() and (directory / "fixture-network-samples.jsonl").is_file()
            assert all("101" in call[call.index("-p") + 1] for call in calls if call[0] == "lsof"), name
            if name.startswith("outbound"):
                violation = report["violations"][0]
                # One held socket is one finding, counted across samples.
                assert len(report["violations"]) == 1 and violation["samples"] == 3 and violation["state"] == "ESTABLISHED"
            if name.startswith("system-owned"):
                listed = report["systemOwned"]
                assert listed and listed[0]["reason"] and listed[0]["entries"] == 1, listed
            print(f"PASS mocked {name}: gate {'passes' if passes else 'fails'}")


FIXTURE_C = r"""
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc > 1) {
        int descriptor = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in address = {.sin_family = AF_INET, .sin_port = htons(atoi(argv[1]))};
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
        if (connect(descriptor, (struct sockaddr *)&address, sizeof(address)) != 0) return 2;
        write(descriptor, "fixture", 7);
    }
    sleep(3);
    return 0;
}
"""


class Listener:
    """A loopback TCP listener that accepts and holds the fixture's connection."""

    def __enter__(self):
        self.server = socket.socket()
        self.server.bind(("127.0.0.1", 0))
        self.server.listen()
        self.port = self.server.getsockname()[1]
        self.accepted = []
        threading.Thread(target=self._accept, daemon=True).start()
        return self

    def _accept(self):
        try:
            while True:
                connection, _ = self.server.accept()
                self.accepted.append(connection)
        except OSError:
            pass

    def __exit__(self, *exc):
        for connection in self.accepted:
            connection.close()
        self.server.close()


def host_cases():
    with tempfile.TemporaryDirectory(prefix="gamecore-network-host-") as temporary:
        root = Path(temporary)
        device = str(uuid.uuid4()).upper()
        bundle = root / f"Devices/{device}/data/Containers/Bundle/Application/{str(uuid.uuid4()).upper()}/Fixture.app"
        bundle.mkdir(parents=True)
        (root / "fixture.c").write_text(FIXTURE_C)
        subprocess.run(["xcrun", "clang", "-O", str(root / "fixture.c"), "-o", str(bundle / "Fixture")],
                       check=True, capture_output=True)

        def runner(command, timeout=30):
            if "log" in command:
                return 0, "", ""  # The log channel needs a simulator; layer 3 covers it.
            return observation._run(command, timeout)

        with Listener() as listener:
            for name, arguments, passes in [("idle host process", [], True),
                                            ("host process connecting to loopback", [str(listener.port)], False)]:
                output = root / name.replace(" ", "-")
                output.mkdir()
                observer = observation.Observer(device, "Fixture", output, "host", runner=runner, interval=0.1).start()
                process = subprocess.Popen([str(bundle / "Fixture")] + arguments)
                try:
                    time.sleep(1.5)
                finally:
                    report = observer.finish()
                    process.wait(timeout=10)
                assert process.returncode == 0, (name, process.returncode)
                assert report["samplesWithApp"] > 0, (name, report)
                assert report["passed"] is passes, (name, observation.summary(report))
                if not passes:
                    assert any(v.get("protocol") == "TCP" and f":{listener.port}" in (v.get("name") or "")
                               for v in report["violations"]), report["violations"]
                print(f"PASS live {name}: gate {'passes' if passes else 'fails'} ({observation.summary(report)[:120]})")


FIXTURE_SWIFT = r"""
import Network
import UIKit

final class FixtureDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var connection: NWConnection?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController()
        window?.makeKeyAndVisible()
        if let value = ProcessInfo.processInfo.environment["FIXTURE_CONNECT_PORT"], let number = UInt16(value),
           let port = NWEndpoint.Port(rawValue: number) {
            let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
            connection.start(queue: .main)
            connection.send(content: Data("fixture".utf8), completion: .contentProcessed { _ in })
            self.connection = connection
        }
        return true
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(FixtureDelegate.self))
"""


def simulator_cases():
    spec = importlib.util.spec_from_file_location("mobile_runner", SCRIPTS / "run-mobile-tests.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    run = runner.run
    owner = "".join(c for c in os.environ.get("GAMECORE_SIM_OWNER", "") if c.isalnum() or c == "-")[:32]
    bundle_identifier = "local.gamecore.NetworkFixture"
    with tempfile.TemporaryDirectory(prefix="gamecore-network-sim-") as temporary:
        root = Path(temporary)
        app = root / "NetworkFixture.app"
        app.mkdir()
        (root / "main.swift").write_text(FIXTURE_SWIFT)
        architecture = os.uname().machine
        subprocess.run(["xcrun", "--sdk", "iphonesimulator", "swiftc", "-swift-version", "5",
                        "-target", f"{architecture}-apple-ios18.0-simulator", str(root / "main.swift"),
                        "-o", str(app / "NetworkFixture")], check=True, capture_output=True)
        with (app / "Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": bundle_identifier, "CFBundleExecutable": "NetworkFixture",
                           "CFBundleName": "NetworkFixture", "CFBundlePackageType": "APPL",
                           "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "MinimumOSVersion": "18.0",
                           "CFBundleSupportedPlatforms": ["iPhoneSimulator"], "UIDeviceFamily": [1, 2],
                           "UILaunchScreen": {}}, stream)
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
        runtime = runner.select_runtime()
        device = None
        try:
            name = " ".join(filter(None, ["GameCore network fixture", owner, uuid.uuid4().hex[:8]]))
            device = run(["xcrun", "simctl", "create", name, "com.apple.CoreSimulator.SimDeviceType.iPhone-12",
                          runtime["identifier"]])
            run(["xcrun", "simctl", "boot", device])
            run(["xcrun", "simctl", "bootstatus", device, "-b"], timeout=600)
            run(["xcrun", "simctl", "install", device, str(app)], timeout=300)
            with Listener() as listener:
                for case, environment, passes in [("idle simulator app", [], True),
                                                  ("simulator app opening a TCP connection",
                                                   [f"SIMCTL_CHILD_FIXTURE_CONNECT_PORT={listener.port}"], False)]:
                    output = root / case.replace(" ", "-")
                    output.mkdir()
                    observer = observation.Observer(device, "NetworkFixture", output, "simulator").start()
                    try:
                        run(["env"] + environment + ["xcrun", "simctl", "launch", device, bundle_identifier], timeout=300)
                        if passes:
                            time.sleep(4)
                        else:
                            # Hold the observation until the connection exists, however loaded the host is.
                            deadline = time.monotonic() + 120
                            while not listener.accepted and time.monotonic() < deadline:
                                time.sleep(0.2)
                            assert listener.accepted, "The fixture app never connected"
                            time.sleep(2)
                    finally:
                        report = observer.finish()
                        try:
                            run(["xcrun", "simctl", "terminate", device, bundle_identifier], timeout=60)
                        except RuntimeError:
                            pass
                    summary = observation.summary(report)
                    assert report["passed"] is passes, (case, summary, report["violations"][:5])
                    if not passes:
                        channels = {v["channel"] for v in report["violations"]}
                        assert "socket" in channels, (case, summary)
                        assert "log" in channels, (case, "Network.framework log entries expected", summary)
                    listed = [f"{item['subsystem']}:{item['category']} x{item['entries']}"
                              for item in report["systemOwned"]]
                    print(f"PASS simulator {case} on iOS {runtime['version']} iPhone 12: gate "
                          f"{'passes' if passes else 'fails'}; system-owned listed: {listed or 'none'}")
        finally:
            if device:
                for operation in ("shutdown", "delete"):
                    try:
                        run(["xcrun", "simctl", operation, device], timeout=90)
                    except RuntimeError as error:
                        print(f"Cleanup warning (network fixture): {error}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--simulator", action="store_true",
                        help="Also build a throwaway app and prove the gate on an owned simulator")
    args = parser.parse_args()
    mocked_cases()
    host_cases()
    if args.simulator:
        simulator_cases()
    print("Network observation gate fails on app-originated connections and passes a clean app")


if __name__ == "__main__":
    main()
