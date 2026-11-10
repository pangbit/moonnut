# Changelog / 更新记录

## Unreleased / 未发布

- Verify socket closure after cancellation/timeouts and concurrent response isolation.
- 验证取消/超时后的连接关闭，以及并发查询响应隔离。

- Exercise actual NUT STARTTLS authentication and credential/certificate rejection paths.
- 增加真实 NUT STARTTLS 认证与凭据/证书拒绝路径验证。

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
