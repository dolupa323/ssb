// 원본 화면의 요소들이 놓인 자리(getBoundingClientRect)를 적는다 → tools/ui/ref/rects-<폭>x<높이>.json
//  Roblox 쪽 배치를 맞출 때 눈대중 대신 숫자로 견주려는 것. 글꼴은 「맑은 고딕」으로 바뀌어 있어 글의 폭 · 줄 높이는 원본 웹 글꼴과 다를 수 있다.
//   node tools/ui/rects.mjs [1280x720 …]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { launch } from '../bake/lib/cdp.mjs';
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const CHROME = ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(p => fs.existsSync(p));
const sizes = (process.argv.slice(2).length ? process.argv.slice(2) : ['1280x720']).map(s => s.split('x').map(Number));
const sleep = ms => new Promise(r => setTimeout(r, ms));
const url = pathToFileURL(path.join(ROOT, 'commute-survival', 'index.html')).href + '#dbg';
const chrome = await launch({ chrome: CHROME, port: 9388, userDataDir: path.join(HERE, 'work', 'chrome-profile'), url, log: () => {} });
const S = 'window.__dbg.sim()';
// 원본의 웹 글꼴을 받아 둔 파일(tools/font/fonts — node tools/font/fetch.mjs)에서 읽게 한다. 바깥 통신은 여전히 막혀 있다.
const FONT_DIR = pathToFileURL(path.join(ROOT, 'tools', 'font', 'fonts')).href;
const FACES = [['Do Hyeon', 400, 'DoHyeon-Regular.ttf'], ['VT323', 400, 'VT323-Regular.ttf'], ['IBM Plex Sans KR', 400, 'IBMPlexSansKR-Regular.ttf'], ['IBM Plex Sans KR', 500, 'IBMPlexSansKR-Medium.ttf'], ['IBM Plex Sans KR', 600, 'IBMPlexSansKR-SemiBold.ttf'], ['IBM Plex Sans KR', 700, 'IBMPlexSansKR-Bold.ttf']];
const FONT_CSS = FACES.map(([fam, w, file]) => `@font-face{font-family:"${fam}";font-weight:${w};src:url("${FONT_DIR}/${file}");}`).join('');
await chrome.send('Page.enable');
await chrome.send('Page.addScriptToEvaluateOnNewDocument', { source: `document.addEventListener('DOMContentLoaded',()=>{const s=document.createElement('style');s.textContent=${JSON.stringify(FONT_CSS)};document.head.appendChild(s);});` });
const fontsReady = "document.fonts.ready.then(()=>Promise.all(['24px \"Do Hyeon\"','24px VT323','400 14px \"IBM Plex Sans KR\"','500 14px \"IBM Plex Sans KR\"','600 14px \"IBM Plex Sans KR\"','700 14px \"IBM Plex Sans KR\"'].map(f=>document.fonts.load(f,'가0')))).then(()=>document.fonts.check('24px \"Do Hyeon\"'))";

const start = `localStorage.clear();document.getElementById('btnStart').click();`;
const STATES = [
  ['menu', `document.getElementById('btnHow').click();`, 400, '.sign,.hero,.when b,.hero h1,.noti,.noti-ic,.route-h,.stops,.stops li,.stops li b,.stops li small,.sign-body>p,.diff-label,.diff-row button,.car,#diffBlurb,#btnStart,.idc,.foot,#best,#btnHow,#btnSetMenu,.how,.keys dt,.keys dd,kbd,.tips li'],
  ['hud', start + `setTimeout(()=>{${S}.S.zt=999;},300);`, 5000, '#xpbar,.vitals,.lvline,.lvline b,.hp,.board,.roundel,#clock,.stn,.stn small,.stn b,.mini,.mini i,.side,.kills,#btnSet,#btnPause,#bossbar,#bossname,#bossbar div,#build,.slot,.slot em,#btnDash,#btnDash span,#hint,#hint b,#hintTxt,#banner,#b0,#b1,#b2'],
  ['levelup', start + `setTimeout(()=>{${S}.S.p.xp=1e6;},600);`, 1500, '#levelup .panel,#luTitle,#luSub,.cards,.card,.card .tag,.card .tag kbd,.card .mid,.card .head,.card img,.card h3,.card .lv,.pips i,.card p,.card .hint,#btnReroll,#btnReroll kbd'],
  ['pause', start + `setTimeout(()=>document.getElementById('btnPause').click(),700);`, 1300, '#pause .panel,#pauseTitle,#pauseSub,.sets,.sets label,.sets .lb,.sets input,.seg,.seg button,.note,#pause .btnrow,#btnResume,#btnQuit'],
  ['end', start + `setTimeout(()=>{const s=${S};s.S.t=95;s.S.kills=1234;s.S.dmg={card:1505,backpack:1366,umbrella:1109};s.S.p.hp=0.01;s.S.p.inv=0;for(let i=0;i<12;i++)s.dbg.spawn('pass',s.S.p.x+i,s.S.p.y);},900);`, 3500, '#end .panel,.slip,.slip-top,.chip,.stamp,.stamp small,#endTitle,#endTitle small,.eroute,.eroute li,.stat-row,.stat-row div,.stat-row small,.stat-row b,.dmg,.dmg div,.dmg i,#end .btnrow,#btnRetry,#btnHome'],
];
for (const [w, h] of sizes) {
  await chrome.send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false });
  const out = {};
  for (const [name, script, wait, sel] of STATES) {
    await chrome.send('Page.navigate', { url: 'about:blank' }); await sleep(100);
    await chrome.send('Page.navigate', { url });
    for (let i = 0; i < 50; i++) { if (await chrome.evaluate("document.readyState==='complete'&&!!window.__dbg&&!!window.__dbg.sim()").catch(() => false)) break; await sleep(100); }
    await chrome.evaluate(fontsReady);
    await sleep(300);
    await chrome.evaluate(script + 'true');
    await sleep(wait);
    out[name] = JSON.parse(await chrome.evaluate(`JSON.stringify(${JSON.stringify(sel.split(','))}.map(q=>[q,[...document.querySelectorAll(q)].slice(0,12).map(e=>{const r=e.getBoundingClientRect();return [Math.round(r.left*10)/10,Math.round(r.top*10)/10,Math.round(r.width*10)/10,Math.round(r.height*10)/10]})]))`));
  }
  fs.writeFileSync(path.join(HERE, 'ref', `rects-${w}x${h}.json`), JSON.stringify(out, null, 0));
  for (const [name, list] of Object.entries(out)) { console.log('## ' + name); for (const [q, rs] of list) console.log('  ' + q.padEnd(22) + rs.slice(0, 7).map(r => r.join(',')).join('  ')); }
}
await chrome.close();
