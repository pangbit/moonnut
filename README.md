# moonnut

**[English documentation](README.mbt.md) · [简体中文文档](README.zh-CN.md)**

A NUT upsd client for **MoonBit native**, independently implemented and licensed
under Apache-2.0. It provides read queries, capability discovery, persistent
sessions, explicit client control requests, and native `upsc`, `upsrw` and
`upscmd` command-line tools. The library needs no NUT executable or Python runtime.

面向 **MoonBit native** 的 NUT upsd 客户端，独立实现，采用 Apache-2.0 许可证。
提供读取、能力发现、持久会话、显式客户端控制，以及原生 `upsc`、`upsrw`、`upscmd`
命令行工具；库运行时不依赖 NUT 可执行程序或 Python。

| Documentation / 文档 | Contents / 内容 |
| --- | --- |
| [English guide](README.mbt.md) / [中文指南](README.zh-CN.md) | Installation, API examples and checks / 安装、API 示例与检查 |
| [Query CLI / 查询 CLI](docs/query-cli.md) | `upsc` usage and verified comparison scope / 用法与实测对照范围 |
| [Management CLIs / 管理 CLI](docs/admin-cli.md) | `upsrw`, `upscmd`, prompts and tracking / 提示与执行结果追踪 |
| [Parity plan / 一致性计划](docs/parity-plan.md) · [Acceptance matrix / 验收矩阵](docs/parity-matrix.md) | Fixed NUT reference, evidence and remaining gaps / 固定参考、证据与剩余差距 |
| [Security / 安全](SECURITY.md) · [Changelog / 更新记录](CHANGELOG.md) | Transport defaults, control semantics and unreleased changes / 传输默认值、控制语义与未发布改动 |

Full NUT **client** parity is the goal and remains in progress; server and UPS-driver
implementations are outside scope. Default transport follows the official CLI:
unverified TLS, with plaintext fallback on STARTTLS refusal. Use explicit verified
TLS when required. Controls can affect devices; validation uses isolated simulations.
See [CI results](https://github.com/pangbit/moonnut/actions/workflows/ci.yml).

目标是完整对齐 NUT **客户端**，当前仍在开发，不实现服务端或 UPS 驱动。
默认按官方 CLI 尝试不验证证书的 TLS，STARTTLS 被拒绝时允许明文；需要验证时显式选择
验证 TLS。控制请求可影响设备，测试仅使用隔离模拟环境。

GitHub `main` contains unreleased work. Mooncakes publication is controlled manually
by the maintainer. GitHub 主分支包含未发布改动，Mooncakes 由维护者亲自控制发布。
