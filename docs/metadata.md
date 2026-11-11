# Descriptions, types and status / 描述、类型与状态

[English README](../README.mbt.md) · [中文 README](../README.zh-CN.md)

## English

These additions are in the current checkout, not the published Mooncakes 0.1.0.
They reuse the existing connection, TLS, timeout and response limits. They add
no writes, background polling, hardware control or automatic shutdown policy.

### Read metadata

| Client method | Protocol | Result |
| --- | --- | --- |
| `get_ups_description(ups)` | `GET UPSDESC` | Configured UPS description |
| `get_var_description(ups, name)` | `GET DESC` | Variable description from the server |
| `get_var_type(ups, name)` | `GET TYPE` | All type tokens in server order |

Descriptions are server text. Preserve `Unavailable` and localized descriptions;
do not use a description as a stable identifier. Type tokens may include `RW`,
`ENUM`, `STRING:n` (maximum length), `RANGE`, `NUMBER`, and future extensions.
For example, `RW STRING:32` becomes `["RW", "STRING:32"]`, not one enum value.
An empty list is valid: the NUT protocol defines an omitted type as numeric.
Unknown tokens are retained. The library does not infer a number, parse a range,
fetch enum choices or validate a value from these flags. `get_var` values remain
strings. `RW` describes the server variable, not this client's capabilities or
the caller's authorization. No write method is added.
See [capability discovery](discovery.md) for explicit ENUM/RANGE and command reads.

```sh
# Only use a server you are authorized to query. Use --tls to require verified TLS.
moon run examples/query --target native -- ups.example.invalid 3493 --ups-desc demo --json
moon run examples/query --target native -- ups.example.invalid 3493 --desc demo ups.model --json
moon run examples/query --target native -- ups.example.invalid 3493 --type demo ups.model --json
```

The type query has this JSON shape (illustrative values):

```json
{"ups":"demo","name":"ups.model","types":["RW","STRING:32"]}
```

### Interpret status without collapsing flags

```sh
# Offline examples; these do not contact a server or real equipment.
moon run examples/status --target native
moon run examples/status --target native -- "OB LB"
moon run examples/status --target native -- "OL FUTURE"
```

`OL CHRG` means the online and charging flags are present together. `OB LB` means
on-battery and low-battery flags are present together. The example splits the
space-separated value, tests exact case-sensitive tokens and keeps the raw value
and unknown tokens. `NOL` must not accidentally match `OL`. It demonstrates four
common flags, not a complete alarm interpreter. Empty, unknown, contradictory or
stale data must not be treated as healthy power, and absence of `LB` does not
prove battery health. Production monitoring must handle query failure, freshness,
other status flags and `ups.alarm` separately. Never base a power-control policy
on this illustrative example alone.

### Reproduce the checks

Run the README's development commands. `moon test --target native` covers quoted
and unavailable descriptions, multiple/omitted/unknown types, wrong identifiers,
malformed shapes, errors, shared limits and exact status tokens.
`scripts/cli_json_smoke.py` checks all eleven query operations on synthetic loopback
replies. In isolated Linux, `scripts/upsd_integration.py` uses real `upsd` and
`dummy-ups` with a virtual UPS. `GET UPSDESC` is compared with official `upsc -L`;
selected string/numeric variable descriptions and types are compared with
official **`upsrw -l` in list-only mode**, never `-s`. This is not a write test.
Pinned PyNUT has no dedicated public APIs for these three metadata queries;
that coverage is explicitly not claimed. Physical UPS behavior is not tested.

References: [NUT protocol](https://networkupstools.org/docs/developer-guide.chunked/net-protocol.html),
[standard variables](https://networkupstools.org/docs/developer-guide.chunked/apas01.html),
[upsrw manual](https://networkupstools.org/docs/man/upsrw.html), and
[comparison baseline](comparison.md).

## 中文

这些新增功能属于当前检出源码，尚未包含在 Mooncakes 0.1.0 中。它们复用现有连接、
TLS、超时与响应限制，不增加写操作、后台轮询、硬件控制或自动关机策略。

### 读取元信息

| Client 方法 | 协议 | 返回值 |
| --- | --- | --- |
| `get_ups_description(ups)` | `GET UPSDESC` | UPS 配置中的描述 |
| `get_var_description(ups, name)` | `GET DESC` | 服务端提供的变量描述 |
| `get_var_type(ups, name)` | `GET TYPE` | 保留顺序的全部类型标记 |

描述是服务端文本，应保留 `Unavailable` 及本地化内容，不能作为稳定标识符。
类型可含 `RW`、`ENUM`、`STRING:n`（最大长度）、`RANGE`、`NUMBER` 及未来扩展。
例如 `RW STRING:32` 返回 `["RW", "STRING:32"]`，而不是一个枚举值。空数组合法：
NUT 协议规定省略类型时默认为数值。未知标记原样保留，不据此自动转换数值、解析范围、
获取枚举候选项或校验值；`get_var` 始终返回字符串。`RW` 只是服务端变量的元信息，
不代表本客户端可写，也不代表调用者获得写入授权。没有新增写接口。
显式读取 ENUM/RANGE 及命令的接口见[只读能力发现](discovery.md#中文)。

上方三条查询命令分别演示 UPS 描述、变量描述、变量类型及 JSON 输出，可加 `--tls` 强制验证 TLS，
仅可针对已授权的服务器执行。类型 JSON 含 `ups`、`name`、`types` 字段，示例值
不是任何真实设备的读数。

### 按多个标记解释状态

上方 `examples/status` 命令完全离线。默认 `OL CHRG` 表示同时包含在线、充电标记；
`OB LB` 表示同时包含电池供电、低电量标记。示例按空格拆分，精确且区分大小写匹配，
保留原始值和未知标记，避免把 `NOL` 误认为 `OL`。它只展示四种常见标记，不是完整
告警解释器。空、未知、矛盾或过期状态不应当作供电正常，没有 `LB` 也不能证明电池
健康。实际监控还需分别处理查询失败、数据时效、其他状态标记及 `ups.alarm`，不能
仅凭此教学示例制定电源控制策略。

### 复现验证

执行 README 的开发命令。MoonBit 测试覆盖引号/不可用描述、多项/省略/未知类型、
标识不匹配、畸形响应、错误与共用限制，以及状态精确匹配。CLI JSON 脚本使用合成
回环响应覆盖全部十一种查询操作。隔离 Linux 的真实 `upsd + dummy-ups` 测试仍使用
虚拟 UPS：将 `GET UPSDESC` 与官方 `upsc -L` 对照，将选定字符串/数值变量的描述和
类型与官方 **`upsrw -l` 只读列表模式**对照，绝不使用 `-s`，不是写入测试。
固定版本 PyNUT 没有这三个元信息查询的专用公开 API，不宣称对应覆盖。
未测试实物 UPS 行为。协议、标准变量、upsrw 手册和固定对照基线链接见上方。
