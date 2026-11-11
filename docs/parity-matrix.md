# NUT parity acceptance matrix / NUT 一致性逐项验收矩阵

**Client scope confirmed / 客户端范围已确认。** 固定基线、用户决定与阶段见 [parity-plan.md](parity-plan.md)。客户端实现和隔离对照继续进行；服务器/UPS 驱动实现范围外。

NUT 固定源码：`541c2ecf0b2ec33dadb9f40b16acbe39042bd103` (2.8.4)。moonnut 审计起点：`709b5deb77afb33fbee940d2f5fa8e9a2bb1427c`；前批次新增 6 项读取及默认传输兼容；本批次补充显式持久会话、凭据、tracking 和 LOGIN/LOGOUT。

状态：**E** = 已实现且有选定场景证据，仍待完整验收；**M** = 缺失；**D** = 已知设计/接口差异；**U** = 未直接对照；**S** = 客户端相关部分待展开；**O** = 用户已确认范围外。`E` 不等于整行已通过。来源为文件级固定源码，最终用例须进一步记录行号/分支及运行证据。

## Network commands / 网络命令

N01–N30 覆盖固定版本顶层命令及 GET/LIST/SET 分支；GET TRACKING 两种形式单列，别名分别列。INSTCMD 的无参数/有参数形式归于同一行。依据 [netcmds.h][cmds]、[netget.c][get]、[netlist.c][list]、[netset.c][set]、[netuser.c][user]、[netmisc.c][misc]、[netinstcmd.c][inst]。这是客户端协议，不能与驱动 socket 协议混为一项。

