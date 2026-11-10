#!/usr/bin/env python3
"""Verify machine-readable CLI output against loopback-only synthetic replies."""
import json
import os
from pathlib import Path
import socket
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "_build/native/debug/build/examples/query/query.exe"


def run_case(command, response, args, expected=None, *, success=True):
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(5)
    port = listener.getsockname()[1]
    errors = []

    def serve():
        try:
            with listener:
                conn, _ = listener.accept()
                with conn:
                    conn.settimeout(5)
                    request = bytearray()
                    while not request.endswith(b'\n'):
                        part = conn.recv(1)
                        if not part:
                            raise EOFError()
                        request.extend(part)
                        assert len(request) <= 1024
                    assert bytes(request) == command
                    conn.sendall(response.encode("utf-8"))
        except Exception as error:
            errors.append(error)

    worker = threading.Thread(target=serve, daemon=True)
    worker.start()
    env = {k: v for k, v in os.environ.items() if not k.startswith("MOONNUT_")}
    result = subprocess.run([str(BINARY), "127.0.0.1", str(port), "--plaintext",
                             "--json", *args], capture_output=True, text=True, env=env, timeout=8)
    worker.join(6)
    assert not worker.is_alive() and not errors, repr(errors)
    assert (result.returncode == 0) == success, result.stdout + result.stderr
    if success:
        assert json.loads(result.stdout) == expected, repr(result.stdout)
    else:
        assert "ACCESS-DENIED" not in result.stdout


def main():
    assert BINARY.is_file(), "run moon build --target native first"
    description = 'Desk "A"\t#3\\电源'
    encoded = description.replace("\\", "\\\\").replace('"', '\\"').replace("#", "\\#")
    run_case(b"LIST UPS\n", f'BEGIN LIST UPS\nUPS demo "{encoded}"\nEND LIST UPS\n', [],
             [{"name": "demo", "description": description}])
    run_case(b'LIST VAR "demo"\n',
             'BEGIN LIST VAR demo\nVAR demo ups.status "OL CHRG"\nVAR demo battery.charge "100"\nEND LIST VAR demo\n',
             ["--vars", "demo"], [{"name": "ups.status", "value": "OL CHRG"},
                                     {"name": "battery.charge", "value": "100"}])
    run_case(b'GET VAR "demo" "ups.status"\n', 'VAR demo ups.status "OL CHRG"\n',
             ["--get", "demo", "ups.status"], {"ups": "demo", "name": "ups.status", "value": "OL CHRG"})
    run_case(b"LIST UPS\n", "BEGIN LIST UPS\nEND LIST UPS\n", [], [])
    run_case(b"LIST UPS\n", "ERR ACCESS-DENIED\n", [], success=False)
    print("CLI JSON smoke: escaped UTF-8, lists, scalar read, empty result and failure exit passed (5 cases)")


if __name__ == "__main__":
    main()
