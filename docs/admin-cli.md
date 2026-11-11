# Management CLIs / 管理 CLI

`cmd/upsrw` and `cmd/upscmd` now provide native MoonBit management programs using
the pinned NUT 2.8.4 CLI behavior as their reference. They do not call or bundle
NUT executables. Their help/version identify **moonnut**. This is an implemented
and testable part of the full-client plan, not a complete drop-in compatibility
claim; the remaining differences below stay in the acceptance matrix.

```sh
moon build --target native
_build/native/debug/build/cmd/upsrw/upsrw.exe -h
_build/native/debug/build/cmd/upscmd/upscmd.exe -h
```

The commands above are offline. Operational syntax requires an authorized endpoint:

```text
upsrw [-l] [-s VAR[=VALUE]] [-u USER] [-p PASSWORD] [-w] [-t SECONDS] [-W SECONDS] ups[@host[:port]]
upscmd [-l] [-u USER] [-p PASSWORD] [-w] [-t SECONDS] [-W SECONDS] ups[@host[:port]] [command [value]]
```

| Behavior | Implemented mapping |
| --- | --- |
| upsrw default / `-l` | Writable variables, descriptions, ordered type handling, STRING/NUMBER/ENUM/RANGE display and SELECTED markers |
| upsrw `-s VAR=VALUE` / `-s VAR` | Quoted/escaped value; missing value is prompted on stdin |
| upscmd `-l` | Ordered command list and descriptions, without submitting credentials |
| upscmd command / optional value | Raw argv text is forwarded like the official CLI; only the first optional value is used |
| `-u` / `-p` | Explicit credentials, or POSIX username/password prompts; no implicit LOGIN |
| `-w` / `-t` | Enable tracking before dispatch, default 10 seconds, poll once per second, preserve terminal result text |
| Terminal tracking `ERR ...` | Print to stderr and exit **0**, matching official CLI behavior; it is not a successful operation |
| Wait deadline / `-t 0` | Print timeout and exit 1; zero still dispatches the operation, then times out without querying its result |
| `-W` / environment | Default connect timeout 10 seconds; valid NUT_DEFAULT_CONNECT_TIMEOUT then -W overrides; zero selects blocking connect |
| Endpoint | Default localhost:3493, explicit host/port and bracket syntax; comprehensive address edge cases remain open |
| Options | Short options, attached values, clusters, `--`, stop parsing at first positional argument; repeated options follow the last applicable value |

Results use stderr; list output and username/value prompts use stdout. Wait time
uses whole wall-clock seconds as in the reference. A timeout after dispatch is an
uncertain outcome; no operation is replayed. A no-wait OK is only upsd acceptance.
The CLI checks the official OK prefix/receipt-length rules, while the typed
Session control methods retain their stricter `CommandReceipt` parsing.

The raw optional command value is intentionally different from the library's
`execute_command(..., parameter=...)`, which represents one quoted protocol
argument. For example, argv `two words` gives upsd extra arguments; NUT 2.8.4
ignores them for INSTCMD. An argv containing literal surrounding quotes makes a
single multiword protocol value, which upsd then forwards without quotes and
NUT dstate rejects by argument count. Neither path is evidence of physical
execution. The isolated fixture records the driver bytes and parsed outcome.

## Single-line protocol support

`Session::request_line(command, read_timeout_ms?)` performs one serialized command
and returns the raw single-line reply, including ERR. It supports the CLI's raw
argument and result mappings without weakening the typed control API. LIST and
STARTTLS are rejected; use typed list methods and configured transport instead.
The existing UTF-8, framing, response limits and cancellation cleanup still apply.
It is not a full replacement for libupsclient's separate send/read or streaming
APIs. Formatted multiline/control-character commands are rejected before sending.

`Client::new(..., connect_timeout_ms=0)` now selects an uncapped connect attempt;
its optional overall timeout still applies if supplied. `request_line` can select
a positive per-read timeout for the CLI tracking loop. DNS, multiple addresses,
write timing and TLS-backend edge cases are not thereby declared equivalent.

## Validation and outstanding differences

Local validation: **49 native tests**, including one focused single-line exchange
and framing test, plus four loopback CLI wire/output checks. Existing TLS and
JSON checks pass. **The new 25-case official CLI comparison is pending Linux CI
execution until a linked result is recorded here.**

[scripts/admin_cli_integration.py](../scripts/admin_cli_integration.py) reuses the
separate in-memory control fixture. Official and MoonBit programs each run on a
fresh loopback upsd with equivalent initial state. The 25 cases cover both lists,
selected ENUM/RANGE output, writes, permission errors, three POSIX prompts,
raw/quoted/empty/escaped parameters, terminal success/failures, timeout and zero
wait. The last tracked command is also a barrier proving earlier driver requests
were consumed. No real driver, upsmon, service manager or shutdown program runs.

