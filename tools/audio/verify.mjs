// 구운 WAV를 다시 읽어 재 본다 (귀로 듣는 대신 할 수 있는 검사).
//   node tools/audio/verify.mjs
// - 구간마다: 최대값 · RMS · 무음이 아닌지 · 잘리지(클리핑) 않았는지 · 앞뒤 0.15초가 완전한 무음인지
// - 끝없이 도는 구간: 끝 → 처음으로 넘어갈 때 파형이 이어지는지
// - 그림: tools/audio/work/png/ (파일 전체의 파형 + 스펙트로그램 · 구간 몇 개 · 순환 이음매)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readWav } from './lib/wav.mjs';
import { Canvas, text } from './lib/png.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const WORK = path.join(HERE, 'work'), PNG = path.join(WORK, 'png');
fs.mkdirSync(PNG, { recursive: true });
const M = JSON.parse(fs.readFileSync(path.join(WORK, 'manifest.json'), 'utf8'));
const SR = M.sampleRate, QUIET = Math.round(0.15 * SR);
const db = v => v > 0 ? 20 * Math.log10(v) : -Infinity;
const fails = [];
const fail = m => { fails.push(m); console.log('  ✗ ' + m); };

const wav = {};
for (const f of M.files) {
  const w = readWav(path.join(ROOT, f.file));
  if (w.sampleRate !== SR || w.channels.length !== f.channels || w.n !== f.samples) fail(`${f.key}: 파일 머리말이 표와 다르다`);
  wav[f.key] = w;
}

// ── 구간 목록 ────────────────────────────────────────────────────────────────
const regions = [];
for (const [name, d] of Object.entries(M.sfx)) for (const [k, list] of Object.entries(d.sets)) for (const e of list) regions.push({ ...e, kind: 'sfx', name });
regions.push({ id: '_heart', kind: 'sfx', ...M.music.heart }, { id: '_crash', kind: 'sfx', ...M.music.crash });
const loops = [];
loops.push({ id: 'menu', ...M.music.menu, l0: M.music.menu.at + M.music.menu.loop0 });
M.music.songs.forEach((s, k) => { loops.push({ id: 'song' + k, ...s, l0: s.at + s.loop0 }); loops.push({ id: 'boss' + k, ...s.boss, l0: s.boss.at }); });
loops.push({ id: '_amb', ...M.music.amb, l0: M.music.amb.at });
for (const l of loops) regions.push({ ...l, kind: 'loop' });

