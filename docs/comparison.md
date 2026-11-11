# Read-only comparison / 只读对照

## English

This checks client behavior against actual NUT software with a **virtual UPS**.
It is not a physical-device certification, full NUT feature comparison or speed ranking.
The library stays independent of NUT executables and Python; only tests need them.

### Fixed baseline

- CI: Ubuntu 26.04, NUT server/client/libraries `2.8.4+really-2` (NSS TLS build).
- MoonBit: `moonc` `0.10.20+65efd5b93`, async `0.22.4`.
- Official [PyNUT from NUT v2.8.4](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/scripts/python/module/PyNUT.py.in),
  module 1.8.0, commit `541c2ecf0b2ec33dadb9f40b16acbe39042bd103`.
- PyNUT SHA-256: `a12d1e40f8cd926314157c137372628322dd09db94d697aca4bc9dc8beb64f82`.

The same temporary `upsd` + `dummy-ups` instance serves all clients on loopback.
Its static fixture has a multi-word model/status and numeric-looking string values.
Even `dummy-once` updates `driver.state` during each driver poll. The disposable
fixture uses a 3600-second poll interval and waits for `quiet` before comparing
full maps, so the sequential reads do not straddle that state change. No fields
are excluded from equality checks; ordinary multi-query reads are not atomic.
Compare dictionaries without relying on row order; decode PyNUT bytes as UTF-8,
but do not coerce values to numbers or silently repair parsing differences.

| Case | moonnut and official NUT clients | PyNUT |
| --- | --- | --- |
| UPS names and descriptions | Direct list comparison (`upsc -L`) | `GetUPSList`, same results |
| UPS description | `GET UPSDESC` matches `upsc -L` | No dedicated GET UPSDESC API |
| String/numeric metadata | `GET DESC` / `GET TYPE` match read-only `upsrw -l` | No dedicated DESC/TYPE APIs |
| RW variables and current values | `LIST RW` matches read-only `upsrw -l` and the variable map | Not compared |
| Commands and descriptions | `LIST CMD` / `GET CMDDESC` match `upscmd -l` | Not compared |
| ENUM and disjoint ranges | Real upsd with synthetic driver state matches `upsrw -l` | Not compared |
| Complete variable map | Direct list comparison | `GetUPSVars`, same results |
| Four selected scalar values | Direct `GET VAR` comparison | Same values via the full map; no direct GET API |
| Unknown UPS | Both fail | `GetUPSVars` raises `ERR UNKNOWN-UPS` |
| Unknown variable | Both fail | No direct GET API; not tested |
| NUMLOGINS, VER, NETVER, PROTVER, HELP | Original read-only adapter calls installed libupsclient | HELP/VER public methods |
| Empty LOGIN client list | `LIST CLIENT` matches `upsc -c` | `ListClients` |
| STARTTLS, credentials, invalid CA/hostname | moonnut tested against actual upsd separately | No native STARTTLS API; not tested |

Metadata comparisons use `ups.model` and `battery.charge`; they cover actual
string/numeric type flags. Separate ENUM/two-interval RANGE checks use a second
synthetic Unix-socket driver state, not dummy-ups or a physical driver.
See [discovery scope](discovery.md). `upsrw` is called
only with `-l`, without write options or credentials. See [metadata examples](metadata.md).

The CLI redacts errors, so failed-query checks assert failure rather than equal
exception classes or error text. The TLS loopback script additionally compares
moonnut and upsc defaults for an untrusted/wrong-host certificate, STARTTLS refusals
and failed handshake. This is not a three-client security comparison. NUT can acknowledge an incorrect password and still permit anonymous
reads; successful reads do not prove the supplied credentials are valid.
Unimplemented PyNUT client capabilities remain open in the [acceptance matrix](parity-matrix.md).
Malformed replies and lifecycle bounds remain separate synthetic tests.

### Reproduce

Use a disposable Linux environment with the above NUT packages, OpenSSL,
`libnss3-tools`, `libupsclient-dev`, a C compiler, Python 3.9+, and MoonBit installed. Build the project, then:

```sh
reference_dir=$(mktemp -d)
curl -fsSL \
  https://raw.githubusercontent.com/networkupstools/nut/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/scripts/python/module/PyNUT.py.in \
  -o "$reference_dir/PyNUT.py"
moon build --target native
cc -Wall -Wextra -Werror scripts/nut_reference.c -lupsclient -o "$reference_dir/nut-reference"
python3 scripts/upsd_integration.py --pynut "$reference_dir/PyNUT.py" --nut-reference "$reference_dir/nut-reference"
```

The script checks the reference hash **before execution**. Run as a regular user;
no service-manager commands, system NUT configuration or real drivers are used.
Only its child processes and temporary configuration are cleaned up. The downloaded
reference remains in the chosen external directory for inspection. It is GPL-3.0-or-later,
not vendored, translated or linked into the Apache-2.0 library. The original C
test adapter links the separately installed libupsclient only in the test process. Omit `--pynut` for
the official CLI-only run; the log explicitly reports that PyNUT was not run.

