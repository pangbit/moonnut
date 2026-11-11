# Read-only use scenarios / 只读使用场景

[English README](../README.mbt.md) · [中文 README](../README.zh-CN.md)

## English

These are engineering examples for the **current checkout**, not a claim that
unreleased CLI features are included in Mooncakes 0.1.0. All three scenarios use
`examples/query`; they solve different consumer tasks, not three protocol modes
or three physical-device certifications.

### Reproduce without hardware

From the repository root, with the MoonBit native toolchain and dependencies in
the README installed:

```sh
moon build --target native
python3 scripts/cli_json_smoke.py
```

This portable, loopback-only check runs the actual query executable for all three
operations. Expect exit status 0 and:

```text
CLI JSON smoke: escaped UTF-8, lists, scalar read, empty result and failure exit passed (5 cases)
```

It verifies JSON shape, escaping, an empty discovery result and a denied query's
nonzero exit. It is a synthetic protocol fixture, not an actual NUT daemon.
For independent protocol evidence, run the existing real-daemon suite once for
all three scenarios in a disposable Linux environment as a regular user:

```sh
python3 scripts/upsd_integration.py
```

Prerequisites: built query executable, Python 3.9+, OpenSSL, NUT server/client
2.8+ with `upsd`, `dummy-ups` and `upsc`; NSS builds also need `libnss3-tools`.
The [fixed CI baseline and optional PyNUT comparison](comparison.md) specify exact
versions. The runner allocates its own loopback port, virtual UPS, certificates
and temporary configuration, invokes the executable and removes its own resources.
No global service configuration or physical device is used. It checks the three
operations against `upsc`, plus TLS and failure behavior. Its success log includes
`PASS: LIST UPS (1 device), complete LIST VAR` and
`Synthetic device only: status=OL CHRG, charge=100%, runtime=600s`.
The complete variable count can vary with the installed NUT version.

### 1. Discover UPS identifiers for a monitoring configuration

**Task:** enumerate a NUT server before selecting which UPS a dashboard should
monitor, retaining human-readable descriptions rather than guessing device names.

**Operation:** `list_ups()`, or the query executable with `--json` and no operation
flag. The real-daemon runner compares the resulting mapping with `upsc -L`.
Its virtual device produces:

```json
[{"name":"demo","description":"Synthetic demo UPS"}]
```

Use the returned `name` as the input for scenarios 2 and 3. An empty array is a
successful discovery with no devices, not a connection error. Row order is not a
contract. The portable check additionally verifies descriptions containing quotes,
a tab, a backslash and Unicode; a consumer must parse JSON rather than split text.

### 2. Collect a variable snapshot for a diagnostics view

**Task:** inspect the available measurements and status of the selected UPS without
requiring a predefined set of driver-specific properties.

**Operation:** `list_vars("demo")`, or `--vars demo --json`. The real-daemon runner
compares the **whole variable map** with `upsc`, not just the four selected values.
Its output includes objects for `ups.model = "Virtual UPS"`,
`ups.status = "OL CHRG"`, `battery.charge = "100"` and
`battery.runtime = "600"`; extra driver/server variables are allowed.
The portable fixture's exact smaller snapshot is:

```json
[{"name":"ups.status","value":"OL CHRG"},{"name":"battery.charge","value":"100"}]
```

Preserve values as strings and handle missing variables; do not assume all UPS
models expose these keys. The list is one read result, not an atomic historical
snapshot or a time series. Unknown UPS names fail rather than returning an empty
successful snapshot.

### 3. Read one status value for a monitoring sample

**Task:** obtain a small machine-readable sample for an external scheduler without
fetching every variable or adding power-control privileges.

**Operation:** `get_var("demo", "ups.status")`, or
`--get demo ups.status --json`. Both fixtures verify:

```json
{"ups":"demo","name":"ups.status","value":"OL CHRG"}
```

The real-daemon suite compares four scalar reads with `upsc`, and checks failure
for an unknown variable. `OL CHRG` contains multiple status words; retain the
original string and interpret individual flags according to NUT documentation.
The example performs **one sample**, not continuous monitoring, alerting or a
shutdown policy. Parse stdout only after exit status 0; failure text is redacted
and is not successful JSON. Do not turn a failed read into a healthy status.

### Using an authorized deployment instead of a fixture

After the local checks, supply a server you are authorized to query. These
`.invalid` commands are templates, not runnable public test endpoints. Replace
`demo` with an identifier returned by discovery:

```sh
moon run examples/query --target native -- ups.example.invalid 3493 --json
moon run examples/query --target native -- ups.example.invalid 3493 --vars demo --json
moon run examples/query --target native -- ups.example.invalid 3493 --get demo ups.status --json
```

