// 원본 게임(commute-survival/index.html)을 화면 없는 Chrome에서 띄워 화면마다 찍어 둔다 → tools/ui/ref/<이름>-<폭>x<높이>.png
//  mock으로 찍은 Roblox 쪽 화면(tools/ui/shots)과 나란히 놓고 견주는 데 쓴다. 원본은 고치지 않는다(읽기만).
//  바깥 통신은 막혀 있다(tools/bake/lib/cdp.mjs). 웹 글꼴은 받아 둔 파일(tools/font/fonts)에서 읽는다 → 원본 그대로의 글꼴로 찍힌다.
//   node tools/ui/ref.mjs [1920x1080 1280x720 844x390 …]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { launch } from '../bake/lib/cdp.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const OUT = path.join(HERE, 'ref');
const CHROME = ['C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe', 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'].find(p => fs.existsSync(p));
const sizes = (process.argv.slice(2).length ? process.argv.slice(2) : ['1920x1080', '1280x720', '844x390']).map(s => s.split('x').map(Number));
const sleep = ms => new Promise(r => setTimeout(r, ms));
fs.mkdirSync(OUT, { recursive: true });

const url = pathToFileURL(path.join(ROOT, 'commute-survival', 'index.html')).href + '#dbg';
const chrome = await launch({ chrome: CHROME, port: 9388, userDataDir: path.join(HERE, 'work', 'chrome-profile'), url, log: s => console.log(s) });
const ev = chrome.evaluate;
// 원본의 웹 글꼴을 받아 둔 파일(tools/font/fonts — node tools/font/fetch.mjs)에서 읽게 한다. 바깥 통신은 여전히 막혀 있다.
const FONT_DIR = pathToFileURL(path.join(ROOT, 'tools', 'font', 'fonts')).href;
const FACES = [['Do Hyeon', 400, 'DoHyeon-Regular.ttf'], ['VT323', 400, 'VT323-Regular.ttf'], ['IBM Plex Sans KR', 400, 'IBMPlexSansKR-Regular.ttf'], ['IBM Plex Sans KR', 500, 'IBMPlexSansKR-Medium.ttf'], ['IBM Plex Sans KR', 600, 'IBMPlexSansKR-SemiBold.ttf'], ['IBM Plex Sans KR', 700, 'IBMPlexSansKR-Bold.ttf']];
const FONT_CSS = FACES.map(([fam, w, file]) => `@font-face{font-family:"${fam}";font-weight:${w};src:url("${FONT_DIR}/${file}");}`).join('');
await chrome.send('Page.enable');
await chrome.send('Page.addScriptToEvaluateOnNewDocument', { source: `document.addEventListener('DOMContentLoaded',()=>{const s=document.createElement('style');s.textContent=${JSON.stringify(FONT_CSS)};document.head.appendChild(s);});` });
const fontsReady = "document.fonts.ready.then(()=>Promise.all(['24px \"Do Hyeon\"','24px VT323','400 14px \"IBM Plex Sans KR\"','500 14px \"IBM Plex Sans KR\"','600 14px \"IBM Plex Sans KR\"','700 14px \"IBM Plex Sans KR\"'].map(f=>document.fonts.load(f,'가0')))).then(()=>document.fonts.check('24px \"Do Hyeon\"'))";


// 화면마다: 이름, 그 상태로 가는 스크립트(페이지 안에서 돈다), 기다릴 시간(ms)
const S = 'window.__dbg.sim()';
const start = diff => `localStorage.clear();document.getElementById('diff${diff}').click();document.getElementById('btnStart').click();`;
const STATES = [
  ['menu', '', 1200],
  ['menu-how', `document.getElementById('btnHow').click();`, 300],
  ['menu-settings', `document.getElementById('btnSetMenu').click();`, 300],
  ['hud', start(1), 3000],
  ['hud-hint', start(0), 2200],
  ['hud-boss', start(1) + `setTimeout(()=>{${S}.S.zt=999;},300);`, 6000],
  ['levelup', start(1) + `setTimeout(()=>{${S}.S.p.xp=1e6;},600);`, 1500],
  ['pause', start(1) + `setTimeout(()=>document.getElementById('btnPause').click(),700);`, 1300],
  ['end-lose', start(1) + `setTimeout(()=>{const s=${S};s.S.t=95;s.S.kills=1234;s.S.p.hp=0.01;s.S.p.inv=0;for(let i=0;i<12;i++)s.dbg.spawn('pass',s.S.p.x+i,s.S.p.y);},900);`, 3500],
  ['end-win', start(1) + `setTimeout(()=>{const s=${S};s.dbg.enterZone(6);s.S.t=500;s.S.zt=999;},500);setTimeout(()=>{const s=${S};if(s.S.gate)s.dbg.kill(s.S.gate,'card');},2500);setTimeout(()=>{const c=document.getElementById('card1');if(c)c.click();},4000);`, 9000],
];

for (const [w, h] of sizes) {
  await chrome.send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false });
  for (const [name, script, wait] of STATES) {
    await chrome.send('Page.navigate', { url: 'about:blank' });
    await sleep(100);
    await chrome.send('Page.navigate', { url });
    for (let i = 0; i < 50; i++) { if (await ev("document.readyState==='complete'&&!!window.__dbg&&!!window.__dbg.sim()").catch(() => false)) break; await sleep(100); }
    if (!(await ev(fontsReady))) console.log('  (알림) 웹 글꼴을 읽지 못했다');
    await sleep(400);
    if (script) await ev(script + 'true');
    await sleep(wait);
    const info = await ev(`(()=>{const s=${S};return JSON.stringify({state:s.S.state,zone:s.S.zone,t:Math.round(s.S.t)});})()`);
    const shot = await chrome.send('Page.captureScreenshot', { format: 'png' });
    const file = path.join(OUT, `${name}-${w}x${h}.png`);
    fs.writeFileSync(file, Buffer.from(shot.data, 'base64'));
    console.log(`${name}-${w}x${h}.png  ${info}`);
  }
}
await chrome.close();
