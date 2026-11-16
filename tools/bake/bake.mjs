// 출근길 서바이벌 — 원본 gfx.js의 그림을 로블록스용 아틀라스로 굽는다.
//   node tools/bake/bake.mjs            전부 다시 굽는다 (Chrome을 화면 없이 띄운다)
//   node tools/bake/bake.mjs --reuse    지난번에 Chrome에서 받아 둔 점 자료(work/raw.*)로 판 짜기부터 다시 한다
// 만드는 것: assets/*.png · src/shared/art/Atlas.luau · src/shared/art/pixels/*.luau · tools/bake/out/* · tools/bake/ART_NOTES.md
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { launch } from './lib/cdp.mjs';
import { encodePNG, decodePNG } from './lib/png.mjs';
import { pack } from './lib/pack.mjs';
import { quantizeInPlace } from './lib/quant.mjs';
import { bleed, encodePage, checksum, luauModules } from './lib/codec.mjs';
import { extract } from './snippets.mjs';

const BAKE = import.meta.dirname, ROOT = path.resolve(BAKE, '..', '..');
const WORK = path.join(BAKE, 'work'), OUT = path.join(BAKE, 'out'), ASSETS = path.join(ROOT, 'assets');
const ART = path.join(ROOT, 'src', 'shared', 'art'), PIX = path.join(ART, 'pixels');
const SRC = path.join(ROOT, 'commute-survival', 'js');
const LUAU = path.join(ROOT, 'tools', 'luau', 'luau.exe');
const CHROME = ['C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe', 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'].find(p => fs.existsSync(p));
const REUSE = process.argv.includes('--reuse');

/* ---- 정한 값 ---- */
const CFG = {
  port: 9377,          // DevTools 포트 (34872 · 34880과 겹치지 않게)
  pageW: 1024, pageH: 1024, pad: 2, extrude: 2,
  floorS: 2,           // 바닥 무늬: 세계 단위당 점 수 (원본과 같은 2 — 1이면 벽돌 줄눈이 흐려 보인다)
  trackS: 1.5,         // 선로 · 차도
  noiseQ: 0,           // 잡음 많은 그림을 미리 줄일 색 수 (0 = 안 줄임)
  // 판 묶음마다 팔레트 색 수. 256 이하면 점마다 1바이트, 넘으면 2바이트(두 면).  시험: BAKE_COLORS="chars=2048,fx=512"
  colors: { chars: 2048, mask: 512, world: 1024, fx: 2048, icons: 2048, floor: 256 },
  maxChars: 180000,    // 점 자료 모듈 하나의 글자 수 (Script.Source 20만 자 제한보다 작게)
};
for (const kv of (process.env.BAKE_COLORS || '').split(',').filter(Boolean)) { const [k, v] = kv.split('='); CFG.colors[k] = +v; }
const colorsOf = name => CFG.colors[Object.keys(CFG.colors).find(k => name.startsWith(k))] || 256;
const log = (...a) => console.log(...a);
for (const d of [WORK, OUT, ASSETS, PIX]) fs.mkdirSync(d, { recursive: true });

/* ================= 1. 원본 → 고친 복사본 · 조각 ================= */
const gsrc = fs.readFileSync(path.join(SRC, 'gfx.js'), 'utf8'), glines = gsrc.split('\n'), SN = extract(gsrc);
{
  const hook = gsrc.match(/return\{\r?\n  init\(canvas\)/g);
  if (!hook || hook.length !== 1) throw new Error('gfx.js의 끝(return{ init(canvas)…)이 예상과 다릅니다');
  // 덧붙이는 것은 이 한 줄뿐: GFX 안쪽의 이름을 바깥에서 읽고 부를 수 있게 한다
  fs.writeFileSync(path.join(WORK, 'gfx.patched.js'), gsrc.replace(/return\{(\r?\n  init\(canvas\))/, 'return{\n  __eval:function(__s){return eval(__s);},$1'));
  fs.writeFileSync(path.join(WORK, 'snippets.js'), 'window.SNIP=' + JSON.stringify(SN) + ';\n');
}
// 원본에서 글 s가 나오는 줄 번호들. word = 이름 뒤에 글자가 더 붙은 것(ST.car ↔ ST.card)은 뺀다
const linesWith = (s, word) => { const r = []; glines.forEach((l, i) => { for (let k = l.indexOf(s); k >= 0; k = l.indexOf(s, k + 1)) if (!word || !/[A-Za-z0-9_]$/.test(s) || !/[A-Za-z0-9_]/.test(l[k + s.length] || '')) { r.push(i + 1); break; } }); return r; };

/* ================= 2. Chrome에서 굽는다 ================= */
let meta, rawBuf, chrome = null;
const cfgPage = { floorS: CFG.floorS, trackS: CFG.trackS, noiseQ: CFG.noiseQ };
async function openChrome() {
  if (chrome) return chrome;
  if (!CHROME) throw new Error('Chrome/Edge를 찾지 못했습니다');
  chrome = await launch({ chrome: CHROME, port: CFG.port, userDataDir: path.join(WORK, 'chrome-profile'), url: pathToFileURL(path.join(BAKE, 'harness.html')).href, log });
  for (let i = 0; i < 100; i++) { if (await chrome.evaluate("typeof BAKE==='object'&&typeof SHEETS==='object'&&document.readyState==='complete'")) break; await new Promise(r => setTimeout(r, 100)); }
  return chrome;
}
if (REUSE && fs.existsSync(path.join(WORK, 'raw.json'))) {
  meta = JSON.parse(fs.readFileSync(path.join(WORK, 'raw.json'), 'utf8')); rawBuf = fs.readFileSync(path.join(WORK, 'raw.bin'));
  if (JSON.stringify(meta.cfg) !== JSON.stringify(cfgPage)) throw new Error('--reuse: 받아 둔 자료의 설정이 지금과 다릅니다. --reuse 없이 다시 구우세요');
  log('받아 둔 점 자료를 씁니다:', meta.sprites.length, '장');
} else {
  const c = await openChrome();
  meta = JSON.parse(await c.evaluate('JSON.stringify(BAKE.buildAll(' + JSON.stringify(cfgPage) + '))')); meta.cfg = cfgPage;
  const parts = []; let i0 = 0;
  while (i0 < meta.sprites.length) { let i1 = i0, n = 0; while (i1 < meta.sprites.length && (i1 === i0 || n + meta.sprites[i1].pw * meta.sprites[i1].ph * 4 < 6e6)) { n += meta.sprites[i1].pw * meta.sprites[i1].ph * 4; i1++; }
    parts.push(Buffer.from(await c.evaluate(`BAKE.pixels(${i0},${i1})`), 'base64')); i0 = i1; }
  rawBuf = Buffer.concat(parts);
  fs.writeFileSync(path.join(WORK, 'raw.json'), JSON.stringify(meta)); fs.writeFileSync(path.join(WORK, 'raw.bin'), rawBuf);
  log('Chrome에서 구운 그림:', meta.sprites.length, '장,', (rawBuf.length / 1e6).toFixed(1), 'MB');
}

/* ================= 3. 조각을 다듬고 판에 채운다 ================= */
const sprites = []; { let p = 0; for (const m of meta.sprites) { const n = m.pw * m.ph * 4; sprites.push({ ...m, w: m.pw, h: m.ph, rgba: new Uint8Array(rawBuf.subarray(p, p + n)) }); p += n; } }
const crop = (sp, x0, y0, w, h) => { const o = new Uint8Array(w * h * 4); for (let y = 0; y < h; y++) o.set(sp.rgba.subarray(((y0 + y) * sp.w + x0) * 4, ((y0 + y) * sp.w + x0 + w) * 4), y * w * 4); return o; };

// 캐릭터: 종류마다 모든 변형 · 걸음 그림의 「보이는 점」을 한데 모은 네모로 자른다 (종류 안에서는 크기와 기준점이 같다)
const trimOf = {};
for (const sp of sprites) if (sp.trim) {
  const t = trimOf[sp.ctype] || (trimOf[sp.ctype] = { x0: 1e9, y0: 1e9, x1: -1, y1: -1, w: sp.w, h: sp.h });
  for (let y = 0; y < sp.h; y++) for (let x = 0; x < sp.w; x++) if (sp.rgba[(y * sp.w + x) * 4 + 3]) { if (x < t.x0) t.x0 = x; if (x > t.x1) t.x1 = x; if (y < t.y0) t.y0 = y; if (y > t.y1) t.y1 = y; }
}
for (const k of Object.keys(trimOf)) { const t = trimOf[k]; t.x0 = Math.max(0, t.x0 - 1); t.y0 = Math.max(0, t.y0 - 1); t.x1 = Math.min(t.w - 1, t.x1 + 1); t.y1 = Math.min(t.h - 1, t.y1 + 1); }
for (const sp of sprites) if (sp.trim) {
  const t = trimOf[sp.ctype], w = t.x1 - t.x0 + 1, h = t.y1 - t.y0 + 1;
  sp.rgba = crop(sp, t.x0, t.y0, w, h); sp.w = w; sp.h = h; sp.ox -= t.x0 / sp.s; sp.oy -= t.y0 / sp.s;
}
for (const k of Object.keys(meta.chars)) { const t = trimOf[k], C = meta.chars[k]; C.tx = t.x0 / C.s; C.ty = t.y0 / C.s; C.tw = (t.x1 - t.x0 + 1) / C.s; C.th = (t.y1 - t.y0 + 1) / C.s; }
for (const sp of sprites) if (sp.q) sp.qn = quantizeInPlace(sp.rgba, sp.q);

// 이어 붙는 그림(tile)과 가장자리까지 꽉 찬 그림(clamp)은 둘레 2점을 덧댄다: 이어 붙는 쪽은 반대편 점을, 아닌 쪽은 가장자리 점을 늘인다
function extruded(sp, e) {
  const W = sp.w + e * 2, H = sp.h + e * 2, o = new Uint8Array(W * H * 4), tx = sp.tile === 'x', ty = sp.tile === 'y';
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    let sx = x - e, sy = y - e;
    sx = tx ? (sx + sp.w) % sp.w : Math.max(0, Math.min(sp.w - 1, sx)); sy = ty ? (sy + sp.h) % sp.h : Math.max(0, Math.min(sp.h - 1, sy));
    const s = (sy * sp.w + sx) * 4, d = (y * W + x) * 4; o[d] = sp.rgba[s]; o[d + 1] = sp.rgba[s + 1]; o[d + 2] = sp.rgba[s + 2]; o[d + 3] = sp.rgba[s + 3];
  }
  return { rgba: o, w: W, h: H };
}

const pages = [], entry = {};   // pages: { name, w, h, rgba }, entry[name] = { page(1부터), x, y, w, h, s, ox, oy }
const groups = [...new Set(sprites.filter(s => s.group !== 'mask').map(s => s.group))];
const byName = Object.fromEntries(sprites.map(s => [s.name, s]));
for (const gname of groups) {
  const list = sprites.filter(s => s.group === gname);
  if (list[0].own) {   // 바닥 무늬: 그림 한 장이 곧 판 한 장 (여백 없음 — 통째로 이어 붙인다)
    for (const sp of list) { pages.push({ name: gname, w: sp.w, h: sp.h, rgba: sp.rgba.slice(), group: gname }); entry[sp.name] = { page: gname, x: 0, y: 0, w: sp.w, h: sp.h, s: sp.s, ox: sp.ox, oy: sp.oy }; }
    continue;
  }
  const items = list.map(sp => { const e = (sp.tile || sp.clamp) ? CFG.extrude : 0, img = e ? extruded(sp, e) : sp; return { sp, e, img, name: sp.name, w: img.w + CFG.pad, h: img.h + CFG.pad }; });
  const np = pack(items, CFG.pageW - CFG.pad, CFG.pageH - CFG.pad);
  for (let p = 0; p < np; p++) {
    const its = items.filter(it => it.page === p), used = Math.max(...its.map(it => it.y + it.h)) + CFG.pad, H = Math.min(CFG.pageH, Math.ceil(used / 4) * 4);
    const pg = { name: gname + (p + 1), w: CFG.pageW, h: H, rgba: new Uint8Array(CFG.pageW * H * 4), group: gname };
    const mk = gname === 'chars' ? { name: 'mask' + (p + 1), w: CFG.pageW, h: H, rgba: new Uint8Array(CFG.pageW * H * 4), group: 'mask' } : null;
    for (const it of its) {
      const X = it.x + CFG.pad, Y = it.y + CFG.pad;
      for (let y = 0; y < it.img.h; y++) pg.rgba.set(it.img.rgba.subarray(y * it.img.w * 4, (y + 1) * it.img.w * 4), ((Y + y) * CFG.pageW + X) * 4);
      entry[it.sp.name] = { page: pg.name, x: X + it.e, y: Y + it.e, w: it.sp.w, h: it.sp.h, s: it.sp.s, ox: it.sp.ox, oy: it.sp.oy };
      if (mk) { const ms = byName[it.sp.name.replace(/^char\//, 'mask/')]; if (!ms || ms.w !== it.sp.w || ms.h !== it.sp.h) throw new Error('가면 그림이 없거나 크기가 다릅니다: ' + it.sp.name);
        for (let y = 0; y < ms.h; y++) mk.rgba.set(ms.rgba.subarray(y * ms.w * 4, (y + 1) * ms.w * 4), ((Y + y) * CFG.pageW + X) * 4);
        entry[ms.name] = { ...entry[it.sp.name], page: mk.name }; }
    }
    pages.push(pg); if (mk) pages.push(mk);
  }
}
// 판 순서: 캐릭터 → 가면 → 세계 → 효과 → 아이콘 → 바닥 (판 번호는 여기서 매긴다)
{ const rank = n => ['chars', 'mask', 'world', 'fx', 'icons'].findIndex(p => n.startsWith(p)) + 1 || 9;
  pages.forEach((p, i) => { p.seq = i; }); pages.sort((a, b) => rank(a.name) - rank(b.name) || a.seq - b.seq);
  const at = Object.fromEntries(pages.map((p, i) => [p.name, i + 1])); for (const e of Object.values(entry)) e.page = at[e.page]; }
log('판:', pages.map(p => `${p.name} ${p.w}×${p.h}`).join(', '));

/* ================= 4. PNG · 점 자료 모듈 ================= */
for (const f of fs.readdirSync(PIX)) if (f.endsWith('.luau') && fs.readFileSync(path.join(PIX, f), 'utf8').startsWith('-- 자동 생성 (tools/bake/bake.mjs)')) fs.unlinkSync(path.join(PIX, f));
for (const f of fs.readdirSync(ASSETS)) if (f.endsWith('.png') && !pages.some(p => p.name + '.png' === f)) log('  (알림) assets에 이번에 굽지 않은 PNG가 있습니다 — 그대로 둡니다:', f);
const report = [];
for (const pg of pages) {
  const png = pg.rgba.slice(); bleed(png, pg.w, pg.h);
  const file = encodePNG(png, pg.w, pg.h); fs.writeFileSync(path.join(ASSETS, pg.name + '.png'), file);
  const back = decodePNG(fs.readFileSync(path.join(ASSETS, pg.name + '.png'))); let same = back.w === pg.w && back.h === pg.h; for (let i = 0; same && i < png.length; i++) if (back.rgba[i] !== png[i]) same = false;
  if (!same) throw new Error('PNG를 다시 읽으니 다릅니다: ' + pg.name);
  const enc = encodePage(pg, colorsOf(pg.name)), mods = luauModules(pg.name, enc, pg.w, pg.h, CFG.maxChars); let bytes = 0, maxMod = 0;
  for (const [fn, txt] of Object.entries(mods)) { fs.writeFileSync(path.join(PIX, fn), txt); bytes += Buffer.byteLength(txt); maxMod = Math.max(maxMod, Buffer.byteLength(txt)); }
  // 색을 줄여서 생긴 차이: PNG의 점과 견준다 (알파를 곱한 색 · 알파)
  let maxErr = 0, sumErr = 0, nvis = 0, over8 = 0, maxA = 0;
  for (let i = 0; i < pg.w * pg.h; i++) {
    const a0 = png[i * 4 + 3], a1 = enc.out[i * 4 + 3]; if (!a0 && !a1) continue; nvis++;
    let e = Math.abs(a0 - a1); maxA = Math.max(maxA, e);
    for (let c = 0; c < 3; c++) e = Math.max(e, Math.abs(png[i * 4 + c] * a0 - enc.out[i * 4 + c] * a1) / 255);
    maxErr = Math.max(maxErr, e); sumErr += e; if (e > 8) over8++;
  }
  pg.enc = enc; pg.parts = Object.keys(mods).length;
  fs.writeFileSync(path.join(WORK, 'q_' + pg.name + '.png'), encodePNG(enc.out, pg.w, pg.h));   // 색을 줄인 뒤의 모습 (견줘 보기용)
  report.push({ name: pg.name, w: pg.w, h: pg.h, png: file.length, luau: bytes, maxMod, parts: pg.parts, colors: enc.colors, unique: enc.unique, exact: enc.exact, maxErr: +maxErr.toFixed(2), meanErr: +(sumErr / Math.max(1, nvis)).toFixed(3), over8, nvis, sum: checksum(enc.out) });
  log(`  ${pg.name.padEnd(13)} ${String(pg.w).padStart(4)}×${String(pg.h).padEnd(4)} PNG ${String(file.length).padStart(7)}  Luau ${String(bytes).padStart(7)} (${pg.parts}조각)  색 ${enc.unique}→${enc.colors}${enc.exact ? ' (그대로)' : ''}  최대 오차 ${maxErr.toFixed(1)} 평균 ${(sumErr / Math.max(1, nvis)).toFixed(3)} (8 넘는 점 ${over8})`);
}
log('  합계: PNG', report.reduce((a, r) => a + r.png, 0), ' Luau', report.reduce((a, r) => a + r.luau, 0));

/* ================= 5. Atlas.luau ================= */
const num = v => { const r = Math.round(v * 1000) / 1000; return String(r); };
const names = Object.keys(entry).sort((a, b) => { const ga = a.split('/')[0], gb = b.split('/')[0]; return ga === gb ? a.localeCompare(b, 'en', { numeric: true }) : ga.localeCompare(gb); });
{
  let s = `-- 자동 생성 (tools/bake/bake.mjs) — 고치지 말 것. 다시 만들려면: node tools/bake/bake.mjs
-- 구운 그림의 목록. 그림 설명 · 원본에서 그리는 줄은 tools/bake/ART_NOTES.md.
--
-- pages[i]   = { name, file(assets/ 안의 PNG), w, h, parts(점 자료 모듈 수: pixels/<name>, pixels/<name>_2, …) }
-- sprites[이름] = { page(pages의 번호), x, y, w, h (판 위의 점), s (세계 단위당 점 수), ox, oy (기준점: 그림 왼쪽 위에서 잰 세계 단위) }
--     화면에 놓는 법: 크기 = (w/s, h/s) × 배율,  왼쪽 위 = 기준점 놓을 자리 − (ox, oy) × 배율.  좌우 뒤집을 때는 왼쪽 위 x = 자리 − (w/s − ox) × 배율.
-- 이름:
--   char/<종류>/<변형>/<걸음>   캐릭터 (오른쪽을 봄). 기준점 = 발 (원본 SPR의 ox, oy). 걸음 번호는 chars[종류].frames[걸음단계+1]로 얻는다.
--   mask/<종류>/<변형>/<걸음>   같은 그림의 흰 실루엣 (맞았을 때 번쩍). 판만 다르고 x, y, w, h는 char와 같다.
--   st/… fx/… ws/…            원본이 미리 그려 두는 캔버스 ST.* · FX.* · WS.* (기준점 = 한가운데, 이어 붙는 띠는 왼쪽 위)
--   floor/<장소 key>           바닥 무늬. 판 한 장을 통째로 쓴다 (512×512 단위로 이어 붙인다)
--   icon/<key> · icon/<key>/evo  무기 · 장비 · 조합 · 회복 아이콘 (48×48 단위 = 96×96 점)
--   sc/… tr/… ui/… prim/…      그리기 반복문 안에 직접 적힌 그림을 구운 것 (바닥 표시 · 열차 안 · 화면 표시 · 도움 도형)
-- chars[종류] = { nv 변형 수, frames 걸음 4단계 → 걸음 그림 번호, w,h,ox,oy 원본 SPR의 값(세계 단위), sc 캔버스 안에서 키운 배율(이미 구워져 있음),
--                 s 밀도, tx,ty,tw,th 구울 때 잘라 낸 네모(원본 캔버스 안, 세계 단위) }
return {
\tpages = {
`;
  for (const pg of pages) s += `\t\t{ name = "${pg.name}", file = "${pg.name}.png", w = ${pg.w}, h = ${pg.h}, parts = ${pg.parts} },\n`;
  s += '\t},\n\tsprites = {\n';
  for (const n of names) { const e = entry[n]; s += `\t\t["${n}"] = { page = ${e.page}, x = ${e.x}, y = ${e.y}, w = ${e.w}, h = ${e.h}, ox = ${num(e.ox)}, oy = ${num(e.oy)}, s = ${num(e.s)} },\n`; }
  s += '\t},\n\tchars = {\n';
  for (const [k, C] of Object.entries(meta.chars)) s += `\t\t${k} = { nv = ${C.nv}, frames = { ${C.frames.join(', ')} }, w = ${C.w}, h = ${C.h}, ox = ${C.ox}, oy = ${C.oy}, sc = ${C.sc}, s = ${C.s}, tx = ${num(C.tx)}, ty = ${num(C.ty)}, tw = ${num(C.tw)}, th = ${num(C.th)} },\n`;
  s += '\t},\n}\n';
  fs.writeFileSync(path.join(ART, 'Atlas.luau'), s);
}
const atlasJson = { pages: pages.map(p => ({ name: p.name, w: p.w, h: p.h })), sprites: entry, chars: meta.chars };
fs.writeFileSync(path.join(OUT, 'atlas.json'), JSON.stringify(atlasJson));

/* ================= 6. luau.exe로 풀어 본다 ================= */
const rel = p => path.relative(WORK, p).split(path.sep).join('/');
{
  let s = `-- 자동 생성: 판마다 점 자료를 풀어 검사 합과 걸린 시간을 찍는다\nlocal Decode = require("${rel(path.join(ART, 'Decode'))}")\nlocal function get(n) return require("${rel(PIX)}/" .. n) end\nlocal names = { ${pages.map(p => '"' + p.name + '"').join(', ')} }\nlocal M = 4294967291\nlocal total = 0\nfor _, name in names do\n\tlocal t0 = os.clock()\n\tlocal head = get(name)\n\tlocal extra = {}\n\tfor i = 2, head.parts do table.insert(extra, get(name .. "_" .. i)) end\n\tlocal t1 = os.clock()\n\tlocal buf, w, h = Decode.page(head, extra)\n\tlocal t2 = os.clock()\n\tlocal a, b = 1, 0\n\tfor i = 0, w * h * 4 - 4, 4 do\n\t\ta = (a + buffer.readu32(buf, i)) % M\n\t\tb = (b + a) % M\n\tend\n\ttotal += t2 - t1\n\tprint(string.format("%s %d %d %d %.0f:%.0f %.4f %.4f", name, w, h, buffer.len(buf), a, b, t1 - t0, t2 - t1))\nend\nprint(string.format("TOTAL %.4f", total))\n`;
  fs.writeFileSync(path.join(WORK, 'verify.luau'), s);
}
const verify = {};
for (const mode of ['interp', 'codegen']) {
  let outp;
  try { outp = execFileSync(LUAU, mode === 'codegen' ? ['--codegen', 'verify.luau'] : ['verify.luau'], { cwd: WORK, encoding: 'utf8', maxBuffer: 1 << 26 }); }
  catch (e) { if (mode === 'codegen') { log('  (--codegen 실행 실패: ' + String(e.message).split('\n')[0] + ')'); continue; } throw e; }
  for (const line of outp.trim().split(/\r?\n/)) {
    const f = line.split(' ');
    if (f[0] === 'TOTAL') { verify['total_' + mode] = +f[1]; continue; }
    const r = report.find(x => x.name === f[0]); if (!r) throw new Error('verify: 모르는 줄 ' + line);
    if (mode === 'interp') { r.ok = +f[1] === r.w && +f[2] === r.h && +f[3] === r.w * r.h * 4 && f[4] === r.sum; r.luauSum = f[4]; r.tReq = +f[5]; r.tDec = +f[6]; if (!r.ok) throw new Error(`검사 합이 다릅니다: ${r.name} luau ${f[4]} / node ${r.sum}`); }
    else { r.tDecJit = +f[6]; if (f[4] !== r.sum) throw new Error('--codegen 검사 합이 다릅니다: ' + r.name); }
  }
}
log(`luau.exe로 푼 결과: ${report.length}장 모두 검사 합이 같습니다. 푸는 시간 합계 ${verify.total_interp?.toFixed(3)}초 (인터프리터)` + (verify.total_codegen !== undefined ? ` · ${verify.total_codegen.toFixed(3)}초 (--codegen)` : ''));
fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify({ cfg: CFG, pages: report, verify }, null, 1));

/* ================= 7. 견본표 ================= */
{
  const c = await openChrome();
  await c.evaluate('SHEETS.setAtlas(' + JSON.stringify(atlasJson) + ')');
  // 견본표는 「게임이 실제로 쓰는 점」(색을 줄인 뒤 · 점 자료 모듈을 풀면 나오는 것)으로 만든다
  for (const pg of pages) await c.evaluate(`SHEETS.addPage(${JSON.stringify(pg.name)}, "data:image/png;base64,${encodePNG(pg.enc.out, pg.w, pg.h).toString('base64')}")`);
  const save = async (file, expr) => { const url = await c.evaluate(expr); fs.writeFileSync(path.join(OUT, file), Buffer.from(url.split(',')[1], 'base64')); };
  for (const f of fs.readdirSync(OUT)) if (/^contact_.*\.png$/.test(f)) fs.unlinkSync(path.join(OUT, f));
  const types = Object.keys(meta.chars), big = types.filter(t => meta.chars[t].w > 100), small = types.filter(t => meta.chars[t].w <= 100);
  const rows = []; let cur = [], n = 0; for (const t of small) { if (n + meta.chars[t].nv > 7 && cur.length) { rows.push(cur); cur = []; n = 0; } cur.push(t); n += meta.chars[t].nv; } if (cur.length) rows.push(cur);
  for (let i = 0; i < rows.length; i++) await save(`contact_chars_${i + 1}.png`, `SHEETS.charSheet(${JSON.stringify(rows[i])}, true)`);
  for (let i = 0; i < big.length; i++) await save(`contact_boss_${i + 1}.png`, `SHEETS.bossSheet(${JSON.stringify([big[i]])})`);
  const rest = names.filter(n => !/^(char|mask|floor)\//.test(n)), cat = {};
  for (const n of rest) { const k = n.split('/')[0]; (cat[k] = cat[k] || []).push(n); }
  for (const [k, list] of Object.entries(cat)) { const per = k === 'icon' ? 60 : 36; for (let i = 0; i * per < list.length; i++) await save(`contact_${k}_${i + 1}.png`, `SHEETS.flowSheet(${JSON.stringify(list.slice(i * per, (i + 1) * per))}, 1280, 300)`); }
  await save('contact_floors.png', `SHEETS.flowSheet(${JSON.stringify(names.filter(n => n.startsWith('floor/')))}, 1340, 420)`);
  for (const pg of pages) if (!pg.name.startsWith('floor')) await save(`contact_page_${pg.name}.png`, `SHEETS.pageSheet(${JSON.stringify(pg.name)}, ${pg.w > 512 ? 1 : 1})`);
  // 이어 붙는 것들의 솔기
  for (const [n, nx, ny, k] of [['st/track', 3, 1, 1], ['ws/road', 3, 1, 1], ['st/tact', 3, 1, 1], ['ws/esc', 1, 3, 1], ['ws/stair', 1, 3, 1]]) await save(`contact_tile_${n.replace('/', '_')}.png`, `SHEETS.tileSheet(${JSON.stringify(n)}, ${nx}, ${ny}, ${k})`);
  for (const n of names.filter(n => n.startsWith('floor/'))) await save(`contact_tile_${n.replace('/', '_')}.png`, `SHEETS.tileSheet(${JSON.stringify(n)}, 2, 2, 1)`);
  log('견본표:', fs.readdirSync(OUT).filter(f => f.startsWith('contact_')).length, '장 →', OUT);
}
if (chrome) await chrome.close();

/* ================= 8. ART_NOTES.md ================= */
{
  const row = (n) => {
    const e = entry[n], m = byName[n]; let where;
    if (m.lines) where = m.lines === '(없음)' ? '—' : 'gfx.js ' + m.lines;
    else if (n.startsWith('char/') || n.startsWith('mask/')) where = '';
    else if (n.startsWith('icon/')) where = 'icon() ' + linesWith('function icon(')[0] + ' · ICON 표 ' + linesWith('const ICON={')[0] + '–' + (linesWith('function icon(')[0] - 1) + ' · 쓰는 곳 main.js 81, 194';
    else { const d = m.def ? linesWith(m.def) : [], u = m.use ? linesWith(m.use, true).filter(l => !d.includes(l)) : []; where = (d.length ? '만듦 ' + d.join(', ') : '') + (u.length ? (d.length ? ' · ' : '') + '그림 ' + (u.length > 14 ? u.slice(0, 14).join(', ') + ' …' : u.join(', ')) : ''); }
    return `| \`${n}\` | ${m.desc || ''} | ${num(e.w / e.s)}×${num(e.h / e.s)} | ${e.w}×${e.h} @${num(e.s)} | ${pages[e.page - 1].name} | ${where} |`;
  };
  const section = (title, pred) => { const l = names.filter(pred); return l.length ? `\n### ${title} (${l.length})\n\n| 이름 | 무엇 | 크기(세계 단위) | 판 위의 점 @밀도 | 판 | 원본 gfx.js 줄 |\n|---|---|---|---|---|---|\n${l.map(row).join('\n')}\n` : ''; };
  let cat = '';
  cat += `\n### 캐릭터 char/<종류>/<변형>/<걸음> · mask/… (${names.filter(n => n.startsWith('char/')).length} + ${names.filter(n => n.startsWith('mask/')).length})\n\n원본: \`SPR\` 표 gfx.js ${linesWith('const SPR={')[0]}–${linesWith('const cache=new Map()')[0] - 1}줄, 몸 그리기 \`chibi\` ${linesWith('function chibi(')[0]}줄 · \`face\` ${linesWith('function face(')[0]}줄, 캐시 \`sprite()\` ${linesWith('function sprite(')[0]}줄, 화면에 놓기 \`drawChar()\` ${linesWith('function drawChar(')[0]}줄 (부르는 곳 ${linesWith('drawChar(').slice(1).join(', ')}줄).\n\n| 종류 | 변형 수 | 걸음 그림 | 원본 캔버스(세계 단위) · 발 기준점 | 잘라 낸 네모 → 판 위 크기 | 누가 쓰나 |\n|---|---|---|---|---|---|\n`;
  const WHO = { player: '플레이어', pass: '승객 · 하차 인파(12명 묶음) · 열차 의자에 앉은 사람 · 승강장 줄', zomb: '스마트폰 좀비', intern: '아아 든 인턴', stud: '백팩 학생', runner: '뛰는 승객', flyer: '전단지 알바 · 보스 「진상 전단지 알바」(×1.7)', uncle: '쩍벌 아저씨 · 보스 「문지기」(×1.9) · 「김 팀장」(×2)', carrier: '캐리어 여행객 · 보스 「진상 캐리어 여행객」(×1.8)', bagman: '보스 「백팩 빌런」', speaker: '보스 「스피커 빌런」' };
  for (const [k, C] of Object.entries(meta.chars)) { const e = entry[`char/${k}/0/0`]; cat += `| \`${k}\` | ${C.nv} | ${[...new Set(C.frames)].join(', ')} (4단계 → ${C.frames.join(',')}) | ${C.w}×${C.h} · (${C.ox}, ${C.oy})${C.sc !== 1 ? ' · 안에서 ×' + C.sc : ''} | (${num(C.tx)}, ${num(C.ty)}) ${num(C.tw)}×${num(C.th)} → ${e.w}×${e.h}점, 기준점 (${num(e.ox)}, ${num(e.oy)}) | ${WHO[k] || ''} |\n`; }
  cat += section('미리 그려 두는 캔버스 — buildStatic의 ST.*', n => n.startsWith('st/'));
  cat += section('미리 그려 두는 캔버스 — buildWorld의 WS.*', n => n.startsWith('ws/'));
  cat += section('효과 · 무기 — buildFx의 FX.*, glow, 그리고 그리기 반복문에서 구운 것', n => n.startsWith('fx/'));
  cat += section('바닥 표시 (그리기 반복문에서 구운 것)', n => n.startsWith('sc/'));
  cat += section('열차 안 (drawTrainIn · drawTrainOver에서 구운 것)', n => n.startsWith('tr/'));
  cat += section('화면 표시', n => n.startsWith('ui/'));
  cat += section('도움 도형 (원본에 없음)', n => n.startsWith('prim/'));
  cat += section('바닥 무늬 floorTile(i)', n => n.startsWith('floor/'));
  cat += section('아이콘 GFX.icon(key, evo)', n => n.startsWith('icon/'));
  let pg = '| 판 | 크기 | PNG 바이트 | Luau 모듈 바이트 (조각 수 · 가장 큰 조각) | 색 수 (원래 → 팔레트) | 최대 오차 · 평균 · 8 넘는 점 | 푸는 시간(초) 인터프리터' + (verify.total_codegen !== undefined ? ' · --codegen' : '') + ' |\n|---|---|---|---|---|---|---|\n';
  for (const r of report) pg += `| \`${r.name}\` | ${r.w}×${r.h} | ${r.png.toLocaleString('en')} | ${r.luau.toLocaleString('en')} (${r.parts} · ${r.maxMod.toLocaleString('en')}) | ${r.unique.toLocaleString('en')} → ${r.colors}${r.exact ? ' (그대로)' : ''} | ${r.maxErr} · ${r.meanErr} · ${r.over8.toLocaleString('en')} / ${r.nvis.toLocaleString('en')} | ${r.tDec.toFixed(3)}${r.tDecJit !== undefined ? ' · ' + r.tDecJit.toFixed(3) : ''} |\n`;
  pg += `| **합계** | ${report.length}장 | ${report.reduce((a, r) => a + r.png, 0).toLocaleString('en')} | ${report.reduce((a, r) => a + r.luau, 0).toLocaleString('en')} | | | ${verify.total_interp.toFixed(3)}${verify.total_codegen !== undefined ? ' · ' + verify.total_codegen.toFixed(3) : ''} |\n`;
  const tplPath = path.join(BAKE, 'notes.template.md');
  if (fs.existsSync(tplPath)) {
    const snipLine = n => SN[n] ? String(SN[n].line) : '?';
    const out = fs.readFileSync(tplPath, 'utf8').replace('{{CATALOGUE}}', () => cat).replace('{{PAGES}}', () => pg).replace('{{DATE}}', new Date().toISOString().slice(0, 10)).replace(/\{\{L:([^}]+)\}\}/g, (_, s) => { const l = linesWith(s); return l.length ? l.join(', ') : '?'; }).replace(/\{\{S:([^}]+)\}\}/g, (_, s) => snipLine(s));
    fs.writeFileSync(path.join(BAKE, 'ART_NOTES.md'), out);
    log('ART_NOTES.md를 다시 썼습니다');
  } else log('(notes.template.md가 없어 ART_NOTES.md는 건너뜁니다)');
}
log('끝.');
