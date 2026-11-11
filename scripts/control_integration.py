#!/usr/bin/env python3
"""Control comparison on a private loopback upsd with an in-memory Unix driver.

No physical driver, system configuration, service manager or upsmon is started.
Each probe gets a new daemon and state; FSD cannot reach a host shutdown process.
The separate read-only DiscoveryDriver remains unchanged.
"""
import argparse
import getpass
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import tempfile
import threading
import time

from upsd_integration import ROOT, configure_tls, locate, run

BINARY = ROOT / "_build/native/debug/build/examples/control_probe/control_probe.exe"
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", re.IGNORECASE)
ESCAPED = 'a"b\\c#d'


def encode(value):
    return ''.join('\\' + c if c in '#\\"' else c for c in value)


def tokens(line):
    """Decode only the ASCII parseconf subset emitted in this fixed fixture."""
    result, word, quoted, escaped, active = [], '', False, False, False
    for c in line:
        if escaped:
            word += c
            escaped = False
        elif c == '\\':
            escaped = True
            active = True
        elif c == '"':
            quoted = not quoted
            active = True
        elif c == '#' and not quoted:
            break
        elif c in ' \t' and not quoted:
            if active:
                result.append(word)
                word, active = '', False
        else:
            word += c
            active = True
    assert not quoted and not escaped, line
    if active:
        result.append(word)
    return result


class ControlDriver:
    """Fixed in-memory state, numeric NUT tracking results, no device access."""
    def __init__(self, folder):
        self.listener = socket.socket(socket.AF_UNIX)
        self.listener.bind(str(folder / 'moonnut-control-control'))
        self.listener.listen(1)
        self.listener.settimeout(0.2)
        self.stop = threading.Event()
        self.errors, self.events, self.held, self.sets = [], [], [], []
        self.state = {'ups.status': 'OL', 'ups.id': 'initial',
                      'ups.beeper.status': 'enabled', 'input.transfer.low': '95'}
        self.worker = threading.Thread(target=self.serve, daemon=True)
        self.worker.start()

    def dump(self):
        state = ''.join(f'SETINFO {k} "{encode(v)}"\n' for k, v in self.state.items())
        state += ('SETFLAGS ups.id RW STRING\nSETAUX ups.id 16\n'
                  'SETFLAGS ups.beeper.status RW STRING\nSETAUX ups.beeper.status 16\n'
                  'ADDENUM ups.beeper.status "enabled"\nADDENUM ups.beeper.status "disabled"\n'
                  'SETFLAGS input.transfer.low RW NUMBER\n'
                  'ADDRANGE input.transfer.low 90 100\nADDRANGE input.transfer.low 102 105\n')
        state += ''.join(f'ADDCMD fixture.{name}\n' for name in
                         ('success', 'invalid', 'failed', 'unknown', 'conversion', 'hold', 'release'))
        return (state + 'DATAOK\nDUMPDONE\n').encode()

    def apply(self, conn, name, value, tracking):
        self.state[name] = value
        conn.sendall(f'SETINFO {name} "{encode(value)}"\n'.encode())
        if tracking:
            conn.sendall(f'TRACKING {tracking} 0\n'.encode())

    def handle(self, conn, raw):
        args = tokens(raw)
        event = {'raw': raw, 'tokens': args, 'result': None}
        self.events.append(event)
        tracking = None
        if args[0] == 'SET':
            assert len(args) in (3, 5), raw
            if len(args) == 5:
                assert args[3] == 'TRACKING' and UUID.fullmatch(args[4]), raw
                tracking = args[4]
            assert args[1] in ('ups.id', 'input.transfer.low', 'ups.beeper.status'), raw
            if args[1] == 'ups.id':
                self.sets.append((args[1], args[2], tracking))
                event['result'] = 'deferred'
            else:
                self.apply(conn, args[1], args[2], tracking)
                event['result'] = 0
        elif args[0] == 'INSTCMD':
            # Match the argument-count boundary in NUT 2.8.4 drivers/dstate.c.
            # This fixture is not evidence of any actual hardware execution.
            if len(args) == 4 and args[2] == 'TRACKING':
                tracking = args[3]
            elif len(args) == 5 and args[3] == 'TRACKING':
                tracking = args[4]
            elif len(args) not in (2, 3):
                event['result'] = 'malformed-driver-request'
                return
            if tracking:
                assert UUID.fullmatch(tracking), raw
            name = args[1].removeprefix('fixture.')
            if name == 'release':
                for values in self.sets:
                    self.apply(conn, *values)
                self.sets.clear()
                for held in self.held:
                    conn.sendall(f'TRACKING {held} 0\n'.encode())
                self.held.clear()
                result = 0
            elif name == 'hold':
                assert tracking, raw
                self.held.append(tracking)
                event['result'] = 'deferred'
                return
            else:
                result = {'success': 0, 'unknown': 1, 'invalid': 2,
                          'failed': 3, 'conversion': 4}[name]
            event['result'] = result
            if tracking:
                conn.sendall(f'TRACKING {tracking} {result}\n'.encode())
        else:
            raise AssertionError('unexpected driver request: ' + raw)

    def serve(self):
        try:
            while not self.stop.is_set():
                try:
                    conn, _ = self.listener.accept()
                except socket.timeout:
                    continue
                with conn:
                    conn.settimeout(0.2)
                    pending = b''
                    while not self.stop.is_set():
                        try:
                            chunk = conn.recv(4096)
                        except socket.timeout:
                            continue
                        if not chunk:
                            break
                        pending += chunk
                        assert len(pending) < 8192
                        while b'\n' in pending:
                            line, pending = pending.split(b'\n', 1)
                            if line == b'DUMPALL':
                                conn.sendall(self.dump())
                            elif line == b'PING':
                                conn.sendall(b'PONG\n')
                            else:
                                self.handle(conn, line.decode('ascii'))
        except Exception as error:
            self.errors.append(error)

    def close(self):
        self.stop.set()
        self.worker.join(2)
        self.listener.close()
        assert not self.worker.is_alive(), 'fixture did not stop'
        assert not self.errors, self.errors
        assert not self.held and not self.sets, 'unreleased fixture state'


