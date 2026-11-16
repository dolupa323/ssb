// 16비트 PCM WAV 쓰기 · 읽기 (npm 없이)
import fs from 'node:fs';

// channels: Float32Array[] (채널마다 같은 길이). 돌려주는 값: { bytes, clipped }
export function writeWav(file, channels, sampleRate) {
  const nch = channels.length, n = channels[0].length, data = Buffer.alloc(n * nch * 2);
  let clipped = 0, o = 0;
  for (let i = 0; i < n; i++) for (let c = 0; c < nch; c++) {
    let v = Math.round(channels[c][i] * 32767);
    if (v > 32767) { v = 32767; clipped++; } else if (v < -32768) { v = -32768; clipped++; }
    data.writeInt16LE(v, o); o += 2;
  }
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + data.length, 4); h.write('WAVE', 8);
  h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(nch, 22);
  h.writeUInt32LE(sampleRate, 24); h.writeUInt32LE(sampleRate * nch * 2, 28); h.writeUInt16LE(nch * 2, 32); h.writeUInt16LE(16, 34);
  h.write('data', 36); h.writeUInt32LE(data.length, 40);
  fs.writeFileSync(file, Buffer.concat([h, data]));
  return { bytes: 44 + data.length, clipped };
}

// 돌려주는 값: { sampleRate, channels: Int16Array[] , n }
export function readWav(file) {
  const b = fs.readFileSync(file);
  if (b.toString('latin1', 0, 4) !== 'RIFF' || b.toString('latin1', 8, 12) !== 'WAVE') throw new Error('WAV가 아닙니다: ' + file);
  let p = 12, fmt = null, data = null;
  while (p + 8 <= b.length) {
    const id = b.toString('latin1', p, p + 4), sz = b.readUInt32LE(p + 4);
    if (id === 'fmt ') fmt = { format: b.readUInt16LE(p + 8), nch: b.readUInt16LE(p + 10), sr: b.readUInt32LE(p + 12), bits: b.readUInt16LE(p + 22) };
    else if (id === 'data') data = b.subarray(p + 8, p + 8 + sz);
    p += 8 + sz + (sz & 1);
  }
  if (!fmt || !data || fmt.format !== 1 || fmt.bits !== 16) throw new Error('16비트 PCM WAV만 읽습니다: ' + file);
  const n = data.length / 2 / fmt.nch, channels = [];
  for (let c = 0; c < fmt.nch; c++) channels.push(new Int16Array(n));
  for (let i = 0, o = 0; i < n; i++) for (let c = 0; c < fmt.nch; c++, o += 2) channels[c][i] = data.readInt16LE(o);
  return { sampleRate: fmt.sr, channels, n, bytes: b.length };
}
