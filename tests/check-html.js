const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
for (const name of ['report_template.html', 'management_template.html']) {
  const html = fs.readFileSync(path.join(root, name), 'utf8');
  const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)].map(match => match[1]);
  if (!scripts.length) throw new Error(`${name}: no inline script found`);
  for (const script of scripts) new Function(script);
  console.log(`${name}: JavaScript syntax OK`);
}

const reportHtml = fs.readFileSync(path.join(root, 'report_template.html'), 'utf8');
if (reportHtml.includes('/?refresh=1') || !reportHtml.includes("apiPost('/api/scan', {})")) {
  throw new Error('report_template.html: rescan must use a token-protected POST');
}
if (!/id="cloudSyncProgress"[\s\S]*cloud-sync-spinner/.test(reportHtml)) {
  throw new Error('report_template.html: cloud save progress indicator missing');
}
if (!/setCloudSaveBusy\(true,[\s\S]*apiPost\('\/api\/manage\/cloudSettings'/.test(reportHtml)) {
  throw new Error('report_template.html: cloud save must enter busy state before request');
}
if (/lazy-checksentry-icon hidden/.test(reportHtml)) {
  throw new Error('report_template.html: lazy icon cannot use display:none before IntersectionObserver');
}
if (!/item-icon-slot[\s\S]*icon-ready/.test(reportHtml)) {
  throw new Error('report_template.html: visible lazy icon slot missing');
}
const managementHtml = fs.readFileSync(path.join(root, 'management_template.html'), 'utf8');
if (/data-icon-key="\$\{escapeHtml\(iconKey\)\}"[^>]*display:none/.test(managementHtml)) {
  throw new Error('management_template.html: lazy rule icon cannot use display:none');
}
// Apps Script is local-only and intentionally absent from GitHub release builds.
const appsPath = path.join(root, 'GoogleAppsScript.gs');
if (fs.existsSync(appsPath)) {
  const vm = require('vm');
  const context = vm.createContext({ console });
  vm.runInContext(fs.readFileSync(appsPath, 'utf8'), context);
  if (vm.runInContext('asSafeSheetValue_("=IMPORTDATA(1)")', context) !== "'=IMPORTDATA(1)" ||
      vm.runInContext('asSafeSheetValue_(123)', context) !== 123) {
    throw new Error('GoogleAppsScript.gs: deletion log formula guard failed');
  }
  console.log('GoogleAppsScript.gs: syntax and formula guard OK');
}
