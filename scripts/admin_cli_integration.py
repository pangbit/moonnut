#!/usr/bin/env python3
"""Compare management CLIs only on fresh isolated upsd + in-memory fixtures.

Raw stdout/stderr are retained. Only explicitly listed NSS diagnostic lines and
random tracking UUIDs are normalized; their exclusion is a known parity gap.
No physical driver, upsmon or shutdown executable participates.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time

from control_integration import UUID, isolated
from upsd_integration import ROOT, locate

NSS_DIAGNOSTICS = {
    'Init SSL without certificate database',
    "Connecting in SSL to '127.0.0.1' (no certificate name specified)",
    'Do not intend to authenticate server 127.0.0.1',
    'SSL handshake done successfully with server 127.0.0.1',
    'Connected to NUT server 127.0.0.1 in SSL',
    'Certificate verification is disabled',
}


def semantic_stderr(text):
    # Preserve every other byte, including prompts, whitespace and error text.
    return ''.join(line for line in text.splitlines(keepends=True)
                   if line.rstrip('\n') not in NSS_DIAGNOSTICS)


def suite(programs):
    def action(port, env):
        target = f'control@127.0.0.1:{port}'
        auth = ['-u', 'operator', '-p', env['MOONNUT_PASSWORD']]
        reader = ['-u', 'reader', '-p', env['MOONNUT_PASSWORD']]
        cases = [
            ('rw-list', 'upsrw', [target], '', 0, None),
            ('cmd-list', 'upscmd', ['-l', target], '', 0, None),
            ('set-accepted', 'upsrw', ['-s', 'ups.beeper.status=disabled', *auth, target], '', 0, 'OK\n'),
            ('set-tracked', 'upsrw', ['-s', 'ups.beeper.status=enabled', *auth, '-wt3', target], '', 0, 'SUCCESS\n'),
            ('range-gap', 'upsrw', ['-s', 'input.transfer.low=101', *auth, target], '', 1, 'Unexpected response from upsd: ERR INVALID-VALUE\n'),
            ('range-prefix', 'upsrw', ['-s', 'input.transfer.low=102tail', *auth, '-w', '-t', '3', target], '', 0, 'SUCCESS\n'),
            ('escaped-value', 'upsrw', ['-s', 'ups.id=a"b\\c#d', *auth, target], '', 0, 'OK\n'),
            ('release-value', 'upscmd', [*auth, target, 'fixture.release'], '', 0, 'OK\n'),
            ('value-prompt', 'upsrw', ['-s', 'ups.beeper.status', *auth, target], 'disabled\n', 0, 'OK\n'),
            ('username-prompt', 'upscmd', ['-p', env['MOONNUT_PASSWORD'], target, 'fixture.success'], 'operator\n', 0, 'OK\n'),
            ('password-prompt', 'upscmd', ['-u', 'operator', target, 'fixture.success'], env['MOONNUT_PASSWORD'] + '\n', 0, 'Password: OK\n'),
            ('wait-failed', 'upscmd', [*auth, '-w', '-t', '3', target, 'fixture.failed'], '', 0, 'ERR FAILED\n'),
            ('wait-invalid', 'upscmd', [*auth, '-w', '-t', '3', target, 'fixture.invalid'], '', 0, 'ERR INVALID-ARGUMENT\n'),
            ('raw-words', 'upscmd', [*auth, target, 'fixture.success', 'two words'], '', 0, 'OK\n'),
            ('quoted-words', 'upscmd', [*auth, target, 'fixture.success', '"two words"'], '', 0, 'OK\n'),
            ('empty-argument', 'upscmd', [*auth, target, 'fixture.success', ''], '', 0, 'OK\n'),
            ('escaped-argument', 'upscmd', [*auth, target, 'fixture.success', r'a\"b\\c\#d'], '', 0, 'OK\n'),
            ('wait-timeout', 'upscmd', [*auth, '-w', '-t', '1', target, 'fixture.hold'], '', 1, "Can't receive status tracking information: timeout\n"),
            ('release-held', 'upscmd', [*auth, target, 'fixture.release'], '', 0, 'OK\n'),
            ('zero-wait', 'upscmd', [*auth, '-w', '-t', '0', target, 'fixture.success'], '', 1, "Can't receive status tracking information: timeout\n"),
            ('unknown-command', 'upscmd', [*auth, target, 'fixture.missing'], '', 1, 'Unexpected response from upsd: ERR CMD-NOT-SUPPORTED\n'),
            ('denied-set', 'upsrw', ['-s', 'ups.beeper.status=enabled', *reader, target], '', 1, 'Unexpected response from upsd: ERR ACCESS-DENIED\n'),
            ('denied-command', 'upscmd', [*reader, target, 'fixture.success'], '', 1, 'Unexpected response from upsd: ERR ACCESS-DENIED\n'),
            ('rw-list-after', 'upsrw', ['-W', '0', '-l', target], '', 0, None),
            # The final tracked result is also a driver-stream barrier.
            ('wait-success', 'upscmd', [*auth, '-wt3', target, 'fixture.success'], '', 0, 'SUCCESS\n'),
        ]
        observations = []
        for label, program, args, stdin, code, stderr in cases:
            started = time.monotonic()
            result = subprocess.run([str(programs[program]), *args], input=stdin,
                                    env=env, capture_output=True, text=True, timeout=10,
                                    start_new_session=True)
            observations.append({'case': label, 'program': program, 'exit': result.returncode,
                                 'stdout': result.stdout, 'stderr': result.stderr,
                                 'elapsed': time.monotonic() - started,
                                 'expected_exit': code, 'expected_stderr': stderr})
        return observations
    return action


def normalize(result):
    normalized = json.loads(json.dumps(result))
    for row in normalized['trace']:
        del row['elapsed']
        row['stderr'] = semantic_stderr(row['stderr'])
    ids = []
    for event in normalized['driver']:
        for value in UUID.findall(event['raw']):
            if value not in ids:
                ids.append(value)
    text = json.dumps(normalized, sort_keys=True)
    for index, value in enumerate(ids):
        text = text.replace(value, f'<tracking-{index + 1}>')
    return json.loads(text)


def verify(result):
    for row in result['trace']:
        actual = semantic_stderr(row['stderr'])
        assert row['exit'] == row['expected_exit'], row
        if row['expected_stderr'] is not None:
            assert actual == row['expected_stderr'], row
        else:
            assert actual == '', row
        if row['case'] == 'wait-timeout':
            # NUT counts whole wall-clock seconds and sleeps one second per poll.
            assert 0.8 <= row['elapsed'] < 5, row
    assert result['state'] == {'ups.status': 'OL', 'ups.id': 'a"b\\c#d',
                              'ups.beeper.status': 'disabled', 'input.transfer.low': '102tail'}
    commands = [event for event in result['driver'] if event['tokens'][0] == 'INSTCMD']
    assert sum(event['result'] == 'malformed-driver-request' for event in commands) == 1
    assert sum(event['tokens'][1] == 'fixture.hold' for event in commands) == 1, 'timeout replayed an operation'
    assert len(result['driver']) == 18, result['driver']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    args = parser.parse_args()
    upsd, upsc = locate('upsd', ('/usr/sbin/upsd',)), locate('upsc')
    candidates = {name: ROOT / f'_build/native/debug/build/cmd/{name}/{name}.exe'
                  for name in ('upsrw', 'upscmd')}
    assert all(path.is_file() for path in candidates.values())
    results = {}
    try:
        for label, programs in (('official', {name: locate(name) for name in candidates}), ('moonnut', candidates)):
            results[label] = isolated(upsd, upsc, suite(programs))
            verify(results[label])
        assert normalize(results['official']) == normalize(results['moonnut']), 'management CLI observations or driver state differ; see raw artifact'
        print('PASS: 25 management CLI cases match stdout, semantic stderr, exit status and driver requests/state')
        print('PASS: raw/quoted/empty parameters, three POSIX prompts, selected listings, terminal failure exit 0 and -t 0/1 waits')
        print('Known difference: six NSS diagnostic lines excluded explicitly; raw stderr retained, no full CLI parity claim')
    finally:
        args.evidence_dir.mkdir(parents=True, exist_ok=True)
        (args.evidence_dir / 'admin-cli.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
