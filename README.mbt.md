# moonnut

[简体中文](README.zh-CN.md)

A small, independently implemented **NUT upsd client for MoonBit native**.
Personally maintained, Apache-2.0 licensed, and deliberately read-only.
The library does not require a NUT executable or a Python runtime.

GitHub main includes unreleased demonstration work. Mooncakes releases are
performed manually by the maintainer; the existing 0.1.0 release is unchanged.

## Scope and safety

- `LIST UPS`, `LIST VAR` and `GET VAR`, with typed device/variable results.
- Verified STARTTLS by default, using system roots or an explicit PEM CA file.
- Optional `USERNAME` / `PASSWORD` submission **only after verified TLS**.
- One fresh connection per query; no shared stream, pooling, automatic retries or downgrade.
- Whole-operation timeout, bounded line length, total response bytes and list rows.
- NUT-style quoting and escaping, strict reply identity and list boundary checks.

There is **no** `FSD`, `SET VAR`, `INSTCMD`, `LOGIN`, `PRIMARY`/`MASTER`, shutdown,
or arbitrary-command API. This is not a power-control agent or a complete RFC 9271
implementation. Authentication itself creates temporary server-side session state.
Only use it against servers you are authorized to query.

**Verification boundary:** tests cover synthetic loopback NUT/TLS servers and
actual NUT 2.8.4 `upsd` + `dummy-ups` programs with a virtual UPS in isolated
Ubuntu CI. The suite compares all three read operations with official `upsc`,
and UPS/variable lists with pinned PyNUT in a separate process on the same daemon.
See the [comparison scope and reproduction steps](docs/comparison.md) and
[CI results](https://github.com/pangbit/moonnut/actions/workflows/ci.yml).
No physical UPS or production deployment has been verified. The actual-daemon
suite also exercises verified STARTTLS with supplied credentials, the server's
incorrect-credential behavior, untrusted certificates and hostname mismatch,
using the installed NUT TLS backend.
The CI log identifies the backend tested; this is not a claim about every NUT
TLS build or a hardware certification.

## Quick start

Requires MoonBit native and `moonbitlang/async` 0.22.4. Verified locally with
`moon` 0.1.20261104 / `moonc` v0.10.20+65efd5b93 on macOS arm64.
Networking and TLS use the official [async library](https://github.com/moonbitlang/async),
including its native platform/OpenSSL requirements. The native suite and loopback TLS checks also pass on Ubuntu GitHub Actions.

```sh
# Offline; no device access
moon run examples/parse --target native
```

Install with `moon add pangbit/moonnut` or use a local workspace dependency.
Import `pangbit/moonnut` in `moon.pkg`;
a package with `async fn main` must also import `moonbitlang/async`.

```mbt check
///|
test "decode a synthetic NUT response" {
  assert_eq(@moonnut.parse_line("VAR demo ups.status \"OL CHRG\""), [
    "VAR", "demo", "ups.status", "OL CHRG",
  ])
}
```

In a native async application, create `Client::new("ups.example.invalid")`, then
call `list_ups()`, `list_vars("demo")` or `get_var("demo", "ups.status")`. Values
remain strings; a status like `OL CHRG` must not be treated as a single enum value.
Each call opens a connection, optionally submits credentials over verified TLS,
and closes the connection, including on failure.

```sh
# Only with authorization for the explicitly named target
moon run examples/query --target native -- ups.example.invalid 3493
moon run examples/query --target native -- ups.example.invalid 3493 --ca /path/to/ca.pem
```

`examples/query` reads optional `MOONNUT_USERNAME` and `MOONNUT_PASSWORD` from the
process environment. Do not put real credentials in commands, source, examples,
issues or Git. The example does not print credentials or raw errors. Applications
should use a credential provider appropriate to their deployment.

## Three-minute demonstration

1. Run `moon run examples/parse --target native`. The offline example decodes a
   multi-word UPS status without opening a socket.
2. In an isolated Linux development environment with NUT 2.8+ (`nut-server` and
   `nut-client`) already installed, run:

   ```sh
   moon build --target native
   python3 scripts/upsd_integration.py
   ```

   The script starts the actual NUT `upsd` and `dummy-ups` programs with disposable
   configuration and a synthetic device, bound only to loopback. It compares
   moonnut's `LIST UPS`, `LIST VAR` and `GET VAR` results with official `upsc`,
   then stops only its own child processes and removes its temporary files.
   It does not use the system's NUT configuration, a service manager, a physical
   device, or a persistent account. It checks both anonymous loopback plaintext
   and verified STARTTLS with a disposable read-only account. It observes the
   server's incorrect-password behavior and rejects an untrusted CA and wrong hostname. OpenSSL is required; NSS-backed
   NUT builds additionally need `libnss3-tools`. Keys and accounts remain temporary.
3. Run `python3 scripts/tls_smoke.py` to demonstrate accepted trusted TLS and
   rejection of untrusted certificates and wrong hostnames before credentials.

The query example also exposes both variable operations for an authorized target:

```sh
moon run examples/query --target native -- ups.example.invalid 3493 --vars demo
moon run examples/query --target native -- ups.example.invalid 3493 --get demo ups.status
```

For monitoring consumers, add `--json` to any query operation. Device and variable
lists become arrays of named objects; a single read includes the UPS, variable
name and string value. Quoting, backslashes, tabs and Unicode are encoded by the
standard JSON serializer. Values remain strings, including numeric-looking values.
Parse stdout only after a zero exit status; failures have redacted text and a
nonzero exit status rather than a misleading successful JSON result.

```sh
moon run examples/query --target native -- ups.example.invalid 3493 --get demo ups.status --json
```

```json
{"ups":"demo","name":"ups.status","value":"OL CHRG"}
```

## API choices

`Client::new` options:

| Option | Default | Meaning |
| --- | --- | --- |
| `port` | `3493` | TCP server port |
| `security` | `Tls` | System roots; `TlsCaFile(path)` uses a custom CA |
| `username`, `password` | absent | Paired credentials, TLS only |
| `timeout_ms` | `5000` | DNS through the complete response |
| `max_line_bytes` | `65536` | Bytes before a line's LF delimiter |
| `max_response_bytes` | `4194304` | Total received protocol bytes, including credential-exchange replies |
| `max_rows` | `4096` | Rows in a list response |

`Plaintext` must be explicitly selected and cannot be combined with credentials.
It provides neither confidentiality nor server authentication and is intended
only for a controlled test or separately secured channel. There is no
"trust all certificates" setting. A refused STARTTLS never falls back to plaintext.
TLS minimum versions and cipher policy are inherited from the underlying TLS
library; moonnut does not currently enforce a separate TLS 1.2/1.3 minimum.

`NutError` distinguishes invalid arguments, malformed replies, canonical server
error codes, resource limits and premature EOF. Transport, TLS and timeout errors
from `moonbitlang/async` are propagated. A failed call closes its connection;
applications decide whether and when to retry. `Client` is opaque and has no
credential-bearing debug representation. Secret memory is not guaranteed to be zeroized.

## Protocol compatibility and references

- [RFC 9271](https://www.rfc-editor.org/rfc/rfc9271): informational UPS protocol description.
- [NUT network protocol](https://networkupstools.org/docs/developer-guide.chunked/net-protocol.html):
  practical `upsd` behavior and differences from RFC 9271.
- [Network UPS Tools](https://github.com/networkupstools/nut) and its
  [PyNUT reference, v2.8.3](https://github.com/networkupstools/nut/blob/v2.8.3/scripts/python/module/PyNUT.py.in):
  reference ecosystem, not embedded dependencies.

RFC 9271 describes mandatory authentication; historical NUT installations also
allow anonymous read-only queries. moonnut permits anonymous reads but respects
`ERR ACCESS-DENIED`; it does not claim the RFC's entire security/profile compliance.
It does not depend on newer command aliases such as `PROTVER` or `PRIMARY`.

**Credential acknowledgment is not authentication proof.** NUT's `PASSWORD` command
stores a password for later commands that require authorization. A server can
reply `OK` to an incorrect password and still allow anonymous read-only queries,
as observed with NUT 2.8.4. moonnut propagates any server rejection, but successful
reads do not certify the credentials. It deliberately does not use `LOGIN` as a
password probe: NUT reserves that command for power-consumer/upsmon coordination.

NUT uses parseconf-style tokens, not JSON or shell syntax: backslash escapes the
next character, double quotes group tokens, single quotes do not, unquoted `=` is
a token and unquoted `#` starts a comment. The encoder also escapes `#` for older
NUT parsers. LF and CRLF replies are accepted; physical newline continuation is
not supported. UTF-8 descriptions are accepted as an extension to the documented
ASCII protocol. Invalid UTF-8 and control characters are rejected.

This is original MoonBit code, not a PyNUT translation. PyNUT is GPL-3.0-or-later;
no PyNUT source is vendored or linked. Its public API runs in a separate process;
CI downloads a commit-pinned, SHA-256-verified module outside the checkout.
The real-daemon comparison covers UPS/variable lists and unknown-UPS failure;
PyNUT's lack of direct `GET VAR` and STARTTLS APIs is marked as not provided,
not a failed test. The older optional `reference_smoke.py` only compares a synthetic
`LIST UPS` fixture. Neither comparison establishes complete parser equivalence.

## Development and verification

```sh
moon update
moon check --target native
moon test --target native
moon build --target native
python3 scripts/tls_smoke.py
python3 scripts/cli_json_smoke.py
# On isolated Linux with NUT 2.8+ installed
python3 scripts/upsd_integration.py
moon info --target native
moon fmt --check
# Optional: external official PyNUT v2.8.3 module, kept outside the repository
python3 scripts/reference_smoke.py /external/path/PyNUT.py
# Same-daemon PyNUT/upsc comparison on isolated Linux, with the pinned module
python3 scripts/upsd_integration.py --pynut /external/path/PyNUT.py
```

MoonBit tests cover parsing, injection rejection, fragmented/coalesced replies,
error handling, identifier matching, empty lists, EOF, TLS refusal, timeout and
resource bounds. Lifecycle tests verify server-observed EOF after timeout or
cancellation, a successful subsequent query, and independent concurrent replies. The TLS script creates disposable loopback certificates and
checks trusted CA, encrypted credential exchange, server credential rejection,
unknown CA and wrong hostname.
No test needs a real UPS, account or persistent credential. Registry publication
is a separate manual maintainer step, not part of these checks or CI. See
[CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) and [LICENSE](LICENSE).
