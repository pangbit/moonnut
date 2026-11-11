# Security / 安全

This is an early, personally maintained client in development, not a safety-critical
power-management component. Use verified TLS and a minimally privileged NUT
account. Do not expose an unauthenticated upsd port to untrusted networks.
The default follows NUT CLI TRYSSL: unverified TLS, with plaintext (including
credentials) on STARTTLS refusal. Use explicit Tls/TlsCaFile or --tls/--ca for
verified transport. Handshake failures do not fall back. Responses and
resource limits are validated, but secrets in process memory are not guaranteed
to be zeroized. Minimum TLS versions and cipher policy follow the underlying TLS
library; this client does not independently enforce a TLS 1.2/1.3 minimum.
No real hardware certification or security audit is claimed.

For a suspected vulnerability, contact the repository maintainer privately using
the contact route on their public profile. Do not open a public issue containing
secrets, private endpoints or an uncoordinated exploit. Use synthetic reproductions.

这是早期的个人维护、开发中的客户端，不是安全关键电源管理组件。使用验证过的 TLS 和
最小权限 NUT 账号，不要将未认证的 upsd 端口暴露给不可信网络。默认按官方 CLI TRYSSL：不验证证书，STARTTLS 被拒绝时回退明文，
包括凭据。显式使用 Tls/TlsCaFile 或 --tls/--ca 可要求验证；握手失败不会回退。项目校验响应与资源上限，但不保证进程中秘密内存安全清零。
最低 TLS 版本及算法策略继承底层库，当前未额外强制 TLS 1.2/1.3 最低版本。
不宣称通过真实硬件认证或安全审计。

发现疑似漏洞请通过维护者公开个人资料中的联系方式私下联系。不要在公开 issue 中
贴出秘密、私有端点或未协调披露的利用方式。请使用合成复现。

NUT may acknowledge USERNAME/PASSWORD without validating them until an authorized
command is requested. Read-only success is not proof of a correct password.
moonnut does not issue LOGIN or power-management commands to probe credentials.

NUT 可能先确认接收 USERNAME/PASSWORD，到需要授权的命令才验证；只读成功不证明
密码正确。moonnut 不使用 LOGIN 或电源管理命令探测凭据。

Explicit Session.login registers a power consumer and affects NUMLOGINS/LIST CLIENT.
It requires authorization even though it does not itself send a UPS control command.
Tracking toggles and credentials are connection state; they do not validate the
password. Requests are never automatically replayed after connection failure.

显式 Session.login 登记供电消费者，影响 NUMLOGINS/LIST CLIENT；即使没有发送 UPS
控制命令，也必须获得目标服务器的授权。tracking 开关与凭据属于连接状态，不证明
密码正确；连接失败后不会自动重放请求。会话对照账号仅授予 LOGIN；控制对照另用完全隔离的临时账号及内存设备。

Explicit SET VAR/INSTCMD can change a real device, and FSD can cause connected
monitors to shut systems down. An accepted request or driver Success is not
independent proof of its physical effect. A lost acknowledgement leaves the
outcome uncertain; never assume it is safe to repeat. The control tests use fresh
loopback daemons, fake credentials and a purely in-memory driver. No real driver,
upsmon, shutdown executable or service manager participates. See [controls](docs/controls.md).

显式 SET VAR/INSTCMD 可改变真实设备，FSD 可使监控程序关闭系统。接受请求或驱动报告
Success 不是实物效果的独立证据；丢失确认时结果不确定，不能据此认为可以安全重发。
控制测试仅使用新建回环守护进程、假凭据和纯内存驱动；不启动真实驱动、upsmon、
关机程序或服务管理器。默认明文回退风险不变，发布仍由用户控制。

Management CLIs retain NUT's plaintext-fallback defaults. A password supplied
with -p is visible in process arguments; POSIX password prompting avoids that
argv exposure. A tracking timeout may happen after dispatch, including -t 0;
never infer that the operation did not execute. Raw single-line requests and CLI
replies are for explicit protocol use; they can issue authorized control actions.
See [management CLI limits](docs/admin-cli.md).

管理 CLI 保留官方明文回退默认。-p 密码可被进程参数观察，POSIX 密码提示可避免该 argv
暴露。tracking 超时可能发生在请求已发送之后，包括 -t 0，不能推断没有执行。
单行协议接口可发送显式控制请求。测试只连接隔离内存设备，发布限制不变。