| ID | 能力 / Request | 当前状态与证据边界 | 逐项验收内容 / Required evidence | 阶段 |
| --- | --- | --- | --- | --- |
| N01 | LIST UPS | E；现有 upsc -L / PyNUT 对照两个虚拟设备 | 无设备、多设备、顺序、描述缺失/转义；全部字段和结束标记 | P1 |
| N02 | LIST VAR | E；18 项虚拟变量表对照 | 完整值与顺序、空表、未知 UPS、驱动断开/陈旧、FSD 状态修饰 | P1；FSD 场景 P4 |
| N03 | GET VAR | E；4 个直接值与 upsc 对照 | 常规值、空/多词/数字字符串、未知变量/UPS；server.info/server.version 特殊路径、大小写、FSD | P1；FSD 场景 P4 |
| N04 | GET UPSDESC | E；有描述场景 | 无 desc 时的占位文本、未知 UPS、与 LIST UPS 的不同占位行为 | P1 |
| N05 | GET DESC | E；选定字符串/数字变量 | 已知/未定义描述、upstream. 前缀、未知变量名不等同必然错误、UPS 不可用 | P1 |
| N06 | GET TYPE | E；STRING/NUMBER/ENUM/RANGE 夹具 | 所有实际类型组合与顺序、无显式标记、STRING 长度、未知变量/UPS | P1 |
| N07 | LIST RW | E；虚拟变量名/当前值 | 无 RW、完整集合/值/顺序、错误；不等于该用户有 SET 权限 | P1 |
| N08 | LIST ENUM | E；两个选项 | 当前值另取、无枚举为空列表、空/转义选项、顺序/重复、未知变量/UPS | P1 |
| N09 | LIST RANGE | E；90..100 与 102..105 | 全部独立区间、边界/顺序、无范围为空、真实整数格式；合成小数另标扩展 | P1 |
| N10 | LIST CMD | E；两个设备命令表 | 空表、完整集合/顺序、未知 UPS、驱动不可用；任何命令名均不执行 | P1 |
| N11 | GET CMDDESC | E；已列命令描述 | 未定义/未列命令的实际占位文本、upstream.、未知 UPS；不假设必然 CMD-NOT-SUPPORTED | P1 |
| N12 | GET NUMLOGINS | E/U；新增真实 upsd 0→1→2→1→0 LOGIN 计数对照脚本；待本批 CI | 零计数、未知/不可用 UPS；登录/断开后的计数生命周期后续补验 | P2/P3 |
| N13 | LIST CLIENT | E/U；新增两个 LOGIN 客户端及重复 IPv4 地址对照；IPv6 实际会话仍未验 | 空列表、IPv4/IPv6 地址、多个 LOGIN 客户端、同地址重复、未知 UPS | P2/P3 |
| N14 | VER | E/U；VER 原文与 libupsclient/PyNUT 一致；[CI 42981570296][current-ci] | 原始版本/构建文本，带多余参数错误；区别本机客户端版本 | P2 |
| N15 | NETVER | E/U；NETVER 与 libupsclient 一致；[CI 42981570296][current-ci] | 协议版本响应、参数错误 | P2 |
| N16 | PROTVER | E/U；PROTVER 与 libupsclient 一致；[CI 42981570296][current-ci] | 与 NETVER 别名行为逐项比较；旧版本 fallback 只有另纳版本才验收 | P2 |
| N17 | HELP | E/U；HELP 原文与 libupsclient/PyNUT 一致；[CI 42981570296][current-ci] | 精确响应；不得将 HELP 未显示的命令认定不支持 | P2 |
| N18 | STARTTLS | E/U；默认 TRYSSL，显式验证/强制 TLS；脚本对照 upsc | 支持/拒绝/无 TLS 构建/重复升级、握手边界、信任与主机名；默认与可选 profile 分开 | P1/P3 |
| N19 | USERNAME | E/U；独立/自动提交、重复拒绝、先密码后用户名；新增官方对照 | 缺失/空/重复、与 PASSWORD 顺序、应答不代表权限有效、会话独立性 | P3 |
| N20 | PASSWORD | E/U；独立提交、重复拒绝、错误密码延迟验证；新增官方对照 | 重复/错误值、延迟验证、明确拒绝；不能用匿名读取成功证明认证成功 | P3 |
| N21 | SET TRACKING ON/OFF | E/U；SET 分派要求先提交两项凭据；开关/重复/跨连接独立性已有实现与对照脚本 | 连接内开关、凭据前置、重复开关、断开清理、支持/不支持构建 | P3 |
| N22 | SET VAR | M | RW/只读/长度/枚举/范围/数值解析、权限、驱动失败、无跟踪 OK 与实际完成区别 | P4 |
| N23 | INSTCMD [parameter] | M | 有/无/空/转义参数、命令名及大小写、未知命令与拒绝顺序、驱动失败、跟踪结果 | P4 |
| N24 | GET TRACKING | E/U；同连接 ON/OFF、新连接 OFF，新增官方对照 | 同一连接 ON/OFF，重连后的状态 | P3 |
| N25 | GET TRACKING id | E/U；返回五种 TrackingStatus，其他协议错误仍抛出；真实未知 ID/未配置对照，实际操作生命周期仍待 P4 | 有效 ID、未开 tracking、未知/过期 ID、pending/success/各失败；不可用普通 fresh-query 代替会话 | P3；实际操作结果 P4 |
| N26 | LOGOUT | E/U；显式 LOGOUT 校验 Goodbye 并关闭；LOGIN 清理对照，close 为本地关闭 | Goodbye、服务端关闭、LOGIN/tracking 清理、重复使用已关闭会话 | P3 |
| N27 | LOGIN ups | E/U；缺凭据、未知 UPS、正确/错误密码、重复、两个消费者及注销计数；新增官方对照 | 缺凭据/拒绝/成功/重复/未知 UPS、NUMLOGINS 与 CLIENT 联动；属于状态操作 | P3 |
| N28 | PRIMARY ups | M | 权限检查、成功文本、拒绝/未知 UPS；别名 fallback 按选定客户端行为 | P4 |
| N29 | MASTER ups | M | 与 PRIMARY 对应权限及不同成功文本；兼容别名仍属于验收范围 | P4 |
| N30 | FSD ups | M | 仅一次性模拟服务中权限、状态标记、重复调用、断开/重启行为；无宿主机关机动作 | P4 |

