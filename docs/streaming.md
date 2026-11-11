# Streaming lists / 流式列表

`Session::with_list(query, callback)` and `ListReader::next()` provide incremental
LIST access without collecting a complete table. Query arguments exclude the LIST
keyword: `["UPS"]`, `["VAR", "demo"]`, `["CLIENT", "demo"]`, or another LIST query.
Each row contains all echoed query tokens and returned fields, in server order.
`next()` returns `None` at the end; errors raise and are not completion signals.

```mbt
// Inside an async application, using an authorized endpoint:
client.with_session(session => {
  session.with_list(["VAR", "demo"], reader => {
    while reader.next() is Some(row) {
      println(row) // validate the fields required by your application
    }
  })
})
```

The session lock covers the entire callback, so **do not issue another request on
that same Session inside the callback**. Use a different session if needed.
Reader `next` calls serialize. A reader used after the callback returns raises
`ConnectionClosed`; it cannot consume a later response. Caller-owned query
arguments are copied and encoded before network IO. This API only emits LIST.

A complete server ERR before BEGIN LIST leaves the connection reusable. A failed
read, early callback return, callback failure or cancellation closes an unfinished
stream. Already delivered rows remain observable, but must be treated as partial.
`timeout_ms` covers the callback and lock wait; read, line, row and total-byte limits
remain active. Limits do not reset per row. No automatic replay occurs.

This generic reader maps selected low-level [libupsclient list behavior](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/upsclient.c#L1440):

- BEGIN LIST and query prefixes compare case-insensitively for ASCII; extra fields
  are accepted and retained in rows.
- Uppercase `END LIST` ends the list without checking trailing query tokens, as in
  `upscli_list_next`. Lowercase end markers are not terminators.
- Too few query-prefix tokens fail without reading beyond the array; malformed
  inputs with undefined behavior in the C reference are not parity evidence.

Existing typed list methods remain buffered and validate complete row shapes and
matching end markers. These stricter methods and the scoped generic API are distinct
interfaces. C-style unscoped start/next, reuse after incomplete responses, raw byte
parsing, all buffer boundaries and complete ABI equivalence remain unresolved.
Empty arguments are explicitly quoted, unlike the C command builder's empty-token
omission; control characters are rejected before sending.

## upsc behavior and validation

The native `upsc` uses the reader for UPS, variable and consumer lists. Following
[upsc.c](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/clients/upsc.c#L115),
a list-start error exits 1. Once started, a read/protocol error stops iteration and
can **exit 0 with only partial output**, without an error message. A successfully
parsed row with too few output fields instead prints the reference's
`Error: insufficient data ...` diagnostic and exits 1, retaining earlier output.
Extra fields are ignored by the CLI. Resource-limit failures remain explicit
moonnut failures (exit 1), an unresolved difference from the C client.

Do not use upsc exit 0 alone as proof that every list row was received. Applications
that need completion/error distinction should use `with_list` and handle exceptions.
Pipe/TTY buffering and flush timing are not established by final-output comparisons.
The native test waits for the first callback-consumed row before allowing END LIST,
so the library's incremental delivery is tested independently of CLI buffering.

Local macOS validation passes **53 native tests** (four new lifecycle tests),
**28 scripted upsc cases**, the existing 20 JSON and 14 library/query-CLI TLS checks.
**The official Linux streaming differential is pending execution.**
The [script](../scripts/list_stream_integration.py) uses disposable loopback sockets,
no daemon, device, credentials or LOGIN. These 28 cases use plaintext after STARTTLS
refusal; mid-list TLS failures are not directly compared by this suite. Existing
TLS/real-upsd tests continue covering complete lists. It compares both implementations' stdout,
semantic stderr and exit status for complete/empty/partial lists, extra/short
fields, errors, EOF/truncated lines, case, end markers, Unicode and fragmented CRLF.

The first official run [43000028237](https://github.com/pangbit/moonnut/actions/runs/43000028237)
passed the first 20 comparisons, then exposed a **UTF-8 difference**: for
`UPS a "测试 UPS"`, official stdout was `a:  UPS`, with six per-byte `addchar`
diagnostics. [parseconf addchar](https://github.com/networkupstools/nut/blob/541c2ecf0b2ec33dadb9f40b16acbe39042bd103/common/parseconf.c#L178)
deliberately rejects non-ASCII bytes; the diagnostic hex representation also depends
on char signedness. moonnut retains the valid UTF-8 text. The revised suite keeps
this as a separately asserted **known parity gap**, including every diagnostic;
it is not a matching case and not removed by NSS normalization. Full parser-profile
alignment remains required. The other 27 cases still require a completed rerun.

The `list-stream.json` CI artifact retains reply bytes as hex, raw client requests,
outputs and expected results. Only the six documented NSS diagnostics are excluded
from stderr equality. Wire requests are recorded but not claimed identical: moonnut
closes incomplete streams immediately, while C cleanup may send LOGOUT; normal
moonnut cleanup also waits for a reply. Artifact retention is seven days.
Tests do not exercise physical effects, host shutdown or publication.

## 中文

新增 `Session::with_list` 与作用域内 `ListReader::next()`，逐行取得包含查询前缀及全部
字段的原始 token 数组；不必等完整表。`None` 表示结束，异常表示失败，已取得的行可能
只是部分结果。回调独占会话，不应在其中对同一 Session 发起其他请求；需要时使用另一会话。
迭代器仅在回调作用域有效，超出作用域再读取会报错。

BEGIN 前完整 ERR 可恢复；读失败、提前返回、回调失败或取消会关闭未完成的会话。
超时、行长、行数与整份响应字节上限仍有效，不自动重试。通用接口按固定 C 客户端接收
额外字段，忽略 ASCII 大小写的查询前缀，并以大写 `END LIST` 结束而不核对尾部查询字段。
原有类型化列表 API 保留整表返回及更严格的帧校验；不能把这两个接口混为完整等价。

`upsc` 的列表已改用流式读取。与固定官方程序一致：列表开始前失败退出 1；开始后部分
读取/协议错误可保留已输出内容并退出 0，不打印错误；合法前缀但输出字段不足则报错并
退出 1。资源上限仍显式失败，是保留差异。因此退出 0 不能证明列表完整，要求完整性时
应使用库接口并处理异常。CLI 管道/TTY 缓冲与刷新时机未验收，不能从最终输出相同推断。

本地 53 项原生、28 项脚本场景及既有 JSON/TLS 检查通过。首次官方运行在第 21 个
UTF-8 场景发现差异而失败：参考 parseconf 丢弃高位字节并发出逐字节诊断，moonnut 保留
合法 UTF-8。它仍是 B01/D 待解决项，不过滤、不算一致；修订脚本分别断言双方结果，
其余 27 场景待完整重跑。
新增四项原生测试检查先取得行再发 END、作用域、异常、取消、提前退出、上限及可恢复 ERR。
脚本只使用 STARTTLS 被拒绝后的明文回环合成回复，保存原始证据；中途 TLS 失败未直接
对照。未完成连接的清理/LOGOUT、完整分词、缓冲边界及
C ABI 等仍保留差异。当前 README 入口形式不变，不操作真实 UPS、不关机、不发布。
