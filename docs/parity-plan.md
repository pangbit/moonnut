# NUT client parity plan / NUT 客户端一致性计划

Status: **Client scope confirmed; implementation in progress.**
状态：**用户已确认仅对齐客户端能力；继续实现和对照。当前尚未达到完整一致。**

## Goal and decisions / 目标与已确认决定

moonnut 的目标是覆盖 NUT 客户端能力，并与固定参考的功能、默认值及可观察行为一致。当前提供 17 种基础读取、显式会话与五项控制请求，不是完整客户端。已有测试通过只证明对应场景，不能称为无缺失、无差异。

- 用户确认「只对齐客户端能力」。实现目标包括客户端协议、库能力、查询/管理 CLI，以及客户端监控功能。**不实现 upsd、UPS 驱动或驱动服务管理器**；它们仅作为隔离参考和夹具。
- 用户选择「默认行为也与官方 CLI 完全一致」。默认传输按 NUT 2.8.4 的 `TRYSSL`：尝试不验证证书的 TLS；STARTTLS 被拒绝时继续同连接明文；握手/IO 失败则终止。凭据允许明文发送。验证证书与强制 TLS 仍作为显式选项。
- 已授权继续可独立推进的客户端实现及对照；不再将普通客户端开发列为待批准。涉及实质性的语义或安全冲突时，提交具体证据和建议供用户裁决。
- 不对真实设备执行控制，不触发宿主机关机，不发布 Mooncakes。版本发布由用户亲自决定。

English: The approved target is full NUT **client** functionality and observable behavior, including official CLI defaults. Server and UPS-driver implementations are excluded by the user's scope decision. Client development and isolated comparisons may continue. Real-device control and publication remain prohibited. No complete-parity claim is made.

## Pinned reference / 固定参考

