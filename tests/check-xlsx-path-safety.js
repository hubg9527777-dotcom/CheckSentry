// Static integration guard for the early XLSX part-name validation.
// Behavioral PowerShell tests must also run on Windows during the official build.
const fs = require('fs');
const assert = require('assert');
const code = fs.readFileSync('Start-ComplianceCheck.ps1', 'utf8');
const start = code.indexOf('function Assert-XlsxArchiveComplete {');
const end = code.indexOf('function Test-AllowedCloudDownloadUri {', start);
assert(start >= 0 && end > start, 'XLSX safety boundary not found');
const fn = code.slice(start, end);
for (const pattern of [
  /\$part\.StartsWith\('\/'\)/,
  /\$part\.Contains\('\\'\)/,
  /\$part\.Contains\(':'\)/,
  /\\.\{1,2\}/,
  /\$part\.Length -gt 1024/,
  /\$entryNames\.ContainsKey/,
  /\$expandedBytes -gt 104857600/,
  /\$actualBytes -gt 104857600/,
  /DtdProcessing = \[System\.Xml\.DtdProcessing\]::Prohibit/,
]) {
  assert(pattern.test(fn), 'Missing XLSX safety condition: ' + pattern);
}
console.log('XLSX archive path safety guards: OK');
