# CheckSentry 1.2.0 安全审核交接

产品版本固定 1.2.0。本轮仅封堵扩展图标元数据通过 UNC/符号链接触发文件/网络访问的风险；没有改变规则业务、云端配置或历史扫描。

必须在 Windows 环境执行：`tests/Run-Tests.ps1`、`tests/Security-Tests.ps1`、`tests/Execution-Tests.ps1`、`dotnet build` 和 `dotnet list package --include-transitive --vulnerable`。

正式发布前需决定：规则写权限、EPPlus 4.5.3.2 淘汰路径、无签名发布策略、便携目录 ACL。详见同批交付安全审核报告。
