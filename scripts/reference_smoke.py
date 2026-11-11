#!/usr/bin/env python3
"""Compare public behavior against an external PyNUT process, never vendoring it.

Usage: python3 scripts/reference_smoke.py /external/path/PyNUT.py
Recommended reference: Network UPS Tools v2.8.4 scripts/python/module/PyNUT.py.in
GPL-3.0-or-later reference code stays outside this Apache-2.0 repository.
This checks a common fixture, not interoperability with a real upsd daemon.
"""
import json
from pathlib import Path
import socket
import subprocess
import sys
import threading
import os

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "_build/native/debug/build/examples/query/query.exe"
REPLY = b'BEGIN LIST UPS\nUPS lab "Desk UPS"\nUPS rack "Rack UPS"\nEND LIST UPS\n'
EXPECTED = {"lab": "Desk UPS", "rack": "Rack UPS"}


def serve(listener, errors):
    try:
        with listener:
            for _ in range(2):
                conn, _ = listener.accept()
                with conn:
                    conn.settimeout(5)
                    data = bytearray()
                    while not data.endswith(b'\n'):
                        part = conn.recv(1)
                        if not part:
                            raise EOFError()
                        data.extend(part)
                    assert data == b"LIST UPS\n", repr(data)
                    conn.sendall(REPLY)
    except Exception as exc:
        errors.append(exc)


def main():
    reference = Path(sys.argv[1]).resolve()
    assert reference.is_file(), "external PyNUT path is required"
    assert ROOT not in reference.parents, "reference code must remain outside this repository"
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(2)
    listener.settimeout(8)
    port = listener.getsockname()[1]
    errors = []
    worker = threading.Thread(target=serve, args=(listener, errors), daemon=True)
    worker.start()
    env = {k: v for k, v in os.environ.items() if not k.startswith("MOONNUT_")}
    ours = subprocess.run([str(BINARY), "127.0.0.1", str(port), "--plaintext"],
                          capture_output=True, text=True, check=True, timeout=10, env=env)
    ours = dict(line.split("\t", 1) for line in ours.stdout.strip().splitlines())
    # Separate process: exercise the reference's public API, not its internals.
    code = """import importlib.util,json,sys
spec=importlib.util.spec_from_file_location('PyNUT',sys.argv[1])
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
client=module.PyNUTClient(host='127.0.0.1',port=int(sys.argv[2]),timeout=5)
def text(value):
    return value.decode('utf-8') if isinstance(value,bytes) else value
print(json.dumps({text(k):text(v) for k,v in client.GetUPSList().items()}))
"""
    theirs = subprocess.run([sys.executable, "-c", code, str(reference), str(port)],
                            capture_output=True, text=True, check=True, timeout=10)
    worker.join(9)
    assert not worker.is_alive() and not errors, repr(errors)
    assert ours == json.loads(theirs.stdout) == EXPECTED
    print("Reference smoke: moonnut and PyNUT agree on LIST UPS fixture (2 devices)")


if __name__ == "__main__":
    main()