// ── 구간마다 재기 ──────────────────────────────────────────────────────────────
function measure(r) {
  const w = wav[r.sheet], a = r.at, b = r.at + r.n;
  let peak = 0, sum = 0, clip = 0, first = -1, last = -1;
  for (const ch of w.channels) for (let i = a; i < b; i++) {
    const v = ch[i], av = Math.abs(v);
    if (av > peak) peak = av; sum += v * v; if (av >= 32767) clip++;
    if (av > 0) { if (first < 0 || i < first) first = i; if (i > last) last = i; }
  }
  // RMS는 소리가 있는 부분(첫 표본~마지막 표본)만으로
  const span = Math.max(1, (last - first + 1) * w.channels.length);
  // 앞뒤 무음: 끝없이 도는 구간에 붙인 덧표본(gPre · gPost)은 건너뛰고 잰다
  let before = 0, after = 0;
  const qa = a - (r.gPre || 0), qb = b + (r.gPost || 0);
  for (const ch of w.channels) { for (let i = Math.max(0, qa - QUIET); i < qa; i++) before = Math.max(before, Math.abs(ch[i])); for (let i = qb; i < Math.min(w.n, qb + QUIET); i++) after = Math.max(after, Math.abs(ch[i])); }
  const roomBefore = qa >= QUIET || qa === 0, roomAfter = qb + QUIET <= w.n;
  return { peak: peak / 32768, rms: Math.sqrt(sum / span) / 32768, clip, before, after, roomBefore, roomAfter, soundSec: (last - first + 1) / SR };
}
let worstQuiet = null, loudest = null, n = 0, minRms = null;
const rows = [];
for (const r of regions) {
  const m = measure(r); n++;
  rows.push({ id: r.id, sheet: r.sheet, t0: r.at / SR, t1: (r.at + r.n) / SR, peakDb: db(m.peak), rmsDb: db(m.rms), kind: r.kind });
  if (m.peak < 0.002) fail(`${r.id}: 거의 무음 (최대 ${db(m.peak).toFixed(1)}dBFS)`);
  if (m.clip) fail(`${r.id}: 잘린 표본 ${m.clip}개`);
  if (m.before !== 0 || m.after !== 0) fail(`${r.id}: 앞뒤 0.15초가 무음이 아니다 (앞 ${m.before} · 뒤 ${m.after})`);
  if (!m.roomBefore) fail(`${r.id}: 앞에 0.15초의 자리가 없다`);
  if (!worstQuiet || m.peak < worstQuiet.peak) worstQuiet = { id: r.id, peak: m.peak };
  if (!loudest || m.peak > loudest.peak) loudest = { id: r.id, peak: m.peak };
  if (!minRms || m.rms < minRms.rms) minRms = { id: r.id, rms: m.rms };
}
// 구간끼리 겹치지 않고 0.15초 이상 떨어져 있는지
for (const f of M.files) {
  const rs = regions.filter(r => r.sheet === f.key).sort((a, b) => a.at - b.at);
  for (let i = 1; i < rs.length; i++) if ((rs[i].at - (rs[i].gPre || 0)) - (rs[i - 1].at + rs[i - 1].n + (rs[i - 1].gPost || 0)) < QUIET) fail(`${rs[i - 1].id} → ${rs[i].id}: 사이가 0.15초보다 짧다`);
}
console.log(`구간 ${n}개: 최대값이 가장 큰 것 ${loudest.id} ${db(loudest.peak).toFixed(2)}dBFS · 가장 작은 것 ${worstQuiet.id} ${db(worstQuiet.peak).toFixed(2)}dBFS · RMS가 가장 작은 것 ${minRms.id} ${db(minRms.rms).toFixed(1)}dBFS`);

// ── 순환 이음매 ─────────────────────────────────────────────────────────────
// 끝 표본 다음에 처음 표본이 오는 자리의 「꺾임」(둘째 차분)을 그 둘레 50ms의 가장 큰 꺾임과 견준다. 1 이하면 둘레의 파형과 구별되지 않는다.
console.log('순환 이음매 (구울 때 잰 차이 = 한 바퀴 뒤 같은 자리의 표본 차이의 최대 · 꺾임 비 = 이음매의 꺾임 ÷ 둘레의 최대 꺾임):');
const seams = [];
for (const l of loops) {
  const w = wav[l.sheet], l0 = l.l0, l1 = l.at + l.n, W = Math.round(0.05 * SR);
  let worst = 0, local = 0, jump = 0;
  for (const ch of w.channels) {
    const seam = [ch[l1 - 2], ch[l1 - 1], ch[l0], ch[l0 + 1]];
    const k = Math.max(Math.abs(seam[2] - 2 * seam[1] + seam[0]), Math.abs(seam[3] - 2 * seam[2] + seam[1]));
    let loc = 1;
    for (let i = l0 + 2; i < l0 + W; i++) loc = Math.max(loc, Math.abs(ch[i] - 2 * ch[i - 1] + ch[i - 2]));
    for (let i = l1 - W; i < l1; i++) loc = Math.max(loc, Math.abs(ch[i] - 2 * ch[i - 1] + ch[i - 2]));
    worst = Math.max(worst, k); local = Math.max(local, loc); jump = Math.max(jump, Math.abs(seam[2] - seam[1]));
  }
  const ratio = worst / local;
  seams.push({ id: l.id, loopSec: (l1 - l0) / SR, bakeDiff: l.wrap.max, bakeDiffDb: db(l.wrap.max), ratio, jump });
  console.log(`  ${l.id.padEnd(6)} 순환 ${((l1 - l0) / SR).toFixed(4)}초(${l1 - l0}표본) · 구울 때 잰 차이 ${l.wrap.max.toExponential(2)}(${db(l.wrap.max).toFixed(0)}dBFS) · 이음매 꺾임 ${worst}/32768 · 둘레 ${local} · 비 ${ratio.toFixed(2)}`);
  if (ratio > 1.5) fail(`${l.id}: 이음매에서 파형이 꺾인다 (비 ${ratio.toFixed(2)})`);
}

