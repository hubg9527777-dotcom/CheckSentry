const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert/strict');
const html = fs.readFileSync(path.join(__dirname, '..', 'special_template.html'), 'utf8');
const script = html.match(/<script[^>]*>([\s\S]*?)<\/script>/)[1];
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.textContent = ''; this.value = ''; this.hidden = false; this.listeners = {}; }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this.children = children; }
  addEventListener(event, action) { this.listeners[event] = action; }
  focus() { this.focused = true; }
  scrollIntoView() { this.scrolled = true; }
  setAttribute(key, value) { this[key] = value; }
  set innerHTML(value) { throw new Error('Untrusted content must be rendered as text, not HTML: ' + value); }
}
const elements = new Map();
const element = id => { if (!elements.has(id)) elements.set(id, new Element('div')); return elements.get(id); };
let fixture = {ok:true, ready:true, scannedAt:'2026-10-23 12:00:00', items:[]}, responseOK = true, fetchBehavior = null;
const storage = new Map([['CheckSentry.special.queries.v1', 'Restored Tool']]);
const context = vm.createContext({
  console, setTimeout, clearTimeout, AbortController, sessionStorage:{getItem:key => storage.get(key) || null, setItem:(key,value) => storage.set(key,value), removeItem:key => storage.delete(key)}, navigator:{clipboard:{writeText:async text => {context.copied = text;}}},
  document:{getElementById:element, createElement:tag => new Element(tag)},
  fetch:async (url, options) => { assert.equal(url, '/api/special/inventory'); assert.equal(options.cache, 'no-store'); if (fetchBehavior) return fetchBehavior(options); return {ok:responseOK, json:async () => fixture}; }
});
vm.runInContext(script, context);
assert.equal(element('queries').value, 'Restored Tool', 'Refresh must restore the draft from this tab');
assert.ok(element('status').textContent.includes('已恢复'));
assert.ok(element('inputCount').textContent.includes('1 个名称'));
const forms = text => context.specialForms(text);
const match = (query, name, locations = []) => context.specialMatch(forms(query), {name, locations});
for (const [query, name] of [
  ['DR_AutoEdit_v1.1', 'dr autoedit v9.8'], ['obs-multi-rtmp', 'OBS_Multi_RTMP_0.6.0'],
  ['DR_AutoEdit', 'DRAutoEdt'], ['obs-multi-rtmp', 'obs-multi-rmt p'],
  ['DR_AutoEdit', 'AutoEdit Pro'], ['obs-multi-rtmp', 'Multi RTMP'],
  ['obs-multi-rtmp', 'RTMP Helper'], ['微信', '企业微信'], ['7-Zip', '7 Zip 24.09'],
  ['360', '360 安全卫士'], ['4K Video Downloader+', '4K Video Downloader 1.2'], ['软件排查', '软件排查助手'],
  ['DR_AutoEdit_v1.1', 'ＤＲ＿ＡｕｔｏＥｄｉｔ＿ｖ２.０']
]) assert.ok(match(query, name), `Missing candidate: ${query} / ${name}`);
assert.equal(match('AutoEdit', '本地工具', ['C:\\Tools\\DR_AutoEdit\\tool.exe']), null, 'Installation paths are display-only, not search evidence');
assert.ok(context.specialMatch(forms('obs-rtmp@example'), {name:'推流扩展', extensionId:'obs-rtmp@example', locations:[]}));
assert.equal(match('DR_AutoEdit', 'Zoom'), null);
assert.ok(match('DR_AutoEdit', 'DR AutoEdit').score > match('DR_AutoEdit', 'DRAutoEdt').score);
assert.equal(forms('DR_AutoEdit_v1.1').core, 'drautoedit', 'Underscore-prefixed version marker must not survive normalization');
assert.equal(forms('DR_AutoEdit_v99.3').core, forms('DR-AutoEdit').core);
assert.ok(forms('DR_AutoEdit_v1.1').keywords.includes('autoedit'));
assert.ok(forms('DRAutoEdit_v1.1').keywords.includes('autoedit'));
assert.ok(!forms('DR_AutoEdit_v1.1').keywords.some(word => ['dr','auto','edit'].includes(word)));
assert.ok(forms('obs-multi-rtmp').keywords.includes('multi'));
assert.ok(!forms('obs-multi-rtmp').keywords.includes('obs'));
for (const [query, name] of [
  ['obs-multi-rtmp','OBS Studio'], ['obs-multi-rtmp','OBS Browser'],
  ['obs-multi-rtmp','Multimedia Player'], ['obs-multi-rtmp','Microsoft Edge'],
  ['DR_AutoEdit_v1.1','Driver Booster'], ['DR_AutoEdit_v1.1','Google Drive'],
  ['DR_AutoEdit_v1.1','Auto Update'], ['DR_AutoEdit_v1.1','Video Editor'],
  ['DR_AutoEdit_v1.1','Visual Studio Code'], ['DR_AutoEdit','DR Auto EXTRA Edit'],
  ['multi','Multimedia Player'], ['multi','Multiple Monitor'], ['multi','Build Tools'],
  ['rtmp','RTP Helper'], ['DR','Driver'], ['DR','DR Helper']
]) assert.equal(match(query,name), null, `Unrelated candidate must be rejected: ${query} / ${name}`);
assert.equal(context.specialMatch(forms('obs'), {name:'翻译工具', extensionId:'obs-helper@example', locations:[]}), null, 'A partial extension ID must not produce a candidate');
assert.equal(match('obs-multi-rtmp','Multi Commander').stage,'keyword');
assert.equal(match('DR_AutoEdit_v1.1','AutoEdit Pro').stage,'keyword');
assert.equal(match('DR_AutoEdit_v1.1','AutoEdt').stage,'keyword', 'A complete fallback compound may contain a small typo');
assert.throws(() => context.parseSpecialQueries('   '));
assert.throws(() => context.parseSpecialQueries('v1.2'));
assert.throws(() => context.parseSpecialQueries('!!!'));
assert.throws(() => context.parseSpecialQueries('a'.repeat(257)));
assert.throws(() => context.parseSpecialQueries(Array(501).fill('Tool').join('\n')));
assert.equal(context.parseSpecialQueries('Tool\r\n\r\nTool\rOther').length, 2);
(async () => {
  const attack = '<img src=x onerror=alert(1)>';
  fixture.items = Array.from({length:210}, (_,i) => ({name:'OBS Multi RTMP ' + i, version:'1.2', type:'软件', publisher:attack, locations:['C:\\Tools\\obs']}));
  fixture.items.push({name:'OBS Multi RTMP ' + attack, version:'3.0', type:'Chromium 浏览器扩展', extensionId:'<script>', locations:[attack]});
  element('queries').value = '完全没有关联的名字\nobs-multi-rtmp\nobs-multi-rtmp';
  element('queries').listeners.input();
  assert.ok(element('inputCount').textContent.includes('1 行重复'));
  assert.equal(storage.get('CheckSentry.special.queries.v1'), element('queries').value);
  await context.runSpecialSearch();
  assert.equal(element('results').hidden, false);
  assert.equal(element('groups').children.length, 2);
  assert.equal(element('groups').children[0].children[0].children[0].textContent, 'obs-multi-rtmp', 'Groups with candidates must appear before groups with no candidates');
  assert.equal(element('queryIndex').children[0].href, '#query-result-0');
  assert.equal(element('totals').children[2].children[0].textContent, '211', 'Candidate total must count installations only once');
  assert.equal(element('results')['aria-busy'], 'false');
  assert.ok(element('results').scrolled, 'Finished search must move the user to results');
  assert.equal(element('groups').children[0].children.length, 213, 'All 211 candidates must be rendered without truncation');
  assert.ok(element('groups').children[1].children[2].textContent.includes('未找到'));
  await element('copy').listeners.click();
  assert.ok(context.copied.includes(attack));
  const firstCard = element('groups').children[0].children[2];
  await firstCard.children[0].children[1].listeners.click();
  assert.ok(context.copied.includes('OBS Multi RTMP'));
  assert.ok(context.copied.includes('位置：'));
  assert.ok(context.copied.includes('匹配依据：'));
  element('queries').listeners.input();
  assert.equal(element('results').hidden, true, 'Changed input must invalidate old results');
  responseOK = false; fixture = {ok:false, error:'会话失效'};
  await context.runSpecialSearch();
  assert.equal(element('results').hidden, true);
  assert.equal(element('run').disabled, false);
  assert.ok(element('status').textContent.includes('会话失效'));
  fixture = {ok:true, ready:true, items:[]}; responseOK = true;
  await context.runSpecialSearch();
  assert.equal(element('results').hidden, false, 'Empty inventory still needs a complete no-results report');
  fixture = {ok:true, ready:true, items:[
    {name:'OBS Multi RTMP 9.0', type:'软件', locations:[]},
    {name:'Multi Commander', type:'软件', locations:[]},
    {name:'OBS Studio', type:'软件', locations:['C:\\obs-multi-rtmp']},
    {name:'Multimedia Player', type:'软件', locations:[]}
  ]};
  element('queries').value = 'obs-multi-rtmp';
  await context.runSpecialSearch();
  assert.equal(element('totals').children[2].children[0].textContent,'1', 'Full-name results must take priority over broad keyword expansion');
  assert.ok(element('groups').children[0].children[1].textContent.includes('完整名称检索'));
  fixture.items = fixture.items.slice(1);
  await context.runSpecialSearch();
  assert.equal(element('totals').children[2].children[0].textContent,'1', 'When full name is absent, only complete keywords may expand the search');
  assert.ok(element('groups').children[0].children[1].textContent.includes('已自动扩展'));
  assert.equal(element('groups').children[0].children[2].children[0].children[0].children[0].textContent,'Multi Commander');
  element('queries').value = 'obs-multi-rtmp\n完全没有关联的名字';
  // Cancelling an in-flight network request must not leave the screen frozen or partial results visible.
  fetchBehavior = options => new Promise((resolve, reject) => {
    options.signal.addEventListener('abort', () => reject(new Error('aborted')));
    setTimeout(() => element('cancel').listeners.click(), 0);
  });
  const pendingRun = context.runSpecialSearch();
  assert.equal(element('run').disabled, true);
  assert.equal(element('cancel').hidden, false);
  await context.runSpecialSearch(); // Repeated execution while busy is ignored.
  await pendingRun;
  assert.equal(element('results').hidden, true);
  assert.equal(element('run').disabled, false);
  assert.equal(element('cancel').hidden, true);
  assert.equal(element('progressArea').hidden, true);
  assert.ok(element('status').textContent.includes('已停止'));
  assert.ok(element('queries').value.includes('obs-multi-rtmp'));
  fetchBehavior = null;
  fixture = {ok:true, ready:true, items:[{name:'OBS Multi RTMP', type:'软件', version:'1.0', locations:[]}]};
  element('queries').value = 'obs\nrtmp';
  await context.runSpecialSearch();
  assert.equal(element('totals').children[2].children[0].textContent, '1', 'One item matched by two inputs must count as one candidate');
  assert.equal(element('groups').children.length, 2, 'Each distinct input must still retain its matches');
  fixture = {ok:true, ready:true, items:Array.from({length:250}, (_,i) => ({name:'OBS Helper ' + i, type:'软件', locations:[]}))};
  element('queries').value = 'obs';
  const matchingRun = context.runSpecialSearch();
  setTimeout(() => element('cancel').listeners.click(), 0);
  await matchingRun;
  assert.equal(element('results').hidden, true, 'Cancelling during matching must not expose incomplete results');
  assert.equal(element('groups').children.length, 0);
  assert.equal(element('queries').disabled, false);
  assert.ok(element('status').textContent.includes('已停止'));
  const allowedStorage = context.sessionStorage;
  context.sessionStorage = {getItem:() => {throw new Error('blocked');}, setItem:() => {throw new Error('blocked');}, removeItem:() => {throw new Error('blocked');}};
  fixture = {ok:true, ready:true, items:[]};
  await context.runSpecialSearch();
  assert.equal(element('results').hidden, false, 'Search must work when the browser blocks storage');
  assert.ok(element('draftHint').textContent.includes('禁止暂存'));
  context.sessionStorage = allowedStorage;
  element('clear').listeners.click();
  assert.equal(element('queries').value, '');
  assert.equal(element('results').hidden, true);
  assert.equal(storage.has('CheckSentry.special.queries.v1'), false, 'Clearing input must remove the draft too');
  assert.equal(element('clear').disabled, true);
  console.log('专项排查：版本去除、完整名称优先、完整关键词回退、拼写容差、短片段及路径误报拦截、全部候选、安全渲染和易用性回归检查通过。');
})().catch(error => {console.error(error); process.exitCode = 1;});
