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
    run_case(b'GET UPSDESC "demo"\n', f'UPSDESC demo "{encoded}"\n',
             ["--ups-desc", "demo"], {"ups": "demo", "description": description})
    run_case(b'GET DESC "demo" "ups.status"\n', 'DESC demo ups.status "UPS status"\n',
             ["--desc", "demo", "ups.status"],
             {"ups": "demo", "name": "ups.status", "description": "UPS status"})
    run_case(b'GET TYPE "demo" "ups.model"\n', 'TYPE demo ups.model RW STRING:32\n',
             ["--type", "demo", "ups.model"],
             {"ups": "demo", "name": "ups.model", "types": ["RW", "STRING:32"]})
    run_case(b'GET TYPE "demo" "battery.charge"\n', 'TYPE demo battery.charge\n',
             ["--type", "demo", "battery.charge"],
             {"ups": "demo", "name": "battery.charge", "types": []})
    run_case(b'LIST RW "demo"\n',
             'BEGIN LIST RW demo\nRW demo ups.id "020"\nEND LIST RW demo\n',
             ["--rw", "demo"], [{"name": "ups.id", "value": "020"}])
    run_case(b'LIST ENUM "demo" "ups.mode"\n',
             'BEGIN LIST ENUM demo ups.mode\nENUM demo ups.mode "Eco mode"\nENUM demo ups.mode ""\nEND LIST ENUM demo ups.mode\n',
             ["--enum", "demo", "ups.mode"], {"ups": "demo", "name": "ups.mode", "values": ["Eco mode", ""]})
    run_case(b'LIST RANGE "demo" "input.transfer.low"\n',
             'BEGIN LIST RANGE demo input.transfer.low\nRANGE demo input.transfer.low "90" "100"\nRANGE demo input.transfer.low "102" "105"\nEND LIST RANGE demo input.transfer.low\n',
             ["--range", "demo", "input.transfer.low"],
             {"ups": "demo", "name": "input.transfer.low", "ranges": [{"min": "90", "max": "100"}, {"min": "102", "max": "105"}]})
    run_case(b'LIST CMD "demo"\n', 'BEGIN LIST CMD demo\nCMD demo load.off\nEND LIST CMD demo\n',
             ["--commands", "demo"], ["load.off"])
    run_case(b'GET CMDDESC "demo" "load.off"\n', 'CMDDESC demo load.off "Turn off the load immediately"\n',
             ["--cmd-desc", "demo", "load.off"],
             {"ups": "demo", "command": "load.off", "description": "Turn off the load immediately"})
    run_case(b"LIST UPS\n", "BEGIN LIST UPS\nEND LIST UPS\n", [], [])
    run_case(b"LIST UPS\n", "ERR ACCESS-DENIED\n", [], success=False)
    print("CLI JSON smoke: escaped UTF-8, lists, scalar read, metadata, discovery, empty result and failure exit passed (14 cases)")


if __name__ == "__main__":
    main()
