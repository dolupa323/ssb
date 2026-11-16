// 원본 audio.js의 합성 소리를 화면 없는 Chrome(OfflineAudioContext)에서 돌려 WAV로 굽는다.
//   node tools/audio/bake.mjs
// 만드는 것: assets/audio/*.wav · src/shared/SoundMap.luau · src/shared/SoundIds.luau(이미 적힌 번호는 지킨다)
//            tools/audio/work/manifest.json(검사 도구가 읽는다)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { launch } from './lib/cdp.mjs';
import { writeWav } from './lib/wav.mjs';
import { updateNotes } from './notes.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const ORIG_DIR = path.join(ROOT, 'commute-survival', 'js');
const WORK = path.join(HERE, 'work');
const OUT = path.join(ROOT, 'assets', 'audio');
const SHARED = path.join(ROOT, 'src', 'shared');
const SR = 44100;
const PORT = 9351;

// ── 굽는 규칙 (바꾸면 다시 구우면 된다) ─────────────────────────────────────────
const PRE = Math.round(0.002 * SR);     // 구간 앞에 두는 무음
const FADE = Math.round(0.03 * SR);     // 꼬리를 자른 뒤 0으로 내리는 길이
const POST = Math.round(0.005 * SR);    // 구간 끝에 두는 무음
const GAP = Math.round(0.25 * SR);      // 구간과 구간 사이의 무음 (요구: 0.15초 이상)
const LEAD = GAP;                       // 파일 맨 앞의 무음
const XF = Math.round(0.03 * SR);       // 순환 이음매를 맞추는 길이
const MAX_BYTES = 19e6;                 // 로블록스 한도 20MB보다 조금 작게
const MAX_SEC = 400;                    // 로블록스 한도 7분(420초)보다 조금 작게
const RND_COUNT = { hit: 3, kill: 4 };  // 무작위로 바뀌는 효과음을 몇 가지 굽나 (기본 3)
const KIND = { '': 'one', evo: 'flag', src: 'key', who: 'key', v: 'pick', n: 'tick' };
const GUARD = 64;                       // 끝없이 도는 구간의 앞뒤에 붙이는 덧표본 수

const log = (...a) => console.log(...a);
const die = m => { console.error('실패: ' + m); process.exit(1); };
const count = (s, sub) => s.split(sub).length - 1;
const fnv = str => { let h = 0x811c9dc5; for (const c of Buffer.from(str, 'utf8')) { h ^= c; h = Math.imul(h, 0x01000193) >>> 0; } return h || 1; };
const db = v => v > 0 ? 20 * Math.log10(v) : -Infinity;
const sec = n => n / SR;

// ── 1. 원본을 복사해 고친다 (원본은 건드리지 않는다) ─────────────────────────────
fs.mkdirSync(WORK, { recursive: true }); fs.mkdirSync(OUT, { recursive: true }); fs.mkdirSync(SHARED, { recursive: true });
let src = fs.readFileSync(path.join(ORIG_DIR, 'audio.js'), 'utf8');
const ANCHOR = '_test:{build,';
if (count(src, ANCHOR) !== 1) die('audio.js에서 `' + ANCHOR + '`를 찾지 못했다 (원본이 바뀌었다)');
if (count(src, 'I.crash(nextT,.3)') !== 1) die('audio.js에서 노래가 바뀔 때의 심벌 `I.crash(nextT,.3)`을 찾지 못했다 (harness.js의 B.crash를 맞춰야 한다)');
// 고친 곳은 하나: 굽는 데 필요한 안쪽 값을 _test로 내놓는다 (소리를 만드는 코드는 그대로)
src = src.replace(ANCHOR, '_test:{I,HIT,VOICE,VOL,setPick(s,lp){streak=s;lastPick=lp;},build,');
fs.writeFileSync(path.join(WORK, 'audio.patched.js'), '/* 자동 생성: commute-survival/js/audio.js의 복사본 + _test에 I·HIT·VOICE·VOL·setPick 추가 (tools/audio/bake.mjs) */\n' + src);

