# CheckSentry 1.2.0 — 安全审核与修复报告

- 审核日期：2026-11-07（美东时间；文件操作环境记录为 UTC）
- 审核基线：用户提供的 `CheckSentry-1.2.0-设计源码候选.zip`。本报告与补丁均基于该候选包，并非已验收的 Windows 正式可部署 EXE。
- **产品版本锁：永久保持 `1.2.0`，直至项目所有者另行明确授权。** .NET 运行时/SDK 安全补丁版本不是产品版本。
- 原则：先审查；只自动修复无需业务取舍的事项；其他高影响事项明确待开发者决定。
- 真实性边界：源码静态分析和部分 Node.js 测试已经完成；本环境无 Windows PowerShell 5.1、`pwsh`、.NET SDK，因此**未完成 Windows 实机测试、程序构建、签名及 Prefetch 实际解析准确率验收**。不得把这份报告理解为“安全性已认证”。

## 一、项目概况和范围

| 项目 | 识别结果 |
|---|---|
| 语言/框架 | C# / .NET 8 Windows 启动器、Windows PowerShell 5.1 脚本、原生 HTML/CSS/JavaScript 页面 |
| 产品版本 | 1.2.0（修复前后相同） |
| 构建 | .NET CLI + `Build-Release.ps1`，Windows `win-x64` self-contained single-file EXE；GitHub Actions 发布工作流 |
| 核心功能 | 已安装软件、浏览器扩展、历史运行记录核对；本地 HttpListener 报告页面；Excel 黑白名单与 Google Sheets XLSX 同步 |
| 包管理 | 无项目 `package.json` / npm lock / requirements.txt / go.mod / Cargo.toml 等；`.csproj` 中 **0 个显式 NuGet PackageReference**；PowerShell `ImportExcel` 第三方模块随包 vendored |
| 审核范围 | 根目录脚本与页面、`launcher/`、`tests/`、`.github/`、随包 `Modules/ImportExcel/7.8.10`、文档、配置及分发脚本；共约 300 个源文件与第三方资源 |
| 历史依赖数据 | `SECURITY-DEPENDENCIES[-UPDATED].json` 是 GitHub Actions 上游仓库的历史 lockfile 快照，**不是此项目自身生产运行环境的 package-lock** |

### 直接依赖及可确认版本

| 类别 | 依赖 | 已确认版本 | 审核状态 |
|---|---|---|---|
| 编译 SDK | .NET SDK | 原 `8.0.425` → 已改最低 `8.0.427` | 解决已知旧补丁风险，等待重新发布 |
| 运行时 | .NET Runtime | `net8.0-windows`，单文件自包含；实际打包补丁版本须核实 | 待 Windows `dotnet publish` 核验 |
| 系统 | Windows PowerShell | 目标 5.1 | 系统内置组件，具体机器版本待查 |
| PowerShell 模块 | ImportExcel | **7.8.10** | 作为项目内随包依赖，文件 SHA-256 清单一致 |
| 间接二进制库 | EPPlus.dll | **实际 AssemblyVersion 待确认**（不能用 ImportExcel 7.8.10 冒充 EPPlus 版本） | 有近期安全公告，需 Windows/IL 元数据核对 |
| NuGet | C# 第三方 `PackageReference` | **0** | 无锁定 NuGet 依赖可做逐包 NuGet audit |
| CI GitHub Action | `actions/checkout` | v7.0.1；已固定 commit SHA | 已核对流程使用方式 |
| CI GitHub Action | `actions/setup-dotnet` | v6.0.0；已固定 commit SHA | 指向 `8.0.x`，同时由 global.json 锁补丁最低版 |
| CI GitHub Action | `github/codeql-action` | v4.38.2；已固定 commit SHA | CodeQL C# 安全扫描 |
| CI GitHub Action | `actions/upload-artifact` | v7.0.1；已固定 commit SHA | 上传构建产物 |
| CI GitHub Action | `actions/download-artifact` | v8.0.1；已固定 commit SHA | 拉取 CI 产物 |
| CI GitHub Action | `actions/attest-build-provenance` | v4.2.2；已固定 commit SHA | 发布包来源证明 |