def isolated(upsd, upsc, action):
    env = {k: v for k, v in os.environ.items() if not k.startswith(('MOONNUT_', 'NUT_'))}
    reservation = socket.socket()
    reservation.bind(('127.0.0.1', 0))
    port = reservation.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix='moonnut-control-') as temp:
        folder = Path(temp)
        env.update(NUT_CONFPATH=temp, NUT_STATEPATH=temp, NUT_ALTPIDPATH=temp,
                   NUT_QUIET_INIT_UPSNOTIFY='true', NSS_DEFAULT_DB_TYPE='sql',
                   MOONNUT_PASSWORD=secrets.token_hex(24))
        _, tls, backend = configure_tls(folder, upsd)
        (folder / 'ups.conf').write_text(
            f'statepath = {temp}\n[control]\n driver = moonnut-control\n port = unused\n')
        (folder / 'upsd.conf').write_text(f'LISTEN 127.0.0.1 {port}\nSTATEPATH {temp}\nMAXAGE 15\n' + tls)
        password = env['MOONNUT_PASSWORD']
        (folder / 'upsd.users').write_text(
            f'[reader]\n password = {password}\n'
            f'[operator]\n password = {password}\n actions = SET\n upsmon primary\n instcmds = ALL\n')
        for file in folder.iterdir():
            if file.is_file():
                file.chmod(0o600)
        driver = ControlDriver(folder)
        child = None
        with (folder / 'process.log').open('w+') as log:
            try:
                reservation.close()
                child = subprocess.Popen([upsd, '-F', '-u', getpass.getuser()], env=env,
                                         stdout=log, stderr=subprocess.STDOUT)
                for _ in range(100):
                    assert child.poll() is None, 'upsd exited'
                    ready = run([upsc, f'control@127.0.0.1:{port}', 'ups.id'], env)
                    if ready.returncode == 0 and ready.stdout.strip() == 'initial':
                        break
                    time.sleep(0.1)
                else:
                    raise AssertionError('synthetic control state not ready')
                output = action(port, env)
                assert not driver.errors, driver.errors
                return {'trace': output, 'driver': driver.events, 'state': driver.state,
                        'tls_backend': backend}
            except Exception:
                log.flush()
                log.seek(0)
                print(log.read())
                raise
            finally:
                if child is not None:
                    child.terminate()
                    try:
                        child.wait(3)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait(3)
                driver.close()
                reservation.close()


def normalized(result):
    trace = result['trace']
    ids = UUID.findall(trace)
    assert len(ids) == len(set(ids)) == 8, ids
    driver_ids = [event['tokens'][-1] for event in result['driver']
                  if len(event['tokens']) >= 4 and event['tokens'][-2] == 'TRACKING']
    assert driver_ids == ids, (driver_ids, ids)
    text = json.dumps(result, sort_keys=True)
    for index, value in enumerate(ids):
        text = text.replace(value, f'<tracking-{index + 1}>')
    return json.loads(text)