## Observable behavior / 横向行为

| ID | 对照维度 | 当前状态 | 必需验收内容 | 阶段/来源 |
| --- | --- | --- | --- | --- |
| B01 | 分词/编码/转义 | E/U/D | 与 parseconf、各客户端编码器比较引号、反斜线、#、=、空串、制表符、非 ASCII、非法字节；明确哪些差异由目标决定 | P1；[parseconf][parse] |
| B02 | 大小写、行结束与形状 | E/U/D；响应标识已按 ASCII 忽略大小写 | 命令/UPS/变量/返回标识大小写、LF/CRLF、分段/粘包、多余 token、缺 END、重复记录；不得仅测试本库严格拒绝 | P1；[C 实现][cimpl] |
| B03 | 流式列表/部分结果 | D/U | libupsclient 迭代返回与当前整表返回的区别、EOF/错误时可见的部分结果、取消后的连接状态 | P1/P2；[C API][capi] |
| B04 | 连接与会话生命周期 | E/U/D；显式会话/关闭、串行化、请求与排队取消；不自动重连，其他生命周期仍待验 | 连接/断开/显式重连、凭据与登录状态、跟踪状态、多个查询；并发和恢复是否属目标 API | P3；[C++ API][cpp] |
| B05 | TLS 默认与策略选项 | E/U/D；用户确认官方默认，本批次落实 TRYSSL/明文凭据 | TRYSSL/REQSSL/CERTVERIF、明文模式/凭据、信任源、每主机策略、客户端证书、握手拒绝；NSS/OpenSSL/无 TLS 分 profile | P1/P3；[C API][capi] |
| B06 | 地址解析与连接目标 | M/U | ups@host:port、默认 localhost:3493、IPv6 方括号、IPv4/IPv6 选择、DNS/连接失败 | P2；[C 实现][cimpl] |
| B07 | 超时与资源边界 | E/D；连接 10s、每次读取 5s、整体截止可选；其他差异未关闭 | 默认值、连接与读取/写入超时、阻塞模式、取消、慢响应、行/行数/总字节限额；比较具体边界值 | P1/P2；[C 实现][cimpl] |
| B08 | 错误与状态机 | E/U/D | 每个实际可达协议错误、传输/解析错误映射、错误优先级、tracking 结果；保留额外错误信息是否属于目标 | P1/P3/P4；[错误定义][errors] |
| B09 | 数据与集合语义 | D/U | 字符串/bytes/vector、数组/map/set、顺序、重复、空值、未知类型、多个值；禁止未审核排序/转换 | P1/P2；[C++ API][cpp]、[PyNUT][pynut] |
| B10 | 描述与服务特殊值 | E/U | 无描述的不同占位、server.*、upstream.*、驱动断开/陈旧；文档示例不是运行结果 | P1；[GET][get]、[LIST][list] |
| B11 | CLI 输出与结束状态 | D | stdout/stderr、精确文本/空格/换行、错误/帮助退出码、版本身份、输入缺失、管道行为 | P1/P2；C01–C14 |
| B12 | 环境/配置优先级 | M/D | NUT_DEFAULT_CONNECT_TIMEOUT、NUT_DEBUG_LEVEL、默认配置/证书与 CLI 参数的真实优先级；MOONNUT_* 当前非等价接口 | P2；[C 实现][cimpl] |
| B13 | 验证覆盖口径 | U | 每个 profile 保存同输入参考结果和本库结果；自测、直接差分、虚拟设备、硬件证据分开 | P0–P6 |
| B14 | 授权、重复与不确定结果 | M/U | 拒绝时无驱动动作；成功 ACK 与完成分开；发送后断线不自动重试；重复调用与参考结果一致 | P4；[SET][set]、[INSTCMD][inst] |

B08 不能只断言“均失败”。使用固定 [server/neterr.h][errors] 中的每个错误码为索引，并加 [upsclient.h][capi] 中 DNS/IO/TLS/解析等本地错误；旧命令遗留码先判定在本版本是否可达。不可达须有源码和审核记录，不能伪造服务器触发路径。当前只检查部分 `Server(code)`，CLI 会合并错误信息。

