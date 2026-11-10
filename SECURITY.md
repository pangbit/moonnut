# Security / 安全

This is an early, personally maintained read-only client, not a safety-critical
power-management component. Use verified TLS and a minimally privileged NUT
account. Do not expose an unauthenticated upsd port to untrusted networks.
Plaintext is an explicit opt-in and must never carry credentials. Responses and
resource limits are validated, but secrets in process memory are not guaranteed
to be zeroized. Minimum TLS versions and cipher policy follow the underlying TLS
library; this client does not independently enforce a TLS 1.2/1.3 minimum.
No real hardware certification or security audit is claimed.

For a suspected vulnerability, contact the repository maintainer privately using
the contact route on their public profile. Do not open a public issue containing
secrets, private endpoints or an uncoordinated exploit. Use synthetic reproductions.

这是早期的个人维护只读客户端，不是安全关键电源管理组件。使用验证过的 TLS 和
最小权限 NUT 账号，不要将未认证的 upsd 端口暴露给不可信网络。明文必须显式选择，
且不得发送凭据。项目校验响应与资源上限，但不保证进程中秘密内存安全清零。
最低 TLS 版本及算法策略继承底层库，当前未额外强制 TLS 1.2/1.3 最低版本。
不宣称通过真实硬件认证或安全审计。

发现疑似漏洞请通过维护者公开个人资料中的联系方式私下联系。不要在公开 issue 中
贴出秘密、私有端点或未协调披露的利用方式。请使用合成复现。

NUT may acknowledge USERNAME/PASSWORD without validating them until an authorized
command is requested. Read-only success is not proof of a correct password.
moonnut does not issue LOGIN or power-management commands to probe credentials.

NUT 可能先确认接收 USERNAME/PASSWORD，到需要授权的命令才验证；只读成功不证明
密码正确。moonnut 不使用 LOGIN 或电源管理命令探测凭据。
