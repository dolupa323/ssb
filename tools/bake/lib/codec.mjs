// 판 한 장 → 게임에 싣는 글 자료 (팔레트 + 번호 → deflate → 85진 글자)
import zlib from 'node:zlib';
import { histogram, reduce } from './quant.mjs';

// 투명한 점 가운데 보이는 점과 맞닿은 것에 이웃의 색을 입힌다(알파는 0 그대로).
// 로블록스가 그림을 늘이거나 줄일 때 가장자리에 검은 테가 끼지 않게 하려는 것.
export function bleed(rgba, w, h) {
  const src = rgba.slice(); let n = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const o = (y * w + x) * 4; if (src[o + 3] !== 0) continue;
    let r = 0, g = 0, b = 0, wt = 0;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const xx = x + dx, yy = y + dy; if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
      const p = (yy * w + xx) * 4, a = src[p + 3]; if (!a) continue;
      r += src[p] * a; g += src[p + 1] * a; b += src[p + 2] * a; wt += a;
    }
    if (wt) { rgba[o] = Math.round(r / wt); rgba[o + 1] = Math.round(g / wt); rgba[o + 2] = Math.round(b / wt); n++; }
    else { rgba[o] = rgba[o + 1] = rgba[o + 2] = 0; }
  }
  return n;
}

// rgba(번지기 전) → { pal: Uint8Array(n*4), idx: Uint8Array(w*h), out: Uint8Array(w*h*4) (풀었을 때 나와야 하는 점들), exact }
// 팔레트 0번은 언제나 완전 투명 (0,0,0,0).
export function indexPage(rgba, w, h, maxColors = 256, bleedSlots = maxColors > 256 ? Math.min(256, maxColors >> 3) : 24) {
  const hist = histogram(rgba), red = reduce(hist.colors, hist.counts, Math.min(hist.colors.length, maxColors - 1 - bleedSlots) || 1);
  const pal = [0]; const slot = new Map([[0, 0]]);
  const palOf = red.palette.length ? Array.from(red.palette, c => { pal.push(c); slot.set(c, pal.length - 1); return pal.length - 1; }) : [];
  const idx = new Uint16Array(w * h);
  for (let i = 0; i < w * h; i++) idx[i] = hist.index[i] < 0 ? 0 : palOf[red.map[hist.index[i]]];
  // 번짐: 투명한 점이 보이는 점과 맞닿으면, 맞닿은 점 가운데 알파가 가장 큰 것의 색(알파 0)을 준다
  const want = new Map(), spots = [];
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = y * w + x; if (idx[i] !== 0) continue;
    let bc = -1, ba = 0;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const xx = x + dx, yy = y + dy; if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
      const k = idx[yy * w + xx]; if (!k) continue; const c = pal[k], a = c >>> 24; if (a > ba) { ba = a; bc = c & 0xffffff; }
    }
    if (bc >= 0 && bc !== 0) { spots.push(i, bc); want.set(bc, (want.get(bc) || 0) + 1); }
  }
  const room = maxColors - pal.length, keep = [...want.entries()].sort((a, b) => b[1] - a[1]).slice(0, room).map(e => e[0]);
  const near = c => { let bd = Infinity, bk = keep[0]; for (const k of keep) { const dr = (c & 255) - (k & 255), dg = ((c >> 8) & 255) - ((k >> 8) & 255), db = ((c >> 16) & 255) - ((k >> 16) & 255), d = dr * dr + dg * dg + db * db; if (d < bd) { bd = d; bk = k; } } return bk; };
  for (const c of keep) { pal.push(c); slot.set(c, pal.length - 1); }   // 알파 0 · 색만 있는 자리
  if (keep.length) for (let s = 0; s < spots.length; s += 2) { const c = slot.has(spots[s + 1]) && (pal[slot.get(spots[s + 1])] >>> 24) === 0 ? spots[s + 1] : near(spots[s + 1]); idx[spots[s]] = slot.get(c); }
  // 많이 쓰는 색이 앞 번호가 되게 다시 줄 세운다 (0번 = 투명은 그대로) — 256색을 넘는 판에서 윗자리 바이트가 거의 0이 되게
  { const use = new Float64Array(pal.length); for (let i = 0; i < idx.length; i++) use[idx[i]]++;
    const ord = Array.from({ length: pal.length - 1 }, (_, i) => i + 1).sort((a, b) => use[b] - use[a] || a - b), to = new Uint16Array(pal.length), np = [0];
    ord.forEach((k, i) => { to[k] = i + 1; np.push(pal[k]); }); for (let i = 0; i < idx.length; i++) idx[i] = to[idx[i]]; pal.length = 0; pal.push(...np); }
  const palBytes = new Uint8Array(pal.length * 4), out = new Uint8Array(w * h * 4);
  pal.forEach((c, k) => { palBytes[k * 4] = c & 255; palBytes[k * 4 + 1] = (c >>> 8) & 255; palBytes[k * 4 + 2] = (c >>> 16) & 255; palBytes[k * 4 + 3] = c >>> 24; });
  for (let i = 0; i < w * h; i++) { const k = idx[i] * 4; out[i * 4] = palBytes[k]; out[i * 4 + 1] = palBytes[k + 1]; out[i * 4 + 2] = palBytes[k + 2]; out[i * 4 + 3] = palBytes[k + 3]; }
  return { pal: palBytes, idx, out, exact: red.exact, colors: pal.length, unique: hist.colors.length };
}