## Existing target CLIs / 现有目标程序

选项按固定源码 getopt/usage 核对，而不是最新版在线手册。所有行还需 B01–B14 中适用的行为；目前没有官方 CLI 可替换结论。

| ID | 程序与操作 | 当前状态 | 验收内容 | 来源/阶段 |
| --- | --- | --- | --- | --- |
| C01 | upsc -l / -L [host] | E/D | 名称/名称+描述、默认地址、端口、精确格式 | [upsc][upsc]；P2 |
| C02 | upsc ups [variable] | E/D | 全变量/单值、server.*、地址解析、错误/输出 | [upsc][upsc]；P1/P2 |
| C03 | upsc -c ups | E/D；API/演示已提供，CLI 可替换尚缺 | 登录客户端列表和输出 | [upsc][upsc]；P2/P3 |
| C04 | upsc -h / -V / -W | M/D | 帮助、版本、连接超时、合法/非法参数及环境覆盖 | [upsc][upsc]；P2 |
| C05 | upsrw 默认 / -l | E/D | 完整变量、描述、类型、长度、选项、SELECTED 标记、当前值；不能只比较集合 | [upsrw][upsrw]；P1/P2 |
| C06 | upsrw -s VAR=VALUE | M | 非交互写入、值转义/边界、错误、完成语义 | [upsrw][upsrw]；P4 |
| C07 | upsrw -s VAR；-u/-p | M | 交互输入值与缺失凭据提示、EOF/非 TTY；只用一次性假凭据 | [upsrw][upsrw]；P4 |
| C08 | upsrw -w / -t | M | tracking、超时默认/覆盖、失败结果/退出码 | [upsrw][upsrw]；P4 |
| C09 | upsrw -h / -V / -W | M/D | 与该程序实际默认及错误逐项匹配 | [upsrw][upsrw]；P2 |
| C10 | upscmd -l ups | E/D | 所有命令及描述、缺描述、顺序/文本、空集合 | [upscmd][upscmd]；P1/P2 |
| C11 | upscmd ups command [value] | M | 无/有参数的实际传递、权限/错误及 ACK | [upscmd][upscmd]；P4 |
| C12 | upscmd -u/-p；缺凭据交互 | M | 明文/TLS profile、提示、EOF/非 TTY、环境策略 | [upscmd][upscmd]；P4 |
| C13 | upscmd -w / -t | M | 与 upsrw 同样逐项验收，不假定两客户端相同 | [upscmd][upscmd]；P4 |
| C14 | upscmd -h / -V / -W | M/D | 参数/默认/输出/退出码及未知选项 | [upscmd][upscmd]；P2 |

JSON 是 moonnut 的额外输出模式，不是以上官方 CLI 的等价证据。保留扩展与是否要求精确 CLI 可替换，需要在 P0 记录。

## Library surfaces / 客户端库能力映射

下表列出低层 C API 全部函数名，以及高层库的业务能力族。不同语言返回类型不能自动视作相同。P0 应按选定 API/ABI 目标将 C++ 对象构造/复制/比较/有效性与 C 包装逐符号展开；这些未展开项仍是待验收工作，不是豁免。

