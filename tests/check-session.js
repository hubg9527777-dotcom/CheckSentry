// Optional real HTTP regression: node tests/check-session.js /path/to/pwsh
const {spawn} = require('node:child_process');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..').replaceAll("'", "''");
const server = spawn(process.argv[2] || 'pwsh', ['-NoProfile', '-Command', `
. '${root}/Start-ComplianceCheck.ps1' -LibraryOnly
function Start-InventoryScanJobs { }
function Stop-InventoryScanJobs { }
function Start-Process { }
function Get-InventoryScanStatus { return @{ Ready = $false; Error = ''; Message = 'Test scan' } }
Start-ReportServer -RequestedPort 18787 -Path '${root}/list_template.xlsx' -IncludeSystem $false
`], {stdio:['ignore','pipe','pipe']});
let output = '';
const timeout = setTimeout(() => server.kill(), 20000);
(async () => {
  try {
    const link = await new Promise((resolve, reject) => {
      server.stdout.on('data', chunk => {
        output += chunk;
        const match = output.match(/http:\/\/localhost:\d+\/#session=[a-f0-9]{64}/);
        if (match) resolve(match[0]);
      });
      server.on('exit', code => reject(new Error(`Server exited ${code}: ${output}`)));
      server.stderr.on('data', chunk => { output += chunk; });
    });
    const url = new URL(link);
    const token = new URLSearchParams(url.hash.slice(1)).get('session');
    const base = url.origin;
    assert.equal((await fetch(base + '/api/scan-status')).status, 401);
    assert.equal((await fetch(base + '/manage')).status, 401);
    const html = await (await fetch(base)).text();
    assert.ok(!html.includes(token));
    new Function(html.match(/<script[^>]*>([\s\S]*?)<\/script>/)[1]);
    const authenticate = async value => fetch(base + '/api/session', {
      method:'POST', headers:{'Content-Type':'application/json','X-CheckSentry-Token':value, Origin:base},
      body: JSON.stringify({token:value})
    });
    assert.notEqual((await authenticate('0'.repeat(64))).status, 200);
    const auth = await authenticate(token);
    assert.equal(auth.status, 200);
    const cookie = auth.headers.get('set-cookie');
    assert.ok(cookie.includes('HttpOnly') && cookie.includes('SameSite=Strict'));
    const headers = {Cookie:cookie.split(';')[0]};
    assert.equal((await fetch(base + '/api/scan-status', {headers})).status, 200);
    const loading = await fetch(base + '/', {headers});
    assert.equal(loading.status, 200);
    assert.ok(!(await loading.text()).includes('/api/session'));
    assert.equal((await fetch(base + '/api/scan-status', {headers:{Cookie:'CheckSentrySession_' + url.port + '=' + '0'.repeat(64)}})).status, 401);
    assert.notEqual((await fetch(base + '/api/scan', {method:'POST', headers:{...headers,'Content-Type':'application/json','X-CheckSentry-Token':'wrong', Origin:base}, body:'{}'})).status, 200);
    console.log('CheckSentry real HTTP session regression passed.');
  } finally { clearTimeout(timeout); server.kill(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
