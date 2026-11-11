# Client control requests / 客户端控制请求

The explicit `Session` now exposes the remaining five control commands. This is
one part of P4, not full NUT client or CLI equivalence. These APIs are available
on an existing session so credentials and tracking belong to the same connection.
Nothing sends LOGIN, changes tracking, waits for completion or retries implicitly.

| API | Request | Successful reply |
| --- | --- | --- |
| `set_var(ups, name, value)` | SET VAR | `CommandReceipt` |
| `execute_command(ups, command, parameter?)` | INSTCMD | `CommandReceipt` |
| `primary(ups)` | PRIMARY | OK PRIMARY-GRANTED |
| `master(ups)` | MASTER | OK MASTER-GRANTED |
| `fsd(ups)` | FSD | OK FSD-SET |

`CommandReceipt::Accepted` means upsd returned OK. `Tracked(id)` means it returned
OK TRACKING with a nonempty ID. **Neither means completion.** Use the existing
`get_tracking_status(id)` on a tracking-enabled session to inspect Pending,
Success, Unknown, InvalidArgument or Failed. Success is the driver's reported
result, not independent evidence of a physical effect. Other server errors still
raise `NutError::Server`; malformed acknowledgements raise `Protocol`.

Values stay strings; ENUM, RANGE, length and permission checks belong to the
reference upsd and driver. The library does not substitute strict numeric parsing
for upstream behavior. An omitted command parameter and an explicitly empty one
produce distinct client requests. Every argument uses NUT quoting/escaping;
control characters are rejected before sending.

A disconnect, cancellation or timeout after dispatch leaves the operation's
outcome uncertain and closes that session. The client never reconnects or repeats
it automatically. A malformed complete acknowledgement can also leave the
operation uncertain even though its response line was consumed. Repeating a
control request is a new action, not a recovery mechanism.

PRIMARY and MASTER are explicit permission checks with different reply text in
NUT 2.8.4. They do not register a consumer or silently fall back to each other.
FSD sets upsd's forced-shutdown flag; real monitoring clients may act on it. The
library does not interpret FSD acknowledgement as a device or host shutdown.

## Reference and evidence

Reference: NUT v2.8.4, commit
`541c2ecf0b2ec33dadb9f40b16acbe39042bd103`. Sources:
[SET](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netset.c),
[INSTCMD](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netinstcmd.c),
[PRIMARY/MASTER](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netuser.c),
[FSD](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netmisc.c),
[driver argument dispatch](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/drivers/dstate.c).

Local macOS validation: 48 native tests pass, including three new focused control
tests for receipts, arguments and an acknowledgement lost after dispatch.
**Linux official comparison is pending for this change until a linked CI result
is recorded.** The new test specifies 52 observable outcomes and 15 driver
requests against installed official libupsclient, plus three actual upsrw/upscmd
invocations. This is the designed acceptance trace, not an executed-pass claim.

[scripts/control_integration.py](../scripts/control_integration.py) starts a new
private loopback upsd and a separate in-memory Unix-socket fixture for each probe.
It uses only artificial `fixture.*` commands and temporary accounts/configuration.
No physical driver, upsmon, service manager or shutdown program is started. The
existing read-only discovery fixture still rejects all control requests.

The original [C adapter](../scripts/nut_control_reference.c) uses official
libupsclient's public API. The [MoonBit adapter](../examples/control_probe/main.mbt)
uses the public Session API. Both accept only the fixture port, with a fixed
loopback host and synthetic UPS name. Equivalent fresh daemon state prevents the
first client's writes/FSD from contaminating the second client's results.

The raw trace, raw driver requests, parsed fixture arguments, fixture-reported
results and final in-memory state are saved as `controls.json` in the CI artifact
`isolated-control-evidence` (seven-day retention). Eight random tracking UUIDs are
checked and correlated with the driver requests before replacing them with ordered
placeholders for comparison. No other result or ordering is normalized.

The fixture deliberately holds a SET after acceptance, then applies it only after
an artificial release command. A real upsd tracking ID is likewise held Pending
until release reports success. Numeric driver statuses 0–4 exercise Success,
Unknown, InvalidArgument, Failed and conversion-error-to-InvalidArgument mapping.
This demonstrates server/driver-message semantics, not any hardware result.

Source-backed behaviors covered by the pending trace:

- Denied requests do not reach the driver. Unsupported INSTCMD is checked before
  permission; SET checks permission before variable lookup.
- Disjoint ranges 90–100 and 102–105 reject 101. upsd uses integer-prefix parsing:
  `102tail` passes this range check and is forwarded unchanged; the synthetic
  driver accepts that string. A hardware driver may reject it.