def validate(result):
    rows = dict(line.split(' ', 1) for line in result['trace'].splitlines())
    expected = {
        'no-user': 'ERR USERNAME-REQUIRED', 'no-password': 'ERR PASSWORD-REQUIRED',
        'denied-set': 'ERR ACCESS-DENIED', 'denied-unknown-cmd': 'ERR CMD-NOT-SUPPORTED',
        'denied-cmd': 'ERR ACCESS-DENIED', 'denied-primary': 'ERR ACCESS-DENIED',
        'denied-master': 'ERR ACCESS-DENIED', 'denied-fsd': 'ERR ACCESS-DENIED',
        'primary': 'OK PRIMARY-GRANTED', 'master': 'OK MASTER-GRANTED', 'logins': '0',
        'missing-primary': 'ERR UNKNOWN-UPS', 'missing-master': 'ERR UNKNOWN-UPS',
        'missing-fsd': 'ERR UNKNOWN-UPS', 'missing-ups': 'ERR UNKNOWN-UPS',
        'missing-var': 'ERR VAR-NOT-SUPPORTED', 'readonly': 'ERR READONLY',
        'too-long': 'ERR TOO-LONG', 'invalid-enum': 'ERR INVALID-VALUE',
        'range-gap': 'ERR INVALID-VALUE', 'delayed-set': 'OK', 'before-apply': 'initial',
        'release-set': 'OK', 'after-apply': ESCAPED, 'range-result': 'SUCCESS',
        'range-value': '102tail', 'held-result': 'PENDING', 'release-held': 'OK',
        'released-result': 'SUCCESS', 'success-result': 'SUCCESS',
        'invalid-result': 'ERR INVALID-ARGUMENT', 'failed-result': 'ERR FAILED',
        'unknown-result': 'ERR UNKNOWN', 'conversion-result': 'ERR INVALID-ARGUMENT',
        'absent': 'OK', 'empty': 'OK', 'escaped': 'OK', 'multiword': 'OK',
        'barrier-result': 'SUCCESS', 'before-fsd': 'OL', 'fsd': 'OK FSD-SET', 'fsd-again': 'OK FSD-SET',
        'after-fsd': 'FSD OL', 'fresh-fsd': 'FSD OL',
    }
    for index, label in enumerate(('range-text', 'hold', 'success', 'invalid', 'failed', 'unknown', 'conversion', 'barrier')):
        expected[label] = f'OK TRACKING <tracking-{index + 1}>'
    assert rows == expected, (rows, expected)
    events = result['driver']
    assert len(events) == 15, events
    assert events[0]['tokens'] == ['SET', 'ups.id', ESCAPED]
    assert events[0]['result'] == 'deferred'
    assert events[2]['tokens'] == ['SET', 'input.transfer.low', '102tail', 'TRACKING', '<tracking-1>']
    assert [e['tokens'] for e in events[-5:-1]] == [
        ['INSTCMD', 'fixture.success'], ['INSTCMD', 'fixture.success'],
        ['INSTCMD', 'fixture.success', ESCAPED], ['INSTCMD', 'fixture.success', 'two', 'words']]
    assert events[-2]['result'] == 'malformed-driver-request'
    assert result['state'] == {'ups.status': 'OL', 'ups.id': ESCAPED,
                               'ups.beeper.status': 'enabled', 'input.transfer.low': '102tail'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--evidence-dir', type=Path)
    args = parser.parse_args()
    assert os.geteuid() != 0, 'run as a regular user'
    assert BINARY.is_file() and args.reference.is_file()
    upsd, upsc = locate('upsd', ('/usr/sbin/upsd',)), locate('upsc')
    results = {}
    for label, binary in (('official-libupsclient', args.reference), ('moonnut', BINARY)):
        def probe(port, env):
            result = run([str(binary), str(port)], env)
            assert result.returncode == 0, label + ': ' + result.stdout + result.stderr
            return result.stdout
        results[label] = isolated(upsd, upsc, probe)
        validate(normalized(results[label]))
    assert normalized(results['official-libupsclient']) == normalized(results['moonnut']), results
    print('PASS: 52 control outcomes and 15 driver requests match official libupsclient; 8 real tracking IDs correlated')
    print('PASS: ACK precedes application; held PENDING becomes SUCCESS; terminal statuses, permissions, disjoint RANGE and FSD checked')

    def official_cli(port, env):
        endpoint = f'control@127.0.0.1:{port}'
        auth = ['-u', 'operator', '-p', env['MOONNUT_PASSWORD'], '-w', '-t', '3']
        observations = []
        for command, expected in (([locate('upsrw'), '-s', 'ups.beeper.status=disabled', *auth, endpoint], 'SUCCESS'),
                                  ([locate('upscmd'), *auth, endpoint, 'fixture.success'], 'SUCCESS'),
                                  ([locate('upscmd'), *auth, endpoint, 'fixture.failed'], 'ERR FAILED')):
            result = run(command, env)
            assert result.returncode == 0 and expected in result.stderr.splitlines(), (result.returncode, result.stdout, result.stderr)
            observations.append({'program': Path(command[0]).name, 'exit': result.returncode,
                                 'stdout': result.stdout, 'stderr': result.stderr})
        return observations
    results['official-cli'] = isolated(upsd, upsc, official_cli)
    assert results['official-cli']['state']['ups.beeper.status'] == 'disabled'
    assert len(results['official-cli']['driver']) == 3
    print('PASS: official upsrw/upscmd -w return driver outcomes; upscmd exits 0 even for ERR FAILED')
    if args.evidence_dir:
        args.evidence_dir.mkdir(parents=True, exist_ok=True)
        (args.evidence_dir / 'controls.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