// ── 그림 ────────────────────────────────────────────────────────────────────
function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) { let bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; } }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = -2 * Math.PI / len, wr = Math.cos(ang), wi = Math.sin(ang);
    for (let i = 0; i < n; i += len) { let cr = 1, ci = 0; for (let k = 0; k < len / 2; k++) { const ur = re[i + k], ui = im[i + k], vr = re[i + k + len / 2] * cr - im[i + k + len / 2] * ci, vi = re[i + k + len / 2] * ci + im[i + k + len / 2] * cr; re[i + k] = ur + vr; im[i + k] = ui + vi; re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi; const t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t; } }
  }
}
const NF = 2048, HANN = Float64Array.from({ length: NF }, (_, i) => 0.5 - 0.5 * Math.cos(2 * Math.PI * i / (NF - 1)));
const heat = v => { // 0..1 → 검정 · 파랑 · 자주 · 주황 · 노랑 · 흰색
  const s = [[0, 0, 0], [20, 30, 120], [150, 30, 140], [240, 110, 40], [255, 230, 90], [255, 255, 255]], x = Math.max(0, Math.min(0.9999, v)) * (s.length - 1), i = Math.floor(x), f = x - i;
  return [0, 1, 2].map(c => Math.round(s[i][c] + (s[i + 1][c] - s[i][c]) * f));
};
const monoAt = (w, i) => { if (i < 0 || i >= w.n) return 0; let v = 0; for (const ch of w.channels) v += ch[i]; return v / w.channels.length / 32768; };
// (x0,y0)에 폭 W로 [a,b) 표본의 파형(높이 hw)과 스펙트로그램(높이 hs, 40Hz~20kHz 로그 눈금, -96~0dB)을 그린다
function draw(cv, w, a, b, x0, y0, W, hw, hs) {
  cv.rect(x0, y0, x0 + W - 1, y0 + hw - 1, [10, 12, 18]);
  const mid = y0 + hw / 2;
  for (let x = 0; x < W; x++) {
    const i0 = Math.floor(a + (b - a) * x / W), i1 = Math.max(i0 + 1, Math.floor(a + (b - a) * (x + 1) / W));
    let lo = 1, hi = -1;
    for (let i = i0; i < i1; i++) for (const ch of w.channels) { const v = (i >= 0 && i < w.n ? ch[i] : 0) / 32768; if (v < lo) lo = v; if (v > hi) hi = v; }
    cv.vline(x0 + x, mid - hi * (hw / 2 - 1), mid - lo * (hw / 2 - 1), [110, 220, 150]);
    if (hs > 0) {
      const c = Math.floor((i0 + i1) / 2) - NF / 2, re = new Float64Array(NF), im = new Float64Array(NF);
      for (let k = 0; k < NF; k++) re[k] = monoAt(w, c + k) * HANN[k];
      fft(re, im);
      for (let y = 0; y < hs; y++) {
        const fr = 40 * Math.pow(20000 / 40, 1 - y / (hs - 1)), bin = Math.min(NF / 2 - 1, Math.max(1, Math.round(fr * NF / SR)));
        const mag = Math.hypot(re[bin], im[bin]) / (NF / 4);
        cv.set(x0 + x, y0 + hw + 2 + y, heat((db(mag) + 96) / 96));
      }
    }
  }
}
// 파일 전체: 한 줄에 50초씩
for (const f of M.files) {
  const w = wav[f.key], ROW = 50 * SR, R = Math.ceil(w.n / ROW), W = 1600, hw = 90, hs = 150, RH = hw + hs + 22;
  const cv = new Canvas(W + 20, R * RH + 10);
  for (let r = 0; r < R; r++) {
    const y0 = 16 + r * RH;
    text(cv, 10, y0 - 10, `${f.key}.wav  ${(r * 50)}S - ${Math.min((r + 1) * 50, f.seconds).toFixed(1)}S`, [200, 200, 210]);
    draw(cv, w, r * ROW, (r + 1) * ROW, 10, y0, W, hw, hs);
    for (const g of regions.filter(q => q.sheet === f.key)) for (const [s, col] of [[g.at, [90, 255, 90]], [g.at + g.n, [255, 80, 80]]]) {
      if (s >= r * ROW && s < (r + 1) * ROW) cv.vline(10 + Math.floor((s - r * ROW) * W / ROW), y0, y0 + 6, col);
    }
  }
  cv.save(path.join(PNG, `sheet_${f.key}.png`));
}
// 구간 몇 개를 크게
const pickIds = ['hit.card#1', 'hit.shoulder#2', 'pick.a0#1', 'pick.b12#1', 'tick.n1#1', 'voice.speaker#1', 'shout.on#1', 'card.on#1', 'boss.one#1', 'level.one#1', 'win.one#1', 'trainpass.one#1', 'hover.one#1', 'bossdie.one#1', '_heart', '_crash'];
{
  const cells = pickIds.map(id => regions.find(r => r.id === id)).filter(Boolean), cols = 4, CW = 400, CH = 250, cv = new Canvas(cols * CW + 10, Math.ceil(cells.length / cols) * CH + 10);
  cells.forEach((r, i) => {
    const x0 = 10 + (i % cols) * CW, y0 = 20 + Math.floor(i / cols) * CH, pad = Math.round(0.05 * SR), row = rows.find(q => q.id === r.id);
    text(cv, x0, y0 - 12, `${r.id}  ${(r.n / SR).toFixed(3)}S  PK ${row.peakDb.toFixed(1)} RMS ${row.rmsDb.toFixed(1)}`, [220, 220, 160]);
    draw(cv, wav[r.sheet], r.at - pad, r.at + r.n + pad, x0, y0, CW - 12, 80, 130);
    const px = s => x0 + Math.floor((s - (r.at - pad)) * (CW - 12) / (r.n + 2 * pad));
    cv.vline(px(r.at), y0, y0 + 80, [90, 255, 90]); cv.vline(px(r.at + r.n), y0, y0 + 80, [255, 80, 80]);
  });
  cv.save(path.join(PNG, 'entries.png'));
}
// 순환 이음매: 끝 20ms 다음에 처음 20ms를 이어 붙여 그린다 (가운데 흰 줄 = 이음매)
{
  const CW = 520, CH = 130, cols = 3, cv = new Canvas(cols * CW + 10, Math.ceil(loops.length / cols) * CH + 10), H = Math.round(0.02 * SR);
  loops.forEach((l, i) => {
    const w = wav[l.sheet], x0 = 10 + (i % cols) * CW, y0 = 20 + Math.floor(i / cols) * CH, l1 = l.at + l.n, hw = 96, Wd = CW - 12, s = seams[i];
    text(cv, x0, y0 - 12, `${l.id}  LOOP ${s.loopSec.toFixed(3)}S  KINK ${s.ratio.toFixed(2)}`, [220, 220, 160]);
    cv.rect(x0, y0, x0 + Wd - 1, y0 + hw - 1, [10, 12, 18]);
    let pk = 1; for (let j = 0; j < 2 * H; j++) { const idx = j < H ? l1 - H + j : l.l0 + j - H; for (const ch of w.channels) pk = Math.max(pk, Math.abs(ch[idx])); }
    w.channels.forEach((ch, c) => {
      let prev = null;
      for (let j = 0; j < 2 * H; j++) {
        const idx = j < H ? l1 - H + j : l.l0 + j - H, x = x0 + Math.floor(j * Wd / (2 * H)), y = y0 + hw / 2 - ch[idx] / pk * (hw / 2 - 2);
        if (prev !== null) cv.vline(x, prev, y, c ? [240, 150, 90] : [110, 220, 150]); prev = y;
      }
    });
    cv.vline(x0 + Wd / 2, y0, y0 + hw - 1, [255, 255, 255]);
  });
  cv.save(path.join(PNG, 'seams.png'));
}

fs.writeFileSync(path.join(WORK, 'verify.json'), JSON.stringify({ regions: rows, seams, fails }, null, 1));
console.log(`그림: ${path.relative(ROOT, PNG)}\\sheet_*.png · entries.png · seams.png`);
if (fails.length) { console.log(`실패 ${fails.length}건`); process.exit(1); }
console.log('모든 구간 통과');