The comparison saves raw stdout/stderr, exit statuses, elapsed times, raw driver
requests and final in-memory state in `admin-cli.json`, alongside the earlier
control artifact. Only these normalization rules are applied:

- Six exact NSS initialization/connection/certificate-warning lines are excluded
  from stderr comparison. **Their absence is a known output difference**, not a
  parity result. Raw stderr is retained; other errors, prompts and whitespace are
  compared exactly.
- Random tracking UUIDs are replaced with ordered placeholders after collecting
  them from driver requests. Elapsed durations are checked by their scenario
  rather than compared as identical numbers.

Remaining gaps include exact help/version/unknown-option diagnostics; complete
network/parse/IO error text and precedence; debug/certificate configuration and
TLS backend logs; POSIX TTY signals and EOF corners; Windows prompts; 512-byte C
buffer truncation versus current string handling; malformed raw argv rejected by
single-line validation; numeric overflow and microsecond connection-time precision;
full environment/endpoint edge cases; and streaming partial-list failures.
The CLI awaits a bounded LOGOUT reply on cleanup, whereas libupsclient disconnect
sends LOGOUT and immediately closes. This lifecycle difference remains open.
These are unfinished compatibility work, not exemptions from the user's target.

Pinned primary sources:
[upsrw.c](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/upsrw.c),
[upscmd.c](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/upscmd.c),
[upsclient.c](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/upsclient.c),
[INSTCMD handler](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netinstcmd.c).

**Transport/credential risk:** default TRYSSL uses unverified TLS and permits
plaintext credentials after STARTTLS refusal. `-p` also exposes credentials in
process arguments, as in NUT; the password prompt avoids that argv exposure.
Use authorized endpoints. The library offers explicit verified Tls/TlsCaFile;
these are not official upsrw/upscmd flags and are not silently substituted for
user-selected CLI defaults. No real UPS control or Mooncakes publication is
performed in this work.

## 中文

新增 `cmd/upsrw` 与 `cmd/upscmd`，原生实现、不依赖或打包官方可执行文件。参考固定
NUT 2.8.4；帮助和版本明确标识 moonnut，不宣称已经可完整替换官方程序。

当前覆盖默认变量列表与命令列表、描述/类型/选项/SELECTED、写变量与即时命令、短选项及
组合、POSIX 用户名/密码/变量值提示、连接目标及超时、tracking 等待。默认等待 10 秒、
每秒轮询；驱动终态 ERR 仍打印至 stderr 并退出 0。`-t 0` 先发送操作，再立即报告超时；
不能把超时当作未执行，不会自动重发。`-W 0` 为阻塞连接，整体期限仍可由库调用者显式设置。

upscmd 可选参数按官方原样拼接 argv；`two words` 会使 upsd 收到多余参数并忽略它们。
含字面外围引号的 argv 才成为单个多词协议值，但 upsd 转发时会丢掉外围引号，驱动可能
按参数数量拒绝。库的 execute_command 参数仍表示一个引用后的协议参数，二者语义有意区分。
单行 request_line 返回原始 ERR，拒绝 LIST、STARTTLS 与多行/控制字符，保留串行化和
取消关闭；不冒充完整底层发送/读取流接口。

本地 49 项原生测试与四个回环 CLI 检查通过，既有 TLS/JSON 回归通过。新增 25 场景官方
差分在记录 CI 链接前仍为待执行，不能提前标通过。双方各使用新建回环 upsd、等价初始
内存设备和假凭据，验证两类列表、SELECTED、写入、权限、三类提示、参数传递及等待结果。
最后一项 tracked 命令确保先前驱动请求都已被消费；无真实驱动、upsmon 或关机程序。

原始 stdout/stderr、退出码、耗时、驱动请求及内存状态保存在 admin-cli.json。
只排除明确列出的六行 NSS 后端日志并归一化随机 tracking ID；耗时按场景范围核验。
NSS 日志缺失是已知输出差异，其他业务文本、提示、空格、顺序直接比较，不称完整 CLI 一致。

帮助/版本/非法选项、完整网络与解析错误、调试/证书配置、TTY/EOF/Windows、C 的 512 字节
截断、畸形参数、数值和微秒精度、完整环境/地址边界及部分列表失败仍待完成。
CLI 等待有界 LOGOUT 回复，官方库发送后即关连接，也保留为生命周期差异。
这些都继续保留在矩阵，不缩小完整客户端目标。

默认与用户选择一致：不验证证书的 TLS，STARTTLS 被拒绝可明文发送凭据；-p 的密码可被
进程参数观察。库仍有显式验证 TLS，但不把它冒充官方管理 CLI 默认。所有测试仅用隔离
模拟环境，不操作真实 UPS、不关闭宿主机、不发布 Mooncakes。