其余上游 Actions 间接依赖的包名、历史锁文件版本和路径见 `SECURITY-DEPENDENCY-INVENTORY-2026-11-07.json` 及原 `SECURITY-DEPENDENCIES-UPDATED.json`。例如上游 **2026-10-02 快照**含 `brace-expansion 1.1.15 / 5.0.6`、`undici 6.27.0`，但不能仅凭上游源码快照推断当前已固定 Action 的预编译执行代码会走到漏洞函数。相关未确认项见 R-08。

### 本次安全公告核对（截至 2026-11-07）

1. **Microsoft .NET 8**：2026-10-25 官方发布 `8.0.33`（SDK `8.0.427`），修复 `CVE-2026-111497` 等安全问题。对 self-contained 单文件应用，必须**重新构建发布**才能替换随包运行时，用户在系统安装新版 .NET 并不能修好旧 EXE。来源：<https://github.com/dotnet/core/blob/main/release-notes/8.0/8.0.33/8.0.33.md>、<https://devblogs.microsoft.com/dotnet/dotnet-october-2026-oob-security-updates/>。
2. **.NET 8 支持期**：微软将于 **2026-11-10** 停止安全支持。升级到 .NET 10 属于**主版本迁移**，本次不擅自执行。来源：<https://devblogs.microsoft.com/dotnet/dotnet-8-9-end-of-support/>。
3. **EPPlus**：厂商在 2026-10 发布 `GHSA-f4h2-2r6m-w59r` 及若干安全修复，许多 EPPlus 7.x/8.x 子分支存在补丁版。**本项目随包 DLL 的真正 EPPlus AssemblyVersion 尚未确认**，且是否使用漏洞功能尚需核查；不能据此宣称本项目已确认漏洞命中。参考：<https://epplussoftware.com/en/Developers/MinorFeaturesAndIssues>、<https://www.epplussoftware.com/en/Security/VulnerabilityDetail?id=18&returnEi=&returnVersion=>。
4. **CI 快照 `brace-expansion`**：GitHub Advisory `GHSA-3jxr-9vmj-r5cp` 影响 `<1.1.16`、`2.0.0–<2.1.2`、`3.0.0–<5.0.7`，漏洞前提是把攻击者可控字符串送入其扩展函数。当前 workflow 使用的是 SHA 固定的预编译 Action，不存在项目自身 npm lock 或直接导入；**待确认当前 Action 编译产物是否受影响、可否到达相关代码路径**。来源：<https://github.com/advisories/GHSA-3jxr-9vmj-r5cp>。
5. 其余 Actions 上游 transitive 依赖：历史安全扫描文件有清单，但不是可安装的项目 lockfile，也不能代替对当前上游 Action 发行包和可达性的审查。任何更换 SHA 都应经过兼容测试与供应链批准。

**维护与依赖名称核查**：未从当前直接依赖清单发现明显仿冒包名或名称混淆；ImportExcel 官方项目仍可定位，但“是否长期维护、随包二进制是否来自官方且未经替换”需要结合发布源和签名/SBOM 核实。唯一明确的支持周期问题是 .NET 8 于 2026-11-10 终止支持。旧的上游 Actions 历史依赖列表不能视为此构建的实时供应链保证。

**本地工具限制**：`npm audit` / `pip-audit` / `cargo audit` 等不适用于本项目（没有相应的依赖清单或包管理项目）；`dotnet restore` / NuGetAudit、Windows PowerShell 扫描与 CodeQL 需要 Windows CI 执行。本次不假装运行了这些工具。

## 二、问题汇总

严重级别评价中，“有条件”表示存在明确利用前提，并不意味着已经发现员工滥用或真实入侵。行号以**本次修改后的源码**为准。

