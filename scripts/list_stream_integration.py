#!/usr/bin/env python3
"""Scripted loopback LIST replies, compared with pinned official upsc.

No upsd, device, credentials, LOGIN or control request is used. The fixture only
accepts STARTTLS, the requested LIST and optional LOGOUT. Raw wire requests and
both CLI outputs are retained; NSS diagnostic differences remain explicit.
"""
import argparse
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import threading
import time

from cli_reference import semantic_stderr

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / '_build/native/debug/build/cmd/upsc/upsc.exe'

# kind, complete reply bytes (possibly truncated), exit, stdout, semantic stderr
CASES = [
    ('ups-complete', 'UPS', b'BEGIN LIST UPS\nUPS a Alpha\nUPS b Beta\nEND LIST UPS\n', 0, 'a: Alpha\nb: Beta\n', ''),
    ('ups-empty', 'UPS', b'BEGIN LIST UPS\nEND LIST UPS\n', 0, '', ''),
    ('start-extra', 'UPS', b'BEGIN LIST UPS extra\nUPS a Alpha\nEND LIST UPS\n', 0, 'a: Alpha\n', ''),
    ('echo-case', 'UPS', b'begin list ups\nups a Alpha\nEND LIST UPS\n', 0, 'a: Alpha\n', ''),
    ('start-wrong-query', 'UPS', b'BEGIN LIST OTHER\n', 1, '', 'Error: Protocol error\n'),
    ('start-wrong-prefix', 'UPS', b'WRONG LIST UPS\n', 1, '', 'Error: Protocol error\n'),
    ('start-server-error', 'UPS', b'ERR ACCESS-DENIED\n', 1, '', 'Error: Access denied\n'),
    ('start-old-server', 'UPS', b'ERR UNKNOWN-COMMAND\n', 1, '', 'Error: upsd is too old to support this query\n'),
    ('start-eof', 'UPS', b'', 1, '', 'Error: Server disconnected\n'),
    ('row-extra', 'UPS', b'BEGIN LIST UPS\nUPS a Alpha extra\nEND LIST UPS\n', 0, 'a: Alpha\n', ''),
    ('row-short', 'UPS', b'BEGIN LIST UPS\nUPS a Alpha\nUPS b\n', 1, 'a: Alpha\n', 'Error: insufficient data (got 2 args, need at least 3)\n'),
    ('row-wrong-prefix', 'UPS', b'BEGIN LIST UPS\nUPS a Alpha\nWRONG b Beta\n', 0, 'a: Alpha\n', ''),
    ('row-server-error', 'UPS', b'BEGIN LIST UPS\nUPS a Alpha\nERR DATA-STALE\n', 0, 'a: Alpha\n', ''),
    ('row-empty', 'UPS', b'BEGIN LIST UPS\nUPS a Alpha\n\n', 0, 'a: Alpha\n', ''),
    ('row-eof', 'UPS', b'BEGIN LIST UPS\nUPS a Alpha\n', 0, 'a: Alpha\n', ''),
    ('row-truncated', 'UPS', b'BEGIN LIST UPS\nUPS a Alpha\nUPS b Bet', 0, 'a: Alpha\n', ''),
    ('end-bare', 'UPS', b'BEGIN LIST UPS\nUPS a Alpha\nEND LIST\n', 0, 'a: Alpha\n', ''),
    ('end-wrong-query', 'UPS', b'BEGIN LIST UPS\nUPS a Alpha\nEND LIST VAR other extra\n', 0, 'a: Alpha\n', ''),
    ('end-lowercase', 'UPS', b'BEGIN LIST UPS\nUPS a Alpha\nend list ups\n', 0, 'a: Alpha\n', ''),
    ('empty-description', 'UPS', b'BEGIN LIST UPS\nUPS a ""\nEND LIST UPS\n', 0, 'a: \n', ''),
    ('unicode-description', 'UPS', 'BEGIN LIST UPS\nUPS a "测试 UPS"\nEND LIST UPS\n'.encode(), 0, 'a: 测试 UPS\n', ''),
    ('vars-extra', 'VAR', b'BEGIN LIST VAR demo\nVAR demo ups.status "OL CHRG" extra\nEND LIST VAR demo\n', 0, 'ups.status: OL CHRG\n', ''),
    ('vars-partial-error', 'VAR', b'BEGIN LIST VAR demo\nVAR demo ups.status OL\nERR DATA-STALE\n', 0, 'ups.status: OL\n', ''),
    ('vars-short', 'VAR', b'BEGIN LIST VAR demo\nVAR demo ups.status OL\nVAR demo ups.model\n', 1, 'ups.status: OL\n', 'Error: insufficient data (got 3 args, need at least 4)\n'),
    ('vars-wrong-device', 'VAR', b'BEGIN LIST VAR demo\nVAR demo ups.status OL\nVAR other ups.model X\n', 0, 'ups.status: OL\n', ''),
    ('clients-partial-eof', 'CLIENT', b'BEGIN LIST CLIENT demo\nCLIENT demo 127.0.0.1\nCLIENT demo 127.0.0.1\n', 0, '127.0.0.1\n127.0.0.1\n', ''),
    ('clients-short', 'CLIENT', b'BEGIN LIST CLIENT demo\nCLIENT demo\n', 1, '', 'Error: insufficient data (got 2 args, need at least 3)\n'),
    ('fragmented-crlf', 'UPS', b'BEGIN LIST UPS\r\nUPS a Alpha\r\nEND LIST UPS\r\n', 0, 'a: Alpha\n', ''),
]


