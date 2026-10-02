# CheckSentry 安全审核报告

审核日期：2026-10-02。目录：`/Users/lee2/Documents/CheckSentry`。
仓库：<https://github.com/hubg9527777-dotcom/CheckSentry>。起始提交：`ba13f7a`。

## 1. 结论与范围

可安全修改的项目已修复并完成本机测试、Windows x64 编译和自包含发布验证。开发者随后批准了自动会话验证和 Actions 主版本升级，实施及复核见第 8 节；第 2～5 节保留首次审核的版本、告警和决策基线。仍有上游依赖告警及旧组件迁移问题，不能据此宣称“没有漏洞”或“所有告警已消失”。

本项目是 PowerShell 扫描程序、.NET 8 Windows 启动器和原生 HTML/JavaScript 本地页面，不是 Electron、浏览器扩展或云端 Web 服务。HTTP 服务使用 `HttpListener`，绑定 `localhost`；工作簿使用 ImportExcel/EPPlus。没有应用级 npm、Python、Go、Rust、Java 等依赖清单；C# 没有显式 `PackageReference` 或已提交的 NuGet 锁文件。Node 仅用于页面语法测试。

范围包括三个应用 PowerShell 文件、启动器、构建/依赖准备脚本、两个页面、BAT、测试、两个工作流、Dependabot、manifest、文档、模板、随包模块、可见本地 Git 历史，以及本地但不纳入 Git 的 `GoogleAppsScript.gs`。起始 290 个受控文件；凭据扫描覆盖 275 个可读文本文件、约 313 万字符的本地历史，以及 18 个工作簿/二进制文件的常见密钥特征。第三方模块按导入链、实际调用和危险操作审查；其所有样例不等于应用可达入口。

没有访问开发者真实云端清单、修改 GitHub 设置、提交代码、打 Tag、发布 Release、安装系统包或轮换密钥。远端分支未取回的历史、GitHub Secrets、旧 Release/Actions 私有产物、用户 Windows 系统补丁和浏览器实际运行行为属于“待确认”。本机为 macOS arm64，Windows 专属动态测试不在已通过范围内。

## 2. 全部直接依赖与关键实际版本

| 依赖/工具 | 实际版本或固定提交 | 说明 |
|---|---|---|
| ImportExcel | 7.8.10 | 唯一直接第三方应用模块，随包离线提供 |
| EPPlus.dll | AssemblyVersion / FileVersion 均为 4.5.3.2 | ImportExcel 的实际二进制依赖，不是根据 NuGet 最新版猜测 |
| .NET 启动器 | net8.0-windows；本次 SDK 8.0.425 / Runtime 8.0.31 | 新增 global.json 固定稳定 8.0.4xx 补丁基线 |
| Microsoft.NET.ILLink.Tasks | 8.0.31 | 本次自包含构建 assets 文件中的间接工具包 |
| Windows PowerShell | 系统提供的 5.1 | EXE 调用 System32 路径；.NET Framework 补丁随 Windows，用户电脑实际状态待确认 |
| actions/checkout | 4.3.1 / 34e114876b0b11c390a56381ad16ebd13914f8d5 | 本次由 4.2.2 非破坏性更新 |
| actions/setup-dotnet | 4.3.1 / 67a3573c9a986a3f9c594539f4ab511d57bb3ce9 | 保持原主版本 |
| github/codeql-action | 4.38.2 / 2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2 | init/analyze 共用同一提交 |
| actions/upload-artifact | 4.6.2 / ea165f8d65b6e75b540449e92b4886f43607fa02 | 保持原主版本 |
| actions/download-artifact | 4.3.0 / d3f86a106a0bac45b974a628896c90dbdf5c8093 | 保持原主版本 |
| actions/attest-build-provenance | 2.4.0 / e8998f949152b193b063cb0ec769d69d929409be | 旧上游 package.json 版本字符串不能当成 Action Tag 版本 |
| node / gh / signtool | 测试或 CI/Windows SDK 提供，未锁具体补丁 | 本次 Node 26.4.0；真实签名未执行 |