| 编号 | 类别 | 级别 | 位置 | 状态 | 问题和利用条件 |
|---|---|---|---|---|---|
| R-01 | 依赖 | **High** | `global.json:3`; `launcher/CheckSentry.Launcher.csproj:4` | **已修改构建基线，发布待验收** | 旧 SDK `8.0.425` 含旧 8.0.31 运行时；自包含 EXE 若继续发布旧运行时会残留安全风险。改最低 `8.0.427`，须重构建确认 `8.0.33`。 |
| R-02 | 依赖 | **High（未来支持风险）** | `launcher/CheckSentry.Launcher.csproj:4` | **待开发者决定** | .NET 8 将于 2026-11-10 EOL。需评估 .NET 10 迁移，不能自动变更主版本。 |
| R-03 | 代码/鉴权 | **High（有条件）** | `Start-ComplianceCheck.ps1:3441-3465,3608-3630` | **待开发者决定** | 会话令牌 + CSRF 能防一般未授权跨站调用，但已能访问报告的会话可提交规则新增、删除、分类等本地清单更改；这不等于通过独立审计管理员身份验证。若员工获得报告会话并具备工作簿写入权限，可能篡改合规结果。 |
| R-04 | 代码/供应链 | **High（有条件）** | `Start-ComplianceCheck.ps1:1311-1324` 及云端规则加载逻辑 | **待开发者决定** | 云端规则目前信任受允许域名的 XLSX 与拥有电子表格编辑权的人；编辑者账号被攻破或被赋予错误权限可能污染合规政策。HTTPS、域名校验不等于规则内容签名。 |
| R-05 | 依赖 | **High / 待确认** | `Modules/ImportExcel/7.8.10/EPPlus.dll` | **待核验后决定** | EPPlus 近期官方安全修补；随包 DLL 真实版本无法可靠确定，需取得 AssemblyVersion、可达使用方式、允许的补丁分支和许可证影响。 |
| R-06 | 代码/执行 | **Medium（有条件）** | `Get-ExecutionHistory.ps1:187-204` | **待开发者决定** | 如果未来放入 `Tools\PECmd\PECmd.exe`，代码会执行它；目前不验证该二进制的数字签名和固定哈希。供应链被篡改可在审计机器上执行代码。原设计包不包含该文件。 |
| R-07 | 供应链 | **Medium（有条件）** | `Start-ComplianceCheck.ps1:90-107` | **待开发者决定** | 随包 ImportExcel 缺失时，会自动向 PowerShell Gallery 安装指定版本，绕开正常随包的完整性固定机制。建议企业正式版缺失即失败，不要临时联网下载。 |
| R-08 | 依赖/CI | **Medium / 待确认** | `.github/workflows/*.yml`; `SECURITY-DEPENDENCIES-UPDATED.json` | **建议关注** | 旧上游 Actions lock 快照含已公告漏洞的间接依赖；当前固定 Action 发行包及漏洞路径可达性未核实，不能断言生产程序受影响。 |
| R-09 | 代码/正确性 | **Medium** | `Get-ExecutionHistory.ps1:5-94,124-183` | **待 Windows 实测** | 自制 Prefetch 解析与路径推断尚未与成熟取证工具逐项核对；可能漏报或误归因，不应作为唯一员工违规证明。 |
| R-10 | 权限/数据 | **Medium（有条件）** | `launcher/Program.cs`、`Start-ComplianceCheck.ps1` 规则工作簿和设置文件路径处理 | **待开发者决定** | 如数据工作簿与设置文件落在员工可写目录，没有额外操作系统 ACL 或中心完整性验证时，可能从工具外直接修改规则。迁移存储位置会改变便携部署和原有数据，不能擅自更改。 |
| R-11 | 加密 | **Medium（长期改进）** | `Start-ComplianceCheck.ps1:1033-1067` | **待开发者决定** | 本地接管密码使用 PBKDF2-HMAC-SHA1、120,000 次、随机盐；不是明文密码，但算法参数旧，升级 SHA-256/迭代次数需要兼容旧记录迁移。 |
| R-12 | 敏感信息 | **Low** | `Start-ComplianceCheck.ps1:3420-3426` | **已修复** | 成功启动时常规终端输出包含带启动会话令牌的 URL；现改为只显示不含 token 的 localhost 地址。浏览器不能启动时仍有手动 URL 回退提示，属于保留的易用性取舍。 |
| R-13 | 版本/CI | **Low（治理）** | `Build-Release.ps1:12-14`; `.github/workflows/build-release.yml:5,82-88`; `special_template.html` | **已修复** | 原构建入口可通过 Version 参数发布非 1.2.0，CI 也允许任意 `v*.*.*` tag，专项页面仍显示 1.1.5。已统一锁 1.2.0。 |
| R-14 | 测试 | **Low** | `.github/workflows/build-release.yml` | **已修复** | CI 中补入现有历史记录静态集成检查，并加入 1.2.0 版本与 SDK 安全补丁基线校验。 |
| R-15 | 发布链 | **Medium（有条件）** | `Build-Release.ps1:45-58`、CI 签名凭据 | **待开发者决定** | 未提供签名证书时构建可产出未签名 EXE。是否强制正式 release 必须签名取决于公司发布策略。 |