// 85진 글자: 4바이트(작은 쪽 먼저인 32비트 수) → 글자 5개 (문자 33~117). 길이는 4의 배수로 0을 채운다.
export function toText85(bytes) {
  const n = Math.ceil(bytes.length / 4), out = Buffer.alloc(n * 5);
  for (let i = 0; i < n; i++) {
    let v = ((bytes[i * 4] || 0) | ((bytes[i * 4 + 1] || 0) << 8) | ((bytes[i * 4 + 2] || 0) << 16) | ((bytes[i * 4 + 3] || 0) << 24)) >>> 0;
    for (let k = 4; k >= 0; k--) { out[i * 5 + k] = 33 + v % 85; v = Math.floor(v / 85); }
  }
  return out.toString('latin1');
}

export function encodePage(page, maxColors) {
  const ix = indexPage(page.rgba, page.w, page.h, maxColors);
  // 256색 이하면 점마다 1바이트, 넘으면 아랫자리 바이트 면 + 윗자리 바이트 면
  const lo = Buffer.alloc(ix.idx.length), hi = Buffer.alloc(ix.idx.length); for (let i = 0; i < ix.idx.length; i++) { lo[i] = ix.idx[i] & 255; hi[i] = ix.idx[i] >> 8; }
  const raw = Buffer.concat(ix.colors > 256 ? [Buffer.from(ix.pal), lo, hi] : [Buffer.from(ix.pal), lo]);
  const z = zlib.deflateRawSync(raw, { level: 9, memLevel: 9 });
  return { ...ix, raw: raw.length, z: z.length, text: toText85(z) };
}

// 풀었을 때 나와야 하는 점들의 검사 합 (Luau 쪽 verify와 같은 셈)
export function checksum(rgba) {
  const u = new Uint32Array(rgba.buffer, rgba.byteOffset, rgba.length >> 2), M = 4294967291; let a = 1, b = 0;
  for (let i = 0; i < u.length; i++) { a = (a + u[i]) % M; b = (b + a) % M; }
  return a + ':' + b;
}

// Luau 모듈 글. 글자 자료는 한 모듈이 maxChars를 넘지 않게 조각낸다 (Script.Source 20만 자 제한 때문).
export function luauModules(name, enc, w, h, maxChars) {
  const chunks = []; for (let p = 0; p < enc.text.length; p += maxChars) chunks.push(enc.text.slice(p, p + maxChars));
  const lit = s => { let n = 0; while (s.includes(']' + '='.repeat(n) + ']')) n++; const e = '='.repeat(n); return '[' + e + '[' + s + ']' + e + ']'; };
  const files = {};
  files[name + '.luau'] = `-- 자동 생성 (tools/bake/bake.mjs) — 고치지 말 것. 판 「${name}」의 점 자료.\n-- 푸는 법: Decode.page(이 표, {나머지 조각들}) → buffer(RGBA8), 가로, 세로.  형식은 tools/bake/ART_NOTES.md\nreturn {\n\tv = 1, w = ${w}, h = ${h}, n = ${enc.colors}, raw = ${enc.raw}, z = ${enc.z}, parts = ${chunks.length},\n\tdata = ${lit(chunks[0])},\n}\n`;
  for (let i = 1; i < chunks.length; i++) files[name + '_' + (i + 1) + '.luau'] = `-- 자동 생성 (tools/bake/bake.mjs) — 판 「${name}」 점 자료의 ${i + 1}번째 조각\nreturn ${lit(chunks[i])}\n`;
  return files;
}