Actions 属于构建依赖，不会被打包进桌面 EXE。固定提交的上游锁文件已经读取，并分别执行 `npm audit --omit=dev --ignore-scripts`，没有安装或运行其 npm 脚本。全部上游直接依赖的声明/实际版本、生产依赖路径、漏洞链接及审计结果保存在 [SECURITY-DEPENDENCIES.json](./SECURITY-DEPENDENCIES.json)。该文件是审计证据，不是本项目新增的应用锁文件。

| Action | 关键间接依赖实际版本 | npm audit 包级结果 Critical / High / Moderate |
|---|---|---|
| checkout 4.3.1 | undici 5.29.0 | 0 / 1 / 5 |
| setup-dotnet 4.3.1 | fast-xml-parser 4.4.1；form-data 2.5.1、4.0.0；undici 5.28.5；brace-expansion 1.1.11；minimatch 3.1.2 | 2 / 3 / 10 |
| codeql-action 4.38.2 | node-forge 1.4.0；undici 6.28.0；brace-expansion 1.1.18、2.1.4、5.0.9 | 0 / 3 / 0 |
| upload-artifact 4.6.2 | form-data 4.0.0；undici 5.28.4；minimatch 9.0.3；cross-spawn 7.0.3；glob 10.3.12；lodash 4.17.21 | 1 / 6 / 10 |
| download-artifact 4.3.0 | 上述部分组件；unzip-stream 0.3.1 | 1 / 7 / 11 |
| attest-build-provenance 2.4.0 | tar 7.4.3；undici 5.29.0；@sigstore/core 2.0.0；glob 10.4.5；minimatch 9.0.5 | 1 / 5 / 7 |

这些计数包含重复依赖链和传导告警，不代表同等数量的独立、已证实可利用漏洞；上游锁文件与发行版 dist bundle 的完全对应及每条间接调用可达性仍需核验。

