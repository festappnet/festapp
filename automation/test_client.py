"""Complete offline client suite. Own process groups, separate JSON per lane."""
import json
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

from client_test_inventory import is_semantic_case

ROOT = Path(__file__).resolve().parent.parent


def client_concurrency():
    # Three workers exceeded the measured budget during shared-session compilation.
    # Keep one portable cap; explicit experiments can override it at invocation.
    value = os.environ.get("FESTAPP_CLIENT_CONCURRENCY")
    if value is None:
        return min(2, max(1, (os.cpu_count() or 2) // 2))
    try:
        workers = int(value)
    except ValueError:
        raise SystemExit("FESTAPP_CLIENT_CONCURRENCY must be a positive integer.")
    if workers < 1:
        raise SystemExit("FESTAPP_CLIENT_CONCURRENCY must be a positive integer.")
    return workers


def main():
    mode = sys.argv[1] if len(sys.argv) == 2 else "all" if len(sys.argv) == 1 else ""
    if mode not in ("all", "core", "flutter"):
        sys.exit("Usage: automation/test_client.sh [all|core|flutter]")
    workers = client_concurrency()
    if not shutil.which("fvm"):
        sys.exit("Client tests require FVM; no system SDK fallback is supported.")
    core = ROOT / "packages/festapp_core"
    for directory in (ROOT, core):
        if not (directory / ".dart_tool/package_config.json").is_file():
            sys.exit(f"Resolve dependencies first in {directory} using FVM pub get.")
    output = Path(os.environ.get("FESTAPP_CLIENT_RESULTS", tempfile.mkdtemp(prefix="festapp-client-")))
    output.mkdir(parents=True, exist_ok=True)
    lanes = []
    if mode in ("all", "core"):
        lanes.append(("core", core, ["fvm", "dart", "test", "--reporter=json"]))
    if mode in ("all", "flutter"):
        lanes.append(("flutter", ROOT, ["fvm", "flutter", "test", "--no-pub", "--reporter=json"]))
    if mode == "all" and (ROOT / "test_dart").is_dir():
        lanes.append(("adapters", ROOT, ["fvm", "dart", "test", "test_dart", "--reporter=json"]))
    for _, _, command in lanes:
        command.append(f"--concurrency={workers}")
    processes = []
    children = []
    observers = ThreadPoolExecutor(max_workers=len(lanes))

    def finish(process, lane_started):
        code = process.wait()
        return code, time.monotonic() - lane_started

    def cancel(signum, _frame):
        for process in children:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            except PermissionError:
                if process.poll() is None:
                    raise
        deadline = time.monotonic() + 5
        for process in children:
            try:
                process.wait(timeout=max(.01, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                pass
            # A parent may already have exited while its testers are still alive.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            except PermissionError:
                # macOS reports EPERM for a group containing only dead members.
                # A live owned parent must still be signalable.
                if process.poll() is None:
                    raise
            process.wait()
        sys.exit(128 + signum)

    signal.signal(signal.SIGINT, cancel)
    signal.signal(signal.SIGTERM, cancel)
    started = time.monotonic()
    try:
        # The guard is an owned process too, including cancellation during startup.
        guard = subprocess.Popen(["fvm", "dart", "run", "tool/check_architecture.dart", str(ROOT)],
                                 cwd=core, start_new_session=True)
        children.append(guard)
        guard_code = None
        if mode != "all":
            guard_code = guard.wait()
            children.remove(guard)
            if guard_code != 0:
                return 1
        # Dart/VM work completes before Flutter's large compiler/engine phase.
        # Their independent results are still collected even when one fails.
        phases = ([[lane for lane in lanes if lane[0] != "flutter"],
                   [lane for lane in lanes if lane[0] == "flutter"]]
                  if mode == "all" else [lanes])
        for phase in phases:
            # The independent architecture check overlaps only cheap Dart/VM
            # work. Every first-phase process finishes before Flutter starts.
            if phase and phase[0][0] == "flutter" and guard_code is None:
                guard_code = guard.wait()
                children.remove(guard)
            pending = []
            for name, cwd, command in phase:
                stdout = (output / f"{name}.jsonl").open("w")
                stderr = (output / f"{name}.stderr").open("w")
                lane_started = time.monotonic()
                process = subprocess.Popen(command, cwd=cwd, stdout=stdout, stderr=stderr, start_new_session=True)
                children.append(process)
                receipt = observers.submit(finish, process, lane_started)
                processes.append((name, process, stdout, stderr, receipt))
                pending.append(receipt)
            for receipt in pending:
                receipt.result()
        failed = guard_code != 0
        results = {"architectureSuccess": guard_code == 0}
        for name, process, stdout, stderr, receipt in processes:
            code, lane_seconds = receipt.result()
            stdout.close()
            stderr.close()
            events = []
            for line in (output / f"{name}.jsonl").read_text().splitlines():
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
            done = next((e for e in reversed(events) if e.get("type") == "done"), {})
            success = code == 0 and done.get("success") is True
            failed |= not success
            test_ids = {e["test"]["id"] for e in events
                        if e.get("type") == "testStart" and is_semantic_case(e["test"])}
            outcomes = [e for e in events if e.get("type") == "testDone" and e["testID"] in test_ids]
            results[name] = {"exitCode": code, "success": success, "seconds": lane_seconds,
                             "testSeconds": done.get("time", 0) / 1000, "cases": len(test_ids),
                             "skipped": sum(e.get("skipped", False) for e in outcomes),
                             "failed": sum(e["result"] != "success" for e in outcomes),
                             "suites": sum(e.get("type") == "suite" for e in events)}
            print(f"{name}: {'PASS' if success else 'FAIL'} ({results[name]['seconds']:.2f}s)", flush=True)
            if not success:
                for event in events:
                    if event.get("type") == "error":
                        print(event.get("error", "Test failed"), file=sys.stderr)
                print((output / f"{name}.stderr").read_text()[-3000:], file=sys.stderr)
        observers.shutdown(wait=True)
        results["mode"] = mode
        results["concurrency"] = workers
        results["schedule"] = "Dart+VM then Flutter" if mode == "all" else "partial"
        if mode == "all":
            check = subprocess.run([sys.executable, str(ROOT / "automation/client_test_inventory.py"), "check", str(output)])
            failed |= check.returncode != 0
            results["inventorySuccess"] = check.returncode == 0
        results["success"] = not failed
        results["seconds"] = time.monotonic() - started
        (output / "summary.json").write_text(json.dumps(results, indent=2) + "\n")
        print(f"{'Complete suite' if mode == 'all' else 'PARTIAL ' + mode}: {results['seconds']:.2f}s; results: {output}")
        return int(failed)
    except BaseException:
        cancel(signal.SIGTERM, None)


if __name__ == "__main__":
    sys.exit(main())
