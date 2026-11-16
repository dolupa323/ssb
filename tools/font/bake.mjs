// 글자 굽기: 원본의 웹 글꼴 Do Hyeon(제목 · 이름) · VT323(전광판 숫자)은 Roblox에 없다 →
//  진짜 글꼴 파일을 화면 없는 Chrome으로 그려 흰 글자 판(아틀라스)으로 굽고, 글자마다의 치수를 적는다.
//   node tools/font/fetch.mjs     글꼴 파일 받기(처음 한 번 · tools/font/fonts/)
//   node tools/font/bake.mjs      굽기 → assets/font_*.png · src/shared/font/pixels/*.luau · src/shared/font/FontAtlas.luau
//  게임에 나올 수 있는 글자를 소스에서 모은다(Sim.luau · src/client 의 문자열). 그 글자가 글꼴에 없으면 멈춘다(아래 BODY_ONLY에 적힌 것만 빼고).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { launch } from '../bake/lib/cdp.mjs';
import { pack } from '../bake/lib/pack.mjs';
import { encodePNG } from '../bake/lib/png.mjs';
import { encodePage, luauModules } from '../bake/lib/codec.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const OUT = path.join(ROOT, 'src', 'shared', 'font');
const PIX = path.join(OUT, 'pixels');
const ASSETS = path.join(ROOT, 'assets');
const CHROME = ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(p => fs.existsSync(p));
const PAGE = 1024, GAP = 2, MAX_CHARS = 180000;

// 큰 글씨(30px 넘게)로 나오는 글: 이 글자들은 큰 판에도 굽는다(작은 판을 키우면 흐려진다)
const BIG = '출근길 서바이벌 0123456789:,. 오늘의 출근템 환승 보너스 레벨 업 일시정지 설정 이어서 출근하기 지각 출근 정시 출근 멘탈이 무너졌습니다';
// 본문 글꼴로만 나오는 글자(제목 글꼴에 없어도 된다). 여기에 없는 글자가 Do Hyeon에 없으면 굽기가 멈춘다
const BODY_ONLY = '→←↑↓「」『』〈〉★◆∥≤≥×ⓘ％～‘’“”•▲▼▶◀○●□■';
// Do Hyeon에 없지만 제목 글꼴 자리에 나오는 문장 부호(보스 줄의 「·」 등): harness.html이 단순한 도형으로 그려 넣는다
const SYNTH = '·…—';

// ---------- 글꼴 파일의 cmap: 어떤 글자가 들어 있는가 ----------
function cmapOf(file) {
  const b = fs.readFileSync(file); const n = b.readUInt16BE(4); let off = 0;
  for (let i = 0; i < n; i++) if (b.toString('latin1', 12 + i * 16, 16 + i * 16) === 'cmap') off = b.readUInt32BE(12 + i * 16 + 8);
  if (!off) throw new Error('cmap 표가 없다: ' + file);
  const has = new Set(); const nt = b.readUInt16BE(off + 2);
  for (let i = 0; i < nt; i++) {
    const so = off + b.readUInt32BE(off + 4 + i * 8 + 4), fmt = b.readUInt16BE(so);
    if (fmt === 4) {
      const seg = b.readUInt16BE(so + 6) / 2, endO = so + 14, startO = endO + seg * 2 + 2, deltaO = startO + seg * 2, rangeO = deltaO + seg * 2;
      for (let s = 0; s < seg; s++) {
        const end = b.readUInt16BE(endO + s * 2), start = b.readUInt16BE(startO + s * 2), delta = b.readInt16BE(deltaO + s * 2), ro = b.readUInt16BE(rangeO + s * 2);
        for (let c = start; c <= end && c !== 0xffff; c++) {
          let g; if (ro === 0) g = (c + delta) & 0xffff; else { const p = rangeO + s * 2 + ro + (c - start) * 2; g = b.readUInt16BE(p); if (g) g = (g + delta) & 0xffff; }
          if (g) has.add(c);
        }
      }
    } else if (fmt === 12) {
      const ng = b.readUInt32BE(so + 12);
      for (let g = 0; g < ng; g++) { const s = b.readUInt32BE(so + 16 + g * 12), e = b.readUInt32BE(so + 20 + g * 12); for (let c = s; c <= e; c++) has.add(c); }
    }
  }
  return has;
}