| ID | libupsclient 固定 API / 能力 | 当前状态 | 验收映射 |
| --- | --- | --- | --- |
| L01 | upscli_init / upscli_cleanup | M/D | TLS 全局配置与重复初始化/清理；若仅语义映射也须记录 |
| L02 | upscli_connect / upscli_tryconnect / upscli_disconnect | E/U/D；connect/with_session/close/logout 已映射；C 断开及重连语义仍有差异 | 显式连接生命周期与超时，B04–B07 |
| L03 | upscli_add_host_cert | M | 每主机证书名、校验、强制 TLS |
| L04 | upscli_get | E/D | 通用 GET、结果形状/所有字段，N03–N06/N11/N12/N24/N25 |
| L05 | upscli_list_start / upscli_list_next | D | 所有 LIST 与迭代、结束/错误、部分结果 |
| L06 | upscli_sendline / upscli_sendline_timeout | M | 通用发送及指定超时；当前无任意命令入口 |
| L07 | upscli_readline / upscli_readline_timeout | M | 原始读取、缓冲/超时/EOF |
| L08 | upscli_splitname / upscli_splitaddr | M | B06 的地址语法、默认和错误 |
| L09 | upscli_fd / upscli_ssl | E/M；is_tls/is_closed 已提供；无 FD 公共映射 | FD 与 TLS 会话状态；跨语言 ABI 目标单独决定 |
| L10 | upscli_upserror / upscli_strerror | D | 错误码及消息，不等于统一 Query failed |
| L11 | upscli_set_default_connect_timeout / upscli_get_default_connect_timeout / upscli_init_default_connect_timeout | M/D | 默认、解析、优先级与阻塞模式 |
| L12 | upscli_str_contains_token | E/U | 当前仅离线示例做精确状态 token；未作为对应公共 API 逐项验证 |
| L13 | upscli_str_add_unique_token | M | 唯一性、容量、回调/拒绝与返回值；不是设备写入 |

来源：[upsclient.h][capi]。仅有 N01–N30 不意味着已覆盖这些低层 API。

| ID | 其他参考接口 | 当前状态与验收内容 |
| --- | --- | --- |
| L14 | libnutclient Client/TcpClient | E/D/M：显式会话、独立凭据、注销已提供；连接/重连/超时/状态/调试、认证/注销；不得把 protected sendQuery 误当公开 API |
| L15 | Device/Variable/Command 包装及 C 接口 | E/M/D：对象身份/有效性/集合、描述/值、查找与 has*；C 返回值/所有权/错误，以及 ABI 需求待逐符号确认 |
| L16 | getDeviceVariableValues / getDevicesVariableValues | M/D：单设备/跨设备批量读取、vector 值、异步请求次序、部分失败；没有原子快照保证 |
| L17 | setDeviceVariable 两种重载 / executeDeviceCommand | M：单值/多值与可选参数，返回 TrackingID；用参考实际服务器接受行为验收 |
| L18 | deviceLogin / deviceGetNumLogins / deviceGetClients / listDeviceClients / devicePrimary / deviceMaster / deviceForcedShutdown | E/M：已有单 UPS 计数/列表读取、LOGIN；primary/master/FSD 及跨设备组合仍缺失；映射 N12/N13/N27–N30 与跨设备组合、别名 fallback |
| L19 | hasFeature / isFeatureEnabled / setFeature / getTrackingResult | E/U/D：tracking 开关/读取/结果已提供；C++ 空 ID 直接成功与本库网络命令语义不同；通用 feature 探测仍缺；TRACKING 能力、启用状态、结果枚举及未知 feature；不能只看版本推断 |
| L20 | libnutclientstub / nutclientmem | S/M：若纳入对应公共测试替身/内存客户端，则另列构造与状态语义，不由网络查询自动覆盖 |
| L21 | PyNUT GetUPSList / GetUPSNames | E/D：仅 GetUPSList 有直接证据；names 列表与 bytes/dict 类型映射待验 |
| L22 | PyNUT GetUPSVars | E/D：完整虚拟变量表有证据，编码/重复/错误/断线未全对照 |
| L23 | PyNUT CheckUPSAvailable | M：LIST CMD 探测的 True/False/异常语义及流消费 |
| L24 | PyNUT GetUPSCommands | E/U/D：命令+描述组合；现有只与 upscmd 对照，没有此 PyNUT 方法直接对照 |
| L25 | PyNUT GetRWVars | E/U/D：对应 RW 值表，尚未对照该方法 |
| L26 | PyNUT SetRWVar / RunUPSCommand | M：写入与执行、编码/返回/异常；P4 后才实施 |
| L27 | PyNUT DeviceLogin / FSD | E/M：LOGIN 已实现，FSD 缺失；状态/授权/结果；P3/P4 后才实施 |
| L28 | PyNUT help / ver / ListClients | E/U：新增原始响应、单设备列表与对照；跨设备行为缺失 |
| L29 | PyNUT 构造/析构 | D：默认 host/port、明文凭据、timeout、debug 输出、LOGOUT、异常与 bytes；敏感日志策略存在需审核冲突 |