[CI](https://github.com/pangbit/moonnut/actions/workflows/ci.yml) prints tool versions,
the reference hash, CLI binary hashes, architecture, case outcomes and the actual TLS backend. A missing pinned
package/hash fails instead of silently using a newer reference. Dependency pins
are a reproducible test baseline, not a recommendation for production updates.

## 中文

本测试针对真实 NUT 软件和**虚拟 UPS**，不是实物兼容认证、全部 NUT 功能评比或
性能排名。库本身仍不依赖 NUT 可执行文件及 Python，仅对照测试需要这些工具。

固定基线为 Ubuntu 26.04、NUT `2.8.4+really-2`（NSS 后端）、上文所列 MoonBit
与 async 版本，以及官方 NUT v2.8.4 中的 PyNUT 1.8.0。PyNUT 的完整提交与 SHA-256
列于上文，执行前必须核验。所有客户端读取同一个仅绑定回环地址的临时
`upsd + dummy-ups`，数据为静态合成设备：包含多词型号/状态和数字字符串。
即使使用 `dummy-once`，驱动每轮也会更新 `driver.state`。临时夹具将轮询间隔设为
3600 秒，并等待 `quiet` 后再比较完整变量表，避免顺序查询跨越状态变化；不排除
任何字段。普通的多次查询不保证原子快照。
比较不依赖行顺序，仅把 PyNUT bytes 解码为 UTF-8，不把数值字符串转为数字或掩盖解析差异。

| 场景 | moonnut 与官方 NUT 客户端 | PyNUT |
| --- | --- | --- |
| UPS 名称及描述 | 直接列表对照，upsc 使用 `-L` | `GetUPSList` 对照相同结果 |
| UPS 描述 | `GET UPSDESC` 与 `upsc -L` 一致 | 无专用 GET UPSDESC API |
| 字符串/数值元信息 | `GET DESC` / `GET TYPE` 与只读 `upsrw -l` 一致 | 无专用 DESC/TYPE API |
| 可写变量及当前值 | `LIST RW` 与 `upsrw -l` 及变量表一致 | 未对照 |
| 命令及描述 | `LIST CMD` / `GET CMDDESC` 与 `upscmd -l` 一致 | 未对照 |
| 枚举及独立区间 | 真实 upsd 加合成驱动状态，与 `upsrw -l` 一致 | 未对照 |
| 完整变量表 | 直接列表对照 | `GetUPSVars` 对照相同结果 |
| 四个选定变量 | 直接 `GET VAR` 对照 | 从完整列表核对值，不提供直接 GET API |
| 未知 UPS | 均失败 | `GetUPSVars` 抛出 `ERR UNKNOWN-UPS` |
| 未知变量 | 均失败 | 不提供直接 GET API，不测此项 |
| NUMLOGINS、VER、NETVER、PROTVER、HELP | 原创只读适配器调用已安装 libupsclient 对照 | HELP/VER 公共方法 |
| 空 LOGIN 客户端列表 | 与 upsc -c 对照 | ListClients |
| STARTTLS、凭据、未知 CA/错误主机名 | 另行验证 moonnut 与真实 upsd | 不提供原生 STARTTLS API，不测此项 |

元信息对照选择 `ups.model` 与 `battery.charge`，覆盖真实字符串/数值类型，
ENUM/双区间 RANGE 另用连接到真实 upsd 的合成 Unix socket 驱动状态，不是 dummy-ups
或物理驱动；详见[能力发现范围](discovery.md#中文)。`upsrw` 仅使用 `-l`，不传写入参数或凭据。
示例与语义说明见[描述、类型与状态](metadata.md#中文)。

CLI 主动脱敏错误，因此比较“失败”结果而非异常类型或报错文本等价。TLS 检查不是
三方安全性比较；回环脚本另将默认不验证证书、STARTTLS 拒绝回退和握手失败与 upsc 直接对照。NUT 即使收到错误密码也可能允许匿名读取，读成功不能证明凭据有效。
不测试或评分超出 moonnut 只读范围的 PyNUT 功能；畸形响应和生命周期边界保留在
独立合成测试中。未验证物理驱动、真实掉电、电池行为、所有 TLS 后端或生产网络。

在已安装上述依赖的隔离 Linux 环境中，以普通用户运行上文复现命令。脚本不使用
系统 NUT 配置、服务管理器或真实驱动；只停止自己的子进程并清理临时配置。
参考源码保留在外部临时目录供检查，GPL-3.0-or-later 源码不会复制、移植或链接进
Apache-2.0 库。不加 `--pynut` 则只运行官方 CLI 对照，日志明确标注 PyNUT 未运行。
CI 记录版本、源码校验值、各项结果和 TLS 后端；固定包缺失或哈希不符即失败，
不悄悄换新版本。这些版本用于可复现测试，不是生产环境更新建议。

本批次同时断言真实 upsd 的空 ENUM/RANGE、不可用描述，以及 server.* 大写请求对应规范小写响应。计数与地址的非空会话生命周期、顺序及其他边界仍见矩阵，不能据本脚本声称完整兼容。
