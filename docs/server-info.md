# Server information / 服务端信息

These six APIs complete the basic stateless read-command inventory alongside
variable and capability discovery. They do not complete the NUT client target:
tracking reads require persistent session work, and the acceptance matrix retains
all remaining client gaps. No LOGIN, SET, instant command or FSD is sent.

| API | Request | Return / 返回 |
| --- | --- | --- |
| `get_num_logins(ups)` | `GET NUMLOGINS ups` | `Int32` LOGIN count, not TCP connection count |
| `list_clients(ups)` | `LIST CLIENT ups` | `Array[String]`, original address order and duplicates |
| `get_server_version()` | `VER` | Raw server banner, without line ending |
| `get_net_version()` | `NETVER` | Raw protocol version |
| `get_protocol_version()` | `PROTVER` | Explicit alias request; NUT 2.8.4 returns the same version |
| `get_help()` | `HELP` | Raw text; HELP omits some supported NUT commands |

```sh
# Templates for an explicitly authorized server. --tls requires verified TLS.
moon run examples/query --target native -- ups.example.invalid 3493 --tls --num-logins demo --json
moon run examples/query --target native -- ups.example.invalid 3493 --tls --clients demo --json
moon run examples/query --target native -- ups.example.invalid 3493 --tls --server-version --json
moon run examples/query --target native -- ups.example.invalid 3493 --tls --net-version --json
moon run examples/query --target native -- ups.example.invalid 3493 --tls --protocol-version --json
moon run examples/query --target native -- ups.example.invalid 3493 --tls --server-help --json
```

JSON count results are `{"ups":"demo","num_logins":0}`; client lists are arrays
of strings; banner/version/help results are JSON strings. Banner whitespace,
quotes and `#` are preserved, without tokenizing and reconstructing the line.
Echoed query tokens use ASCII-insensitive comparison as in libupsclient; returned
values retain their original case. Requests are still quoted and bounded.

The default transport now follows NUT 2.8.4 official CLIs: try unverified TLS and
continue in plaintext when the STARTTLS response is not accepted. Credentials can
therefore travel in plaintext. TLS handshake/IO failure terminates the operation.
Explicit `Tls`/`--tls` and `TlsCaFile`/`--ca` require verified TLS;
`TlsUnverified`/`--tls-unverified` requires TLS without certificate verification.
Default connection timeout is 10 seconds, transport-read timeout 5 seconds, and
`timeout_ms` is an optional overall deadline. Timing/backend/resource-bound
parity is still open in B07, not certified by these default numbers.

Native synthetic tests cover raw text, aliases/errors, count parsing, repeated
IPv4/IPv6 client addresses and canonical response case. The isolated Linux script
compares counts and server information using the installed official libupsclient,
empty lists with `upsc -c`, and HELP/VER/client lists through PyNUT public methods.
TLS fixtures compare default behavior with official upsc when installed.
Nonzero counts tied to real LOGIN state remain for the session phase. No physical
equipment is part of these tests. See [comparison](comparison.md) and
[remaining acceptance items](parity-matrix.md).

## 中文

这六项 API 补齐基本无状态读取命令，不代表完整客户端完成；tracking 读取仍依赖后续
持久会话。调用不会发送 LOGIN、写变量、即时命令或 FSD。

`NUMLOGINS` 统计向该 UPS 执行 LOGIN 的客户端，不是所有 TCP 连接。客户端地址列表
保留顺序及重复项。VER/NETVER/PROTVER/HELP 返回去掉行结束符的原始字符串，保留空格、
引号及 `#`；不能用 HELP 文本作为完整能力清单。响应标识按官方 C 库忽略 ASCII
大小写，变量值不改变大小写。上方命令的 `--tls` 显式要求验证证书与主机名。

默认已按用户选择改为官方 CLI 策略：尝试不验证证书的 TLS，STARTTLS 被拒绝后允许
同连接明文，凭据也可能明文发送；握手或 IO 错误则终止。`Tls`/`TlsCaFile` 强制验证，
`TlsUnverified` 强制 TLS 但不验证证书。默认连接超时 10 秒、每次传输读取 5 秒；
`timeout_ms` 为可选整体截止时间。不同 TLS 后端、DNS/地址重试与资源边界尚未完全对照。

本地测试覆盖原文、别名/错误、计数解析、重复 IPv4/IPv6 地址及大小写。
Linux 隔离脚本将计数和服务信息与官方 libupsclient 对照，空列表与 upsc -c 对照，
HELP/VER/客户端列表与 PyNUT 对照。非零计数及 LOGIN 生命周期留在会话阶段验收。
真实 upsd 配合虚拟设备只是协议参考，不涉及物理设备控制。
