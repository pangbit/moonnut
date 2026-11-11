# Native upsc / 原生查询 CLI

The executable `cmd/upsc` implements common NUT 2.8.4 read-only CLI workflows.
The fixed reference is [upsc.c](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/upsc.c)
and [upsclient.c](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/upsclient.c).
This is an unreleased moonnut executable, not a complete replacement claim.
The custom `examples/query` interface remains available for JSON and explicit TLS policy.

```sh
moon build --target native
# Use the address of an authorized test server:
_build/native/debug/build/cmd/upsc/upsc.exe -L 127.0.0.1:3493
_build/native/debug/build/cmd/upsc/upsc.exe demo@127.0.0.1:3493 ups.status
_build/native/debug/build/cmd/upsc/upsc.exe -c demo@127.0.0.1:3493
```

| Form | Behavior |
| --- | --- |
| `-l [host[:port]]` | UPS names, one per line; default localhost:3493 |
| `-L [host[:port]]` | `name: description`, preserving server order |
| `ups[@host[:port]]` | All variables as `name: value`, preserving server order |
| `ups[@host[:port]] variable` | Value only, with a final newline; includes `server.info` / `server.version` |
| `-c ups[@host[:port]]` | Addresses of registered consumers; duplicate addresses are retained |
| `-W seconds` | Connect timeout, overriding `NUT_DEFAULT_CONNECT_TIMEOUT`; built-in 10 seconds; zero selects blocking connect |
| `-h` / `-V` | Help / local client version, exit 0; moonnut product identity is explicit |

Short options can be clustered and `-W` values attached. Parsing stops at the first
positional argument; `--` also ends option parsing. List mode wins over `-c`;
once selected, `-L` remains verbose even if followed by `-l`. Additional positional
arguments are ignored as in the reference. A variable without a dot is rejected
after connecting, before issuing GET. Common server and address errors exit 1.
Invalid timeout values warn and retain the preceding valid setting.

The CLI never submits credentials, LOGIN or control requests. `-c` observes
registered consumers; it does not register itself. Default transport tries
**unverified TLS and permits plaintext on STARTTLS refusal**. A handshake failure
aborts. There is no verified-TLS flag in this official-style CLI; use the library's
explicit `Tls`/`TlsCaFile` or `examples/query --tls/--ca` when verification is required.

## Validation and open differences

Local macOS checks: 49 existing native tests, 20 JSON scenarios, 10 library TLS
scenarios and four additional native-upsc transport scenarios pass. The four
cover an untrusted/wrong-host certificate, two STARTTLS refusal replies and a failed
TLS handshake, using disposable loopback sockets. Native check/build/info/format pass.

