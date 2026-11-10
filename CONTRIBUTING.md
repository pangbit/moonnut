# Contributing / 贡献指南

Keep changes small and focused. Open an issue before adding new protocol commands,
platforms or architecture. Include a synthetic regression test for a bug fix.
Run the development checks in the English/Chinese README. Never connect tests to
real power equipment or include real device data, credentials, private addresses,
certificates, keys or local paths. Generated API interfaces belong in Git; build
outputs and downloaded reference implementations do not. Contributions use Apache-2.0.

请保持修改精简。新增协议命令、平台或架构前先通过 issue 讨论；修复问题应附合成
回归测试。提交前执行中英文 README 中的检查。测试不得连接真实电源设备，不得提交
真实设备数据、凭据、内网地址、证书、密钥或本机路径。生成的 API 接口应提交，
构建产物及下载的参考实现不应提交。贡献使用 Apache-2.0 许可证。

## Releases / 发布

The maintainer performs Mooncakes releases manually. Automation and assistants
must not publish registry versions. GitHub main may contain unreleased changes;
keep the changelog explicit and never overwrite an existing version or tag.

Mooncakes 版本由维护者手动发布，自动化及助手不得代为发布。GitHub main 可能包含
未发布修改，应明确记录更新日志，不覆盖已有版本或标签。