TLS verification is the default. Add `--ca /path/to/ca.pem` for an application-managed
CA. Optional paired credentials come from `MOONNUT_USERNAME` and `MOONNUT_PASSWORD`
through a trusted launcher, never from committed files or command arguments.
Each query owns and closes its connection; no automatic retries or TLS downgrade
occur. Successful reads do not prove credential validity: NUT may allow anonymous
reads after acknowledging an incorrect password. These examples do not verify
physical UPS behavior, real power loss, production policy or all NUT TLS builds.

## 中文

本文是**当前源码版本**的工程示例，不代表 Mooncakes 0.1.0 已包含尚未发布的 CLI
功能。三个场景共用 `examples/query`，分别解决不同使用者任务，并非三种协议模式，
也不是三个实物设备认证。

### 无硬件复现

在仓库根目录、已安装 README 所列 MoonBit native 工具链和依赖的环境中运行：

```sh
moon build --target native
python3 scripts/cli_json_smoke.py
```

此跨平台回环测试调用真正的查询程序，覆盖三种查询、JSON 转义、空列表和拒绝响应。
预期退出码为 0，输出上文所列 `CLI JSON smoke: ... passed (5 cases)`。
它是合成协议服务，不是真实 NUT 守护进程。

要取得独立协议证据，在隔离 Linux 环境中以普通用户运行一次：

```sh
python3 scripts/upsd_integration.py
```

需要已构建的查询程序、Python 3.9+、OpenSSL、NUT 2.8+ 的 `upsd`、`dummy-ups`、
`upsc`；NSS 构建还需 `libnss3-tools`。精确 CI 版本和可选 PyNUT 对照见
[对照文档](comparison.md#中文)。脚本自行分配回环端口、虚拟 UPS、临时证书及配置，
运行后只清理自己的资源，不使用系统服务配置或实物设备。一次运行覆盖三个场景、
`upsc` 对照、TLS 和错误行为；成功日志包含上文的 `PASS: LIST UPS (1 device),
complete LIST VAR` 和 `Synthetic device only: ...`。完整变量数量可随 NUT 版本变化。

### 1. 为监控配置发现 UPS 标识

目标是先列出服务器上的 UPS，保留描述，避免猜测设备名。调用 `list_ups()`，或
查询程序仅加 `--json`。真实守护进程测试与 `upsc -L` 比较，预期得到设备 `demo`、
描述 `Synthetic demo UPS`，JSON 结构见英文场景 1。将返回的 `name` 用于后续查询。
空数组表示查询成功但没有设备，不是连接失败；不要依赖行顺序。跨平台测试还验证了
含引号、制表符、反斜杠和中文的描述，消费者应解析 JSON，不应自行分割文本。

### 2. 为诊断界面收集变量快照

目标是查看所选 UPS 提供的状态和测量值，而非提前假设每种驱动都有固定属性。
调用 `list_vars("demo")`，或 `--vars demo --json`。真实守护进程测试与 `upsc`
比较**完整变量映射**，并核对型号 `Virtual UPS`、状态 `OL CHRG`、电量字符串 `100`
和剩余时间字符串 `600`；允许存在额外的驱动/服务端变量。跨平台测试的精确小型
JSON 结果见英文场景 2。

值保留为字符串，缺失字段应单独处理，不可假设所有 UPS 均提供这些变量。一次列表
结果不是原子的历史快照或时间序列。未知 UPS 应失败，不能伪装成成功的空快照。

### 3. 为监控采样读取单个状态值

目标是为外部调度器取得一条小型、机器可读样本，无需每次拉取全量变量或获得电源
控制权限。调用 `get_var("demo", "ups.status")`，或
`--get demo ups.status --json`。两个测试均核对英文场景 3 所列 JSON，值为 `OL CHRG`。
真实守护进程测试还将四个单值读取与 `upsc` 对照，并检查未知变量失败。

`OL CHRG` 包含多个状态词，应保留原值并按 NUT 文档解释各标记。例子仅执行**一次采样**，
不实现持续监控、告警或关机策略。仅在退出码为 0 后解析 stdout；失败输出已脱敏，
不是成功的 JSON，不要将读取失败转换成健康状态。

### 换成已授权部署

英文部分的三条 `.invalid` 命令是模板，不是可直接连接的公共测试地址。替换为
明确授权的服务器，`demo` 替换为发现结果中的标识。默认验证 TLS；自有 CA 可用
`--ca /path/to/ca.pem`。可选凭据通过可信启动器提供成对环境变量
`MOONNUT_USERNAME`、`MOONNUT_PASSWORD`，不要写入提交文件或命令参数。
每次查询独立连接并关闭，不自动重试或降级。NUT 可能在接受错误密码后仍允许匿名读，
所以读成功不证明凭据有效。上述验证不代表物理 UPS、真实掉电、生产策略或所有
NUT TLS 构建均已通过。
