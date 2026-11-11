# moonnut

[English](README.mbt.md)

面向 **MoonBit native** 的小型 NUT upsd 客户端，独立实现、个人维护、
Apache-2.0 开源，刻意保持只读。库运行时不依赖 NUT 可执行文件或 Python。

GitHub main 包含未发布的演示改进。Mooncakes 由维护者手动发布，已有 0.1.0 版本保持不变。

## 功能与安全边界

- `LIST UPS`、`LIST VAR`、`GET VAR`，返回设备和变量结构。
- `GET UPSDESC`、`GET DESC`、`GET TYPE`，读取描述及原始类型元信息。
- 默认使用 STARTTLS，验证证书链及主机名，可用系统根证书或指定 PEM CA 文件。
- 可选提交 `USERNAME` / `PASSWORD`，只在 TLS 验证成功后发送。
- 每次查询独立连接，不共享协议流，不做连接池、自动重试或 TLS 降级。
- 整个操作的超时、单行长度、响应总字节数、列表行数均有限制。
- 支持 NUT 引号和转义规则，校验响应标识及列表边界。

**不提供** `FSD`、`SET VAR`、`INSTCMD`、`LOGIN`、`PRIMARY`/`MASTER`、关机或
任意命令接口。它不是电源控制代理，也不是完整 RFC 9271 实现。
认证会创建临时服务端会话状态；只查询你有权访问的服务器。

