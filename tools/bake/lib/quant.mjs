// 색 줄이기 — 판 한 장을 팔레트(많아야 256색) + 점마다 1바이트 번호로 바꾼다.
// 거리는 알파를 곱한 색(premultiplied) + 알파의 4차원에서 잰다. 불투명한 점은 불투명한 색으로만 간다.

// rgba: Uint8Array(n*4) → { colors: Uint32Array(k) (r | g<<8 | b<<16 | a<<24, 알파 0은 뺀다), counts, index: Int32Array(n) (색 번호 · 투명은 -1) }
export function histogram(rgba) {
  const n = rgba.length >> 2, map = new Map(), index = new Int32Array(n), colors = [], counts = [];
  const u32 = new Uint32Array(rgba.buffer, rgba.byteOffset, n);
  for (let i = 0; i < n; i++) {
    if (rgba[i * 4 + 3] === 0) { index[i] = -1; continue; }
    const c = u32[i]; let k = map.get(c);
    if (k === undefined) { k = colors.length; map.set(c, k); colors.push(c); counts.push(0); }
    counts[k]++; index[i] = k;
  }
  return { colors: Uint32Array.from(colors), counts: Float64Array.from(counts), index };
}

// colors(보이는 색들) → 많아야 limit개의 팔레트. 돌려주는 값: { palette: Uint32Array, map: Int32Array(색 번호 → 팔레트 번호) }
export function reduce(colors, counts, limit) {
  const N = colors.length;
  if (N <= limit) return { palette: Uint32Array.from(colors), map: Int32Array.from({ length: N }, (_, i) => i), exact: true };
  // 알파를 곱한 좌표
  const P = new Float32Array(N * 4), OPQ = new Uint8Array(N);
  for (let i = 0; i < N; i++) { const c = colors[i], a = c >>> 24, f = a / 255; P[i * 4] = (c & 255) * f; P[i * 4 + 1] = ((c >>> 8) & 255) * f; P[i * 4 + 2] = ((c >>> 16) & 255) * f; P[i * 4 + 3] = a; OPQ[i] = a === 255 ? 1 : 0; }
  const C = new Float32Array(limit * 4), CO = new Uint8Array(limit), fixed = new Uint8Array(limit); let K = 0;
  const best = new Float32Array(N).fill(Infinity), who = new Int32Array(N).fill(-1);
  const BIG = 1e9;
  const addCenter = (x, y, z, w, opq, fix) => {
    const k = K++; C[k * 4] = x; C[k * 4 + 1] = y; C[k * 4 + 2] = z; C[k * 4 + 3] = w; CO[k] = opq; fixed[k] = fix ? 1 : 0;
    for (let i = 0; i < N; i++) { const dx = P[i * 4] - x, dy = P[i * 4 + 1] - y, dz = P[i * 4 + 2] - z, dw = P[i * 4 + 3] - w, d = dx * dx + dy * dy + dz * dz + dw * dw + (OPQ[i] !== opq ? BIG : 0); if (d < best[i]) { best[i] = d; who[i] = k; } }
  };
  // 1) 넓게 칠해진 색은 그대로 팔레트에 둔다 (평평한 면이 흐트러지지 않게)
  let total = 0; for (let i = 0; i < N; i++) total += counts[i];
  const order = Array.from({ length: N }, (_, i) => i).sort((a, b) => counts[b] - counts[a]);
  const minCount = Math.max(48, total * 0.0004), maxFixed = Math.floor(limit * 0.55);
  for (const i of order) { if (K >= maxFixed || counts[i] < minCount) break; addCenter(P[i * 4], P[i * 4 + 1], P[i * 4 + 2], P[i * 4 + 3], OPQ[i], true); }
  if (K === 0) { const i = order[0]; addCenter(P[i * 4], P[i * 4 + 1], P[i * 4 + 2], P[i * 4 + 3], OPQ[i], true); }
  // 2) 나머지 자리는 「지금 팔레트로는 가장 크게 틀리는 색」부터 하나씩 채운다
  while (K < limit) {
    let bi = -1, bs = 0;
    for (let i = 0; i < N; i++) { const s = Math.min(best[i], 1e6) * Math.sqrt(counts[i]); if (s > bs) { bs = s; bi = i; } }
    if (bi < 0) break;
    addCenter(P[bi * 4], P[bi * 4 + 1], P[bi * 4 + 2], P[bi * 4 + 3], OPQ[bi], false);
  }
  // 3) k-평균으로 몇 번 다듬는다 (고정한 색은 움직이지 않는다)
  for (let it = 0; it < 6; it++) {
    const S = new Float64Array(K * 4), Wt = new Float64Array(K);
    for (let i = 0; i < N; i++) { const k = who[i], w = counts[i]; S[k * 4] += P[i * 4] * w; S[k * 4 + 1] += P[i * 4 + 1] * w; S[k * 4 + 2] += P[i * 4 + 2] * w; S[k * 4 + 3] += P[i * 4 + 3] * w; Wt[k] += w; }
    for (let k = 0; k < K; k++) if (!fixed[k] && Wt[k] > 0) { for (let j = 0; j < 4; j++) C[k * 4 + j] = S[k * 4 + j] / Wt[k]; if (!CO[k] && C[k * 4 + 3] > 254) C[k * 4 + 3] = 254; }
    for (let i = 0; i < N; i++) {
      let bd = Infinity, bk = 0; const x = P[i * 4], y = P[i * 4 + 1], z = P[i * 4 + 2], w = P[i * 4 + 3], o = OPQ[i];
      for (let k = 0; k < K; k++) { if (CO[k] !== o) continue; const dx = x - C[k * 4], dy = y - C[k * 4 + 1], dz = z - C[k * 4 + 2], dw = w - C[k * 4 + 3], d = dx * dx + dy * dy + dz * dz + dw * dw; if (d < bd) { bd = d; bk = k; } }
      who[i] = bk; best[i] = bd;
    }
  }
  // 4) 곧은 알파의 정수 색으로 되돌린다
  const palette = new Uint32Array(K);
  for (let k = 0; k < K; k++) {
    let a = Math.round(C[k * 4 + 3]); a = CO[k] ? 255 : Math.max(1, Math.min(254, a));
    const f = 255 / Math.max(C[k * 4 + 3], 1e-3), q = v => Math.max(0, Math.min(255, Math.round(v * f)));
    palette[k] = (q(C[k * 4]) | (q(C[k * 4 + 1]) << 8) | (q(C[k * 4 + 2]) << 16) | (a << 24)) >>> 0;
  }
  return { palette, map: who, exact: false };
}

// 조각 그림 하나를 q색으로 미리 줄인다 (잡음이 많은 바탕 무늬용)
export function quantizeInPlace(rgba, q) {
  const h = histogram(rgba); if (h.colors.length <= q) return h.colors.length;
  const r = reduce(h.colors, h.counts, q), u32 = new Uint32Array(rgba.buffer, rgba.byteOffset, rgba.length >> 2);
  for (let i = 0; i < u32.length; i++) if (h.index[i] >= 0) u32[i] = r.palette[r.map[h.index[i]]];
  return r.palette.length;
}
