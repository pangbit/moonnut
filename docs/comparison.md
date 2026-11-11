# Read-only comparison / 只读对照

## English

This checks client behavior against actual NUT software with a **virtual UPS**.
It is not a physical-device certification, full NUT feature comparison or speed ranking.
The library stays independent of NUT executables and Python; only tests need them.

### Fixed baseline

- CI: Ubuntu 26.04, NUT server/client/libraries `2.8.4+really-2` (NSS TLS build).
- MoonBit: `moonc` `0.10.20+65efd5b93`, async `0.22.4`.
- Official [PyNUT from NUT v2.8.3](https://github.com/networkupstools/nut/blob/c0acf09af3be41752abad90a19a11a26c9256b28/scripts/python/module/PyNUT.py.in),
  module 1.8.0, commit `c0acf09af3be41752abad90a19a11a26c9256b28`.
- PyNUT SHA-256: `a12d1e40f8cd926314157c137372628322dd09db94d697aca4bc9dc8beb64f82`.

The same temporary `upsd` + `dummy-ups` instance serves all clients on loopback.
Its static fixture has a multi-word model/status and numeric-looking string values.
Compare dictionaries without relying on row order; decode PyNUT bytes as UTF-8,
but do not coerce values to numbers or silently repair parsing differences.

| Case | moonnut and upsc | PyNUT |
| --- | --- | --- |
| UPS names and descriptions | Direct list comparison (`upsc -L`) | `GetUPSList`, same results |
| UPS description | `GET UPSDESC` matches `upsc -L` | No dedicated GET UPSDESC API |
| String/numeric metadata | `GET DESC` / `GET TYPE` match read-only `upsrw -l` | No dedicated DESC/TYPE APIs |
| Complete variable map | Direct list comparison | `GetUPSVars`, same results |
| Four selected scalar values | Direct `GET VAR` comparison | Same values via the full map; no direct GET API |
| Unknown UPS | Both fail | `GetUPSVars` raises `ERR UNKNOWN-UPS` |
| Unknown variable | Both fail | No direct GET API; not tested |
| STARTTLS, credentials, invalid CA/hostname | moonnut tested against actual upsd separately | No native STARTTLS API; not tested |

Metadata comparisons use `ups.model` and `battery.charge`; they cover actual
string/numeric type flags, not every ENUM/RANGE combination. `upsrw` is called
only with `-l`, without write options or credentials. See [metadata examples](metadata.md).

The CLI redacts errors, so failed-query checks assert failure rather than equal
exception classes or error text. TLS checks are **not** a three-client security
comparison. NUT can acknowledge an incorrect password and still permit anonymous
reads; successful reads do not prove the supplied credentials are valid.
PyNUT features outside moonnut's read-only scope are not exercised or scored.
Malformed replies and lifecycle bounds remain separate synthetic tests.

### Reproduce

Use a disposable Linux environment with the above NUT packages, OpenSSL,
`libnss3-tools`, Python 3.9+, and MoonBit installed. Build the project, then:

```sh
reference_dir=$(mktemp -d)
curl -fsSL \
  https://raw.githubusercontent.com/networkupstools/nut/c0acf09af3be41752abad90a19a11a26c9256b28/scripts/python/module/PyNUT.py.in \
  -o "$reference_dir/PyNUT.py"
moon build --target native
python3 scripts/upsd_integration.py --pynut "$reference_dir/PyNUT.py"
```

The script checks the reference hash **before execution**. Run as a regular user;
no service-manager commands, system NUT configuration or real drivers are used.
Only its child processes and temporary configuration are cleaned up. The downloaded
reference remains in the chosen external directory for inspection. It is GPL-3.0-or-later,
not vendored, translated or linked into the Apache-2.0 library. Omit `--pynut` for
the upsc-only run; the log explicitly reports that PyNUT was not run.

[CI](https://github.com/pangbit/moonnut/actions/workflows/ci.yml) prints tool versions,
the reference hash, case outcomes and the actual TLS backend. A missing pinned
package/hash fails instead of silently using a newer reference. Dependency pins
are a reproducible test baseline, not a recommendation for production updates.

## 中文

本测试针对真实 NUT 软件和**虚拟 UPS**，不是实物兼容认证、全部 NUT 功能评比或
性能排名。库本身仍不依赖 NUT 可执行文件及 Python，仅对照测试需要这些工具。

固定基线为 Ubuntu 26.04、NUT `2.8.4+really-2`（NSS 后端）、上文所列 MoonBit
与 async 版本，以及官方 NUT v2.8.3 中的 PyNUT 1.8.0。PyNUT 的完整提交与 SHA-256
列于上文，执行前必须核验。所有客户端读取同一个仅绑定回环地址的临时
`upsd + dummy-ups`，数据为静态合成设备：包含多词型号/状态和数字字符串。
比较不依赖行顺序，仅把 PyNUT bytes 解码为 UTF-8，不把数值字符串转为数字或掩盖解析差异。

| 场景 | moonnut 与 upsc | PyNUT |
| --- | --- | --- |
| UPS 名称及描述 | 直接列表对照，upsc 使用 `-L` | `GetUPSList` 对照相同结果 |
| UPS 描述 | `GET UPSDESC` 与 `upsc -L` 一致 | 无专用 GET UPSDESC API |
| 字符串/数值元信息 | `GET DESC` / `GET TYPE` 与只读 `upsrw -l` 一致 | 无专用 DESC/TYPE API |
| 完整变量表 | 直接列表对照 | `GetUPSVars` 对照相同结果 |
| 四个选定变量 | 直接 `GET VAR` 对照 | 从完整列表核对值，不提供直接 GET API |
| 未知 UPS | 均失败 | `GetUPSVars` 抛出 `ERR UNKNOWN-UPS` |
| 未知变量 | 均失败 | 不提供直接 GET API，不测此项 |
| STARTTLS、凭据、未知 CA/错误主机名 | 另行验证 moonnut 与真实 upsd | 不提供原生 STARTTLS API，不测此项 |

元信息对照选择 `ups.model` 与 `battery.charge`，覆盖真实字符串/数值类型，
不代表所有 ENUM/RANGE 组合。`upsrw` 仅使用 `-l`，不传写入参数或凭据。
示例与语义说明见[描述、类型与状态](metadata.md#中文)。

CLI 主动脱敏错误，因此比较“失败”结果而非异常类型或报错文本等价。TLS 检查不是
三方安全性比较。NUT 即使收到错误密码也可能允许匿名读取，读成功不能证明凭据有效。
不测试或评分超出 moonnut 只读范围的 PyNUT 功能；畸形响应和生命周期边界保留在
独立合成测试中。未验证物理驱动、真实掉电、电池行为、所有 TLS 后端或生产网络。

在已安装上述依赖的隔离 Linux 环境中，以普通用户运行上文复现命令。脚本不使用
系统 NUT 配置、服务管理器或真实驱动；只停止自己的子进程并清理临时配置。
参考源码保留在外部临时目录供检查，GPL-3.0-or-later 源码不会复制、移植或链接进
Apache-2.0 库。不加 `--pynut` 则只运行 upsc 对照，日志明确标注 PyNUT 未运行。
CI 记录版本、源码校验值、各项结果和 TLS 后端；固定包缺失或哈希不符即失败，
不悄悄换新版本。这些版本用于可复现测试，不是生产环境更新建议。
