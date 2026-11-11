# Changelog / 更新记录

## Unreleased / 未发布

- Add explicit persistent Session connections with all 17 existing reads,
  independent credential submission, tracking, LOGIN/LOGOUT and encryption state.
  Preserve fresh connections for Client reads; serialize session requests and
  close incomplete/cancelled streams without automatic replay.
- Add focused lifecycle tests and a loopback-only 44-outcome comparison with
  official libupsclient using a disposable LOGIN-only account. No UPS writes or
  power commands are added; real operation-tracking outcomes remain unverified.
- 新增显式持久会话，复用 17 项读取，并提供独立凭据、tracking、LOGIN/LOGOUT 及连接状态。
  Client 读取仍用独立连接；会话串行执行，未完整读取或取消后关闭，不自动重放。
- 新增必要生命周期测试及官方 C 库 44 项回环对照，账号仅有 LOGIN 权限；没有新增 UPS
  写入/电源命令，真实操作 tracking 结果仍待后续隔离验收。默认明文回退风险保持明确说明。

- Confirm the complete NUT client target and pin NUT 2.8.4; add a staged plan and
  acceptance matrix retaining all remaining client gaps. Servers and UPS drivers
  are outside the approved implementation scope.
- Follow official CLI transport defaults: try unverified TLS, permit plaintext
  credentials after STARTTLS refusal, and fail on handshake errors. Keep explicit
  verified/required TLS modes. Use separate 10-second connect and 5-second read
  defaults, with an optional overall deadline; other timing differences remain open.
- Add NUMLOGINS, CLIENT, VER, NETVER, PROTVER and HELP reads, raw banners, and
  ASCII-insensitive echoed identifiers. Compare with official libupsclient,
  upsc and PyNUT in isolated CI; existing discovery comparisons continue passing.
- 确认完整客户端目标，固定 NUT 2.8.4，新增阶段计划及逐项验收矩阵；服务端和 UPS
  驱动实现范围外，客户端剩余缺口继续保留，未宣称完整一致。
- 默认按官方 CLI 尝试不验证证书的 TLS，STARTTLS 拒绝后允许明文凭据，握手失败终止；
  保留显式强制/验证 TLS。默认连接 10 秒、每次读取 5 秒，总截止可选；其他计时差异仍待验。
- 新增六项服务信息读取，保留原始文本，响应标识按 ASCII 忽略大小写；隔离 CI 与
  官方 C 库、upsc、PyNUT 对照通过，既有发现能力对照继续通过。

- Add read-only RW/ENUM/RANGE and command discovery, preserving every range as
  string endpoints and validating each command's exact row shape.
- Add five CLI/JSON operations, bilingual examples and bounded malformed-response
  coverage; compare real upsd discovery with list-only upsrw/upscmd. ENUM/RANGE
  use synthetic driver state because dummy-ups does not provide these metadata.
- 新增只读 RW/ENUM/RANGE 与命令发现，保留多个独立区间的字符串端点并严格校验各命令行格式。
- 增加五种 CLI/JSON 操作、双语示例与畸形响应测试，使用官方 upsrw/upscmd 只读模式对照
  真实 upsd；ENUM/RANGE 由合成驱动状态提供，不冒充 dummy-ups 或实物覆盖。

- Add read-only UPS/variable descriptions and raw multi-token type metadata,
  query CLI options, and an offline exact-token UPS status example.
- Compare metadata with official upsc/upsrw in list-only mode on a virtual UPS;
  cover malformed replies, omitted/unknown types and JSON output.
- 新增只读 UPS/变量描述、保留多项标记的类型元信息、查询参数及精确匹配状态的离线示例。
- 在虚拟 UPS 上使用官方 upsc/upsrw 只读模式对照元信息，验证畸形响应、
  省略/未知类型及 JSON 输出。

- Compare pinned PyNUT and upsc with moonnut on one isolated dummy-ups daemon,
  including full variable lists, direct single reads and failed queries.
- 使用固定版本 PyNUT、upsc 与 moonnut 对照同一隔离 dummy-ups 守护进程，
  覆盖完整变量列表、直接单值读取及查询失败；明确不提供的能力。

- Clarify deferred NUT credential validation and verify explicit server rejection over TLS.
- 澄清 NUT 延迟验证凭据的语义，验证 TLS 内服务端明确拒绝时客户端停止。

- Add machine-readable JSON query output with UTF-8 and escaping regression checks.
- 新增机器可读 JSON 查询输出，并验证 UTF-8、转义与错误退出行为。

- Verify socket closure after cancellation/timeouts and concurrent response isolation.
- 验证取消/超时后的连接关闭，以及并发查询响应隔离。

- Exercise actual NUT STARTTLS credential exchange and certificate rejection paths.
- 增加真实 NUT STARTTLS 凭据交换与证书拒绝路径验证。

- Add an isolated NUT upsd + dummy-ups interoperability demo and CI check.
- Extend the query example with variable listing and single-variable reads.
- 新增隔离 NUT upsd + dummy-ups 互操作演示与 CI 检查。
- 查询示例新增变量列表和单变量读取。

## 0.1.0 (2026-11-10)

- Initial native read-only NUT client: LIST UPS, LIST VAR and GET VAR.
- Verified STARTTLS, optional TLS-only authentication, bounded responses and timeouts.
- Bilingual documentation, offline/query examples, loopback and optional reference tests.
- 首个原生只读 NUT 客户端，支持设备列表、变量列表和变量查询。
- 验证 STARTTLS、仅 TLS 认证、响应资源限制和超时。
- 中英文文档、离线/查询示例、回环测试与可选参考实现对照。