来源：[nutclient.h][cpp]、[nutclientmem.h][mem]、[PyNUT][pynut]。PyNUT 没有专用 API 的 NUT 能力仍保留在网络矩阵，不能据此删去。

## Suite roles and environment blockers / 套件角色与环境阻塞

X01–X08 为 **O**：用户明确不实现服务端或 UPS 驱动及其管理。X09–X11/X14 为 **M**：客户端能力保留；X12/X13/X15 的客户端部分为 **S/M**，继续逐程序展开，不因当前为库而排除。此节是族级盘点，不是逐选项清单已完成的声明。

| ID | 程序/组件 | 需覆盖的能力 | 平台/权限/硬件验收依赖 |
| --- | --- | --- | --- |
| X01 | upsd | LIST/GET/SET 分派、用户权限、状态缓存、陈旧/断线、TLS、连接/跟踪、重载/退出/限制 | 多客户端与合成驱动；NSS/OpenSSL/无 TLS 构建；系统安装另审批 |
| X02 | 驱动 → upsd socket 消息 | SETINFO/DELINFO、SETFLAGS/SETAUX、ADD/DEL ENUM/RANGE/CMD、PID、DUMPDONE、DATAOK/DATASTALE、PONG、TRACKING、退出回应 | Unix socket / Windows named pipe、权限、初始 dump 与增量更新、重连 |
| X03 | upsd/工具 → 驱动请求 | PING、DUMPALL/DUMPVALUE/DUMPSTATUS、GETPID、BROADCAST/NOBROADCAST、SET/INSTCMD、LOGOUT | 合成 socket 服务可验协议；产品驱动效果另验，不将夹具算产品 |
| X04 | NUT 软件驱动 | dummy-ups、clone、clone-outlet、failover、apcupsd-ups；skel 模板是否为交付目标须确认 | 各模式/配置/状态；当前仅运行 dummy-once，未实现对应驱动 |
| X05 | 串口/USB/HID 驱动 | 固定 drivers/Makefile.am 全部 SERIAL、USB、SERIAL_USB 成员及子驱动/quirk | 串口/USB 权限、设备型号/固件、抓取/回放与物理验证；当前禁止实物 |
| X06 | 网络/平台/总线驱动 | SNMP、netxml、Modbus、IPMI、PowerMan、macosx、Linux I2C、GPIO 各成员 | 依赖库、OS API、平台构建与对应设备；族名不能替代全部成员验收 |
| X07 | upsdrvctl | 驱动启动/停止/状态、配置、重载/退出、关机路径、失败顺序 | 隔离子进程与替身动作；真实电源动作不授权 |
| X08 | upsdrvsvcctl / nut-driver-enumerator | 配置到服务实例映射、枚举、启停/重载、守护模式 | systemd/Solaris 等管理器；仅隔离系统镜像，宿主机不改服务 |
| X09 | upsmon | 多 UPS/primary/secondary、供电判断、状态/通知、凭据/TLS、重连、关机协调 | 本地权限/通知/关机命令以替身验证；无真实掉电或宿主机关机 |
| X10 | upslog | 格式字段、定时/多目标、日志/重开、断线、进程/信号 | 时钟与临时文件、平台信号，不能由一次 GET 代替 |
| X11 | upssched / upssched-cmd | 事件匹配、定时器启动/取消、命令触发、IPC/退出 | 可控时钟与仅记录的命令替身；仅隔离替身动作 |
| X12 | nut-scanner / libnutscan | 编译启用的 USB/SNMP/XML/NUT/IPMI/串口/其他扫描后端及配置输出 | 逐后端确认；只能扫描隔离测试网络/设备，不能扫描生产网 |
| X13 | nutconf / libnutconf | 配置解析、生成、命令行与配置模型、无效配置及 round-trip | 固定配置样本和临时目录；完整符号/选项清单待展开 |
| X14 | NUT-Monitor 与 CGI | GUI 状态/管理及 upsstats.cgi、upsimage.cgi、upsset.cgi | Qt/GTK、Web/图形依赖、展示/权限/写入界面需单列 |
| X15 | 安装/平台服务/外部集成 | systemd、udev/devd/hotplug、Solaris、Windows nut/halt/message；其他绑定/插件逐项列明 | 各 OS、服务管理器与权限；上游仅链接的第三方项目另固定版本，不能假定随 NUT 标签固定 |