The new [official CLI comparison](../scripts/upsc_cli_integration.py) is wired into
[isolated upsd integration](../scripts/upsd_integration.py). **All 40 differential
cases passed [CI 42996781132](https://github.com/pangbit/moonnut/actions/runs/42996781132),
code `7aba3416dc8aa0f480fa9e805f6b1364e95d4442`.** The reference uses Ubuntu
26.04 NUT packages `2.8.4+really-2`, with NSS; it does not represent all NUT platforms.

| Matrix IDs | Cases and observations |
| --- | --- |
| C01 | `names`, `descriptions`, `list-precedence`: two synthetic devices, ordered output and description formatting |
| C02 / N02–N03 | Two full variable tables; four scalar values; server.info/version; missing UPS/variable; old-name error precedence; `--`, extra arguments and option termination |
| C03 / N12 | Empty, one and two LOGIN consumers, duplicate loopback addresses, eventual LOGOUT cleanup |
| C04 / B12 / L08 / L11 | Zero/fractional/invalid timeout options and environment values; bracketed host, numeric port prefix and common malformed addresses |
| B11 | Exit status, exact stdout and semantic stderr for each case; separate raw help/version records retain their known identity difference |

The same CI also passed all earlier read/PyNUT comparisons, 44 session outcomes in
each of three transport profiles, 52 control outcomes and 25 management CLI cases.
All control regressions use isolated in-memory devices. No real-device result is inferred.

The artifact `upsc-cli.json` in `isolated-control-evidence` retains both raw outputs,
arguments and expected results even when comparison fails (CI retention: seven days). The name is inherited
from the earlier control suite; these 40 cases send no device controls. Two temporary
LOGIN-only consumers belong to the isolated test setup, using disposable credentials.
The read-only discovery fixture still rejects any driver control request.

Only the six exact NSS diagnostic lines listed in [cli_reference.py](../scripts/cli_reference.py)
are excluded from stderr equality; raw lines remain in the evidence. Every other
byte and output order is compared. Help/version identity records are separate from
the 40 passing/failing differential cases. A successful reachable-server `-W` case
checks parsing/diagnostics, not deadline behavior or elapsed-time equivalence.

Remaining differences and unverified boundaries stay in the [matrix](parity-matrix.md):

- Lists now use the [scoped streaming reader](streaming.md). Selected partial-output,
  extra-field and list-error behavior passed 27 official comparisons; a UTF-8 parser
  difference was separately reproduced. Resource limits, full parsing and pipe/TTY behavior still differ or
  remain unverified.
- Help/version, unknown-option/missing-option diagnostics, NSS/debug/config output,
  full server-error catalog and DNS/connect/IO/TLS error text remain incomplete.
- Default addresses are implemented but the direct daemon comparison uses explicit
  loopback ports. IPv6, unusual address delimiters, 512-byte C truncation, numeric
  extremes and sub-millisecond timeout precision remain open.
- Cleanup currently waits for a bounded LOGOUT reply; libupsclient sends LOGOUT
  and closes without waiting. Signals, TTY behavior and Windows are not verified.

Monitoring clients and the remaining library capabilities remain in the approved
full-client target. No real UPS, host shutdown or Mooncakes publication is involved.

## 中文

`cmd/upsc` 新增官方风格只读入口，支持 `-l/-L`、全变量、单变量、`-c`、`-W`、`-h/-V`。
列表保持服务端顺序，`-c` 保留重复地址；`server.info/server.version` 返回服务端信息。
无主机时默认 localhost:3493，连接超时默认 10 秒，环境变量先覆盖、命令行后覆盖，0 表示阻塞连接。
参数在首个位置参数或 `--` 后停止解析，列表优先于 `-c`，旧式变量名在连接后拒绝。

此 CLI 不发送凭据、LOGIN 或设备控制。默认仍是不验证 TLS，STARTTLS 被拒绝时回退明文，
握手失败则终止。官方风格入口没有验证 TLS 参数；有验证需求时使用库的显式 TLS 模式，
或保留的 `examples/query --tls/--ca`。JSON 仍由演示入口提供。

本地 49 项原生、20 项 JSON、10 项原有 TLS 及 4 项新增 upsc 传输检查已通过。
新增 40 场景官方差分已通过[固定 Linux CI 42996781132](https://github.com/pangbit/moonnut/actions/runs/42996781132)，
对应代码 `7aba3416dc8aa0f480fa9e805f6b1364e95d4442`；只证明列明场景。
复用两个虚拟设备及只授予 LOGIN 的临时账号，比较双端原始输出、顺序、错误及退出码；
两个临时消费者仅属于测试准备，不代表查询 CLI 会登录。没有真实设备控制或宿主关机。

`upsc-cli.json` 保存原始证据；仅排除明确列举的六行 NSS 后端日志做业务 stderr 比较，
因此仍保留日志差异。帮助/版本身份另存，不混入 40 个差分场景；可达服务上的 `-W`
检查不冒充超时精度或计时边界验证。默认地址、IPv6、完整错误、长输入、完整流式/缓冲边界、
LOGOUT 等待、信号/管道及 Windows 等仍未完成。客户端完整目标与用户控制发布的限制不变。

流式增量的实现、部分列表退出 0 语义和实际验收状态见[流式列表](streaming.md#中文)。
