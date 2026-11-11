# Read-only capability discovery / 只读能力发现

[English README](../README.mbt.md) · [中文 README](../README.zh-CN.md)

## English

These APIs are unreleased GitHub main additions. The Mooncakes 0.1.0 package is
unchanged. Discovery does not grant permission to change variables or execute
commands. There is no `SET VAR`, `INSTCMD` or arbitrary-command API.

| Client method | Request | Result |
| --- | --- | --- |
| `list_rw(ups)` | `LIST RW` | `Array[Variable]`: variable name and current string value |
| `list_enum(ups, name)` | `LIST ENUM` | Allowed string values in server order |
| `list_range(ups, name)` | `LIST RANGE` | `Array[VariableRange]`: string `min` and `max` for every interval |
| `list_commands(ups)` | `LIST CMD` | Command names in server order, without executing them |
| `get_command_description(ups, command)` | `GET CMDDESC` | Server-provided command description |

Use `get_var_type` to inspect `ENUM`/`RANGE` flags before requesting options.
`get_var` or `list_rw` supplies the current value; ENUM rows do not mark a selected
option. Range endpoints remain strings, including decimals, signs and leading
zeroes. Multiple intervals are retained separately: `90..100` and `102..105`
do not permit `101`. The client does not merge intervals, sort, coerce numbers,
validate an intended write, or infer safety/authorization from metadata.

Every list validates its exact BEGIN/END identity and its command-specific rows:
`RW ups variable value`, `ENUM ups variable value`, `RANGE ups variable min max`,
and `CMD ups command`. Empty lists are valid; unknown UPS/variable/command,
`NOT-ENUM`, `NOT-RANGE` and access errors, if sent, are propagated. NUT 2.8.4
returns an empty ENUM/RANGE list for an existing variable without those metadata. A list is returned only after the matching END line.
Descriptions may be localized or `Description unavailable`; use command names as identifiers.
Each call uses the NUT CLI TRYSSL default, fresh connection, timeouts, row,
line and byte limits as existing reads. Multiple calls are not an atomic snapshot.

### Example

Only query a server you are authorized to access. These flags only read metadata,
even when a listed command is named `load.off`.

```sh
moon run examples/query --target native -- ups.example.invalid 3493 --rw demo --json
moon run examples/query --target native -- ups.example.invalid 3493 --enum demo ups.beeper.status --json
moon run examples/query --target native -- ups.example.invalid 3493 --range demo input.transfer.low --json
moon run examples/query --target native -- ups.example.invalid 3493 --commands demo --json
moon run examples/query --target native -- ups.example.invalid 3493 --cmd-desc demo load.off --json
```

Illustrative range result, not a real UPS reading:

```json
{"ups":"demo","name":"input.transfer.low","ranges":[{"min":"90","max":"100"},{"min":"102","max":"105"}]}
```

`--rw` emits an array of `{name,value}` objects; `--enum` emits
`{ups,name,values}`; `--commands` emits an array of names; `--cmd-desc` emits
`{ups,command,description}`. Check for a zero exit status before parsing stdout.
Use the documented read-only `upsrw -l` and `upscmd -l` modes for comparison,
never `upsrw -s` or an `upscmd` command argument.

### Verification boundary

The standard development checks include strict row shapes, wrong identifiers and
boundaries, fragmented UTF-8/CRLF, quoted and empty options, decimal string
endpoints, multiple ranges, empty lists, errors, EOF and resource bounds. The CLI
JSON smoke covers all eleven query operations.

`scripts/upsd_integration.py` runs actual `upsd` with a disposable `dummy-ups`
virtual UPS, compares RW variables with official `upsrw -l`, and command names
and descriptions with official `upscmd -l`. Since dummy-ups does not advertise
ENUM/RANGE metadata, a second **synthetic Unix-socket driver state fixture** feeds
actual upsd two enum options and two disjoint integer ranges. moonnut and upsrw
read those same server results, comparing complete option sets per variable and
both command names/descriptions (`load.off` and `test.battery.start.quick`).
This tests real upsd serialization and client compatibility, not a physical
driver's range behavior. No write or command is
executed; the fixture rejects unexpected driver requests. Fractional formatting
is tested with synthetic wire responses, not NUT 2.8.4 upsrw's integer-only range display.
The existing PyNUT comparison remains scoped to UPS/variable lists and errors.