| Item / 项目 | Reference / 固定值 |
| --- | --- |
| NUT source | `v2.8.4` → **`541c2ecf0b2ec33dadb9f40b16acbe39042bd103`**；不是“最新版”声明 |
| Protocol | `1.3`；按实际命令 handler 盘点，HELP 不是完整能力列表 |
| Runtime reference | Ubuntu 26.04；`nut-server`、`nut-client`、`libupsclient7`、`libupsclient-dev`、`libnutscan4` = `2.8.4+really-2`；NSS 构建 |
| Client references | `upsc`、`upsrw`、`upscmd`、`libupsclient`、`libnutclient`、PyNUT；监控客户端逐阶段展开 |
| PyNUT | 固定 NUT 提交中的模块 1.8.0；SHA-256 `a12d1e40f8cd926314157c137372628322dd09db94d697aca4bc9dc8beb64f82`；与原 v2.8.3 参考文件逐字节相同 |
| moonnut audit start | `709b5deb77afb33fbee940d2f5fa8e9a2bb1427c`；当时为 11 种业务读取，默认验证 TLS |
| Toolchain | `moonc 0.10.20+65efd5b93`、async `0.22.4`、native |
| Current control evidence | [CI 42988803694](https://github.com/pangbit/moonnut/actions/runs/42988803694)；代码 `0e5413fe7f4ac2090c27fb491525e08279223105`：48 项原生、52 项控制结果、15 条驱动请求、8 个 tracking ID、三次官方 CLI；既有读取/会话/TLS/JSON 回归通过 |
| Previous session evidence | [CI 42984926159](https://github.com/pangbit/moonnut/actions/runs/42984926159)；代码 `c2527e0457a2905c610661fde1b5e341c9c95b3a`：45 个原生测试、既有 TLS/JSON/真实 upsd 对照及会话 44 项结果 × 3 种传输配置全部通过 |
| Previous read evidence | [CI 42981570296](https://github.com/pangbit/moonnut/actions/runs/42981570296)；代码 `79c962ad323f33d7f0bf1027040ca8f34b830e4b`：38 个原生测试、20 个 JSON、10 个本库 TLS、4 个官方 upsc 传输对照场景及真实 upsd 读取对照全部通过 |
| Previous evidence | [CI 42973210924](https://github.com/pangbit/moonnut/actions/runs/42973210924)：34 个原生测试、14 个 JSON 用例、5 个 TLS 用例及真实 upsd 虚拟设备的选定对照 |

CI 记录包版本、架构、官方 CLI 二进制 SHA-256 和动态库/TLS 后端。发行包可能带补丁，源码标签与发行构建分别记录。后续更换参考版本/构建需列出差异并重新对照，不能静默升级。Mac arm64 仅有 moonnut 本地验证，不冒充官方 NSS/Linux 全部平台对照。

## Scope / 客户端边界

| Layer / 层次 | Scope / 范围 | Current gap / 当前缺口 |
| --- | --- | --- |
| Network client library | 所有 N01–N30 请求、响应/错误/状态机、传输；C/C++/PyNUT 业务能力的 MoonBit 映射 | 持久会话、tracking 与控制协议已推进；库便捷映射、低层 API 等仍有缺口 |
| Official client CLIs | upsc、upsrw、upscmd 的参数、默认、交互、输出/退出状态、等待语义 | `examples/query` 仍是演示，不是三个程序的替代品 |
| Monitoring clients | upsmon、upslog、upssched、GUI/CGI 客户端功能，X09–X11/X14 | 未实现；逐程序/配置项继续展开，不能因当前为库而删除 |
| Adjacent tools | X12/X13/X15 保留客户端相关扫描、配置及平台接入；非客户端后端按角色区分 | 需逐项映射；USB/物理驱动与服务端安装不纳入产品实现 |
| Server/drivers | X01–X08 | 用户确认范围外；官方 upsd、dummy-ups、合成 socket 状态仅用于测试 |

NUT 链路：设备 ↔ 驱动 ↔ 驱动 socket 协议 ↔ upsd ↔ **TCP 客户端协议** ↔ 客户端。客户端不实现 `SETINFO`、`ADDRANGE` 等驱动消息；测试脚本使用它们构造静态或内存状态。客户端验收可在隔离参考服务和虚拟设备上进行，不声称验证真实电源效果。

## Stages / 分阶段工作

| Stage / 阶段 | Deliverable / 交付内容 | Acceptance / 完成条件 |
| --- | --- | --- |
| P0 — 固定与盘点 | 本计划、[逐项矩阵](parity-matrix.md)、源码/构建证据、用户决定 | 每项有归属和当前状态；未解决差异明确保留 |
| P1 — 现有读取对照 | N01–N11、B01/B02/B10，复用现有 upsd/CLI 夹具 | 真实空值、错误、大小写、独立 RANGE、完整命令列表逐项有证据 |
| P2 — 缺失读取与连接基础 | N12–N17；TLS 默认、地址解析、超时/错误、只读库映射与 CLI 基础 | 所有只读能力有实现与直接参考对照；未完成边界不可标通过 |
| P3 — 持久会话与 tracking | N18–N21、N24–N27；最小会话连接/关闭、身份和连接内状态 | 隔离回环验证多请求、登录计数、开关、注销、取消/断线；无自动重试 |
| P4 — 客户端写入与控制 | N22/N23/N28–N30；参数、权限、结果跟踪、失败顺序、管理 CLI | 仅一次性合成驱动和替身动作；拒绝不触发动作、ACK 不冒充完成、断线不重复控制 |
| P5 — 其余客户端能力 | C/L 未完成行、监控/日志/调度、客户端平台集成 | 逐选项/配置/状态验收；系统权限动作使用替身或隔离镜像 |
| P6 — 总体验收 | 固定参考 → 实现 → 同输入差分 → 平台证据 | 确认范围内没有未解决缺失/差异/跳过项，才可声称完整一致；发布由用户决定 |

前一批次落实 P1/P2 的可独立部分：六项读取、TLS 默认、明文凭据、大小写响应匹配；默认连接 10 秒、每次传输读取 5 秒，整体截止时间改为显式选项。真实上游超时还涉及地址重试、DNS、TLS 后端和环境覆盖，B07/B12 **仍未关闭**。行/行数/总字节上限、UTF-8 策略与严格列表结束标识也仍是待对照差异。

前批次 P3 采用显式 Session 承载 tracking/LOGIN：复用全部读取、独立凭据、注销/关闭、串行化与取消清理；增加仅 LOGIN 权限账号，与官方 C 库对照 44 项结果。真实有效 tracking ID 生命周期由本批 P4 独立内存夹具推进。P4 仅在隔离环境实现和验收。既有一次查询一连接的 API 可继续使用，但不能伪装为具有连接内状态的客户端。无需为本批次提前建设通用模拟框架。

## Conflicts and remaining decisions / 冲突及后续裁决

| ID | Evidence / 事实 | Treatment / 处理建议或决定 |
| --- | --- | --- |
| D01 | CLI/监控能力、控制便捷映射及部分会话边界尚缺 | 保留 M 状态，按 P3–P5 继续；不能以本批次完成宣称客户端完整 |
| D02 | 安全默认与官方 TRYSSL 不同 | **用户已裁决官方默认优先**；前批次已改为 TryTls；显式 Tls/TlsCaFile 仍验证证书 |
| D03 | C/C++/PyNUT 默认、容器和错误不完全相同 | 默认使用官方 C CLI profile；各库业务能力逐项映射；发生互斥语义时列出双方结果，不能同时声称完全等同 |
| D04 | C ABI、C++ 对象与 MoonBit API 不同 | 当前推进 MoonBit 业务语义映射；ABI/源码可替换尚无证据，不冒充等价；如用户需要二进制替换需单列产物 |
| D05 | query 演示的参数、脱敏 stdout 错误和 JSON 与官方 CLI 不同 | C01–C14 保留；后续提供相应 CLI 行为。产品版本/帮助身份应明确标识 moonnut，是否要求字面替换需在该阶段裁决 |
| D06 | PyNUT debug 可打印密码 | 建议业务/协议兼容而不输出秘密；尚未实现相应 debug 模式，若精确日志兼容成为要求再交用户裁决 |
| D07 | 2.8.4 upsd 对无 ENUM/RANGE 的已知变量返回空表；描述可为 Description unavailable；RANGE 为整数 | 本批次加真实 upsd 断言；合成错误传播/分数输入不能当成官方正常行为 |
| D08 | 官方库会接受部分 moonnut 拒绝的边界；各 TLS 后端超时不同 | 边界分别记录；未直接对照的差异保留，不把“更严格”自动当成符合 |
| D09 | 目前官方直接对照主要为 Linux NSS；无 Windows/Solaris 等执行环境 | 保留平台未验状态，先完成已有平台；不得声称跨平台完整一致 |

固定源码入口：[命令表](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netcmds.h)、[GET](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netget.c)、[LIST](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netlist.c)、[C 客户端](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/upsclient.c)。

## Evidence rules / 验收规则

每条记录关联矩阵 ID、参考 profile、前置状态/输入、参考结果、moonnut 结果、差异、证据位置和结论。只读读同一静态服务；有状态操作使用等价初始状态的隔离夹具。原始输出/顺序/错误不擅自归一化；现有按 map/set 比较的用例只证明其已声明的值或集合语义，不证明顺序相同。

源码核对、自测、直接官方差分、真实 upsd 虚拟设备对照分别标明。缺能力、缺环境或测试未执行都不是通过。复用现有脚本，仅针对已列需求和确定性差距增加测试，避免泛化框架和无差别参数组合。

English: Current progress adds six read operations, CLI-compatible TLS negotiation, plaintext credential support, ASCII-insensitive echoed identifiers, and separate connection/read defaults. This does not close session, control, CLI replacement, parser limits, all timeout behavior, other client-library semantics, or monitoring/platform gaps. The matrix keeps these explicit. Compare equivalent states against pinned clients; retain raw evidence and distinguish synthetic tests from real-upsd differential tests. All control testing must remain disposable and isolated.

English session progress: explicit connect/with_session, shared read methods, credential commands, tracking, LOGIN/LOGOUT and cancellation-safe serialization are implemented. The isolated session comparison adds 44 outcomes using official libupsclient; it does not exercise any UPS write or power action. Valid operation IDs are covered by P4 below; C++ empty-ID semantics, automatic reconnect and remaining CLI/platform behaviors stay open.

## Current P4 subset / 当前 P4 子集

五项 Session 控制 API 已实现；本地 48 项原生测试通过。新增独立内存驱动、固定回环
MoonBit/C 探针及官方 upsrw/upscmd 等待对照，Linux 官方对照已通过，实际结果与限制见[控制文档](controls.md)。
检查 52 项可观察结果、15 条驱动请求及 8 个真实生成的 tracking ID；UUID 单独声明归一化。
ACK 与实际应用分开，Pending 通过人工 release 转为 Success，FSD 不接触真实设备或监控程序。
这仍不是 P4 整体完成；管理 CLI、C++ fallback/多值/便捷等待、参数边界和平台证据继续保留。

English: The current P4 subset adds five explicit Session control methods and
three focused native tests (48 total). A separate disposable in-memory driver
supports official-library/CLI comparisons with equivalent fresh server state,
real upsd tracking IDs and raw driver evidence. See controls.md for execution
status. CLI replacement, convenience/library mappings and other matrix gaps
remain open. Neither simulated completion nor passing selected traces proves
physical effects or full client parity. No real UPS control or publication.