- upsd forwards INSTCMD parameters without enclosing quotes. Empty parameters
  collapse at the driver parser; escaped single-token values survive; `two words`
  becomes two tokens, which the NUT dstate argument-count branch rejects. An OK
  from upsd therefore does not establish that the driver accepted the request.
- PRIMARY/MASTER leave NUMLOGINS at zero. Repeated FSD returns OK, GET VAR gains
  the `FSD ` prefix, a new client still sees it, and the driver retains `OL` with
  no FSD request. Only disposal/recreation supplies the next fresh server state.
- Official upscmd prints a terminal `ERR FAILED` with exit status zero; this is a
  CLI outcome to preserve in future CLI work, not a successful driver result.

The library's optional parameter represents one protocol argument, as quoted by
the C adapter. Official upscmd builds its command from raw argv text and has
additional CLI quoting behavior; that is still open in C11. C++ PRIMARY fallback,
multi-value setters, convenience waits/timeouts and full CLI mappings also remain
open. The [matrix](parity-matrix.md) retains these gaps.

Reproduce in the existing isolated Linux development environment, as a regular
user with pinned NUT packages and a native build:

```sh
cc -Wall -Wextra -Werror scripts/nut_control_reference.c -lupsclient -o /tmp/nut-control-reference
python3 scripts/control_integration.py --reference /tmp/nut-control-reference --evidence-dir /tmp/moonnut-control-evidence
```

**Default transport risk:** TryTls follows the official CLI: unverified TLS and
plaintext credentials if STARTTLS is refused. Explicit Tls/TlsCaFile verify the
server. Controls require target authorization. Validation never targets a real
UPS, and Mooncakes publication remains under the user's control.

## 中文

本批在显式 Session 增加 SET VAR、INSTCMD、PRIMARY、MASTER、FSD 五项客户端请求，
属于 P4 的协议部分，不能宣称完整客户端或 CLI 一致。凭据及 tracking 留在同一连接；
不会隐式 LOGIN、开启 tracking、等待完成或重试。

Accepted 表示收到 upsd 的 OK；Tracked(id) 表示带 ID 的接收确认，二者都不是完成。
调用 get_tracking_status 查询五种结果。Success 仅表示驱动报告成功，不是实际电源
动作的独立证据。值保留字符串；权限、长度、ENUM/RANGE 校验交给 upsd/驱动。
无参数与显式空参数在客户端请求中区分；控制字符在发送前拒绝。

请求发送后断线、取消或超时意味着结果可能不确定，会话关闭且不自动重发。完整但畸形的
确认也可能使结果不确定；再次调用是一次新动作。PRIMARY/MASTER 只是权限检查，不登记
消费者或自动回退别名。FSD 设置 upsd 标记，真实监控程序可能据此触发关机。

本地 48 项原生测试通过。本批新增 Linux 官方对照在记录 CI 链接前仍是待执行，
不能以夹具设计冒充通过。设计对照 52 项结果、15 条驱动请求和 8 个真实生成的 tracking ID，
并运行三次官方 upsrw/upscmd。每个探针新建等价的临时 upsd 与内存驱动；仅回环、合成 UPS、
人工 fixture.* 命令。没有物理驱动、upsmon、服务管理器或关机进程。

原始结果、驱动字节、参数、模拟结果和状态保存在 CI 的 controls.json（保留七天）。
随机 UUID 先验证并对应到驱动请求，再按顺序归一化；其他内容与顺序直接比较。
延迟 SET 及 Pending→Success 由明确 release 控制，不用延时猜测动作已经完成。
数字状态 0–4 覆盖真实 upsd 的 tracking 映射，但模拟驱动成功不代表实物成功。

固定源码还显示：RANGE 按整数前缀检查，102tail 可通过第二个区间并原样转发；
INSTCMD 参数外围引号在 upsd 转发时丢失，空参数会折叠，多词参数可能被驱动分成多个参数
并拒绝；FSD 仅在服务端修饰状态，驱动本身仍为 OL；官方 upscmd 等待得到 ERR FAILED
仍退出 0。这些均列入隔离对照，不把 ACK 或退出 0 当作设备完成。

C++ 别名回退、多值 setter、等待便捷 API、全部管理 CLI 仍未对齐。moonnut 参数接口表示
一个协议参数，官方 upscmd 原始 argv 拼接的差异另留 C11 验收。默认仍为用户选择的官方
TRYSSL 行为，可能明文传输凭据；需要验证时显式使用 Tls/TlsCaFile。禁止真实 UPS 控制，
不发布 Mooncakes，完整目标及未验项继续保留在矩阵。