角色核对索引是固定源码的 [drivers/Makefile.am][drivers]、[clients/Makefile.am][clients]、[scripts/Makefile.am][scripts]、[tools/Makefile.am][tools] 及 [设备兼容表][hcl]。后续只展开用户确认的客户端相关成员；服务端/驱动列表用于确认角色边界。

## Evidence and completion / 证据与关闭条件

现有 E 的依据是 [固定 moonnut CI](https://github.com/pangbit/moonnut/actions/runs/42973210924)、[真实服务脚本](../scripts/upsd_integration.py)、[发现自测](../discovery_wbtest.mbt)、[CLI 自测](../scripts/cli_json_smoke.py) 与 [TLS 自测](../scripts/tls_smoke.py)。本批次运行 38 个原生测试、20 个 JSON 用例及 10 个本库 TLS 用例；代码提交 `79c962ad323f33d7f0bf1027040ca8f34b830e4b` 的 [CI 42981570296][current-ci] 已全部通过，包括上述新增读取及默认传输与官方 upsc 的 4 个场景。默认 TLS 信任/回退已取得直接证据，TLS 全配置/后端及其他默认行为仍未全部关闭。

本批本机 45 项原生测试、20 项 JSON 和 10 项 TLS 用例通过；官方会话对照待本批 CI。

本批会话代码与[会话文档](sessions.md)、[原生会话测试](../session_wbtest.mbt)、[官方 C 会话适配器](../scripts/nut_session_reference.c)关联。真实对照包含 44 项结果，明文/default TRYSSL 配置相同，另重复 moonnut 验证 TLS 的业务结果；注销计数按一秒内最终清理验收，不冒充瞬时清理或有效控制结果。

每个验收 ID 至少关联 `reference profile → case/input/state → reference result → moonnut result → diff → evidence → verdict`。跨行共用一个真实场景可以，但各断言须可定位。`未实现`、`未测`、`环境阻塞`、`双方行为冲突待裁定` 都不能记作通过。已经选择的范围内，任何未解决差异都阻止“完全一致”的结论。

English: Client scope and official CLI defaults are confirmed. X01–X08 server/driver implementations are outside scope by user decision. Client APIs, CLIs and monitoring capabilities retain explicit missing/unverified/different states; client-adjacent families still need expansion. Unit counts and selected virtual-device comparisons do not establish complete parity. Development and isolated comparisons continue; real-device control and publishing remain prohibited.

[cmds]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netcmds.h
[get]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netget.c
[list]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netlist.c
[set]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netset.c
[user]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netuser.c
[misc]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netmisc.c
[inst]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/netinstcmd.c
[errors]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/server/neterr.h
[parse]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/common/parseconf.c
[capi]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/upsclient.h
[cimpl]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/upsclient.c
[cpp]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/nutclient.h
[mem]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/nutclientmem.h
[pynut]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/scripts/python/module/PyNUT.py.in
[upsc]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/upsc.c
[upsrw]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/upsrw.c
[upscmd]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/upscmd.c
[drivers]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/drivers/Makefile.am
[clients]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/Makefile.am
[scripts]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/scripts/Makefile.am
[tools]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/tools/Makefile.am
[hcl]: https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/data/driver.list.in

[current-ci]: https://github.com/pangbit/moonnut/actions/runs/42981570296
