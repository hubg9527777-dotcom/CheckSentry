'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, '..', 'Get-InstalledExtensions.ps1'), 'utf8');
assert.match(source, /function Test-LocalExtensionIconPath\s*\{/);
assert.match(source, /Path -notmatch '\^\[A-Za-z\]:\\\\'/);
assert.match(source, /FileAttributes\]::ReparsePoint/);
for (const functionName of ['Resolve-ExtensionIconPath', 'Resolve-FirefoxIconPath']) {
  const start = source.indexOf(`function ${functionName} {`);
  const next = source.indexOf('\nfunction ', start + 10);
  const part = source.slice(start, next === -1 ? source.length : next);
  assert.match(part, /Test-LocalExtensionIconPath -Path \$candidate/,
      `${functionName}: missing local icon guard`);
}
console.log('Browser extension icon path regression guard OK (static).');