**验证范围：** 覆盖合成回环 NUT/TLS 服务，以及隔离 Ubuntu CI 中真实 NUT 2.8.4
`upsd` + `dummy-ups` 程序与虚拟 UPS。测试将列表、变量值及 UPS 描述与官方 `upsc` 对照，
将选定变量的描述和类型与只读 `upsrw -l` 对照，
并让固定版本 PyNUT 在独立进程中对同一守护进程查询设备/变量列表。
详见[对照范围及复现步骤](docs/comparison.md#中文)与
[CI 结果](https://github.com/pangbit/moonnut/actions/workflows/ci.yml)。未验证物理 UPS 或生产部署；
真实守护进程测试还覆盖验证 STARTTLS 后提交凭据、服务端对错误密码的行为、未知证书及错误主机名，
采用当前安装的 NUT TLS 后端。CI 日志注明具体后端，不代表所有 NUT TLS 构建或硬件认证。

## 快速开始

依赖 MoonBit native 和 `moonbitlang/async` 0.22.4。本地已验证 macOS arm64、
`moon` 0.1.20261104 / `moonc` v0.10.20+65efd5b93。
网络与 TLS 使用官方 [async 库](https://github.com/moonbitlang/async)，需满足其
原生平台/OpenSSL 依赖。原生测试与回环 TLS 检查也已在 Ubuntu GitHub Actions 通过。

```sh
# 离线示例，不连接设备
moon run examples/parse --target native
```

执行 `moon add pangbit/moonnut` 安装，也可使用检出源码或本地 workspace 依赖。在 `moon.pkg` 导入 `pangbit/moonnut`。含 `async fn main` 的包
还需导入 `moonbitlang/async`。

原生异步应用中创建 `Client::new("ups.example.invalid")`，然后调用
`list_ups()`、`list_vars("demo")`、`get_var("demo", "ups.status")`。
变量值保留为字符串，例如 `OL CHRG` 不能当成单一枚举值。
每次操作独立建立连接，可选在验证过的 TLS 中提交凭据，然后关闭连接，失败也会关闭。

```sh
# 仅针对已授权且明确指定的服务器
moon run examples/query --target native -- ups.example.invalid 3493
moon run examples/query --target native -- ups.example.invalid 3493 --ca /path/to/ca.pem
```

查询示例从进程环境读取可选 `MOONNUT_USERNAME`、`MOONNUT_PASSWORD`，不会输出凭据或
原始错误。不要把真实凭据写进命令、源码、示例、问题单或 Git；实际应用应使用适合其
部署环境的凭据提供方式。

三个完整使用场景、回环复现命令及预期结果见[只读使用场景](docs/scenarios.md#中文)。
元信息查询与离线多标记状态解释示例见[描述、类型与状态](docs/metadata.md#中文)。

## 三分钟演示

1. 运行 `moon run examples/parse --target native`，离线解析包含多个状态词的响应，
   不打开网络连接。
2. 在已安装 NUT 2.8+（`nut-server`、`nut-client`）的隔离 Linux 开发环境中运行：

   ```sh
   moon build --target native
   python3 scripts/upsd_integration.py
   ```

   脚本使用临时配置启动真实 NUT `upsd` 与 `dummy-ups` 程序，创建合成设备，
   仅绑定回环地址；将 moonnut 的 `LIST UPS`、`LIST VAR`、`GET VAR` 与官方 `upsc`
   对照，并使用 `upsc -L`、只读 `upsrw -l` 核对描述和类型元信息。
   结束后只停止自己创建的子进程并清理临时文件，不使用系统 NUT 配置、
   服务管理器、物理设备或长期账号。它同时验证匿名回环明文与使用临时只读账号的
   STARTTLS，观察服务端对错误密码的行为，并拒绝未知 CA 及错误主机名。需要 OpenSSL；NSS 后端构建
   还需 `libnss3-tools`。密钥和账号均为临时测试产物。
3. 运行 `python3 scripts/tls_smoke.py`，演示接受可信 TLS，以及在发送凭据前
   拒绝未知证书与错误主机名。

查询示例也提供针对已授权目标的变量操作：

```sh
moon run examples/query --target native -- ups.example.invalid 3493 --vars demo
moon run examples/query --target native -- ups.example.invalid 3493 --get demo ups.status
```

监控程序可为任意查询增加 `--json`：设备/变量列表输出带字段名的对象数组，
单变量读取输出 UPS、变量名和字符串值。标准 JSON 序列化器负责引号、反斜杠、
制表符和 Unicode 的编码；看起来像数字的值也仍是字符串。
只有退出码为零时才解析标准输出；失败时输出脱敏文本并返回非零退出码，
不伪装成成功的 JSON 数据。

```sh
moon run examples/query --target native -- ups.example.invalid 3493 --get demo ups.status --json
```

```json
{"ups":"demo","name":"ups.status","value":"OL CHRG"}
```

## API 约定

`Client::new` 参数：

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `port` | `3493` | TCP 端口 |
| `security` | `Tls` | 系统根证书；`TlsCaFile(path)` 使用自定义 CA |
| `username`、`password` | 无 | 成对提供，仅允许 TLS |
| `timeout_ms` | `5000` | 从 DNS 到完整响应的总超时 |
| `max_line_bytes` | `65536` | 一行 LF 分隔符之前的最大字节数 |
| `max_response_bytes` | `4194304` | 含认证响应的协议总接收字节数 |
| `max_rows` | `4096` | 列表最大行数 |

`Plaintext` 必须显式指定，且禁止携带凭据。明文既无保密性也无服务端认证，
仅用于受控测试或另有安全保障的通道。没有跳过证书验证的设置；STARTTLS 被拒绝时
绝不会回退到明文。TLS 最低版本与算法策略继承底层 TLS 库，当前 moonnut
不额外强制 TLS 1.2/1.3 最低版本。

`NutError` 区分非法参数、错误响应格式、规范的服务端错误码、资源超限和提前 EOF。
网络、TLS、超时错误保留 `moonbitlang/async` 错误。失败后由应用决定是否及何时重试。
`Client` 不公开内部字段，也没有携带凭据的调试输出；不保证秘密内存被安全清零。

## 协议差异与对照项目

- [RFC 9271](https://www.rfc-editor.org/rfc/rfc9271)：信息类 UPS 协议描述。
- [NUT 网络协议文档](https://networkupstools.org/docs/developer-guide.chunked/net-protocol.html)：
  实际 `upsd` 行为及与 RFC 的差异。
- [Network UPS Tools](https://github.com/networkupstools/nut) 与
  [PyNUT v2.8.3](https://github.com/networkupstools/nut/blob/v2.8.3/scripts/python/module/PyNUT.py.in)：
  参考项目，不是嵌入式依赖。

RFC 9271 描述强制认证，但历史 NUT 部署允许匿名只读查询。moonnut 允许匿名查询，
遵守 `ERR ACCESS-DENIED`，不宣称符合 RFC 的全部安全要求。
不依赖 `PROTVER`、`PRIMARY` 等新别名。

**凭据接收确认不是认证证明。** NUT 的 `PASSWORD` 命令只是保存密码，供后续需要授权
的命令使用。服务端可能对错误密码返回 `OK`，随后仍允许匿名只读查询，NUT 2.8.4
实测即为如此。moonnut 会传播服务端明确返回的拒绝，但读取成功不证明密码正确。
不会为探测密码而使用 `LOGIN`，因为 NUT 将该命令用于供电设备消费者与 upsmon 协调。

NUT 使用 parseconf 风格，不是 JSON 或 shell：反斜杠转义下一个字符，双引号分组，
单引号不分组；未加引号的 `=` 独立成词，`#` 开始注释。编码器也会转义 `#`，
兼容旧解析器。接受 LF 和 CRLF，不支持物理换行续行。接受 UTF-8 描述作为对文档
所述 ASCII 协议的扩展；拒绝非法 UTF-8 与控制字符。

本项目为原创 MoonBit 实现，不是 PyNUT 移植。PyNUT 使用 GPL-3.0-or-later，
本仓库不复制、不内嵌、不链接其源码。独立进程仅调用其公共 API，CI 下载固定提交、
SHA-256 验证的模块至检出目录之外。真实守护进程对照覆盖设备/变量列表及未知 UPS
失败；PyNUT 没有直接 `GET VAR` 或 STARTTLS API，标为“不提供”而非“测试失败”。
原有可选 `reference_smoke.py` 仅比较合成 `LIST UPS` 场景；两种对照均不代表完整解析器等价。

## 开发与验证

```sh
moon update
moon check --target native
moon test --target native
moon build --target native
python3 scripts/tls_smoke.py
python3 scripts/cli_json_smoke.py
# 在已安装 NUT 2.8+ 的隔离 Linux 环境中
python3 scripts/upsd_integration.py
moon info --target native
moon fmt --check
# 可选：官方 PyNUT v2.8.3 模块须放在本仓库之外
python3 scripts/reference_smoke.py /external/path/PyNUT.py
# 隔离 Linux 上，使用固定模块与 upsc 对照同一真实守护进程
python3 scripts/upsd_integration.py --pynut /external/path/PyNUT.py
```

MoonBit 测试覆盖解析、命令注入防护、分片/合并响应、错误处理、标识匹配、空列表、
EOF、TLS 拒绝、超时与资源上限。生命周期测试确认超时或取消后服务端收到 EOF、
后续查询正常，以及并发查询响应相互隔离。TLS 脚本生成临时回环证书，验证可信 CA、加密提交凭据、服务端凭据拒绝、
未知 CA 和错误主机名。测试不需要真实 UPS、账号或长期凭据。注册表发布是维护者另行手动执行的步骤，
不属于上述检查或 CI。
另见 [贡献指南](CONTRIBUTING.md)、[安全说明](SECURITY.md)、[许可证](LICENSE)。
