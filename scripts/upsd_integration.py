#!/usr/bin/env python3
"""Disposable NUT upsd + synthetic UPS interoperability demo, no physical UPS access.

Requires Linux NUT 2.8+ (nut-server and nut-client), OpenSSL, Python 3.9+, and a built
examples/query executable. NSS-enabled NUT also needs libnss3-tools.
Optionally pass --pynut /external/path/PyNUT.py for a pinned public-API comparison.
Run as a regular user. This creates only temporary
configuration/state, binds only loopback, and stops only its own child processes.
No service-manager commands, global NUT configuration or real driver are used.
"""
import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import shutil
import secrets
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "_build/native/debug/build/examples/query/query.exe"
PYNUT_SHA256 = "a12d1e40f8cd926314157c137372628322dd09db94d697aca4bc9dc8beb64f82"
EXPECTED = {
    "ups.model": "Virtual UPS",
    "ups.status": "OL CHRG",
    "battery.charge": "100",
    "battery.runtime": "600",
}


class DiscoveryDriver:
    """Minimal synthetic driver state for real upsd, not a physical/dummy driver.

    dummy-ups does not advertise ENUM/RANGE metadata. This fixture supplies two
    disjoint ranges and a string enum through NUT's documented Unix socket
    protocol, so official upsrw and moonnut read the same real upsd responses.
    No client write or instant command is accepted.
    """
    def __init__(self, folder):
        self.listener = socket.socket(socket.AF_UNIX)
        self.listener.bind(str(folder / "moonnut-fixture-metadata"))
        self.listener.listen(1)
        self.listener.settimeout(0.2)
        self.stop = threading.Event()
        self.errors = []
        self.worker = threading.Thread(target=self.serve, daemon=True)
        self.worker.start()

    def serve(self):
        state = (
            'SETINFO ups.status "OL"\n'
            'SETINFO ups.beeper.status "enabled"\n'
            'SETFLAGS ups.beeper.status RW STRING\n'
            'SETAUX ups.beeper.status 16\n'
            'ADDENUM ups.beeper.status "enabled"\n'
            'ADDENUM ups.beeper.status "disabled"\n'
            'SETINFO input.transfer.low "95"\n'
            'SETFLAGS input.transfer.low RW NUMBER\n'
            'ADDRANGE input.transfer.low 90 100\n'
            'ADDRANGE input.transfer.low 102 105\n'
            'ADDCMD load.off\n'
            'ADDCMD test.battery.start.quick\n'
            'DATAOK\nDUMPDONE\n'
        ).encode()
        try:
            while not self.stop.is_set():
                try:
                    conn, _ = self.listener.accept()
                except socket.timeout:
                    continue
                with conn:
                    conn.settimeout(0.2)
                    pending = b""
                    while not self.stop.is_set():
                        try:
                            chunk = conn.recv(4096)
                        except socket.timeout:
                            continue
                        if not chunk:
                            break
                        pending += chunk
                        assert len(pending) < 8192, "driver request too long"
                        while b"\n" in pending:
                            line, pending = pending.split(b"\n", 1)
                            if line == b"DUMPALL":
                                conn.sendall(state)
                            elif line == b"PING":
                                conn.sendall(b"PONG\n")
                            else:
                                raise AssertionError("unexpected driver request: " + repr(line))
        except Exception as error:
            self.errors.append(error)

    def close(self):
        self.stop.set()
        self.worker.join(2)
        self.listener.close()
        assert not self.worker.is_alive(), "fixture driver failed to stop"
        assert not self.errors, self.errors


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


def validate_pynut(path):
    path = Path(path).resolve()
    if ROOT == path or ROOT in path.parents:
        raise RuntimeError("Keep the GPL reference outside this repository")
    if hashlib.sha256(path.read_bytes()).hexdigest() != PYNUT_SHA256:
        raise RuntimeError("Expected the unmodified official PyNUT v2.8.3 reference")
    return path


