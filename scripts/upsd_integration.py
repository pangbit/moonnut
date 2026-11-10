#!/usr/bin/env python3
"""Disposable NUT upsd + dummy-ups interoperability demo, no physical UPS access.

Requires Linux NUT 2.8+ (nut-server and nut-client), Python 3.9+, and a built
examples/query executable. Run as a regular user. This creates only temporary
configuration/state, binds only loopback, and stops only its own child processes.
No service-manager commands, global NUT configuration or real driver are used.
"""
import getpass
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "_build/native/debug/build/examples/query/query.exe"
EXPECTED = {
    "device.model": "Virtual UPS",
    "ups.status": "OL CHRG",
    "battery.charge": "100",
    "battery.runtime": "600",
}


def locate(name, candidates=()):
    result = shutil.which(name)
    if result:
        return result
    for candidate in candidates:
        if Path(candidate).is_file():
            return candidate
    # Distribution layouts differ, including /usr/libexec/nut on newer Ubuntu.
    if name == "dummy-ups" and shutil.which("dpkg-query"):
        result = subprocess.run(["dpkg-query", "--listfiles", "nut-server"],
                                capture_output=True, text=True, timeout=5)
        for entry in result.stdout.splitlines():
            path = Path(entry)
            if path.name == name and path.is_file():
                return str(path)
    raise RuntimeError(f"{name} is required; install NUT 2.8+ in an isolated development environment")


def run(args, env):
    return subprocess.run(args, env=env, capture_output=True, text=True, timeout=10)


def main():
    if os.geteuid() == 0:
        raise RuntimeError("Run as a regular user, not root")
    if not BINARY.is_file():
        raise RuntimeError("Run moon build --target native first")
    upsd = locate("upsd", ("/usr/sbin/upsd",))
    driver = locate("dummy-ups", ("/lib/nut/dummy-ups", "/usr/lib/nut/dummy-ups", "/usr/libexec/nut/dummy-ups"))
    upsc = locate("upsc")
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("MOONNUT_", "NUT_"))}
    # The temporary listen reservation is released immediately before upsd starts.
    reservation = socket.socket()
    reservation.bind(("127.0.0.1", 0))
    port = reservation.getsockname()[1]
    children = []
    with tempfile.TemporaryDirectory(prefix="moonnut-upsd-") as folder:
        folder = Path(folder)
        env.update(NUT_CONFPATH=str(folder), NUT_STATEPATH=str(folder),
                   NUT_ALTPIDPATH=str(folder), NUT_QUIET_INIT_UPSNOTIFY="true")
        (folder / "ups.conf").write_text(
            f"statepath = {folder}\n[demo]\n  driver = dummy-ups\n"
            f"  port = {folder / 'demo.dev'}\n  mode = dummy-once\n"
            '  desc = "Synthetic demo UPS"\n')
        (folder / "demo.dev").write_text(
            "device.mfr: moonnut-fixture\n" +
            "".join(f"{key}: {value}\n" for key, value in EXPECTED.items()))
        (folder / "upsd.conf").write_text(
            f"LISTEN 127.0.0.1 {port}\nSTATEPATH {folder}\nMAXAGE 15\n")
        (folder / "upsd.users").write_text("")
        for file in folder.iterdir():
            file.chmod(0o600)
        with (folder / "process.log").open("w+") as log:
            try:
                username = getpass.getuser()
                children.append(subprocess.Popen(
                    [driver, "-a", "demo", "-F", "-u", username], env=env,
                    stdout=log, stderr=subprocess.STDOUT))
                reservation.close()
                children.append(subprocess.Popen(
                    [upsd, "-F", "-u", username], env=env,
                    stdout=log, stderr=subprocess.STDOUT))
                reference = None
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    if any(child.poll() is not None for child in children):
                        raise RuntimeError("NUT child exited during startup")
                    result = run([upsc, f"demo@127.0.0.1:{port}"], env)
                    if result.returncode == 0:
                        values = dict(line.split(": ", 1) for line in result.stdout.splitlines()
                                      if ": " in line)
                        if all(values.get(k) == v for k, v in EXPECTED.items()):
                            reference = values
                            break
                    time.sleep(0.1)
                if reference is None:
                    raise RuntimeError("NUT dummy device did not become ready")

                def query(*args):
                    result = run([str(BINARY), "127.0.0.1", str(port), "--plaintext", *args], env)
                    if result.returncode:
                        raise RuntimeError("moonnut query failed: " + result.stdout)
                    return result.stdout.strip()

                assert query() == "demo\tSynthetic demo UPS"
                variables = dict(line.split("\t", 1) for line in query("--vars", "demo").splitlines())
                for name, expected in EXPECTED.items():
                    assert variables.get(name) == reference[name] == expected, name
                    assert query("--get", "demo", name) == expected, name
                print("upsd integration: LIST UPS, LIST VAR and GET VAR agree with NUT upsc")
                print("Synthetic device only: status=OL CHRG, charge=100%, runtime=600s")
                print("Transport scope: anonymous loopback plaintext; TLS is tested separately")
            except Exception:
                log.flush()
                log.seek(0)
                print(log.read())
                raise
            finally:
                reservation.close()
                for child in reversed(children):
                    if child.poll() is None:
                        child.terminate()
                        try:
                            child.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            child.kill()
                            child.wait(timeout=5)


if __name__ == "__main__":
    main()
