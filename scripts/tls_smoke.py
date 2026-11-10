#!/usr/bin/env python3
"""Loopback-only STARTTLS tests. No network device or persistent credentials.

Requires Python 3.9+, openssl, and `moon build --target native`.
An ephemeral CA/certificate/key is created in the OS temporary directory.
"""
import os
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "_build/native/debug/build/examples/query/query.exe"
REPLY = b'BEGIN LIST UPS\nUPS demo "Test UPS"\nEND LIST UPS\n'


def line(sock):
    result = bytearray()
    while not result.endswith(b'\n'):
        chunk = sock.recv(1)
        if not chunk:
            raise EOFError()
        result.extend(chunk)
        if len(result) > 1024:
            raise AssertionError("oversized client line")
    return bytes(result)


def run_case(context, *, host, ca=None, auth=False, success=True):
    errors = []
    commands = []
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(8)
    port = listener.getsockname()[1]

    def serve():
        try:
            with listener:
                conn, _ = listener.accept()
                conn.settimeout(5)
                with conn:
                    commands.append(line(conn))
                    assert commands[-1] == b"STARTTLS\n"
                    conn.sendall(b"OK STARTTLS\n")
                    try:
                        with context.wrap_socket(conn, server_side=True) as tls:
                            if auth:
                                commands.append(line(tls))
                                assert commands[-1] == b'USERNAME "fixture-user"\n'
                                tls.sendall(b"OK\n")
                                commands.append(line(tls))
                                assert commands[-1] == b'PASSWORD "fixture-only"\n'
                                tls.sendall(b"OK\n")
                            commands.append(line(tls))
                            assert commands[-1] == b"LIST UPS\n"
                            tls.sendall(REPLY)
                    except (ssl.SSLError, EOFError, ConnectionResetError):
                        if success:
                            raise
        except Exception as exc:
            errors.append(exc)

    worker = threading.Thread(target=serve, daemon=True)
    worker.start()
    env = {k: v for k, v in os.environ.items() if not k.startswith("MOONNUT_")}
    if auth:
        env.update(MOONNUT_USERNAME="fixture-user", MOONNUT_PASSWORD="fixture-only")
    args = [str(BINARY), host, str(port)]
    if ca:
        args += ["--ca", str(ca)]
    proc = subprocess.run(args, capture_output=True, text=True, env=env, timeout=10)
    worker.join(9)
    assert not worker.is_alive(), "fixture did not terminate"
    assert not errors, repr(errors)
    assert (proc.returncode == 0) == success, proc.stdout + proc.stderr
    if success:
        assert proc.stdout.strip() == "demo\tTest UPS", repr(proc.stdout)
    else:
        assert commands == [b"STARTTLS\n"], "query or credentials sent before trust verification"


def main():
    assert BINARY.is_file(), "run moon build --target native first"
    with tempfile.TemporaryDirectory(prefix="moonnut-tls-") as folder:
        folder = Path(folder)
        cert, key, config = folder / "cert.pem", folder / "key.pem", folder / "openssl.cnf"
        config.write_text("[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=ext\n"
                          "[dn]\nCN=localhost\n[ext]\nsubjectAltName=DNS:localhost\n"
                          "basicConstraints=critical,CA:TRUE\n")
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                        "-days", "1", "-keyout", str(key), "-out", str(cert),
                        "-config", str(config)], check=True, capture_output=True)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        run_case(context, host="localhost", ca=cert)
        run_case(context, host="localhost", ca=cert, auth=True)
        run_case(context, host="localhost", auth=True, success=False)
        run_case(context, host="127.0.0.1", ca=cert, auth=True, success=False)
    print("TLS smoke: trusted CA, encrypted auth, untrusted CA, wrong hostname passed (4 cases)")


if __name__ == "__main__":
    main()
