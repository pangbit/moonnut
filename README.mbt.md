# moonnut

[简体中文](README.zh-CN.md)

A small, independently implemented **NUT upsd client for MoonBit native**.
Personally maintained, Apache-2.0 licensed, and deliberately read-only.

## Scope and safety

- `LIST UPS`, `LIST VAR` and `GET VAR`, with typed device/variable results.
- Verified STARTTLS by default, using system roots or an explicit PEM CA file.
- Optional `USERNAME` / `PASSWORD` authentication **only after verified TLS**.
- One fresh connection per query; no shared stream, pooling, automatic retries or downgrade.
- Whole-operation timeout, bounded line length, total response bytes and list rows.
- NUT-style quoting and escaping, strict reply identity and list boundary checks.

There is **no** `FSD`, `SET VAR`, `INSTCMD`, `LOGIN`, `PRIMARY`/`MASTER`, shutdown,
or arbitrary-command API. This is not a power-control agent or a complete RFC 9271
implementation. Authentication itself creates temporary server-side session state.
Only use it against servers you are authorized to query.

**Verification boundary:** tests use synthetic loopback NUT/TLS servers. A common
`LIST UPS` fixture is also compared with PyNUT in a separate process. No physical
UPS or real `upsd` deployment has been verified; no hardware-compatibility claim is made.

## Quick start

Requires MoonBit native and `moonbitlang/async` 0.22.4. Verified locally with
`moon` 0.1.20261104 / `moonc` v0.10.20+65efd5b93 on macOS arm64.
Networking and TLS use the official [async library](https://github.com/moonbitlang/async),
including its native platform/OpenSSL requirements. Linux CI is configured but must
be checked on the published commit before claiming a Linux pass.

```sh
# Offline; no device access
moon run examples/parse --target native
```

After a registry release is available: `moon add pangbit/moonnut`. Before publication,
use a checkout/local workspace dependency. Import `pangbit/moonnut` in `moon.pkg`;
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
Each call opens, authenticates and closes its own connection, including on failure.

```sh
# Only with authorization for the explicitly named target
moon run examples/query --target native -- ups.example.invalid 3493
moon run examples/query --target native -- ups.example.invalid 3493 --ca /path/to/ca.pem
```

`examples/query` reads optional `MOONNUT_USERNAME` and `MOONNUT_PASSWORD` from the
process environment. Do not put real credentials in commands, source, examples,
issues or Git. The example does not print credentials or raw errors. Applications
should use a credential provider appropriate to their deployment.

## API choices

`Client::new` options:

| Option | Default | Meaning |
| --- | --- | --- |
| `port` | `3493` | TCP server port |
| `security` | `Tls` | System roots; `TlsCaFile(path)` uses a custom CA |
| `username`, `password` | absent | Paired credentials, TLS only |
| `timeout_ms` | `5000` | DNS through the complete response |
| `max_line_bytes` | `65536` | Bytes before a line's LF delimiter |
| `max_response_bytes` | `4194304` | Total received protocol bytes, including authentication replies |
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

NUT uses parseconf-style tokens, not JSON or shell syntax: backslash escapes the
next character, double quotes group tokens, single quotes do not, unquoted `=` is
a token and unquoted `#` starts a comment. The encoder also escapes `#` for older
NUT parsers. LF and CRLF replies are accepted; physical newline continuation is
not supported. UTF-8 descriptions are accepted as an extension to the documented
ASCII protocol. Invalid UTF-8 and control characters are rejected.

This is original MoonBit code, not a PyNUT translation. PyNUT is GPL-3.0-or-later;
no PyNUT source is vendored or linked. The optional comparison runs its public API
in a separate process against the same synthetic fixture. That comparison covers
`LIST UPS` names/descriptions only, not all parser edge cases or real-daemon interoperability.

## Development and verification

```sh
moon check --target native
moon test --target native
moon build --target native
python3 scripts/tls_smoke.py
moon info --target native
moon fmt --check
# Optional: external official PyNUT v2.8.3 module, kept outside the repository
python3 scripts/reference_smoke.py /external/path/PyNUT.py
# Packaging validation only, not a release
moon publish --dry-run
```

MoonBit tests cover parsing, injection rejection, fragmented/coalesced replies,
error handling, identifier matching, empty lists, EOF, TLS refusal, timeout and
resource bounds. The TLS script creates disposable loopback certificates and
checks trusted CA, encrypted authentication, unknown CA and wrong hostname.
No test needs a real UPS, account or persistent credential. See
[CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) and [LICENSE](LICENSE).
