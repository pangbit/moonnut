#!/usr/bin/env python3
"""Disposable NUT upsd + dummy-ups interoperability demo, no physical UPS access.

Requires Linux NUT 2.8+ (nut-server and nut-client), OpenSSL, Python 3.9+, and a built
examples/query executable. NSS-enabled NUT also needs libnss3-tools.
Run as a regular user. This creates only temporary
configuration/state, binds only loopback, and stops only its own child processes.
No service-manager commands, global NUT configuration or real driver are used.
"""
import getpass
import os
from pathlib import Path
import shutil
import secrets
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "_build/native/debug/build/examples/query/query.exe"
EXPECTED = {
    "ups.model": "Virtual UPS",
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



def configure_tls(folder, upsd):
    """Create an ephemeral server identity for the installed NUT TLS backend."""
    cert, key = folder / "cert.pem", folder / "key.pem"
    config = folder / "openssl.cnf"
    config.write_text("[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=ext\n"
                      "[dn]\nCN=localhost\n[ext]\nsubjectAltName=DNS:localhost\n"
                      "basicConstraints=critical,CA:TRUE\n")
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                    "-days", "1", "-keyout", str(key), "-out", str(cert),
                    "-config", str(config)], check=True, capture_output=True)
    links = subprocess.run(["ldd", upsd], check=True, capture_output=True, text=True).stdout
    if "libnss3" in links:
        certutil, pk12util = locate("certutil"), locate("pk12util")
        database = folder / "certdb"
        database.mkdir(mode=0o700)
        db = "sql:" + str(database)
        bundle = folder / "bundle.p12"
        subprocess.run([certutil, "-N", "-d", db, "--empty-password"],
                       check=True, capture_output=True)
        subprocess.run(["openssl", "pkcs12", "-export", "-in", str(cert), "-inkey", str(key),
                        "-out", str(bundle), "-name", "moonnut-fixture", "-passout", "pass:"],
                       check=True, capture_output=True)
        subprocess.run([pk12util, "-i", str(bundle), "-d", db, "-W", "", "-K", ""],
                       check=True, capture_output=True)
        directives = f'CERTPATH {database}\nCERTIDENT "moonnut-fixture" ""\n'
        backend = "NSS"
    elif "libssl" in links:
        bundle = folder / "server.pem"
        bundle.write_bytes(cert.read_bytes() + key.read_bytes())
        directives = f"CERTFILE {bundle}\n"
        backend = "OpenSSL"
    else:
        raise RuntimeError("The NUT integration requires an OpenSSL or NSS-enabled upsd")
    return cert, directives + "DISABLE_WEAK_SSL true\n", backend


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
                   NUT_ALTPIDPATH=str(folder), NUT_QUIET_INIT_UPSNOTIFY="true",
                   NSS_DEFAULT_DB_TYPE="sql")
        (folder / "ups.conf").write_text(
            f"statepath = {folder}\n[demo]\n  driver = dummy-ups\n"
            f"  port = {folder / 'demo.dev'}\n  mode = dummy-once\n"
            '  desc = "Synthetic demo UPS"\n')
        (folder / "demo.dev").write_text(
            "ups.mfr: moonnut-fixture\n" +
            "".join(f"{key}: {value}\n" for key, value in EXPECTED.items()))
        cert, tls_directives, backend = configure_tls(folder, upsd)
        password = secrets.token_hex(24)
        (folder / "upsd.conf").write_text(
            f"LISTEN 127.0.0.1 {port}\nSTATEPATH {folder}\nMAXAGE 15\n" + tls_directives)
        # No actions or instant commands are granted to this disposable account.
        (folder / "upsd.users").write_text(f"[fixture]\n  password = {password}\n")
        for file in folder.iterdir():
            if file.is_file():
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
                        if all(k in values for k in EXPECTED):
                            reference = values
                            break
                    time.sleep(0.1)
                if reference is None:
                    raise RuntimeError("NUT dummy device did not become ready: " +
                                       result.stdout + result.stderr)

                def query(*args):
                    result = run([str(BINARY), "127.0.0.1", str(port), "--plaintext", *args], env)
                    if result.returncode:
                        raise RuntimeError("moonnut query failed: " + result.stdout)
                    return result.stdout.strip()

                assert query() == "demo\tSynthetic demo UPS"
                variables = dict(line.split("\t", 1) for line in query("--vars", "demo").splitlines())
                for name, expected in EXPECTED.items():
                    assert variables.get(name) == reference[name] == expected, (name, variables.get(name), reference[name], expected)
                    assert query("--get", "demo", name) == expected, name
                print("upsd integration: LIST UPS, LIST VAR and GET VAR agree with NUT upsc")
                print("Synthetic device only: status=OL CHRG, charge=100%, runtime=600s")
                auth_env = dict(env, MOONNUT_USERNAME="fixture", MOONNUT_PASSWORD=password)
                trusted = [str(BINARY), "localhost", str(port), "--ca", str(cert)]
                secure = run(trusted + ["--get", "demo", "ups.status"], auth_env)
                assert secure.returncode == 0 and secure.stdout.strip() == EXPECTED["ups.status"], "verified NUT TLS/auth GET failed"
                secure_devices = run(trusted, auth_env)
                assert secure_devices.returncode == 0 and secure_devices.stdout.strip() == "demo\tSynthetic demo UPS", "verified NUT TLS/auth LIST UPS failed"
                secure_variables = run(trusted + ["--vars", "demo"], auth_env)
                assert secure_variables.returncode == 0, "verified NUT TLS/auth LIST VAR failed"
                secure_values = dict(line.split("\t", 1) for line in secure_variables.stdout.strip().splitlines())
                assert all(secure_values.get(k) == v for k, v in EXPECTED.items())
                wrong_password = run(trusted, dict(auth_env, MOONNUT_PASSWORD="wrong-fixture-password"))
                # NUT stores USERNAME/PASSWORD for later privileged commands.
                # Anonymous reads may still succeed; OK is not an auth verdict.
                if wrong_password.returncode == 0:
                    assert wrong_password.stdout.strip() == "demo\tSynthetic demo UPS"
                    print("NUT permits read-only queries after a wrong password; credentials are not proven valid")
                else:
                    print("This NUT policy rejects the supplied incorrect credentials")
                untrusted = run([str(BINARY), "localhost", str(port)], auth_env)
                assert untrusted.returncode != 0, "untrusted NUT certificate was accepted"
                wrong_host = run([str(BINARY), "127.0.0.1", str(port), "--ca", str(cert)], auth_env)
                assert wrong_host.returncode != 0, "NUT certificate hostname mismatch was accepted"
                print(f"NUT {backend} STARTTLS: credentialed reads and certificate rejection passed")
                print("Transport scope: loopback plaintext and verified TLS with credentials; no physical device")
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