def observe(program, case):
    label, kind, reply, *_ = case
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    listener.listen(1)
    listener.settimeout(8)
    port = listener.getsockname()[1]
    requests, errors = [], []

    def serve():
        try:
            with listener:
                conn, _ = listener.accept()
                with conn, conn.makefile('rwb', buffering=0) as stream:
                    conn.settimeout(6)
                    line = stream.readline()
                    requests.append(line.decode())
                    assert line == b'STARTTLS\n', requests
                    stream.write(b'ERR FEATURE-NOT-SUPPORTED\n')
                    line = stream.readline()
                    requests.append(line.decode())
                    assert shlex.split(line.decode()) == ['LIST', kind] + ([] if kind == 'UPS' else ['demo']), requests
                    if label == 'fragmented-crlf':
                        for byte in reply:
                            stream.write(bytes([byte]))
                            time.sleep(0.002)
                    else:
                        stream.write(reply)
                    # EOF is delivered deliberately, including a truncated last line.
                    # Complete lists still succeed before observing the half-close.
                    conn.shutdown(socket.SHUT_WR)
                    while True:
                        line = stream.readline()
                        if not line:
                            break
                        requests.append(line.decode())
                        assert line == b'LOGOUT\n', requests
        except (ConnectionResetError, BrokenPipeError):
            pass  # Client may close immediately on a protocol error.
        except Exception as error:
            errors.append(repr(error))

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    endpoint = f'127.0.0.1:{port}'
    args = ['-L', endpoint] if kind == 'UPS' else (['-c', 'demo@' + endpoint] if kind == 'CLIENT' else ['demo@' + endpoint])
    env = {k: v for k, v in os.environ.items() if not k.startswith(('NUT_', 'MOONNUT_'))}
    try:
        result = subprocess.run([str(program), *args], env=env, capture_output=True, timeout=10)
    finally:
        thread.join(8)
        listener.close()
    assert not thread.is_alive() and not errors, (label, errors)
    return {'exit': result.returncode, 'stdout': result.stdout.decode('utf-8'),
            'stderr': result.stderr.decode('utf-8'), 'requests': requests}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, help='pinned official upsc executable')
    parser.add_argument('--evidence-dir', type=Path)
    args = parser.parse_args()
    assert BINARY.is_file(), 'run moon build --target native'
    if args.reference:
        version = subprocess.run([str(args.reference), '-V'], capture_output=True, text=True, check=True)
        assert '2.8.4' in version.stdout + version.stderr
    evidence = {'reference': 'NUT 2.8.4 upsc / libupsclient', 'cases': [], 'known_differences': []}
    try:
        for case in CASES:
            label, kind, reply, code, stdout, stderr = case
            row = {'case': label, 'query': kind, 'reply_hex': reply.hex(),
                   'expected': {'exit': code, 'stdout': stdout, 'stderr': stderr}}
            evidence['cases'].append(row)
            if label == 'unicode-description':
                # Fixed Linux build: parseconf addchar rejects high-bit bytes;
                # signed char promotion determines the diagnostic hex spelling.
                row['expected_official'] = {
                    'exit': 0, 'stdout': 'a:  UPS\n',
                    'stderr': ''.join(f'addchar: discarding invalid character (0x{byte | 0xffffff00:02x})!\n'
                                      for byte in '测试'.encode('utf-8')),
                }
                evidence['known_differences'].append(label)
            programs = [('moonnut', BINARY)]
            if args.reference:
                programs.insert(0, ('official', args.reference))
            for name, program in programs:
                actual = row[name] = observe(program, case)
                comparable = {key: actual[key] for key in ('exit', 'stdout', 'stderr')}
                comparable['stderr'] = semantic_stderr(comparable['stderr'])
                expected = row.get('expected_official', row['expected']) if name == 'official' else row['expected']
                assert comparable == expected, row
        if args.reference:
            print(f"PASS: {len(CASES) - len(evidence['known_differences'])} streaming upsc cases match official stdout, semantic stderr and exit status")
            print("KNOWN DIFFERENCE: UTF-8 text is preserved by moonnut; official parseconf drops high-bit bytes with per-byte diagnostics (not normalized away)")
        else:
            print(f"PASS: {len(CASES)} local streaming expectations; official comparison NOT RUN")
    finally:
        if args.evidence_dir:
            args.evidence_dir.mkdir(parents=True, exist_ok=True)
            (args.evidence_dir / 'list-stream.json').write_text(json.dumps(evidence, indent=2) + '\n')


if __name__ == '__main__':
    main()
