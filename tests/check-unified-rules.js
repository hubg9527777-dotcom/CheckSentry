// Static rules integration checks; PowerShell behavior is verified by Run-Tests.ps1 on Windows.
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const root = path.join(__dirname, '..');
const code = fs.readFileSync(path.join(root, 'Start-ComplianceCheck.ps1'), 'utf8');
const html = fs.readFileSync(path.join(root, 'management_template.html'), 'utf8');
const report = fs.readFileSync(path.join(root, 'report_template.html'), 'utf8');
assert(code.includes("$script:AllowedItemTypes = @('软件', '浏览器扩展')"), 'only two new business types allowed');
assert(code.includes("'Chromium插件' { return '浏览器扩展' }") && code.includes("'Firefox插件' { return '浏览器扩展' }"), 'legacy browser extension type mapping missing');
assert(code.includes("$whiteMatcher = New-RuleMatcher -Rules @($AllRules.'白名单') -ItemType '软件'"), 'historical whitelist matcher missing');
assert(code.includes("$pendingMatcher = New-RuleMatcher -Rules @($AllRules.'待定') -ItemType '软件'"), 'historical pending matcher missing');
assert(code.includes('PolicySheet = $policySheet') && code.includes('ExecutionStatus = $executionStatus'), 'compliance must be separate from evidence');
assert(!html.includes('<option value="Chromium插件">') && !html.includes('<option value="Firefox插件">'), 'management UI must only offer 2 types');
assert(html.includes('<option value="浏览器扩展">浏览器扩展</option>'), 'new browser extension option missing');
assert(report.includes('row.dataset.executionStatus'), 'portable filter must use evidence status');
assert(!/Get-CheckSentryPecmdEvidence|Start-Process[^\n]*PECmd/i.test(code), 'PECmd auto launch must not be introduced');
assert(code.includes('历史运行 / 疑似免安装软件'), 'original history section not preserved');
console.log('Unified two-type rule schema and historical three-sheet classification checks passed (static).');