// ---------- 게임에 나올 수 있는 글자 ----------
function walk(dir, out = []) { for (const e of fs.readdirSync(dir, { withFileTypes: true })) { const p = path.join(dir, e.name); if (e.isDirectory()) { if (e.name !== 'pixels' && e.name !== 'art' && e.name !== 'font') walk(p, out); } else if (e.name.endsWith('.luau')) out.push(p); } return out; }
const sources = [path.join(ROOT, 'src', 'shared', 'Sim.luau'), ...walk(path.join(ROOT, 'src', 'client'))];
const need = new Set();
for (let c = 0x20; c <= 0x7e; c++) need.add(c);
for (const f of sources) {
  for (const line of fs.readFileSync(f, 'utf8').split(/\r?\n/)) {
    const code = line.replace(/--(?!\[).*$/, '');   // 주석은 뺀다(문자열 안의 "--"는 이 소스들에 없다)
    for (const m of code.matchAll(/"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'/g)) for (const ch of (m[1] ?? m[2])) { const c = ch.codePointAt(0); if (c > 0x7e) need.add(c); }
  }
}
for (const ch of BIG) need.add(ch.codePointAt(0));
const dh = cmapOf(path.join(HERE, 'fonts', 'DoHyeon-Regular.ttf')), vt = cmapOf(path.join(HERE, 'fonts', 'VT323-Regular.ttf'));
const bodyOnly = new Set([...BODY_ONLY].map(c => c.codePointAt(0)));
const synth = new Set([...SYNTH].map(c => c.codePointAt(0)));
for (const c of synth) { need.add(c); dh.add(c); }
const missing = [...need].filter(c => !dh.has(c) && !bodyOnly.has(c));
if (missing.length) {
  console.error('굽기 멈춤: 게임의 글에 있는데 Do Hyeon 글꼴에 없는 글자 ' + missing.length + '개: ' + missing.map(c => String.fromCodePoint(c) + '(U+' + c.toString(16).toUpperCase() + ')').join(' '));
  console.error('  본문 글꼴로만 나오는 글자라면 tools/font/bake.mjs의 BODY_ONLY에 적는다.');
  process.exit(1);
}
const dhChars = [...need].filter(c => dh.has(c)).sort((a, b) => a - b);
const skipped = [...need].filter(c => !dh.has(c)).sort((a, b) => a - b);
const bigChars = [...new Set([...BIG].map(c => c.codePointAt(0)))].filter(c => dh.has(c)).sort((a, b) => a - b);
const vtChars = []; for (let c = 0x20; c <= 0x7e; c++) if (vt.has(c)) vtChars.push(c);
console.log(`글자: 소스 ${sources.length}개에서 ${need.size}자 → Do Hyeon ${dhChars.length}자(큰 판 ${bigChars.length}자) · VT323 ${vtChars.length}자 · 본문 전용이라 뺀 것 ${skipped.length}자 ${skipped.map(c => String.fromCodePoint(c)).join('')}`);

// ---------- Chrome으로 그린다 ----------
const chrome = await launch({ chrome: CHROME, port: 9391, userDataDir: path.join(HERE, 'work', 'chrome-profile'), url: pathToFileURL(path.join(HERE, 'harness.html')).href, log: s => console.log(s) });
for (let i = 0; i < 50; i++) { if (await chrome.evaluate("typeof BAKE==='object'&&document.readyState==='complete'").catch(() => false)) break; await new Promise(r => setTimeout(r, 100)); }
if (!(await chrome.evaluate('BAKE.ready()'))) { await chrome.close(); throw new Error('글꼴을 읽지 못했다(tools/font/fonts/ — node tools/font/fetch.mjs)'); }
const FACES = [
  { name: 'dh_s', family: 'DoHyeon', em: 28, chars: dhChars },
  { name: 'dh_l', family: 'DoHyeon', em: 56, chars: bigChars },
  { name: 'vt', family: 'VT323', em: 40, chars: vtChars },
];
for (const f of FACES) {
  const r = await chrome.evaluate(`BAKE.face(${JSON.stringify(f.family)}, ${f.em}, ${JSON.stringify(String.fromCodePoint(...f.chars))})`);
  f.asc = r.asc; f.desc = r.desc; f.glyphs = r.glyphs;
  const bin = Buffer.from(r.alpha, 'base64'); let p = 0;
  for (const g of f.glyphs) { g.a = bin.subarray(p, p + g.w * g.h); p += g.w * g.h; }
}
// 검사용: 브라우저가 직접 그린 줄(구운 글자를 같은 자리에 놓아 견준다)
const CHECK = [['DoHyeon', 54, '출근길 서바이벌', 'dh_l'], ['DoHyeon', 20, '진상 전단지 알바 · 폭주까지 1:09', 'dh_s'], ['VT323', 36, '08:59', 'vt']];
const checks = [];
for (const [fam, px, text, face] of CHECK) checks.push({ fam, px, text, face, ...(await chrome.evaluate(`BAKE.line(${JSON.stringify(fam)}, ${px}, ${JSON.stringify(text)})`)) });
await chrome.close();

// ---------- 판에 채운다 ----------
fs.mkdirSync(PIX, { recursive: true });
for (const f of fs.readdirSync(PIX)) if (f.endsWith('.luau')) fs.unlinkSync(path.join(PIX, f));
const report = [];
for (const f of FACES) {
  const items = f.glyphs.filter(g => g.w > 0).map(g => ({ g, w: g.w + GAP, h: g.h + GAP }));
  const n = pack(items, PAGE, PAGE);
  f.pages = [];
  for (let pi = 0; pi < n; pi++) {
    const mine = items.filter(it => it.page === pi);
    const w = PAGE, h = Math.min(PAGE, Math.ceil(Math.max(...mine.map(it => it.y + it.h)) / 4) * 4);
    const rgba = new Uint8Array(w * h * 4);
    for (const it of mine) {
      const g = it.g; g.page = pi; g.x = it.x + 1; g.y = it.y + 1;
      for (let y = 0; y < g.h; y++) for (let x = 0; x < g.w; x++) { const a = g.a[y * g.w + x]; if (a) { const o = ((g.y + y) * w + g.x + x) * 4; rgba[o] = rgba[o + 1] = rgba[o + 2] = 255; rgba[o + 3] = a; } }
    }
    const name = 'font_' + f.name + (n > 1 ? '_' + (pi + 1) : '');
    f.pages.push({ name, w, h });
    // 올릴 PNG: 흰색 + 알파(투명한 곳도 흰색으로 — 늘일 때 검은 테가 끼지 않게)
    const png = new Uint8Array(rgba); for (let i = 0; i < w * h; i++) { png[i * 4] = png[i * 4 + 1] = png[i * 4 + 2] = 255; }
    const file = encodePNG(png, w, h); fs.writeFileSync(path.join(ASSETS, name + '.png'), file);
    const enc = encodePage({ rgba, w, h }, 256), mods = luauModules(name, enc, w, h, MAX_CHARS);
    let bytes = 0;
    for (const [fn, txt] of Object.entries(mods)) { const t = txt.replace('tools/bake/bake.mjs', 'tools/font/bake.mjs').replace('tools/bake/ART_NOTES.md', 'tools/bake/ART_NOTES.md 4장(그림 판과 같은 형식)'); fs.writeFileSync(path.join(PIX, fn), t); bytes += Buffer.byteLength(t); }
    f.pages[pi].parts = Object.keys(mods).length;
    report.push({ name, w, h, png: file.length, luau: bytes, parts: Object.keys(mods).length, glyphs: mine.length });
    f.pages[pi].rgba = rgba;
  }
}

// ---------- 치수 표 ----------
const r3 = v => Math.round(v * 1000) / 1000;
let s = `-- 자동 생성 (tools/font/bake.mjs) — 고치지 말 것. 구운 글자 판의 목록과 글자마다의 치수.\n`;
s += `-- faces[이름] = { em(구운 크기 px), asc · desc(밑줄 위 · 아래 높이 px), pages = { { name, w, h, parts } }, glyphs = { [코드] = { page, x, y, w, h, ox, oy, adv } } }\n`;
s += `--   x y w h = 판 위의 잉크 네모 · ox oy = 펜 자리(밑줄 위)에서 잰 그 네모의 왼쪽 위(위쪽이 음수) · adv = 다음 글자까지. 모두 em 크기에서의 px — 쓸 때는 (글씨 크기 / em)을 곱한다.\n`;
s += `-- 글꼴: Do Hyeon(dh_s 작은 판 · dh_l 큰 글씨용) · VT323(vt) — SIL Open Font License 1.1 (tools/font/fonts/*.OFL.txt)\nreturn {\n\tfaces = {\n`;
for (const f of FACES) {
  s += `\t\t${f.name} = {\n\t\t\tem = ${f.em}, asc = ${r3(f.asc)}, desc = ${r3(f.desc)},\n\t\t\tpages = { ${f.pages.map(p => `{ name = "${p.name}", w = ${p.w}, h = ${p.h}, parts = ${p.parts} }`).join(', ')} },\n\t\t\tglyphs = {\n`;
  for (const g of f.glyphs) s += g.w > 0 ? `\t\t\t\t[${g.c}] = { ${g.page + 1}, ${g.x}, ${g.y}, ${g.w}, ${g.h}, ${g.ox}, ${g.oy}, ${r3(g.adv)} },\n` : `\t\t\t\t[${g.c}] = { 0, 0, 0, 0, 0, 0, 0, ${r3(g.adv)} },\n`;
  s += `\t\t\t},\n\t\t},\n`;
}
s += `\t},\n}\n`;
fs.writeFileSync(path.join(OUT, 'FontAtlas.luau'), s);

// ---------- 검사: 구운 글자를 치수대로 놓은 줄 ↔ 브라우저가 직접 그린 줄 ----------
for (const c of checks) {
  const f = FACES.find(x => x.name === c.face), k = c.px / f.em; const ref = Buffer.from(c.data, 'base64');
  let pen = 4, maxDiff = 0; const base = Math.round(c.px * 1.15); const mine = new Float32Array(c.w * c.h);
  for (const ch of c.text) {
    const g = f.glyphs.find(x => x.c === ch.codePointAt(0)); if (!g) throw new Error('검사 글자가 판에 없다: ' + ch);
    if (g.w && k === 1) for (let y = 0; y < g.h; y++) for (let x = 0; x < g.w; x++) { const X = Math.round(pen + g.ox) + x, Y = base + g.oy + y; if (X >= 0 && X < c.w && Y >= 0 && Y < c.h) mine[Y * c.w + X] = Math.max(mine[Y * c.w + X], g.a[y * g.w + x]); }
    pen += g.adv * k;
  }
  if (k === 1) for (let i = 0; i < ref.length; i++) maxDiff = Math.max(maxDiff, Math.abs(ref[i] - mine[i]));
  console.log(`검사 「${c.text}」 ${c.fam} ${c.px}px: 브라우저 폭 ${r3(c.width)} · 치수로 셈한 폭 ${r3(pen - 4)}` + (k === 1 ? ` · 같은 크기로 놓았을 때 점 차이 최대 ${maxDiff}/255` : ''));
  const hasSynth = [...c.text].some(ch => synth.has(ch.codePointAt(0)));   // (도형으로 그린 부호의 폭은 브라우저가 고른 대체 글꼴과 조금 다를 수 있다)
  if (Math.abs(c.width - (pen - 4)) > (hasSynth ? 1 : 0.05)) { console.error('  폭이 다르다(커닝이 있는 글꼴?)'); process.exitCode = 1; }
}

// ---------- 검사: Luau로 풀리는가 ----------
let v = `local Decode = require("../../../src/shared/art/Decode")\nlocal ok = true\n`;
for (const f of FACES) for (const p of f.pages) {
  let cnt = 0; for (let i = 3; i < p.rgba.length; i += 4) if (p.rgba[i] > 0) cnt++;
  v += `do local buf, w, h = Decode.load(function(n) return require("../../../src/shared/font/pixels/" .. n) end, "${p.name}")\n local c = 0 for i = 3, w * h * 4 - 1, 4 do if buffer.readu8(buf, i) > 0 then c += 1 end end\n print("${p.name}", w, h, c) if w ~= ${p.w} or h ~= ${p.h} or c ~= ${cnt} then ok = false print("  다르다: 나와야 하는 것 ${p.w} ${p.h} ${cnt}") end end\n`;
}
v += `print(ok and "VERIFY OK" or "VERIFY FAIL")\n`;
fs.writeFileSync(path.join(HERE, 'work', 'verify.luau'), v);
const r = spawnSync(path.join(ROOT, 'tools', 'luau', 'luau.exe'), [path.join(HERE, 'work', 'verify.luau')], { encoding: 'utf8' });
console.log((r.stdout || '').trim()); if (!/VERIFY OK/.test(r.stdout || '')) { console.error(r.stderr); process.exitCode = 1; }

for (const p of report) console.log(`${p.name}: ${p.w}x${p.h} · 글자 ${p.glyphs}개 · PNG ${p.png}바이트 · Luau ${p.luau}바이트(조각 ${p.parts})`);
fs.writeFileSync(path.join(HERE, 'work', 'report.json'), JSON.stringify({ pages: report, chars: { dohyeon: dhChars.length, big: bigChars.length, vt323: vtChars.length, skipped: skipped.map(c => String.fromCodePoint(c)).join('') } }, null, 1));
