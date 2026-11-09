// No external packages required. Enforce the owner's CheckSentry 1.2.0 release lock.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root,name), 'utf8').replace(/^\uFEFF/, '');
const sdk = JSON.parse(read('global.json'));
assert.equal(sdk.sdk.version, '10.0.403', 'Must require security-patched .NET 10 SDK');
assert.equal(sdk.sdk.rollForward, 'latestFeature');
assert.equal(sdk.sdk.allowPrerelease, false);
const csproj = read('launcher/CheckSentry.Launcher.csproj');
assert.match(csproj, /<TargetFramework>net10\.0-windows<\/TargetFramework>/);
assert.match(csproj, /<SelfContained>true<\/SelfContained>/);
assert.match(csproj, /<PublishSingleFile>true<\/PublishSingleFile>/);
assert.ok(!csproj.includes('Tools\\PECmd'), 'Do not embed unapproved PECmd executable');
assert.ok(!read('Get-ExecutionHistory.ps1').includes('Get-CheckSentryPecmdEvidence'), 'Do not invoke unapproved PECmd binary');
assert.ok(!/Install-Module\s|Install-PackageProvider\s/i.test(read('Start-ComplianceCheck.ps1')), 'Never silently download a third-party PowerShell module');
assert.match(read('launcher/CheckSentry.Launcher.csproj'), /<Version>1\.2\.0<\/Version>/);
assert.match(read('Build-Release.ps1'), /if \(\$Version -cne '1\.2\.0'\) \{ throw/);
const workflow = read('.github/workflows/build-release.yml');
assert.match(workflow, /tags: \['v1\.2\.0'\]/);
assert.match(workflow, /dotnet-version: '10\.0\.x'/);
assert.match(read('.github/workflows/codeql.yml'), /dotnet-version: '10\.0\.x'/);
assert.match(workflow, /\$version = '1\.2\.0'/);
assert.ok(!workflow.includes("'0.0.0-test'"), 'Must not silently publish a fallback version');
assert.ok(!read('special_template.html').includes('CheckSentry 1.1.5'), 'Stale UI version');
assert.ok(!read('Start-ComplianceCheck.ps1').includes('报告服务已启动：$url'), 'Do not print bootstrap secret during a successful start');

// All workbook inputs to the legacy bundled EPPlus must pass zip/XML preflight.
const ps = read('Start-ComplianceCheck.ps1');
assert.match(ps, /function Import-CloudRuleSheets \{[\s\S]*?param\(\[string\]\$Path\)\s+[^\r\n]*\r?\n\s*Assert-XlsxArchiveComplete -Path \$Path/, 'Cloud snapshot must be preflighted before EPPlus');
assert.match(ps, /function Invoke-WorkbookTransaction \{[\s\S]*?Copy-Item -LiteralPath \$Path -Destination \$temporaryPath -ErrorAction Stop\s+[^\r\n]*\r?\n\s*Assert-XlsxArchiveComplete -Path \$temporaryPath/, 'Rule-write transaction must preflight temp XLSX before parsing');
assert.match(ps, /\$settings\.DtdProcessing = \[System\.Xml\.DtdProcessing\]::Prohibit/, 'XLSX XML parser must reject DTD');

console.log('Security baseline: .NET 10 self-contained, no PECmd execution, and CheckSentry 1.2.0 lock OK');
