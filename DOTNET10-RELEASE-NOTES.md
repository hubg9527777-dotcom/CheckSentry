# CheckSentry 1.2.0 — .NET 10 运行时与依赖决策（2026-11-08）

**产品版本永久保持 1.2.0，直到项目所有者明确批准更改。**

## 运行方式

- 启动器目标平台：`net10.0-windows`。
- SDK：微软官方 `10.0.403` 起，`global.json` 设置 `latestFeature`，以允许后续 10.0 安全补丁和 Feature Band；构建 CI 为 `10.0.x`。
- 发布：`win-x64`、`--self-contained true`、`PublishSingleFile=true`，内置 .NET 10 运行时。正常使用不检查电脑是否安装 .NET，也不联网下载安装。用户即使未安装 .NET 10 仍可直接运行**正确构建的发布版**。
- 这是由开发者在 CI/构建机使用微软 SDK 完成的封装；必须用 Windows 完成首次 `dotnet restore/build/publish` 测试，并在干净、无网络且未安装 .NET 10 的 Windows 虚拟机上检验真正独立运行。
- 不能承诺每次双击都会检测运行时或自动升级；自包含运行时的安全更新需要 **重新构建并分发 CheckSentry 1.2.0**，而不是依赖员工电脑已安装的 .NET。

## PECmd 授权边界

- 未获得用户批准：**本版不下载、不捆绑、不安装、不执行 PECmd**。
- 构建清单删除了 `Tools/PECmd` 资源通配符，扫描器删除了第三方可执行程序调用接口，即使有人将 `PECmd.exe` 放在项目目录，也不会自动被调用或封装。
- 目前本地 Prefetch 解析仍使用 `Get-ExecutionHistory.ps1` 内 PowerShell `Add-Type` + Windows 原生解压函数；这部分依赖 Windows PowerShell 5.1 使用的 .NET Framework，并**不是**因为启动器升级到 .NET 10 就自动获取了更精确的 Prefetch 解析能力。
- 4688、正在运行进程等已有采集源继续工作；运行证据、历史路径与所读文件，必须明确来源与可信度。
- Prefetch 解析可靠性、路径验证、Windows 10/11 版本兼容性，继续标注 **待实机确认**，严禁用未验证路径作为证明违规或一键定位依据。

## 第三方组件范围

`Modules/ImportExcel/7.8.10` 是旧版已有、随项目提供的 PowerShell 依赖。升级 .NET 10 **不会消除该组件**，也没有新增其他第三方 EXE。为了不在员工电脑自动安装未知组件，如果随包 ImportExcel 缺失或校验失败，程序直接报告错误，不再执行 `Install-Module`、`Install-PackageProvider` 或系统级未经校验的替代模块。`Prepare-Dependencies.ps1` 是开发者显式手动操作的独立命令，不会在员工电脑启动时调用。

## Windows 发布验收（必做）

1. 用微软官方 .NET 10 SDK `10.0.403` 或同系列更新正式版在 Windows 执行 `dotnet --info`。
2. `dotnet restore launcher/CheckSentry.Launcher.csproj`，`dotnet build launcher/CheckSentry.Launcher.csproj -c Release`。
3. 运行 `tests/Run-Tests.ps1`、`tests/Execution-Tests.ps1` 及 Node 静态测试。
4. 执行 `Build-Release.ps1 -Version 1.2.0` 构建自包含 CheckSentry.exe。
5. 在未安装 .NET 10、断网的干净 Windows x64 虚拟机启动，验证无运行时安装提示、无远程依赖下载、旧插件扫描仍正确。
6. 以未授权、普通用户、授权管理员分别运行，验证 Prefetch/4688 覆盖不足状态；不默认为每个员工静默提权。
7. 对照正式取证工具做隔离测试，确认 Prefetch 名称、执行时间、同名程序与路径有效性；没有用户同意不把任何第三方解析工具交付或安装到审计机。

## 官方参考

- https://dotnet.microsoft.com/en-us/download/dotnet/10.0
- https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview
- https://learn.microsoft.com/en-us/dotnet/core/tools/global-json
