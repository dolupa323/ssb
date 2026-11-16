// Decode.luau의 deflate 풀기를 따로 시험한다: 실제 판에서는 잘 안 나오는 덩어리 종류(압축 안 함 · 고정 허프만)와 겹치는 복사, 256색 넘는 판.
//   node tools/bake/test-decode.mjs
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { execFileSync } from 'node:child_process';
import { toText85, checksum } from './lib/codec.mjs';
const BAKE = import.meta.dirname, ROOT = path.resolve(BAKE, '..', '..'), WORK = path.join(BAKE, 'work');
let seed = 12345; const rnd = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296;
function make(name, w, h, n, fill, opt) {
  const pal = new Uint8Array(n * 4); for (let i = 4; i < n * 4; i++) pal[i] = rnd() * 256 | 0;   // 0번은 투명
  const idx = new Uint16Array(w * h); for (let i = 0; i < w * h; i++) idx[i] = fill(i) % n;
  const lo = Buffer.from(idx.map(v => v & 255)), hi = Buffer.from(idx.map(v => v >> 8));
  const raw = Buffer.concat(n > 256 ? [Buffer.from(pal), lo, hi] : [Buffer.from(pal), lo]), z = zlib.deflateRawSync(raw, opt);
  const out = new Uint8Array(w * h * 4); for (let i = 0; i < w * h; i++) out.set(pal.subarray(idx[i] * 4, idx[i] * 4 + 4), i * 4);
  const text = toText85(z), cut = Math.ceil(text.length / 15) * 5;   // 세 조각으로 나눠 조각 잇기도 시험
  const parts = [text.slice(0, cut), text.slice(cut, cut * 2), text.slice(cut * 2)].filter(s => s.length);
  return { name, w, h, n, raw: raw.length, z: z.length, parts, sum: checksum(out) };
}
const cases = [
  make('stored', 64, 48, 200, () => rnd() * 200 | 0, { level: 0 }),                                   // 압축 안 한 덩어리
  make('fixed', 64, 48, 16, i => (i >> 3) + (i % 7 === 0 ? 3 : 0), { strategy: zlib.constants.Z_FIXED }),   // 고정 허프만
  make('runs', 256, 64, 5, i => (i % 256 < 200 ? 0 : 1 + (i >> 9) % 4), { level: 9 }),                 // 긴 되풀이 (겹치는 복사 · 거리 1)
  make('period3', 90, 30, 4, i => i % 3, { level: 9 }),                                               // 거리 3짜리 겹치는 복사
  make('noise16', 128, 128, 3000, () => rnd() * 3000 | 0, { level: 9 }),                              // 256색 넘는 판 · 긴 허프만 부호
  make('huge', 1024, 64, 256, i => (i * 2654435761 >>> 20) % 256, { level: 6 }),
  make('tiny', 1, 1, 2, () => 1, { level: 9 }), make('odd', 7, 3, 300, i => i * 37, { level: 9 }),
];
const lit = s => { let n = 0; while (s.includes(']' + '='.repeat(n) + ']')) n++; const e = '='.repeat(n); return '[' + e + '[' + s + ']' + e + ']'; };
let s = `local Decode = require("${path.relative(WORK, path.join(ROOT, 'src', 'shared', 'art', 'Decode')).split(path.sep).join('/')}")\nlocal M = 4294967291\nlocal function sum(buf)\n\tlocal a, b = 1, 0\n\tfor i = 0, buffer.len(buf) - 4, 4 do a = (a + buffer.readu32(buf, i)) % M; b = (b + a) % M end\n\treturn string.format("%.0f:%.0f", a, b)\nend\n`;
for (const c of cases) s += `do\n\tlocal buf, w, h = Decode.page({ v = 1, w = ${c.w}, h = ${c.h}, n = ${c.n}, raw = ${c.raw}, z = ${c.z}, parts = ${c.parts.length}, data = ${lit(c.parts[0])} }, { ${c.parts.slice(1).map(lit).join(', ')} })\n\tprint("${c.name}", w, h, buffer.len(buf), sum(buf))\nend\n`;
s += `print(pcall(Decode.page, { v = 2, w = 1, h = 1, n = 1, raw = 5, z = 1, parts = 1, data = "!!!!!" }))\n`;
fs.writeFileSync(path.join(WORK, 'testdec.luau'), s);
let bad = 0;
for (const args of [['testdec.luau'], ['--codegen', 'testdec.luau']]) {
  const out = execFileSync(path.join(ROOT, 'tools', 'luau', 'luau.exe'), args, { cwd: WORK, encoding: 'utf8' }).trim().split(/\r?\n/);
  cases.forEach((c, i) => { const f = out[i].split(/\s+/), ok = f[0] === c.name && +f[1] === c.w && +f[2] === c.h && +f[3] === c.w * c.h * 4 && f[4] === c.sum; if (!ok) bad++; console.log((ok ? 'ok  ' : 'FAIL') + ' ' + (args.length > 1 ? 'codegen ' : 'interp  ') + c.name.padEnd(9) + ` ${c.w}×${c.h} n=${c.n} z=${c.z} 조각 ${c.parts.length}  ${f[4]} ${ok ? '' : '≠ ' + c.sum}`); });
  console.log('     모르는 형식(v=2) → ' + out[cases.length]);
}
process.exit(bad ? 1 : 0);