def pynut_results(path, port, env):
    # Only public methods, in a separate process; no copied reference internals.
    code = """import importlib.util,json,sys
spec=importlib.util.spec_from_file_location('PyNUT',sys.argv[1])
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
client=module.PyNUTClient(host='127.0.0.1',port=int(sys.argv[2]),timeout=5)
def text(value):
    return value.decode('utf-8') if isinstance(value,bytes) else value
def mapping(values):
    return {text(k):text(v) for k,v in values.items()}
result={'ups':mapping(client.GetUPSList()),'variables':mapping(client.GetUPSVars('demo'))}
try:
    client.GetUPSVars('missing')
except module.PyNUTError as error:
    result['unknown_ups']=str(error)
print(json.dumps(result))
"""
    result = run([sys.executable, "-c", code, str(path), str(port)], env)
    if result.returncode:
        raise RuntimeError("PyNUT comparison failed: " + result.stderr)
    return json.loads(result.stdout)


def upsc_mapping(result):
    assert result.returncode == 0, result.stdout + result.stderr
    return dict(line.split(": ", 1) for line in result.stdout.splitlines())


def rw_sections(result):
    assert result.returncode == 0, result.stdout + result.stderr
    sections = {}
    current = None
    for line in result.stdout.splitlines():
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            assert current not in sections, "duplicate upsrw variable"
            sections[current] = []
        elif current and line:
            sections[current].append(line)
    return sections


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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pynut", type=validate_pynut,
                        help="External official PyNUT v2.8.3 module (SHA-256 verified)")
    args = parser.parse_args()
    if os.geteuid() == 0:
        raise RuntimeError("Run as a regular user, not root")
    if not BINARY.is_file():
        raise RuntimeError("Run moon build --target native first")
    upsd = locate("upsd", ("/usr/sbin/upsd",))
    driver = locate("dummy-ups", ("/lib/nut/dummy-ups", "/usr/lib/nut/dummy-ups", "/usr/libexec/nut/dummy-ups"))
    upsc = locate("upsc")
    upsrw = locate("upsrw")
    upscmd = locate("upscmd")
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("MOONNUT_", "NUT_"))}
    for program in (upsd, driver, upsc, upsrw, upscmd):
        version = run([program, "-V"], env)
        assert version.returncode == 0, version.stderr
        banner = (version.stdout + version.stderr).strip().splitlines()[0]
        print(Path(program).name + ": " + banner, flush=True)
    if args.pynut:
        print("PyNUT: NUT v2.8.3 / module 1.8.0 / SHA-256 " + PYNUT_SHA256, flush=True)
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
            '  desc = "Synthetic demo UPS"\n'
            '[metadata]\n  driver = moonnut-fixture\n  port = unused\n'
            '  desc = "Synthetic discovery state"\n')
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
        discovery_driver = DiscoveryDriver(folder)
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
                            metadata_ready = run([upsc, f"metadata@127.0.0.1:{port}"], env)
                            if metadata_ready.returncode == 0:
                                metadata_values = upsc_mapping(metadata_ready)
                                if all(k in metadata_values for k in ("ups.beeper.status", "input.transfer.low")):
                                    reference = values
                                    break
                    time.sleep(0.1)
                if reference is None:
                    raise RuntimeError("NUT synthetic devices did not become ready: " +
                                       result.stdout + result.stderr)

                def query(*args):
                    result = run([str(BINARY), "127.0.0.1", str(port), "--plaintext", *args], env)
                    if result.returncode:
                        raise RuntimeError("moonnut query failed: " + result.stdout)
                    return result.stdout.strip()

                # Compare identical logical results, not CLI formatting or order.
                # Values remain strings, including numbers and multi-word status.
                endpoint = f"127.0.0.1:{port}"
                devices = {item["name"]: item["description"]
                           for item in json.loads(query("--json"))}
                assert devices == upsc_mapping(run([upsc, "-L", endpoint], env)) == {"demo": "Synthetic demo UPS", "metadata": "Synthetic discovery state"}
                variables = {item["name"]: item["value"]
                             for item in json.loads(query("--vars", "demo", "--json"))}
                reference = upsc_mapping(run([upsc, "demo@" + endpoint], env))
                assert variables == reference, "complete LIST VAR results differ"
                for name, expected in EXPECTED.items():
                    assert variables.get(name) == reference[name] == expected, (name, variables.get(name), reference[name], expected)
                    scalar = run([upsc, "demo@" + endpoint, name], env)
                    assert scalar.returncode == 0 and scalar.stdout.rstrip("\n") == expected, name
                    assert json.loads(query("--get", "demo", name, "--json"))["value"] == expected, name
                print(f"PASS: LIST UPS ({len(devices)} devices), complete LIST VAR ({len(variables)} values) and 4 direct GET VAR reads match upsc")
                ups_description = json.loads(query("--ups-desc", "demo", "--json"))
                assert ups_description == {"ups": "demo", "description": devices["demo"]}
                # Official upsrw in list-only mode reads DESC/TYPE. Never use -s.
                # Compare known string/numeric fixture fields, not its full UI.
                sections = rw_sections(run([upsrw, "-l", "demo@" + endpoint], env))
                for name, kind in (("ups.model", "STRING"), ("battery.charge", "NUMBER")):
                    section = sections[name]
                    description = json.loads(query("--desc", "demo", name, "--json"))
                    assert description == {"ups": "demo", "name": name, "description": section[0]}
                    metadata = json.loads(query("--type", "demo", name, "--json"))
                    assert metadata["ups"] == "demo" and metadata["name"] == name
                    types = metadata["types"]
                    assert "RW" in types and "Type: " + kind in section
                    if kind == "STRING":
                        length = next(line.removeprefix("Maximum length: ") for line in section
                                      if line.startswith("Maximum length: "))
                        assert set(types) == {"RW", "STRING:" + length}
                    else:
                        assert set(types) == {"RW", "NUMBER"}
                print("PASS: GET UPSDESC matches upsc -L; GET DESC/TYPE match read-only upsrw -l for string and numeric fixtures")
                writable = {item["name"]: item["value"]
                            for item in json.loads(query("--rw", "demo", "--json"))}
                assert set(writable) == set(sections), "LIST RW names differ from upsrw -l"
                assert writable == {name: variables[name] for name in sections}
                def commands_for(device):
                    result = run([upscmd, "-l", device + "@" + endpoint], env)
                    assert result.returncode == 0, result.stderr
                    descriptions = dict(line.split(" - ", 1) for line in result.stdout.splitlines()
                                        if " - " in line)
                    commands = json.loads(query("--commands", device, "--json"))
                    assert sorted(commands) == sorted(descriptions) and commands
                    for command in commands:
                        description = json.loads(query("--cmd-desc", device, command, "--json"))
                        assert description == {"ups": device, "command": command,
                                               "description": descriptions[command]}
                    return commands

                commands_for("demo")
                # These reads use real upsd with synthetic driver state, not dummy-ups.
                metadata_sections = rw_sections(run([upsrw, "-l", "metadata@" + endpoint], env))

                def options_for(name):
                    # upsrw adds SELECTED to its UI, not to protocol ENUM/RANGE rows.
                    return sorted(line.removeprefix('Option: "').removesuffix(' SELECTED').removesuffix('"')
                                  for line in metadata_sections[name] if line.startswith('Option: "'))

                metadata_writable = {item["name"]: item["value"]
                                     for item in json.loads(query("--rw", "metadata", "--json"))}
                assert set(metadata_writable) == set(metadata_sections)
                assert metadata_writable == {"ups.beeper.status": "enabled", "input.transfer.low": "95"}
                for name, expected_types in (("ups.beeper.status", {"RW", "ENUM", "STRING:16"}),
                                             ("input.transfer.low", {"RW", "RANGE", "NUMBER"})):
                    assert set(json.loads(query("--type", "metadata", name, "--json"))["types"]) == expected_types
                enum = json.loads(query("--enum", "metadata", "ups.beeper.status", "--json"))
                assert enum["ups"] == "metadata" and enum["name"] == "ups.beeper.status"
                assert set(enum["values"]) == {"enabled", "disabled"} and len(enum["values"]) == 2
                assert sorted(enum["values"]) == options_for("ups.beeper.status")
                ranges = json.loads(query("--range", "metadata", "input.transfer.low", "--json"))
                assert ranges["ups"] == "metadata" and ranges["name"] == "input.transfer.low"
                assert sorted((r["min"], r["max"]) for r in ranges["ranges"]) == [("102", "105"), ("90", "100")]
                assert sorted(interval["min"] + '-' + interval["max"] for interval in ranges["ranges"]) == options_for("input.transfer.low")
                assert set(commands_for("metadata")) == {"load.off", "test.battery.start.quick"}
                print("PASS: LIST RW matches upsrw -l; LIST CMD/GET CMDDESC match upscmd -l on dummy-ups")
                print("PASS: real upsd + synthetic driver state RW/TYPE/ENUM and disjoint RANGE 90..100, 102..105 match upsrw -l; two commands and descriptions match upscmd -l")

                # The public CLI intentionally redacts errors. Compare failure,
                # not exception types/messages; inspect known reference errors.
                for options, reference_args, message in (
                    (("--vars", "missing"), ["missing@" + endpoint], "Unknown UPS"),
                    (("--get", "demo", "missing.variable"), ["demo@" + endpoint, "missing.variable"], "Variable not supported"),
                    (("--ups-desc", "missing"), ["missing@" + endpoint], "Unknown UPS"),
                    (("--type", "demo", "missing.variable"), ["demo@" + endpoint, "missing.variable"], "Variable not supported"),
                ):
                    failed = run([str(BINARY), "127.0.0.1", str(port), "--plaintext", *options], env)
                    baseline = run([upsc, *reference_args], env)
                    assert failed.returncode != 0 and baseline.returncode != 0
                    assert message.lower() in baseline.stderr.lower(), baseline.stderr
                print("PASS: unknown UPS and unknown variable fail in moonnut and upsc (not error-text equivalence)")
                if args.pynut:
                    python_reference = pynut_results(args.pynut, port, env)
                    assert python_reference["ups"] == devices
                    assert python_reference["variables"] == variables
                    assert python_reference["unknown_ups"] == "ERR UNKNOWN-UPS"
                    print("PASS: PyNUT matches LIST UPS, complete LIST VAR and unknown-UPS failure on the same daemon")
                    print("PyNUT GET VAR: not provided; selected values agree via GetUPSVars, not a direct GET")
                    print("PyNUT GET UPSDESC/DESC/TYPE: no dedicated public APIs; metadata uses upsc/upsrw")
                    print("PyNUT STARTTLS: not provided; TLS checks below exercise moonnut only")
                else:
                    print("PyNUT comparison: not run (provide --pynut with the pinned external module)")
                print("Synthetic device only: status=OL CHRG, charge=100%, runtime=600s")
                auth_env = dict(env, MOONNUT_USERNAME="fixture", MOONNUT_PASSWORD=password)
                trusted = [str(BINARY), "localhost", str(port), "--ca", str(cert)]
                secure = run(trusted + ["--get", "demo", "ups.status"], auth_env)
                assert secure.returncode == 0 and secure.stdout.strip() == EXPECTED["ups.status"], "verified NUT TLS/auth GET failed"
                secure_devices = run(trusted, auth_env)
                assert secure_devices.returncode == 0 and set(secure_devices.stdout.strip().splitlines()) == {"demo\tSynthetic demo UPS", "metadata\tSynthetic discovery state"}, "verified NUT TLS/auth LIST UPS failed"
                secure_variables = run(trusted + ["--vars", "demo"], auth_env)
                assert secure_variables.returncode == 0, "verified NUT TLS/auth LIST VAR failed"
                secure_values = dict(line.split("\t", 1) for line in secure_variables.stdout.strip().splitlines())
                assert all(secure_values.get(k) == v for k, v in EXPECTED.items())
                wrong_password = run(trusted, dict(auth_env, MOONNUT_PASSWORD="wrong-fixture-password"))
                # NUT stores USERNAME/PASSWORD for later privileged commands.
                # Anonymous reads may still succeed; OK is not an auth verdict.
                if wrong_password.returncode == 0:
                    assert set(wrong_password.stdout.strip().splitlines()) == {"demo\tSynthetic demo UPS", "metadata\tSynthetic discovery state"}
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
                discovery_driver.close()


if __name__ == "__main__":
    main()
