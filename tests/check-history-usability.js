// CheckSentry 1.2.0 static UI and source-compatibility checks; does not require Windows.
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const root = path.join(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'Start-ComplianceCheck.ps1'), 'utf8');
const page = fs.readFileSync(path.join(root, 'report_template.html'), 'utf8');
const requiredHtml = [
  'exec-row-chk', 'exec-group-select', 'data-history-batch-status', 'execCopySelected',
  'exec-rule-fields', 'namePattern', 'matchedRuleId', 'itemType',
  '如何补全扫描？', '以管理员身份运行', '云端规则需管理员另行维护',
  '下载目录', '桌面 / 文档目录', '其他磁盘', '系统目录'
];
for (const item of requiredHtml) assert(source.includes(item) || page.includes(item), `Missing ${item}`);
assert(source.includes("$ruleFields = \"<form class='exec-rule-fields'"), 'History rows must use same form contract as existing batch actions');
assert(source.includes("$historyEvidenceWeak = if"), 'Must distinguish weak history identity');
assert(source.includes('LocationRank = $locationRank'), 'Path-origin priority must be retained');
assert(source.includes('Sort-Object LocationRank'), 'History must sort by origin within its policy group');
assert(source.includes('if (-not [bool]$entry.PathVerified)'), 'Unverified path must not masquerade as proven location');
assert(source.includes('Source -eq \'4688\''), '4688 availability should be reported');
assert(page.includes('copySelectedRows(historyOnly = false)') && page.includes('submitBatch(status, historyOnly = false)'), 'Historical and installed rows must share same 11-column copy and API paths');
assert(page.includes('if (historyOnly) {\n    const identities'), 'History multi-path selections must not create duplicate rules');
assert(page.includes("if (!active) {\n        const checkbox"), 'Filtered-out historical rows must not remain secretly selected');
assert(page.includes("status === '允许'"), 'Weak whitelist confirmation missing');
assert(source.includes('黑名单规则命中 / 关联') && source.includes('白名单关联'), 'Must preserve classification groups');
assert(page.includes("const status = '待定'"), 'Copy format schema must remain unchanged');
console.log('History prioritization, actionable diagnostics, checked-row actions, A:K copy schema and safe batch behavior: static OK');
