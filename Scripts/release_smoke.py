#!/usr/bin/env python3
"""Install/launch a built app using a renewing, scoped Simlock lease."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def run_leased(lease, command):
    if lease.poll() is not None:
        raise RuntimeError("Simlock lease ended; stopping the smoke check")
    process = subprocess.Popen(command)
    try:
        while True:
            try:
                code = process.wait(timeout=0.2)
                break
            except subprocess.TimeoutExpired:
                if lease.poll() is not None:
                    raise RuntimeError("Simlock lease ended; stopping the smoke check")
        if code:
            raise subprocess.CalledProcessError(code, command)
        if lease.poll() is not None:
            raise RuntimeError("Simlock lease ended during the smoke check")
    finally:
        stop(process)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--bundle-id", required=True)
    args = parser.parse_args()
    if not args.app.is_dir():
        parser.error(f"app does not exist: {args.app}")
    subprocess.run(["simlock", "whoami"], check=True)
    subprocess.run(["simlock", "instructions"], check=True)
    subprocess.run(["simlock", "catalog"], check=True)
    # Let Simlock pick an available phone unless the operator selects a model
    # from the catalog. Never create a simulator or allow runtime downloads.
    command = ["simlock", "lease", "--platform", "ios", "--timeout", "5m"]
    if os.environ.get("SIMLOCK_DEVICE"):
        command += ["--device", os.environ["SIMLOCK_DEVICE"]]
    else:
        command += ["--class", "phone"]
    command += ["--os", os.environ.get("SIMLOCK_OS", ">=26.0")]
    lease = subprocess.Popen(command, stdout=subprocess.PIPE, text=True)
    try:
        line = lease.stdout.readline()
        if not line:
            raise RuntimeError(f"Simlock did not grant a lease (exit {lease.wait()})")
        grant = json.loads(line)
        address = grant["device"]["address"]
        lease_id = grant["lease"]["id"]
        prefix = ["simlock", "simctl", "--lease", lease_id]
        run_leased(lease, prefix + ["bootstatus", address, "-b"])
        run_leased(lease, prefix + ["install", address, str(args.app.resolve())])
        run_leased(lease, prefix + ["launch", address, args.bundle_id])
        print("Simulator install/launch passed (not a UI acceptance test).", flush=True)
    finally:
        # The foreground CLI renews its own lease and releases it on SIGTERM.
        stop(lease)
        lease.stdout.close()


if __name__ == "__main__":
    def interrupted(signum, frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, interrupted)
    main()
