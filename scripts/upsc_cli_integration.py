"""Read-only upsc differential, called inside the existing isolated upsd fixture.

Keep ordered raw output and exit status. Only the documented NSS diagnostic lines
are excluded from stderr comparison. LOGIN setup uses disposable secondary-only
credentials; it cannot SET, INSTCMD, PRIMARY or FSD. No host shutdown is involved.
"""
import json
from pathlib import Path
import socket
import subprocess
import time

from cli_reference import semantic_stderr

BINARY = Path(__file__).resolve().parents[1] / '_build/native/debug/build/cmd/upsc/upsc.exe'


def compare_query_cli(official, port, env, password, evidence_dir):
    assert BINARY.is_file(), 'build cmd/upsc first'
    host = f'127.0.0.1:{port}'
    target = 'demo@' + host
    invalid_ups = 'Error: invalid UPS definition.\nRequired format: upsname[@hostname[:port]]\n'
    invalid_host = 'Error: invalid hostname.\nRequired format: [hostname[:port]]\n'
    cases = [
        ('names', ['-l', host], 0, None, ''),
        ('descriptions', ['-L', host], 0, None, ''),
        ('list-precedence', ['-cLl', host, 'ignored'], 0, None, ''),
        ('all-demo', [target], 0, None, ''),
        ('all-metadata', ['metadata@' + host], 0, None, ''),
        ('status', [target, 'ups.status'], 0, 'OL CHRG\n', ''),
        ('model', [target, 'ups.model'], 0, 'Virtual UPS\n', ''),
        ('charge', [target, 'battery.charge'], 0, '100\n', ''),
        ('runtime', [target, 'battery.runtime'], 0, '600\n', ''),
        ('server-info', [target, 'server.info'], 0, None, ''),
        ('server-version', [target, 'server.version'], 0, None, ''),
        ('clients-empty', ['-c', target], 0, '', ''),
        ('missing-ups-list', ['missing@' + host], 1, '', 'Error: Unknown UPS\n'),
        ('missing-ups-get', ['missing@' + host, 'ups.status'], 1, '', 'Error: Unknown UPS\n'),
        ('missing-ups-clients', ['-c', 'missing@' + host], 1, '', 'Error: Unknown UPS\n'),
        ('missing-variable', [target, 'fixture.missing'], 1, '', 'Error: Variable not supported by UPS\n'),
        ('old-variable', [target, 'STATUS'], 1, '', 'Error: old-style variable names are not supported\n'),
        ('old-variable-precedence', ['missing@' + host, 'STATUS'], 1, '', 'Error: old-style variable names are not supported\n'),
        ('stop-options', [target, '-l'], 1, '', 'Error: old-style variable names are not supported\n'),
        ('extra-positionals', [target, 'ups.status', 'ignored'], 0, 'OL CHRG\n', ''),
        ('end-options', ['--', target, 'ups.status'], 0, 'OL CHRG\n', ''),
        ('blocking-connect', ['-W0', target, 'ups.status'], 0, 'OL CHRG\n', ''),
        ('fractional-connect', ['-W', '0.5', target, 'ups.status'], 0, 'OL CHRG\n', ''),
        ('port-prefix', [target + 'tail', 'ups.status'], 0, 'OL CHRG\n', ''),
        ('bracketed-host', [f'demo@[127.0.0.1]:{port}', 'ups.status'], 0, 'OL CHRG\n', ''),
        ('missing-target', [], 1, '', invalid_ups),
        ('empty-ups', [''], 1, '', "upscli_splitname: can't parse empty string\n" + invalid_ups),
        ('at-only', ['@localhost'], 1, '', 'upscli_splitname: got empty upsname string\n' + invalid_ups),
        ('ups-port-only', ['demo:3493'], 1, '', 'upscli_splitname: port specified, but not a hostname\n' + invalid_ups),
        ('missing-host', ['demo@'], 1, '', 'upscli_splitname: got the @ separator and then an empty hostname[:port] string\n' + invalid_ups),
        ('empty-list-host', ['-l', ''], 1, '', "upscli_splitaddr: can't parse empty string\n" + invalid_host),
        ('unclosed-bracket', ['-l', '[127.0.0.1'], 1, '', 'upscli_splitaddr: missing closing bracket in [domain literal]\n' + invalid_host),
        ('missing-port', ['-l', '127.0.0.1:'], 1, '', "upscli_splitaddr: no port specified after ':' separator\n" + invalid_host),
        ('invalid-port', ['demo@127.0.0.1:65536'], 1, '', "upscli_splitaddr: no port specified after ':' separator\n" + invalid_ups),
    ]
    evidence = {'reference': 'NUT 2.8.4 / Ubuntu package 2.8.4+really-2 / NSS',
                'cases': [], 'known_identity_differences': []}

    def compare(label, args, code, stdout, stderr, overrides=None):
        row = {'case': label, 'args': args, 'expected_exit': code,
               'expected_stdout': stdout, 'expected_stderr': stderr}
        evidence['cases'].append(row)
        for name, program in [('official', official), ('moonnut', BINARY)]:
            result = subprocess.run([str(program), *args], env=dict(env, **(overrides or {})),
                                    capture_output=True, text=True, timeout=10)
            row[name] = {'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}
        expected, actual = row['official'], row['moonnut']
        for result in (expected, actual):
            assert result['exit'] == code, row
            assert semantic_stderr(result['stderr']) == stderr, row
            if stdout is not None:
                assert result['stdout'] == stdout, row
        assert expected['stdout'] == actual['stdout'], row
        return actual['stdout']

    sockets = []
    try:
        for case in cases:
            compare(*case)
        compare('invalid-cli-timeout', ['-Wbad', target, 'ups.status'], 0, 'OL CHRG\n',
                "upscli_init_default_connect_timeout: cli_secs='bad' value was not recognized, ignored\n")
        compare('environment-timeout', [target, 'ups.status'], 0, 'OL CHRG\n', '',
                {'NUT_DEFAULT_CONNECT_TIMEOUT': '0.5'})
        compare('cli-overrides-environment', ['-W0', target, 'ups.status'], 0, 'OL CHRG\n',
                "upscli_init_default_connect_timeout: NUT_DEFAULT_CONNECT_TIMEOUT='bad' value was not recognized, ignored\n",
                {'NUT_DEFAULT_CONNECT_TIMEOUT': 'bad'})
        for count in (1, 2):
            conn = socket.create_connection(('127.0.0.1', port), timeout=5)
            stream = conn.makefile('rwb', buffering=0)
            sockets.append((conn, stream))
            for command in ('USERNAME session-fixture', 'PASSWORD ' + password, 'LOGIN demo'):
                stream.write((command + '\n').encode())
                assert stream.readline() == b'OK\n', 'isolated LOGIN setup failed'
            compare(f'clients-{count}', ['-c', target, 'ignored'], 0, '127.0.0.1\n' * count, '')
        for conn, stream in sockets:
            stream.write(b'LOGOUT\n')
            assert stream.readline() == b'OK Goodbye\n'
            stream.close()
            conn.close()
        sockets.clear()
        # Server cleanup is eventual; this is not a latency-equivalence claim.
        for _ in range(20):
            result = subprocess.run([official, '-c', target], env=env, capture_output=True,
                                    text=True, timeout=10)
            if result.returncode == 0 and result.stdout == '':
                break
            time.sleep(0.05)
        compare('clients-after-logout', ['-c', target], 0, '', '')
        for option in ('-h', '-V'):
            row = {'option': option}
            evidence['known_identity_differences'].append(row)
            for name, program in [('official', official), ('moonnut', BINARY)]:
                result = subprocess.run([str(program), option], env=env, capture_output=True,
                                        text=True, timeout=10)
                row[name] = {'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}
                assert result.returncode == 0 and result.stdout, row
            assert 'moonnut upsc' in row['moonnut']['stdout']
        print(f"PASS: {len(evidence['cases'])} upsc CLI cases match ordered stdout, semantic stderr and exit status; help/version identity differences retained")
    finally:
        for conn, stream in sockets:
            stream.close()
            conn.close()
        if evidence_dir:
            evidence_dir.mkdir(parents=True, exist_ok=True)
            (evidence_dir / 'upsc-cli.json').write_text(json.dumps(evidence, indent=2) + '\n')
