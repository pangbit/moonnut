# Persistent sessions / 持久会话

`Client` remains connection configuration. Its 17 existing read methods each open
and close a separate connection. Use `connect()` to obtain an explicit `Session`,
or `with_session()` to guarantee closure when a callback returns, throws or is
cancelled. All 17 read methods are available on the same session.

```mbt
// In an async application; use an authorized endpoint and credential provider.
let client = @moonnut.Client::new("ups.example.invalid", security=@moonnut.Tls)
client.with_session(session => {
  let devices = session.list_ups()
  for device in devices {
    println(session.get_var(device.name, "ups.status"))
  }
})
```

| API | Protocol / behavior |
| --- | --- |
| `set_username(value)` / `set_password(value)` | Independently submit credentials; repeated setters propagate the server error |
| `get_tracking()` | `GET TRACKING` → `Bool`, connection-local state |
| `set_tracking(enabled)` | `SET TRACKING ON/OFF`; requires both credential fields to have been submitted in NUT 2.8.4 |
| `get_tracking_status(id)` | `GET TRACKING id` → `TrackingStatus` |
| `login(ups)` | Explicit `LOGIN`; registers a power consumer and changes NUMLOGINS/LIST CLIENT |
| `logout()` | `LOGOUT`, validate `OK Goodbye`, close the connection |
| `close()` | Idempotent immediate local close; no network command |
| `is_closed()` / `is_tls()` | Local connection/encryption state; TLS alone does not imply certificate verification |

`USERNAME`/`PASSWORD` OK only acknowledges storage. NUT's dispatch requires both
fields before SET TRACKING, but that handler does not validate their correctness.
LOGIN separately checks the LOGIN permission. Even a wrong password can therefore
enable tracking and read anonymous data while LOGIN is denied. LOGIN is never
sent implicitly or used to check a password. No SET VAR, INSTCMD, PRIMARY/MASTER
or FSD API is added by this stage.

`TrackingStatus` distinguishes `Pending`, `Success`, `Unknown`, `InvalidArgument`
and `Failed`. The last three are NUT tracking outcomes, despite their `ERR` wire
prefix. Other protocol errors, including FEATURE-NOT-CONFIGURED, still raise
`NutError::Server`. This is the explicit network-command profile: an empty ID is
sent as an empty quoted argument. The C++ library's shortcut treating an empty ID
as success without sending anything is a separate unresolved mapping in L19.
Known terminal outcomes are only synthetically tested until the simulated write
phase can create real tracking IDs. This API never starts or retries an operation.

Session requests are serialized with the async library's mutex. A complete server
error before a list begins leaves the connection usable. An incomplete list,
framing/transport failure, timeout or cancellation after acquiring the stream
closes it; queued requests then fail with `ConnectionClosed`. Cancelling while
waiting for the mutex does not close another request's connection. Fully consumed
scalar replies can fail typed validation without leaving unread response bytes.
There is no implicit reconnect or replay, including after an uncertain outcome.

`timeout_ms`, when supplied, covers connect/authentication for `connect`, each
request including lock wait for `Session`, and the entire callback for
`with_session`. Read deadlines remain per transport read. Response byte/row limits
reset per reply, not per session lifetime. `close()` does not wait for LOGOUT;
call `logout()` explicitly when its acknowledgement matters. These choices are
recorded as API mappings, not C ABI or complete lifecycle equivalence.

**Transport risk remains unchanged:** default `TryTls` follows the official CLI:
unverified TLS, plaintext including credentials after STARTTLS refusal. Use
explicit `Tls` or `TlsCaFile` when certificate and hostname verification is needed.
No real UPS or host shutdown action is used in validation.

[CI 42984926159](https://github.com/pangbit/moonnut/actions/runs/42984926159) passed for code `c2527e0457a2905c610661fde1b5e341c9c95b3a`.
The native fixtures cover state sequencing, recoverable errors, distinct tracking
outcomes, per-reply limits, concurrent serialization and cancellation. The Linux
integration adds a LOGIN-only disposable account and compares 44 observable
outcomes with installed official libupsclient on the same virtual upsd. It covers
two simultaneous LOGIN clients, repeated addresses, logout cleanup, wrong
password, and fresh-session state. Plaintext and default TLS use matching transport
profiles; moonnut verified TLS repeats the same semantic trace against the C
TRYSSL reference. Login count cleanup is checked eventually within one second,
not assumed to happen at the instant the Goodbye line arrives.

## 中文

`Client` 的 17 项读取仍各自使用新连接；`connect()` 返回显式持久 `Session`，
`with_session()` 在回调返回、抛错或取消时保证关闭。会话拥有同样的 17 项读取 API，
另提供表中的凭据、tracking、LOGIN、LOGOUT 和连接状态操作。

USERNAME/PASSWORD 的 OK 只是接收确认。NUT 2.8.4 的分派入口要求 SET TRACKING 前
已提交两项凭据，但 tracking 处理本身不验证密码；LOGIN 才另外检查 LOGIN 权限。
因此错误密码可能仍允许 tracking 与匿名读取，同时 LOGIN 被拒绝。不会隐式 LOGIN，
也不以 LOGIN 探测密码。本阶段不增加写变量、即时命令、PRIMARY/MASTER 或 FSD 接口。

TrackingStatus 保留五种结果；ERR UNKNOWN、ERR INVALID-ARGUMENT、ERR FAILED
按 tracking 结果返回，其他协议错误仍抛出 Server。空 ID 按网络协议原样发送；C++ 库
不发送请求、直接把空 ID 当作成功的规则仍是 L19 未完成映射。真实有效 ID 的结果生命周期
仍待隔离写入阶段，本阶段没有用合成结果冒充真实操作完成证据。

会话内请求串行执行。列表开始前的完整服务端错误不会关闭连接；未读完列表、分帧或
传输错误、请求执行中的超时/取消会关闭连接。排队期间取消不会影响正在执行的请求。
关闭后的调用报 ConnectionClosed，不自动重连或重发。完整标量行的类型校验错误不留下
未读数据。字节/行数上限按每个响应重置。connect 的总超时覆盖连接及凭据提交，Session
总超时覆盖单次请求及锁等待，with_session 总超时覆盖整个回调。

默认传输仍遵从用户选择的官方 CLI 行为：不验证证书的 TLS，STARTTLS 拒绝后可明文发送
凭据。需要验证时显式选择 Tls/TlsCaFile。LOGIN 改变服务端消费者计数，不是纯读取；
所有本项目对照仅使用临时回环服务、虚拟设备及仅有 LOGIN 权限的账号。

Linux 对照通过官方 libupsclient 比较 44 项结果，涵盖两个同时登录的连接、重复地址、
注销清理、错误密码和新连接状态。明文与默认 TLS 配置相同；另用 moonnut 验证 TLS
重复业务结果对照。注销计数在一秒内等待收敛，不声称 Goodbye 到达瞬间一定已经清理。
上述会话对照已由 [CI 42984926159](https://github.com/pangbit/moonnut/actions/runs/42984926159) 验证通过；尚未完整对齐的能力仍列于[验收矩阵](parity-matrix.md)，当前不宣称完整客户端一致。