**目前没有证据确认已存在 Critical 漏洞。** 没有发现可以直接复现的 SQL/NoSQL 注入（没有数据库层）、开放 CORS、公开的外网 HTTP 监听、明确的任意命令执行入口或硬编码生产密钥。此结论仅限本次源码静态检查，非漏洞不存在保证。

## 三、本次已直接修复的改动

1. `global.json`：`.NET SDK 8.0.425 → 8.0.427`，同为 .NET 8 SDK 补丁线；SDK `rollForward: latestPatch` 继续保留。**必须在 CI/Windows 重新构建自包含 EXE**，源代码修改不等于旧已发 EXE 已更新。
2. `Build-Release.ps1`：任何非 `1.2.0` 的 `-Version` 参数直接报错，防止误打包新版本。
3. `.github/workflows/build-release.yml`：只响应 `v1.2.0` 标签，禁止根据其他标签生成产品版本，也去掉原来的 `0.0.0-test` 备用版本；加上构建时标签断言。
4. `special_template.html`：两个可见的旧 `CheckSentry 1.1.5` 字样改成 `1.2.0`。
5. `Start-ComplianceCheck.ps1`：成功启动时的常规输出不再打印 `#session=...` 启动秘密，降低被控制台日志或屏幕截图意外采集的机会。
6. `.github/workflows/build-release.yml`：CI 新增 `check-history.js` 和新 `check-security-baseline.js` 检查。
7. `tests/check-security-baseline.js`（新增）：验证 .NET 补丁最低版本、产品版本锁、GitHub 发布标签限制、旧 UI 版本清理和终端令牌保护；零 npm 第三方包。
8. `SECURITY-DEPENDENCY-INVENTORY-2026-11-07.json`（新增）：依赖、证据范围和历史 Actions 依赖快照版本的独立清单，便于复查。

**未做修改**：黑白名单业务规则、权限模式、密码记录格式、云端同步约定、历史扫描源逻辑、ImportExcel/EPPlus 程序二进制、项目产品版本和主要 UI 结构。

## 四、需要开发者决定的事项（按顺序）

### D-1｜合规规则的修改权限（优先级最高）

- **方案 A（推荐）**：员工/审计一般会话默认只读；规则新增、删除、批量分类、Undo 和云端同步管理都必须经过独立的授权管理员角色 / 二次身份验证；保存操作留下审计事件。需规划谁持有凭据、如何恢复、是否支持离线。
- 方案 B：保留本机编辑方式，但使用受到适当 ACL 保护的规则文件 + 中央批准与签名规则版本；需要设计可信来源和兼容性。
- 方案 C：继续任何已授权报告会话可编辑；风险由运营流程接受，不推荐用于被审计人员可接触的公司电脑。

### D-2｜.NET 10 运行时迁移

- **推荐**：在 1.2.0 产品版本不变的前提下，单独提出 `net10.0-windows` / SDK 10.0.x、单文件封装与 Windows 兼容性测试方案，获得授权后实施。主运行时迁移属于重大依赖升级，本次未擅自决定。
- 暂时保留 .NET 8.0.33 作为过渡需要记录 2026-11-10 之后失去官方安全修复的事实。

### D-3｜EPPlus DLL 与 ImportExcel 兼容方案