ImportExcel 官方 Gallery 的当前版本仍为 7.8.10，发布日期为 2024-10-21；属于长期未发布新版的关注项，但没有依据认定其已经停止维护。EPPlus 4.x 是旧系列。没有发现依赖名称疑似仿冒的证据。[ImportExcel 官方版本](https://www.powershellgallery.com/packages/ImportExcel/7.8.10)、[EPPlus 官方安全公告](https://www.epplussoftware.com/en/Security/Vulnerabilities)。

对实际 EPPlus 4.5.3.2 查询 OSV，返回空结果；GitHub Advisory/NVD 相关检索未确认针对这个实际版本的公告。新版 EPPlus 的 System.Text.Json/System.Security.Cryptography.Xml 公告不能直接套用到这个 DLL。未发现公告不等于旧版安全。NuGet 自包含项目审计没有报告易受攻击包，但不会覆盖这个手工随包 DLL，也不会覆盖 PowerShell Gallery 模块。

### Critical/High 告警的适用性与修复版本

| 组件/公告 | 影响条件与项目实际情况 | 公告修复版本/处理 |
|---|---|---|
| fast-xml-parser，[GHSA-m7jm-9gc2-mpf2](https://github.com/advisories/GHSA-m7jm-9gc2-mpf2) Critical | setup-dotnet 的认证辅助代码读取 NuGet.config；当前工作流没有传 source-url，未确认进入受影响解析路径，也没有把其结果渲染到网页 | 4.5.4 / 5.3.5 修复该条；还有其他公告，不能仅按此最低版本修复所有问题。Action 内部依赖不能在本仓库改锁文件来修复 |
| form-data，[GHSA-fjxv-7rqg-78g4](https://github.com/advisories/GHSA-fjxv-7rqg-78g4) Critical | 需要攻击者控制 multipart 字段并观测随机输出；本工作流没有主动发出这类请求，上游模块间接可达性待确认 | 2.5.4 / 3.0.4 / 4.0.4 修复该条；证据清单另有后续告警 |
| tar，[GHSA-23hp-3jrh-7fpw](https://github.com/advisories/GHSA-23hp-3jrh-7fpw) Critical | 需要解包恶意 tar；项目仅生成 ZIP，证书证明 Action 间接 tar 调用是否触达攻击者内容待确认 | 7.5.19 修复该条，其他后续 tar 告警需要更高补丁，见证据清单 |
| node-forge，[GHSA-86w9-cpqp-85rv](https://github.com/advisories/GHSA-86w9-cpqp-85rv) High | 需要用易受影响的低指数 RSA 路径验证恶意签名；CodeQL 的具体调用条件待确认，不是本程序的密码哈希实现 | 官方公告目前无修复版本；不能声称升级某个版本即可解决 |
| undici 6.28.0，[GHSA-rfgv-xxqx-mfg5](https://github.com/advisories/GHSA-rfgv-xxqx-mfg5) High | 需要连接恶意 WebSocket；本项目未配置 WebSocket；CodeQL 间接调用待确认。其他 undici 告警条件不同 | 6.28.1 / 7.29.1 / 8.10.2 修复该条；旧 Action 包里的 5.x 不能自行跨主版本替换 |
| unzip-stream 0.3.1，[GHSA-6jrj-vc65-c983](https://github.com/advisories/GHSA-6jrj-vc65-c983) High | Extract 处理恶意 ZIP；release 下载的是同一次受信任 Tag 构建的 artifact，没有跨 PR/workflow_run 下载，但不能仅因此把组件视为已修复 | 0.3.2；download-artifact 内部需由上游升级。Action 已避开旧 download-artifact 自身 [GHSA-cxww-7g56-2vh6](https://github.com/advisories/GHSA-cxww-7g56-2vh6)，但旧间接包告警另算 |
| brace-expansion / minimatch High | 需要可控的高复杂度展开模式；工作流使用固定 ZIP 路径。恶意文件名的影响及上游匹配实现仍待确认 | 全部受影响范围和官方链接见证据清单；不是应用正则匹配漏洞 |
| glob High | 相关命令注入公告需要其 CLI 命令执行选项；当前工作流未调用 glob CLI 的命令选项 | 不认定当前已可命令注入；仍应由上游更新 |
| cross-spawn / lodash High | 分别需要病态输入或特定原型污染使用；没有发现应用级直接调用，Action bundle 路径待确认 | 保留在供应链清单，不把它们算作桌面程序已证实入口 |

## 3. 问题汇总

表中依赖项严重级别采用公告最高等级；本项目可利用性不确定的已另行标记。

| 编号 | 类别 | 严重级别 | 位置 | 状态 |
|---|---|---|---|---|
| D01 | 依赖 | Critical | .github/workflows/build-release.yml:25、48、75、89；上游 Actions 锁文件 | 待开发者决定；调用可达性待确认 |
| D02 | 依赖 | High | CodeQL Action 固定提交的 node-forge 1.4.0 | 待开发者决定；无修复版本、可达性待确认 |
| D03 | 依赖 | Medium | Modules/ImportExcel/7.8.10/EPPlus.dll；global.json:3 | 建议关注旧组件与 .NET 生命周期 |
| C01 | 代码 | Medium | Start-ComplianceCheck.ps1:1310 | 已修复：下载跳转前校验 |
| C02 | 代码 | Medium | Start-ComplianceCheck.ps1:488、519、1251 | 已修复：XML/压缩包资源限制加固 |
| C03 | 代码 | Medium | Start-ComplianceCheck.ps1:3275；report_template.html:651 | 已修复：重新扫描改为令牌保护 POST |
| C04 | 代码 | High | Prepare-Dependencies.ps1:6、20 | 已修复：不可信模块包在校验前进入加载路径 |
| C05 | 代码 | Medium | Start-ComplianceCheck.ps1:68 | 已修复：额外可执行模块文件遗漏校验 |
| C06 | 代码 | Medium | launcher/Program.cs:123、153、210 | 已加固：拒绝重解析点，停止递归删除旧目录；竞态风险仍见下文 |
| C07 | 代码 | Medium | Build-Release.ps1:12 | 已修复：任意非空输出目录递归删除 |
| C08 | 代码 | Medium | Get-InstalledSoftware.ps1:26；Start-ComplianceCheck.ps1:2647 | 已修复直接网络图标访问；浏览器远程配置路径另需决定 |
| C09 | 代码 | Medium | Get-InstalledExtensions.ps1:47；Start-ComplianceCheck.ps1:2647 | 已修复：JSON/图片读入前缺少大小限制 |
| C10 | 代码 | Medium | GoogleAppsScript.gs:542、549、561 | 已修复：删除记录的文本再解释为公式 |
| C11 | 代码 | Low | launcher/Program.cs:15、78；两个 PowerShell 原生 API 声明 | 已修复签名与异常日志加固；不宣称消除 P/Invoke 告警 |
| C12 | 代码 | High | Start-ComplianceCheck.ps1:3189、3234、3296 | 待开发者决定：本地多用户访问隔离 |
| C13 | 代码 | Medium | Start-ComplianceCheck.ps1:1032、3290 | 待开发者决定：密码迁移和尝试限速 |
| C14 | 代码 | Medium | Build-Release.ps1:47 | 待开发者决定：签名密码出现在子进程参数 |
| C15 | 代码 | Medium | Start-ComplianceCheck.ps1:89；Get-InstalledExtensions.ps1:270、500 | 待开发者决定：未校验模块回退、浏览器网络路径 |
| C16 | 代码 | Low | Start-ComplianceCheck.ps1:3189、3082 | 建议关注：单线程处理和慢请求可用性 |
| K01 | 密钥 | Low | .gitignore:22；.github/workflows/build-release.yml:72 | 已加固：敏感文件忽略、证书 finally 清理 |

## 4. 每项已修复问题：原因、条件和改动

### C01：云端下载只在自动跳转后检查主机

旧实现已经把请求发往跳转目标才检查最终主机，不能防止中间跳转或 HTTPS 降级访问。攻击者必须能影响受信 Google 导出响应或其跳转链；未证实存在可滥用的 Google 跳转入口，因此不是已经复现的任意 SSRF。

改为最多五次手动跳转，每次发请求前检查 HTTPS、443、空用户凭据和精确 Google 主机/带点后缀；初始 Sheets 链接也拒绝自定义端口和 userinfo。未关闭 TLS 证书验证。

### C02：XML 与压缩包限制不完整

恶意/损坏的 XLSX 可以耗费内存和 CPU；原实现主要统计 ZIP 声明长度，XML 解析没有显式统一 DTD/实体策略。本次没有把未复现的外部实体访问直接认定为已发生的 XXE。

新增 100 MB 文件和实际解压上限、10000 条目上限、重复条目拒绝。云端所有 XML/rels 在 EPPlus 读取前禁用 DTD、外部解析器并限制字符数；本地工作簿和兼容修复也先做资源限制。兼容修复允许先处理既有命名空间问题，再执行完整 XML 校验，不通过关闭安全校验来修复工作簿。

### C03：GET 请求执行同步/扫描

运行中的本地程序可被外部网页诱导访问 `/?refresh=1`，旧代码由此触发同步和扫描，造成非预期操作/阻塞。

删除这个 GET 写操作，使用 `/api/scan` POST，并复用 JSON Content-Type、CSRF Token 和 Origin 验证；按钮在执行期间禁用，失败后恢复。扫描/分类业务规则不变。普通报告 GET 仍保留既有“自动加入待定”的业务行为，它不是完整鉴权边界，见 C12。

### C04/C05：依赖包信任链

旧 Prepare 脚本先删除现有模块，再解压用户提供的包并调用 Test-ModuleManifest。攻击者若能替换下载包或诱导开发者传入恶意包，可能在验证前进入程序集/模块加载路径。

已对官方 Gallery 7.8.10 包重新下载比对，SHA-256 与随包记录完全一致：`d8a1d79dc8cf10c0eea30b68b70459b3fb4cac0042fb756fcb23890671857e4c`。脚本固定这条审核基线，先比对再解压，使用临时目录准备成功后才切换；原模块保留为 `.tmp` 备份，切换失败恢复。

应用模块加载除了验证清单中的哈希，还拒绝未列入清单的 ps1/psm1/psd1/dll，避免第三方 psm1 的通配导入加载额外脚本。哈希清单是完整性检查，不是签名；能同时改清单和文件的同权限本地攻击者仍可绕过，不能把它称作本地抗篡改保护。

### C06/C07：文件路径和清理

Path.Join/Combine 的字符串边界校验不能检测目录联接、符号链接。共享可写目录中的攻击者可能预先放置链接，将资源写入别处。现在释放资源、迁移来源/目的和日志路径都检查重解析点；资源拒绝绝对路径、冒号及越界规范化路径。失败的临时资源文件清理。旧 LocalAppData Runtime 不再递归删除，保留给用户核实后清理。

构建脚本不再递归删除 OutputDirectory；拒绝项目目录/祖先、链接目录和非空输出目录，并验证 Version，防止路径片段注入。重新本地构建时需要新的空输出目录；已存在的输出不会被自动清空。

这些检查不能彻底消除同权限进程在检查与写入之间换目录的竞态，也不能保护被其他用户写入的便携软件包。请不要从不受信共享可写目录或管理员权限运行。

### C08/C09：图标和浏览器输入

注册表 DisplayIcon、卸载字符串或快捷方式目标若直接指向 UNC/WebDAV 网络路径，扫描时可能触发远程访问及 Windows 身份验证。现在软件图标解析和最终图标读取在文件操作前拒绝直接网络/URL/设备前缀；只影响远程图标，不改变软件去重或名称/版本分类。浏览器自定义网络配置路径及链接间接跳转仍见 C15。

浏览器 JSON 原来 ReadToEnd 没有限制；现在文件/字符上限为 32 MB，超过则由既有容错机制跳过并保留错误线索。非 EXE/DLL 图标先检查 512 KB，避免先读完整大文件再判断；图标仍按既有缓存/懒加载方式工作。

### C10：Google Apps 删除记录公式注入

`getDisplayValues()` 取得的文本若以 `=` 开头，重新 `setValues()` 会把它当作公式。拥有表格编辑权限的输入者可让备份/迁移记录执行意外公式。

删除备份和旧记录迁移使用统一安全转换，给这类文本加文本前缀，保留原来的 A:K 11 列和 L 列删除时间；数值、Date 和普通文本不变。脚本仍由 .gitignore 排除，没有加入 EXE 或 GitHub。

### C11：启动器告警

保留用户已有的 Path.Join、System32 DLL 搜索限制及错误处理修改；新增 BOOL 返回值封送、原生控制台调用返回码检查、完整异常堆栈，以及资源/迁移安全检查。PowerShell 中 shell32/msi 的 Unicode 入口明确为 W 版本，系统 DLL 限定 System32。

固定相对子路径没有以斜杠开头的问题；动态资源采用“拒绝绝对路径 + GetFullPath + 根目录包含校验”，没有用 TrimStart 把恶意绝对路径静默变成有效路径。

Main 和最终错误提示处保留通用 Exception 捕获，因为这是进程最外层失败保护；现在记录完整上下文，而非只有 Message。P/Invoke 本身属于设计必要能力，不是漏洞；CodeQL 仍可能给出非托管代码提示，需逐条审阅而不是为了清零删功能。没有在本机运行 GitHub CodeQL，不能保证 28 处告警全部消失。

### K01：敏感信息与 CI 清理

当前和本地历史中没有找到真实 API Key、Token、密码或私钥。两处疑似连接串以及历史对应项均是 ImportExcel 无密码的 Excel/OLE DB 示例。二进制/工作簿常见密钥特征扫描也没有命中；不代表排除了任意编码或未知形式的秘密。

新增 .env、私钥/证书、日志、运行目录和 dist-* 忽略；原有 list.xlsx、云端设置、密码设置及 Apps 脚本忽略保持不变。`.env.example` 只提供两个 GitHub signing secret 名称，没有真实值；程序不会自动加载这个文件，需要在 GitHub 仓库 Secrets 配置。签名证书即使构建失败也在 finally 删除；checkout 不再持久化 Git 凭据。

如果密钥曾被提交、发到聊天或打入旧产物，必须到平台撤销并重新生成；只删文件、忽略文件或清 Git 历史都不能替代轮换。本次没有发现必须立即轮换的具体密钥。

## 5. 需要开发者决定的事项

### A. Actions 升级/没有修复版的依赖（D01/D02）

选择一：保持现有主版本，接受记录中的供应链告警，继续限制只下载同一次受信 Tag 的产物。风险：旧间接依赖仍在，不是完全修复。

选择二（建议）：批准升级需要变化的 Actions 主版本，逐个核对 Node/runner 最低要求、输入及产物行为，固定提交并重新审核其实际 bundle；无修复版 node-forge 单独作可达性评估，必要时采用上游规避方案。不要在本项目新增一个 package-lock 来假装修好了远端 Action。

checkout 已安全更新到非破坏性 4.3.1；4.4.0 官方标注破坏性 PR 安全默认值变更，自动安全审查拒绝采用。本次未绕过该限制。CodeQL 4.38.2、upload 4.6.2、download 4.3.0、setup 4.3.1 已是查询时对应主版本的最新发布，继续更新部分依赖需要改主版本或等待上游。

### B. 本地访问控制（C12）

利用条件：同一 Windows 主机存在不可信的其他登录用户/本地程序，尤其 CheckSentry 被提升权限启动时。任意可连接 localhost 的本地客户端能 GET /manage 取得 CSRF token，再调用允许的维护接口；CSRF token 防网站跨站请求，不是本地用户认证。接管状态也是进程级共享状态，密码目前只保护特定元数据操作，并非整个界面。

选择一：明确只支持单一可信用户、普通权限使用，保持现在无需登录的便捷方式。

选择二（建议）：增加每次启动的秘密引导和浏览器会话，所有敏感 GET/POST 验证会话，接管按会话隔离；需要同时调整加载页面、自动打开浏览器和多标签体验。若需要隔离不同 Windows 用户，还应评估 Windows 身份验证/受 ACL 保护的本地 IPC。未擅自加登录或改变接管权限。

### C. 密码格式/限速（C13）

现有记录使用随机 16 字节盐、PBKDF2-HMAC-SHA1 120000 次及固定长度比较，不是明文密码；但离线猜测成本和在线尝试限制不足。用户文件本身可被拥有写权限的人改掉，所以它不是抵抗同权限恶意进程的强安全边界。

选择一：暂保留旧格式，加强 Windows 文件权限并要求不复用其他平台密码。

选择二（建议）：设计兼容迁移，旧密码成功验证后升级为带算法字段的 PBKDF2-HMAC-SHA256，并基准测试工作因子、失败限速和会话隔离；不删除现有设置/强制重置。[OWASP 密码存储建议](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)。

### D. 签名密码（C14）

signtool `/p` 会让有权限查看子进程参数的本地进程看到证书密码。GitHub 日志 masking 不会隐藏 OS 进程参数。当前托管隔离 runner 降低了风险，但不建议在多用户自托管 runner 使用。

选择一：保留 PFX/密码方案，只在可信临时 runner 签名。

选择二（建议）：使用受控 Windows 证书存储或远程签名服务，不通过命令行传密码；涉及证书部署、私钥权限和签名验证，需要开发者选择方案。没有轮换现有证书或改签名供应商。

### E. 模块回退与远程浏览器路径（C15）

随包模块缺失时仍有原来的 CurrentUser 安装/已有同名模块回退，这条路径没有随包 CONTENT-SHA256 校验。另有 Chromium 配置路径、Firefox profiles.ini 可引用网络目录，读取时可能触发 SMB/卡顿；拒绝全部网络配置会影响真实装在网络盘的开发模式插件。

建议批准后：只允许经过固定包哈希校验的离线模块；随包文件缺失时显示修复提示，不偷偷改用其他安装。浏览器默认只扫描本地路径，对网络路径显式提示/选择。没有直接删除用户模块或静默遗漏网络插件。

### F. 组件生命周期与扫描可信度

.NET 8 预计 2026-11-10 结束支持，之后应规划迁到受支持 LTS；这是大版本升级，未擅自执行。本次仍使用官方安全补丁 8.0.31，并确保不被机器上预装的其他主版本 SDK 意外接管。[微软生命周期](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core)、[8.0.31 发布记录](https://github.com/dotnet/core/blob/main/release-notes/8.0/8.0.31/8.0.31.md)。

EPPlus 升级需评估 ImportExcel 兼容性和许可证；可选继续隔离旧解析器、迁移现代工作簿库或购买/采用合适授权，不直接把新版 DLL 塞进旧模块。

插件 ID、manifest 作者、注册表软件发布者都是识别信息，不是正版/签名保证；开发模式插件可以声明公共 key 来形成指定 ID。若需要安全真实性判定，应另加开发模式/签名/来源风险展示及可选严格策略，而不是把同名或 ID 变化自动当作恶意。这个改变涉及现有白名单业务，未擅自更改。

## 6. 已检查但未确认漏洞的入口

- 未发现应用执行规则文本、SQL/NoSQL 拼接、eval、反序列化任意对象或网络下载代码后执行的应用入口。第三方样例中动态表达式和数据库 API 不在应用调用链上，未因此批量修改第三方代码。
- HTTP POST 已有 JSON 类型、CSRF、Origin 和正文上限；本次验证跨源与错误令牌拒绝。没有 `Access-Control-Allow-Origin: *`，没有网络监听地址扩展，也没有公网访问鉴权保证。
- HTML 文本/属性已有编码，备注链接限制 HTTP/HTTPS 且无 userinfo，采用 noopener/noreferrer；已测试脚本/事件属性输入按文本处理。CSP、禁止 frame 和 nosniff 保留。
- 扫描读取扩展 manifest，不运行其代码；项目没有自己的 extension permissions/host_permissions 或消息接收器，因此对应扩展权限审查不适用。
- 没有 Electron nodeIntegration/WebView 或原生 IPC 接口；桌面信任边界主要是进程、localhost、便携目录和工作簿。
- 没有 pull_request_target/workflow_run 跨信任发布；Action 固定 SHA，默认 token 只读，发布写权限按 job 限定。CodeQL 成功作为 Tag 发布前置条件保留。
- 规则正则已有 250 ms 超时；这不排除大量合法规则累计耗时。单线程请求、云端重试、慢请求仍可能影响可用性，建议后续做队列/总时限和 Windows HTTP.sys 超时测试，不贸然修改业务并发。
- 误差风险包括损坏/过大浏览器配置被跳过、历史残留文件、浏览器正在写入、metadata 伪造及开发者模式状态；UI 的扫描结果不等于防恶意软件执行的安全控制。

## 7. 测试与交付

本次使用隔离的临时 PowerShell 7.6.6 和官方 .NET SDK 8.0.425；没有要求用户电脑额外安装 PowerShell 来运行 EXE。

| 检查 | 结果 |
|---|---|
| tests/Run-Tests.ps1 原有分类/插件/同步/工作簿/后台扫描回归 | 通过 |
| tests/Security-Tests.ps1 | 通过：下载 URI、跨源请求、错误令牌、超大流式 JSON、DTD XLSX、网络图标、超大浏览器 JSON、错误模块包、构建路径与文件保留 |
| 两个页面 JavaScript 语法与刷新入口检查 | 通过 |
| 本地 GoogleAppsScript.gs 语法及公式转换 | 通过；没有连接或写入真实 Google 表格 |
| Windows x64 启动器编译 | 0 警告、0 错误 |
| Windows x64 自包含 EXE 发布 | 通过 |
| 项目原有 Build-Release.ps1：EXE、ZIP、SHA-256 | 通过；测试产物只在临时目录，未发布 |
| NuGet vulnerability 检查 | 没有报告易受攻击包；不覆盖手工 DLL |
| 6 个 Actions 上游 npm audit | 已执行；未消除的告警见依赖证据文件 |
| git diff --check | 通过 |
| Windows PowerShell 5.1 / 真机/ARM VM / P/Invoke 动态调用 | 待确认；已新增 Windows PowerShell 5.1 CI 回归步骤 |
| Authenticode 签名/真实 Google 同步/在线 CodeQL | 待确认；没有可用签名证书或运行真实用户云端数据 |

macOS 的 ImportExcel AutoFit/libgdiplus 警告是非目标平台图形能力警告，未导致测试失败，未为此安装系统包。历史 TESTING.md 中的其他工具结论没有冒充成本次重新执行结果。

本次改动均在工作区，保留了用户原来的启动器修改；没有提交、推送、重发版本或更改云端规则。所有业务规则（同名不同发布者保留、ID 精确白名单、空规则进入待定、同步事务、日期格式）保持原测试约束。待开发者决定事项应先明确选择，再继续实现和验收。

## 8. 经批准的补充修复与当前状态

### 自动会话验证（C12）

已在 `Start-ComplianceCheck.ps1:3189` 增加随机启动秘密和浏览器会话。启动器自动打开带片段的链接，页面自动验证、移除地址栏片段并进入原进度页，不新增登录操作。启动秘密不进入 HTTP URL/查询日志，也不嵌入匿名网页。GET/POST 敏感入口均先检查会话；每个会话单独生成 CSRF 令牌；接管权限按会话保存，同一浏览器多个标签页继续共享。Cookie 为 HttpOnly、SameSite=Strict，服务仍只监听本机 HTTP。

原扫描、软件/插件分类、图标、云端同步、11 列规则格式及便携数据位置未改变。手动访问须使用启动窗口的完整链接；重启后旧会话失效。启动链接本身包含秘密，不应发给其他人。实现设置了 64 个会话上限以约束内存。

状态：已修复匿名读取和跨浏览器接管权限继承。此方案不是 Windows 用户身份验证：同机恶意软件、能读取启动窗口/进程的用户，以及 localhost Cookie 不隔离端口的浏览器机制仍有局限；需要强多用户隔离时，Windows 身份验证/ACL IPC 仍待决定。没有声称 Cookie 可以隔离所有本机攻击者。

### Actions 主版本升级（D01）

根据官方发布提交升级并固定 SHA：[checkout 7.0.1](https://github.com/actions/checkout/releases/tag/v7.0.1)、[setup-dotnet 6.0.0](https://github.com/actions/setup-dotnet/releases/tag/v6.0.0)、[upload-artifact 7.0.1](https://github.com/actions/upload-artifact/releases/tag/v7.0.1)、[download-artifact 8.0.1](https://github.com/actions/download-artifact/releases/tag/v8.0.1)、[attest-build-provenance 4.2.2](https://github.com/actions/attest-build-provenance/releases/tag/v4.2.2)。新版使用 Node 24；项目均为 GitHub 托管 windows-latest/ubuntu-latest，未引入自托管 runner 升级需求。setup 输入保留；artifact 显式 `archive: true` 保持 ZIP/校验文件组合，下载继续解压并合并；Tag 发布继续等待 CodeQL 成功。CodeQL 4.38.2 保留，不关闭扫描。

已重新查询升级提交的实际锁文件并执行 `npm audit --omit=dev --ignore-scripts`，不安装、不执行上游依赖脚本。证据在 `SECURITY-DEPENDENCIES-UPDATED.json`；原始证据文件保留用于对照。attest-build-provenance 新版是 composite，实际执行其固定的 actions/attest 4.2.1，也纳入复核。

| 当前上游锁文件 | Critical | High | Moderate |
|---|---:|---:|---:|
| checkout 7.0.1 | 0 | 1 | 0 |
| setup-dotnet 6.0.0 | 0 | 3 | 0 |
| CodeQL 4.38.2 | 0 | 3 | 0 |
| upload-artifact 7.0.1 | 0 | 5 | 0 |
| download-artifact 8.0.1 | 1 | 5 | 0 |
| attest 4.2.1 | 0 | 3 | 4 |

升级不等于零告警。download-artifact 的 fast-xml-parser 仍命中 [GHSA-m7jm-9gc2-mpf2](https://github.com/advisories/GHSA-m7jm-9gc2-mpf2)，此外仍有 undici、brace-expansion、lodash 等告警；CodeQL 的无修复版 node-forge 告警保留。锁文件告警不证明预编译 bundle 的实际利用链，可达性仍标记待确认。下载只取本次受信任构建产物，通配符为固定维护者输入，没有跨 PR 下载。不能在本项目改一个 npm 锁文件就修复远端 Action。

后续选项：继续固定官方版本并跟踪上游补丁（建议，功能影响最低）；或维护自有 Action 分支重新构建 bundle 并验证，其维护、供应链和签名成本需要单独批准。未自行删除上传/下载、签名证明或 CodeQL 功能。

### 补充验收

原有 `tests/Run-Tests.ps1` 与扩展的 `Security-Tests.ps1` 全部通过。新增 `tests/check-session.js` 启动真实回环 HTTP 服务，验证匿名 API/维护页拒绝、错误令牌拒绝、正确会话进入进度页、刷新及错误 Cookie 拒绝；已通过，并加入 Windows CI。Windows x64 自包含 EXE、ZIP、SHA-256 已重新完整构建成功，产物位于临时目录 `release-session-verified`，没有发布。

Windows PowerShell 5.1 真机浏览器/原生扫描、实际 Google 同步、签名及 GitHub 在线工作流仍待确认。代码与业务回归已通过，不把未执行的 Windows 真机验收写成已通过。