// ── 2. 원본이 어떤 이름 · 인자로 효과음을 부르는지 훑는다 ──────────────────────────
function scanCalls() {
  const uses = {};
  for (const f of ['sim.js', 'main.js']) {
    const text = fs.readFileSync(path.join(ORIG_DIR, f), 'utf8');
    const re = /(?:host|AudioSys)\.sfx\(/g; let m;
    while ((m = re.exec(text))) {
      let i = m.index + m[0].length, depth = 0, start = i; const parts = [];
      for (; i < text.length; i++) {
        const c = text[i];
        if (c === '(' || c === '[' || c === '{') depth++;
        else if (c === ')' || c === ']' || c === '}') { if (depth === 0) break; depth--; }
        else if (c === ',' && depth === 0) { parts.push(text.slice(start, i)); start = i + 1; }
      }
      parts.push(text.slice(start, i));
      // 첫 인자 안의 글자들이 이름이다. 견주는 데 쓴 글자(src==='train' 같은 것)는 뺀다
      const names = [...parts[0].replace(/[=!]==?\s*'[^']*'/g, '').matchAll(/'([A-Za-z0-9_]+)'/g)].map(x => x[1]);
      if (!names.length) continue;                      // host.sfx(n,x,arg) 같은 전달 코드
      for (const n of names) { (uses[n] ||= []).push({ file: f, arg: (parts[2] || '').trim() }); }
    }
  }
  return uses;
}
const uses = scanCalls();

// ── 3. Chrome을 띄운다 ────────────────────────────────────────────────────────
const chrome = [process.env.CHROME, 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe', 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'].find(p => p && fs.existsSync(p));
if (!chrome) die('Chrome/Edge를 찾지 못했다');
const page = await launch({ chrome, port: PORT, userDataDir: path.join(WORK, 'chrome-profile'), url: pathToFileURL(path.join(HERE, 'harness.html')).href, log: m => log('  ' + m) });
const call = (fn, arg) => page.evaluate(`B.${fn}(${arg === undefined ? '' : JSON.stringify(arg)})`);
const f32 = b => { const buf = Buffer.from(b, 'base64'); const out = new Float32Array(buf.length / 4); for (let i = 0; i < out.length; i++) out[i] = buf.readFloatLE(i * 4); return out; };
async function fetchStereo(id) {
  const n = await call('len', id), ch = [new Float32Array(n), new Float32Array(n)], STEP = 1 << 20;
  for (let c = 0; c < 2; c++) for (let off = 0; off < n; off += STEP) ch[c].set(f32(await page.evaluate(`B.take(${id},${c},${off},${Math.min(STEP, n - off)})`)), off);
  await call('drop', id);
  return ch;
}

try {
  for (let i = 0; i < 50 && !(await page.evaluate('typeof B!=="undefined"&&B.ready===true')); i++) await new Promise(r => setTimeout(r, 100));
  const info = await call('info');
  log(`원본 효과음 이름 ${info.names.length}개 · 타격음 ${info.hit.length}종 · 보스 목소리 ${info.voice.length}종 · 노래 ${info.songs.length}곡 + 메뉴`);

  // ── 4. 효과음: 이름 × 인자 × 무작위 갈래 ─────────────────────────────────────
  const sfx = {};        // name → { gap, kind, default?, sets: { key → [entry] } }
  const entries = [];    // 구울 것 전부 (순서 = 파일에 놓이는 순서)
  for (const name of info.names) {
    const kind = KIND[info.argName[name]];
    if (!kind) die(`효과음 ${name}의 인자 이름 '${info.argName[name]}'을 모른다 (bake.mjs의 KIND에 더할 것)`);
    const nr = RND_COUNT[name] || (info.rnd.includes(name) ? 3 : 1);
    const def = { gap: info.gap[name], kind, sets: {} };
    const add = (key, arg, extra) => { def.sets[key] = []; for (let r = 0; r < nr; r++) { const e = { id: `${name}.${key}#${r + 1}`, name, key, arg, ...extra }; def.sets[key].push(e); entries.push(e); } };
    if (kind === 'one') add('one', undefined);
    else if (kind === 'flag') { add('off', false); add('on', true); }
    else if (kind === 'key') { const keys = name === 'hit' ? info.hit : name === 'voice' ? info.voice : die('key 종류인데 hit/voice가 아니다: ' + name); def.default = name === 'hit' ? 'card' : 'bagman'; for (const k of keys) add(k, k); }
    else if (kind === 'pick') { for (let s = 0; s <= 12; s++) add('a' + s, 1, { streak: s }); for (let s = 0; s <= 12; s++) add('b' + s, 3, { streak: s }); }
    else if (kind === 'tick') { for (let n = 0; n <= 10; n++) add('n' + n, n); }
    sfx[name] = def;
  }
  log(`효과음 ${entries.length}개를 굽는다 …`);
  let t = Date.now();
  for (const e of entries) {
    const r = await call('sfx', { name: e.name, arg: e.arg, streak: e.streak, seed: fnv(e.id), pre: PRE, post: FADE, len: 6.5 });
    if (r.silent) die(`${e.id}: 소리가 없다`);
    if (r.hitEnd) die(`${e.id}: 굽는 길이(6.5초)보다 소리가 길다`);
    Object.assign(e, { data: f32(r.data), peak: r.peak, sideRatio: r.sideRatio, onset: r.first - info.QT, audible: r.last - r.first + 1 });
  }
  log(`  ${((Date.now() - t) / 1000).toFixed(1)}초`);
  // 덧붙이는 한 번짜리: 심장 박동(체력 낮음) · 심벌(노래 바뀜)
  const heart = { id: '_heart', name: '_heart' }, crash = { id: '_crash', name: '_crash' };
  { const r = await call('heart', { pre: PRE, post: FADE }); if (r.silent) die('심장 박동이 구워지지 않았다'); Object.assign(heart, { data: f32(r.data), peak: r.peak, sideRatio: r.sideRatio, audible: r.last - r.first + 1 }); }
  { const r = await call('crash', { seed: fnv('_crash'), pre: PRE, post: FADE }); if (r.silent) die('심벌이 구워지지 않았다'); Object.assign(crash, { data: f32(r.data), peak: r.peak, sideRatio: r.sideRatio, audible: r.last - r.first + 1 }); }
  // 꼬리를 0까지 내린다 (data = [앞 무음 PRE][소리][FADE])
  for (const e of [...entries, heart, crash]) { const d = e.data, n = d.length; for (let j = 0; j < FADE; j++) d[n - FADE + j] *= 1 - (j + 1) / FADE; }

  // ── 5. 끝없이 도는 것: 웅성거림 · 보스 층 ─────────────────────────────────────
  const mono = ch => { const o = new Float32Array(ch[0].length); let dmax = 0; for (let i = 0; i < o.length; i++) { o[i] = (ch[0][i] + ch[1][i]) / 2; const d = Math.abs(ch[0][i] - ch[1][i]); if (d > dmax) dmax = d; } return { o, dmax }; };
  const maxAbsDiff = (x, a, b, n) => { let m = 0, s = 0; for (let c = 0; c < x.length; c++) for (let j = 0; j < n; j++) { const d = Math.abs(x[c][a + j] - x[c][b + j]); if (d > m) m = d; s += d * d; } return { max: m, rms: Math.sqrt(s / (n * x.length)) }; };
  // 순환부를 잘라 낸다: x[l0,l1) 의 첫 XF표본을 「끝의 자연스러운 이어짐 x[l1+j]」에서 시작해 제자리로 옮겨 타게 한다
  //  → 끝에서 처음으로 돌아갈 때 파형이 이어진다. 도입부가 있으면 그 끝 XF표본도 순환부 직전의 흐름으로 옮겨 탄다.
  function cutLoop(x, i0, i1, l0, l1) {
    const introN = i1 - i0, out = x.map(() => new Float32Array(introN + (l1 - l0)));
    for (let c = 0; c < x.length; c++) {
      out[c].set(x[c].subarray(i0, i1), 0);
      if (introN > 0 && i1 !== l0) for (let j = 0; j < XF; j++) { const w = (j + 1) / XF; out[c][introN - XF + j] = (1 - w) * x[c][i1 - XF + j] + w * x[c][l0 - XF + j]; }
      out[c].set(x[c].subarray(l0, l1), introN);
      for (let j = 0; j < XF; j++) { const w = j / XF; out[c][introN + j] = (1 - w) * x[c][l1 + j] + w * x[c][l0 + j]; }
    }
    return { ch: out, loop0: introN, wrap: maxAbsDiff(x, l1, l0, 2 * SR), join: introN > 0 && i1 !== l0 ? maxAbsDiff(x, i1, l0, XF) : { max: 0, rms: 0 } };
  }
  const peakOf = chs => { let p = 0; for (const c of chs) for (let i = 0; i < c.length; i++) { const a = Math.abs(c[i]); if (a > p) p = a; } return p; };

  log('웅성거림 · 보스 층 · 노래를 굽는다 …'); t = Date.now();
  const AMB_CROWD = 400, AMB_SEC = 6;
  const amb = { id: '_amb', name: '_amb' };
  {
    const x = await fetchStereo((await call('amb', { len: 6 + AMB_SEC + 3, crowd: AMB_CROWD })).id);
    const a = 6 * SR, b = a + AMB_SEC * SR, c = cutLoop(x, a, a, a, b), m = mono(c.ch);
    Object.assign(amb, { data: m.o, peak: peakOf([m.o]), lrDiff: m.dmax, wrap: c.wrap, loop: true });
  }
  const songs = [], stems = [];
  // 64스텝의 표본 수: 128의 배수로 맞춘다(Chrome이 128표본씩 만들기 때문에 주기가 그 배수여야 되풀이가 정확히 같아진다). 박자 오차 0.02% 이하
  const p64of = bpm => Math.round(64 * (60 / bpm / 4) * SR / 128) * 128;
  for (let k = 0; k < info.songs.length; k++) {
    const p64 = p64of(info.songs[k].bpm), n = k2 => info.M0 + k2 * p64 / 64, seed = fnv('song' + k);
    // 4악구(256스텝)까지는 악기가 하나씩 더해지는 도입부, 그 뒤는 2악구(128스텝)마다 되풀이된다
    const sig = await call('calls', { song: k, i0: 0, n: 768 });
    for (let j = 0; j < 128; j++) if (sig[256 + j] !== sig[384 + j] || sig[384 + j] !== sig[512 + j] || sig[512 + j] !== sig[640 + j]) die(`노래 ${k}: 256스텝 뒤가 128스텝 주기가 아니다 (스텝 ${j})`);
    const x = await fetchStereo((await call('song', { song: k, i0: 0, n: 512 + 48, p64, reseed: 128, seed, lenSamples: Math.ceil(n(512 + 48)) + SR })).id);
    const c = cutLoop(x, n(0), n(256), n(384), n(512));
    songs.push({ id: 'song' + k, k, name: info.songs[k].name, bpm: info.songs[k].bpm, p64, ch: c.ch, loop0: c.loop0, wrap: c.wrap, join: c.join, peak: peakOf(c.ch) });
    // 보스 층: 4악구 뒤로는 64스텝 주기 (킥 · 낮은 드론 · 두 음 경보)
    const bs = await call('calls', { song: k, i0: 256, n: 256, boss: 'only' });
    for (let j = 0; j < 64; j++) if (bs[j] !== bs[64 + j] || bs[j] !== bs[128 + j] || bs[j] !== bs[192 + j]) die(`노래 ${k}: 보스 층이 64스텝 주기가 아니다 (스텝 ${j})`);
    const y = await fetchStereo((await call('song', { song: k, i0: 256, n: 192 + 48, p64, reseed: 64, seed: fnv('boss' + k), boss: 'only', lenSamples: Math.ceil(n(192 + 48)) + SR })).id);
    const s = cutLoop(y, n(64), n(64), n(64), n(128)), m = mono(s.ch);
    stems.push({ id: 'boss' + k, k, data: m.o, peak: peakOf([m.o]), lrDiff: m.dmax, wrap: s.wrap, loop: true, calls: [...new Set(bs.slice(0, 64).join(' ').split(' ').filter(Boolean).map(v => v.split('(')[0]))] });
    log(`  노래 ${k} ${info.songs[k].name} ${info.songs[k].bpm}bpm: 도입 ${sec(c.loop0).toFixed(3)}초 + 순환 ${sec(n(512) - n(384)).toFixed(3)}초 · 이음매 차이 ${c.wrap.max.toExponential(2)} · 보스 층 ${sec(m.o.length).toFixed(3)}초(이음매 차이 ${s.wrap.max.toExponential(2)} · 좌우 차이 ${m.dmax.toExponential(1)})`);
  }
  let menu;
  {
    const p64 = p64of(info.menu.bpm), n = k2 => info.M0 + k2 * p64 / 64;
    const sig = await call('calls', { song: 'menu', i0: 0, n: 256 });
    for (let j = 0; j < 64; j++) if (sig[j] !== sig[64 + j] || sig[j] !== sig[128 + j] || sig[j] !== sig[192 + j]) die(`메뉴 노래가 64스텝 주기가 아니다 (스텝 ${j})`);
    const x = await fetchStereo((await call('song', { song: 'menu', i0: 0, n: 128 + 48, p64, reseed: 64, seed: fnv('menu'), lenSamples: Math.ceil(n(128 + 48)) + SR })).id);
    const c = cutLoop(x, n(0), n(64), n(64), n(128));
    menu = { id: 'menu', name: 'menu', bpm: info.menu.bpm, p64, ch: c.ch, loop0: c.loop0, wrap: c.wrap, join: c.join, peak: peakOf(c.ch) };
    log(`  메뉴 ${info.menu.bpm}bpm: 도입 ${sec(c.loop0).toFixed(3)}초 + 순환 ${sec(n(128) - n(64)).toFixed(3)}초 · 이음매 차이 ${c.wrap.max.toExponential(2)}`);
  }
  log(`  웅성거림 ${AMB_SEC}초: 이음매 차이 ${amb.wrap.max.toExponential(2)} · 좌우 차이 ${amb.lrDiff.toExponential(1)}`);
  log(`  ${((Date.now() - t) / 1000).toFixed(1)}초`);
  await page.close();
  // 한 바퀴 뒤 같은 자리의 소리가 같아야 되풀이가 매끄럽다 (-60dBFS보다 크게 다르면 굽는 방법이 틀린 것)
  for (const e of [...songs, menu, ...stems, amb]) if (e.wrap.max > 1e-3) die(`${e.id}: 되풀이가 주기적이지 않다 (한 바퀴 뒤와의 차이 ${e.wrap.max.toExponential(2)})`);

  // ── 6. 파일에 담는다 ─────────────────────────────────────────────────────────
  // 파일마다: { key, nch, parts:[{e, at}] } — at = 그 조각이 시작하는 표본
  const files = [];
  const newFile = (key, nch) => { const f = { key, nch, len: LEAD, parts: [] }; files.push(f); return f; };
  // 조각 하나를 놓는다. put = 적을 표본(채널마다), gPre = 구간 앞에 붙은 덧표본 수, core = 구간의 길이
  const place = (f, e, put, gPre, core) => { e.sheet = f.key; e.put = put; e.gPre = gPre; e.gPost = put[0].length - gPre - core > 0 ? put[0].length - gPre - core : 0; e.at = f.len + gPre; e.n = core; f.parts.push(e); f.len += Math.max(put[0].length, gPre + core) + GAP; };
  // 끝없이 도는 조각에는 덧표본을 붙인다: 끝 뒤에 「처음 GUARD표본」, (도입부가 없으면) 처음 앞에 「끝 GUARD표본」.
  // 로블록스가 되풀이 경계를 한두 표본 다르게 잡아도 이어지는 소리가 맞게 나온다.
  const guarded = (chs, loop0, pre) => chs.map(c => { const n = c.length, o = new Float32Array((pre ? GUARD : 0) + n + GUARD); if (pre) o.set(c.subarray(n - GUARD), 0); o.set(c, pre ? GUARD : 0); o.set(c.subarray(loop0, loop0 + GUARD), (pre ? GUARD : 0) + n); return o; });
  // sfx1(모노): 끝없이 도는 것(보스 층 · 웅성거림)을 맨 앞에 — 파일 앞쪽일수록 시각을 더 정밀하게 적을 수 있다(로블록스의 NumberRange는 32비트 실수)
  let sheet = newFile('sfx1', 1);
  for (const e of [...stems, amb]) place(sheet, e, guarded([e.data], 0, true), GUARD, e.data.length);
  // 한 번짜리: 이름 단위로 차례로 담고, 한도를 넘으면 다음 파일로
  const byName = new Map(); for (const e of [...entries, heart, crash]) { if (!byName.has(e.name)) byName.set(e.name, []); byName.get(e.name).push(e); }
  for (const [, list] of byName) {
    const need = list.reduce((a, e) => a + e.data.length + POST + GAP, 0);
    if ((sheet.len + need) * 2 + 44 > MAX_BYTES || sec(sheet.len + need) > MAX_SEC) sheet = newFile('sfx' + (files.filter(f => f.nch === 1).length + 1), 1);
    for (const e of list) place(sheet, e, [e.data], 0, e.data.length + POST);
  }
  // 음악(스테레오): 노래 0+1 · 2+3 · 4+메뉴
  const m1 = newFile('music1', 2), m2 = newFile('music2', 2), m3 = newFile('music3', 2);
  const mfile = { 0: m1, 1: m1, 2: m2, 3: m2, 4: m3 };
  for (const s of songs) place(mfile[s.k], s, guarded(s.ch, s.loop0, false), 0, s.ch[0].length);
  place(m3, menu, guarded(menu.ch, menu.loop0, false), 0, menu.ch[0].length);

  const manifest = { sampleRate: SR, files: [], sfx: {}, music: {}, uses, generatedFrom: 'commute-survival/js/audio.js' };
  for (const f of files) {
    const total = f.len - GAP + LEAD, ch = Array.from({ length: f.nch }, () => new Float32Array(total));
    for (const e of f.parts) for (let c = 0; c < f.nch; c++) ch[c].set(e.put[e.put.length > 1 ? c : 0], e.at - e.gPre);
    const file = path.join(OUT, f.key + '.wav'), w = writeWav(file, ch, SR);
    if (w.bytes > 20e6 || sec(total) > 420) die(`${f.key}.wav가 로블록스 한도를 넘는다 (${w.bytes}바이트 · ${sec(total).toFixed(1)}초)`);
    manifest.files.push({ key: f.key, file: 'assets/audio/' + f.key + '.wav', channels: f.nch, samples: total, seconds: sec(total), bytes: w.bytes, clipped: w.clipped, entries: f.parts.length });
  }

  // ── 7. 표: SoundMap.luau · SoundIds.luau · manifest.json ───────────────────────
  const T = n => (n / SR).toFixed(6).replace(/0+$/, '').replace(/\.$/, '.0');
  const region = e => `{ sheet = "${e.sheet}", t0 = ${T(e.at)}, t1 = ${T(e.at + e.n)}, vol = 1 }`;
  const lkey = k => /^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : `["${k}"]`;
  const mreg = e => ({ sheet: e.sheet, at: e.at, n: e.n, gPre: e.gPre, gPost: e.gPost, t0: sec(e.at), t1: sec(e.at + e.n), peak: e.peak, peakDb: db(e.peak), sideRatio: e.sideRatio, loop: !!e.loop, wrap: e.wrap, lrDiff: e.lrDiff });
  let L = [];
  L.push('--!strict');
  L.push('-- 자동 생성 (tools/audio/bake.mjs) — 손으로 고치지 말 것. 다시 구우면 덮어쓴다.');
  L.push('-- 원본 commute-survival/js/audio.js의 합성 소리를 구운 파일(assets/audio/*.wav) 안의 구간 표.');
  L.push('-- 시각은 초. 구간 = { sheet = 파일 이름(SoundIds의 키), t0 = 시작, t1 = 끝, vol = 음량 배수 }');
  L.push('local SoundMap = {}');
  L.push('');
  L.push('-- 구운 파일');
  L.push('SoundMap.sheets = {');
  for (const f of manifest.files) L.push(`\t${lkey(f.key)} = { file = "${f.key}.wav", length = ${T(f.samples)}, channels = ${f.channels} },`);
  L.push('}');
  L.push('');
  L.push('-- 효과음. gap = 원본의 최소 간격(초 — 이보다 빨리 다시 부르면 무시). sets[갈래] = 무작위로 하나 고르는 구간들.');
  L.push('-- kind가 인자(arg)로 갈래를 고르는 법:');
  L.push('--   "one"  인자 없음 → sets.one');
  L.push('--   "flag" 인자가 참(진화한 무기)이면 sets.on, 아니면 sets.off');
  L.push('--   "key"  인자가 글자(hit: 무기 이름 · voice: 보스 종류) → sets[arg], 없으면 sets[default]. hit은 간격도 무기마다 따로 잰다');
  L.push('--   "pick" 원두 줍기: 0.4초 안에 이어 주우면 음이 한 칸씩 오른다(0~12). 값(arg)이 3 이상이면 sets["b"..칸], 아니면 sets["a"..칸]');
  L.push('--   "tick" 남은 초(arg 0~10) → sets["n"..arg]');
  L.push('SoundMap.sfx = {');
  for (const name of info.names) {
    const d = sfx[name];
    L.push(`\t${lkey(name)} = { gap = ${d.gap}, kind = "${d.kind}",${d.default ? ` default = "${d.default}",` : ''} sets = {`);
    for (const [k, list] of Object.entries(d.sets)) L.push(`\t\t${lkey(k)} = { ${list.map(region).join(', ')} },`);
    L.push('\t} },');
    manifest.sfx[name] = { gap: d.gap, kind: d.kind, default: d.default, called: !!uses[name], sets: Object.fromEntries(Object.entries(d.sets).map(([k, list]) => [k, list.map(e => ({ id: e.id, ...mreg(e), audible: sec(e.audible) }))])) };
  }
  L.push('}');
  L.push('');
  L.push('-- 음악. t0 = 처음, loop0 = 되풀이가 시작하는 곳, t1 = 끝 (t0→t1까지 튼 뒤 loop0~t1을 끝없이 되풀이).');
  L.push('-- phrase = 64스텝(4마디)의 길이(초). boss = 보스가 있을 때 겹쳐 트는 층(64스텝 순환, 노래의 스텝에 맞춘다).');
  L.push('SoundMap.music = {');
  const mus = e => `sheet = "${e.sheet}", t0 = ${T(e.at)}, loop0 = ${T(e.at + e.loop0)}, t1 = ${T(e.at + e.n)}, vol = 1, bpm = ${e.bpm}, phrase = ${T(e.p64)}`;
  L.push(`\tmenu = { ${mus(menu)} },`);
  L.push('\tsongs = {');
  for (const s of songs) L.push(`\t\t[${s.k}] = { name = "${s.name}", ${mus(s)}, boss = ${region(stems[s.k])} },`);
  L.push('\t},');
  L.push(`\tcrash = ${region(crash)}, -- 노래가 바뀔 때 한 번 (음악 쪽 음량으로)`);
  L.push(`\theart = ${region(heart)}, -- 체력 30% 미만일 때 heartEvery초마다 (효과음 쪽 음량으로)`);
  L.push('\theartEvery = 0.78,');
  L.push(`\tamb = ${region(amb)}, -- 웅성거림(끝없이 되풀이). 음량 = min(1, 적 수 / ambFull) (효과음 쪽 음량으로)`);
  L.push(`\tambFull = ${AMB_CROWD}, ambTau = 0.4,`);
  L.push('\tlateSpeed = 1.08, -- 지각 상태: 원본은 박자만 8% 빨라진다 → PlaybackSpeed');
  L.push('\tmuffle = { low = 0, mid = -16, high = -48, tau = 0.12 }, -- 멈춤 화면: 원본은 520Hz 저역 통과 → EqualizerSoundEffect(dB)');
  L.push('}');
  L.push('');
  L.push('return SoundMap');
  fs.writeFileSync(path.join(SHARED, 'SoundMap.luau'), L.join('\n') + '\n');

  manifest.music = {
    menu: { ...mreg(menu), loop0: menu.loop0, bpm: menu.bpm, p64: menu.p64, join: menu.join },
    songs: songs.map(s => ({ name: s.name, ...mreg(s), loop0: s.loop0, bpm: s.bpm, p64: s.p64, join: s.join, boss: { ...mreg(stems[s.k]), calls: stems[s.k].calls } })),
    crash: mreg(crash), heart: mreg(heart), amb: mreg(amb),
  };
  fs.writeFileSync(path.join(WORK, 'manifest.json'), JSON.stringify(manifest, null, 1));

  // SoundIds: 이미 적어 둔 번호는 지킨다
  const idsFile = path.join(SHARED, 'SoundIds.luau'), old = {};
  if (fs.existsSync(idsFile)) for (const m of fs.readFileSync(idsFile, 'utf8').matchAll(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]*)"/gm)) old[m[1]] = m[2];
  const I = [];
  I.push('--!strict');
  I.push('-- 구운 소리 파일을 로블록스에 올린 뒤 받은 에셋 번호를 적는 곳.');
  I.push('-- 예: sfx1 = "rbxassetid://1234567890"  (assets/audio/sfx1.wav를 올리고 받은 번호)');
  I.push('-- 비어 있는("") 파일의 소리는 나지 않는다(오류 없이 조용히 넘어간다).');
  I.push('-- tools/audio/bake.mjs가 다시 만들어도 여기 적은 번호는 그대로 둔다.');
  I.push('return {');
  for (const f of manifest.files) I.push(`\t${lkey(f.key)} = "${old[f.key] || ''}", -- assets/audio/${f.key}.wav · ${f.seconds.toFixed(1)}초 · ${f.channels === 1 ? '모노' : '스테레오'}`);
  I.push('}');
  fs.writeFileSync(idsFile, I.join('\n') + '\n');

  // ── 8. 보고 ────────────────────────────────────────────────────────────────
  log('');
  log('파일                길이(초)   크기(MB)  채널  조각  잘린 표본');
  for (const f of manifest.files) log(`${(f.key + '.wav').padEnd(18)} ${f.seconds.toFixed(2).padStart(8)} ${(f.bytes / 1e6).toFixed(2).padStart(9)} ${String(f.channels).padStart(5)} ${String(f.entries).padStart(5)} ${String(f.clipped).padStart(6)}`);
  const all = [...entries, heart, crash];
  const loud = all.reduce((a, e) => e.peak > a.peak ? e : a), quiet = all.reduce((a, e) => e.peak < a.peak ? e : a);
  const side = all.reduce((a, e) => e.sideRatio > a.sideRatio ? e : a);
  log(`한 번짜리 ${all.length}개: 가장 큰 것 ${loud.id} ${db(loud.peak).toFixed(1)}dBFS · 가장 작은 것 ${quiet.id} ${db(quiet.peak).toFixed(1)}dBFS · 모노로 합치며 잃는 좌우 차이가 가장 큰 것 ${side.id} (옆/가운데 에너지 ${(side.sideRatio * 100).toFixed(1)}%)`);
  const never = info.names.filter(n => !uses[n]), unknown = Object.keys(uses).filter(n => !info.names.includes(n));
  log(`원본이 부르지 않는 이름(구워 두기는 했다): ${never.join(', ') || '없음'}`);
  if (unknown.length) die('원본이 부르는데 audio.js에 없는 이름: ' + unknown.join(', '));
  if (updateNotes()) log('tools/audio/AUDIO_NOTES.md의 표를 새로 썼다');
  log('끝. 검사: node tools/audio/verify.mjs · node tools/audio/test/run.mjs');
} catch (e) {
  await page.close();
  die(e.stack || e.message);
}