- 在 Windows 执行：`[Reflection.AssemblyName]::GetAssemblyName('模块完整路径\EPPlus.dll').FullName`，记录 AssemblyVersion（但仍需与对应 NuGet/源代码包 FileVersion 和 SBOM 交叉核对）。
- **推荐**：确定确实命中厂商 GHSA 的版本和调用功能后，选择同一兼容产品线的安全补丁并做 Excel/工作簿、文件大小、许可条款回归测试；如需要更换 ImportExcel 大版本或商业许可，先取得开发者批准。

### D-4｜本地规则文件/云端规则真实性

- 推荐：企业规则由受控存储/审批流程提供，至少加版本签名及回滚机制；需要商定谁可编辑 Google Sheets、审计对象是否能写入本地 `list.xlsx`。
- 不要只因为域名是 Google 就把内容视为“可信合规政策”。

### D-5｜外部 PECmd 与模块离线化

- **推荐**：Release 中若允许 PECmd，必须固定官方获取来源、确切版本、可复核 SHA-256、数字签名状态和许可；审计时不得从不受控目录动态执行。缺失 vendor ImportExcel 时正式版 fail-closed；开发模式可以保留单独手动安装步骤。

### D-6｜签名与密码迁移

- 推荐：生产正式发版要求签名；采用兼容旧密码记录的双格式验证和登录后迁移机制；不应直接重置用户密码或改变权限流程。

## 五、密钥、凭据与日志

- 本地文本及配置静态扫描覆盖 `.ps1`、`.cs`、HTML/JS、YAML/JSON、README、测试、示例和构建脚本；没有发现匹配常见私钥块、AWS / GitHub / Google / Slack token、OpenAI Key、Webhook 明文等模式的**高置信度**泄露。
- `.gitignore` 已覆盖 `.env`、`.env.*`（保留 `.env.example`）、`*.pfx`、`*.p12`、`*.key`、`*.pem`、本地 XLSX/配置、临时文件和构建目录；示例配置仅含签名证书变量名，不含明文值。
- 当前上传的是源码 ZIP，**不包含 `.git` 提交历史**，无法确认过去提交是否曾泄露密钥。检测结果不应被解释成“历史上绝无泄露”。
- **如果在 Git 历史或曾对外分发的工件中发现真实密钥**：必须到提供方平台立即撤销并重新生成；仅删除文件或新增 `.gitignore` 不会使旧凭据失效。
- 控制台已移除正常启动时的完整会话秘密，异常手动启动仍可能显示；建议对终端日志访问做权限保护。

## 六、代码面安全审查摘要

- **SQL/NoSQL 注入**：未使用数据库，不适用；Excel 规则写入与导出仍需关注公式注入的业务情境和不可信字符串转义，需 Windows Excel 测试证明完整覆盖。
- **命令注入/动态执行**：已检索 `Start-Process`、`Add-Type`、子进程执行及 PowerShell 构建调用；启动器使用参数列表传参，未确认可利用的外部 HTTP 参数直接拼接 shell 命令；可选 PECmd 是明确的供应链执行边界。
- **Web**：本地 HTTP 服务有随机令牌会话、POST CSRF/Origin 保护、CSP nonce 及有限数据接口；没有发现启用外网监听或开放 CORS 的直接证据。最主要问题是**登录报告并不等于授权更改公司合规规则**。
- **文件处理**：云端 XLSX 包含大小限制、域名/HTTPS 检查和 ZIP 包内容校验；继续关注 CSV/HTML 注入、特殊路径、临时目录竞争和 Excel 引擎漏洞。不能仅因存在检查就断言完全杜绝 XXE/zip bomb。
- **加密**：CSPRNG 会话令牌与随机盐为正面防护；接管密码的 PBKDF2-SHA1 强化建议见 R-11；未发现关闭 TLS 证书验证的直接证据。
- **浏览器扩展**：CheckSentry 是扫描浏览器扩展的软件，**本项目自身不是浏览器扩展**，无需审查 manifest 权限；扫描脚本读取用户扩展清单的授权范围仍需 Windows 验证。
- **桌面/IPC**：C# 启动器、PowerShell 脚本和本地 HTTP 页面是关键边界；仍需 Windows UAC、文件 ACL、普通账户和不同用户配置实测。
- **CI/CD**：GitHub Actions SHA 已固定；CI 有 CodeQL C# 扫描，已加强版本锁与 JavaScript 检查；正式产物签名缺省允许跳过需由开发者决定。