Follow [the fixed baseline and reproduction steps](comparison.md), plus the
README development commands. No test connects to physical UPS equipment.
Protocol references: [NUT network protocol](https://networkupstools.org/docs/developer-guide.chunked/net-protocol.html),
[driver socket protocol](https://github.com/networkupstools/nut/blob/v2.8.4/docs/sock-protocol.txt),
[upsrw](https://networkupstools.org/docs/man/upsrw.html),
[upscmd](https://networkupstools.org/docs/man/upscmd.html).

## 中文

以上 API 属于 GitHub main 的未发布改进，Mooncakes 0.1.0 保持不变。发现可写变量或
命令不代表获得写入/执行授权。本库不提供 `SET VAR`、`INSTCMD` 或任意命令接口。

- `list_rw(ups)` 返回变量名及当前字符串值。
- `list_enum(ups, name)` 按服务端顺序返回候选字符串，不标注当前选中项。
- `list_range(ups, name)` 返回全部 `VariableRange`，每项含字符串 `min`、`max`。
- `list_commands(ups)` 只列出命令名称，不执行命令。
- `get_command_description(ups, command)` 只读取命令描述。

可先通过 `get_var_type` 查看 `ENUM`/`RANGE` 标记，再读取候选值或范围；当前值应另用
`get_var` 或 `list_rw` 获取。范围保留符号、小数、前导零及各个独立区间，不能把
`90..100` 与 `102..105` 合并为 `90..105`，否则会错误地接受 `101`。库不进行数值
转换、排序、合并或写入验证，也不从这些信息推导操作安全性与授权。

列表按各命令的确切行格式与请求标识校验，包括 BEGIN/END。RW 为变量+值、ENUM 为
单候选值、RANGE 为两个端点、CMD 为单命令名。空列表有效；未知 UPS/变量/命令、
`NOT-ENUM`、`NOT-RANGE` 和访问错误若由服务端返回则原样传播；NUT 2.8.4 对已知但无相应元信息的变量返回空 ENUM/RANGE 列表。收到匹配 END 前不返回部分
结果。描述可能是本地化文字或 `Description unavailable`，应使用命令名作为标识。
每次查询沿用官方 TRYSSL 默认、独立连接、连接/读取超时、行数/行长/总字节限制；多次读取不是
原子快照。即使命令叫 `load.off`，上方示例也只读其名称和描述。

上方五条命令均支持 JSON。`--rw` 返回 `{name,value}` 对象数组；`--enum` 返回
`{ups,name,values}`；`--range` 返回上方示例结构；`--commands` 返回名称数组；
`--cmd-desc` 返回 `{ups,command,description}`。应先检查退出码为零，再解析 stdout。
官方客户端对照只使用 `upsrw -l`、`upscmd -l`，不使用写入或执行参数。

### 验证范围

MoonBit 测试覆盖各命令行宽、标识/边界错误、分段 UTF-8/CRLF、引号/空候选值、
小数端点、多区间、空列表、错误、EOF 及资源限制，CLI JSON 覆盖全部十一种查询。
真实 `upsd + dummy-ups` 使用虚拟 UPS，将可写变量与 `upsrw -l`、命令及描述与
`upscmd -l` 对照。dummy-ups 不提供 ENUM/RANGE，因此另用小型**合成 Unix socket
驱动状态**向真实 upsd 提供两个枚举值及两个不连续整数区间，由 moonnut 与 upsrw
读取同一服务端结果，逐变量比较完整候选项，并核对 `load.off` 和
`test.battery.start.quick` 两个命令的名称及描述。该步骤验证真实 upsd 的序列化和客户端
兼容性，不验证物理驱动。
未执行任何写入或命令，合成驱动会拒绝意外请求。小数原样保留使用合成线上响应验证，
不声称已通过只能显示整数区间的 NUT 2.8.4 upsrw 对照。现有 PyNUT 对照仍限于设备/变量列表和错误。
复现步骤、固定基线见[对照说明](comparison.md#中文)，开发命令见 README。
所有测试均不连接实物 UPS。