## 七、测试与核查结果

| 项目 | 结果 | 说明 |
|---|---|---|
| `node tests/check-html.js` | **通过** | 三个 HTML 页面中的脚本语法 |
| `node tests/check-special.js` | **通过** | 专项界面逻辑测试 |
| `node tests/check-history.js` | **通过** | 历史模块静态集成、接口、只读与版本检查；**不是 Windows 执行验证** |
| `node tests/check-security-baseline.js` | **通过** | 本次新增版本锁和安全构建基线 |
| ImportExcel 文件完整性 | **通过** | `CONTENT-SHA256.json` 所列 213 项与当前解压文件的哈希一致；只证明相对清单一致，不证明官方真实性 |
| 常见秘密模式搜索 | **未发现高置信度命中** | 不含 Git 历史、系统凭据或运行时环境变量 |
| `node tests/check-session.js` | **未运行/不适用此系统** | 需要 `pwsh` 子进程 |
| PowerShell `tests/Run-Tests.ps1`、`Execution-Tests.ps1`、`Security-Tests.ps1` | **未执行** | 运行环境无 Windows PowerShell / pwsh |
| `dotnet restore / build / publish / NuGetAudit` | **未执行** | 环境无 .NET SDK；须在 Windows CI 运行 |
| 真实 Prefetch 记录与 PECmd 一致性 | **待确认** | 各种 Windows 10/11 版本、重启、PathValidated、文件删除、同名文件、普通/管理员用户均需实测 |
| 最终 EXE Authenticode 签名 | **待确认** | 尚未制作 Windows 签名二进制 |

### 正式验收必做清单

1. Windows 使用 SDK `8.0.427+`（.NET 8 线）执行 `dotnet --info`、`dotnet restore .\launcher\CheckSentry.Launcher.csproj`、`dotnet publish ... -c Release -r win-x64 --self-contained true`，审查最终自包含单文件确实使用安全补丁运行时。
2. 执行 `.\tests\Run-Tests.ps1`、`.\tests\Execution-Tests.ps1`、`.\tests\Security-Tests.ps1`、全部 Node 测试和 GitHub Actions CodeQL；每项保存真实通过/失败日志。
3. 验证普通员工账号与管理员辅助身份场景的软件/浏览器扩展扫描结果相同，不因提权切换用户配置。
4. 比较 CheckSentry 历史记录与 PECmd 对同一份 Prefetch 的 Name、LastRun、PreviousRun、PathValidated；未经验证的路径不可提供“已确认”定位。
5. 验证黑白名单规则是否可由拥有报告会话但没有审计管理员身份的用户更改；按开发者最终授权模型修复。
6. 核实 EPPlus 实际二进制版本与应用使用到的 XLSX 功能；测试恶意/过大/损坏工作簿不会导致未授权行为。
7. 正式发布时核对文件版本、UI、ZIP、Release 标签都为 **1.2.0**，签名和 SHA-256 校验符合组织要求。

## 八、结论

本次完成了 **安全补丁最低版本升级、固定产品 1.2.0 发布版本、减少启动会话令牌泄漏、修复旧界面版本号、补充 CI 测试和依赖盘点**。这些是兼容性风险低、不涉及员工审核业务规则的直接修复。

**尚不能直接宣称发布合格**：规则编辑权限、规则文件/云端政策来源完整性、将于 2026-11-10 停止支持的 .NET 8、EPPlus DLL 实际版本以及 Windows Prefetch 取证准确性，都需要按上文 D-1 至 D-6 由开发者决定和完成实机核验。未经授权，本次没有改变上述业务或依赖主版本。最终交付为**安全修复源码候选包**，不是经过 Windows 实机认证的正式 EXE。
