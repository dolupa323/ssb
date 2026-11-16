// 글꼴 파일을 Google Fonts 저장소(github.com/google/fonts)에서 받는다. 받는 것은 공개 글꼴 파일과 그 라이선스 글뿐이다(이 프로젝트의 정보는 보내지 않는다).
//   node tools/font/fetch.mjs      → tools/font/fonts/<이름>.ttf · <이름>.OFL.txt
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const OUT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'fonts');
fs.mkdirSync(OUT, { recursive: true });
const BASE = 'https://raw.githubusercontent.com/google/fonts/main/ofl/';
const FILES = [
  ['dohyeon/DoHyeon-Regular.ttf', 'DoHyeon-Regular.ttf'], ['dohyeon/OFL.txt', 'DoHyeon.OFL.txt'],
  ['vt323/VT323-Regular.ttf', 'VT323-Regular.ttf'], ['vt323/OFL.txt', 'VT323.OFL.txt'],
  ['ibmplexsanskr/IBMPlexSansKR-Regular.ttf', 'IBMPlexSansKR-Regular.ttf'], ['ibmplexsanskr/IBMPlexSansKR-Medium.ttf', 'IBMPlexSansKR-Medium.ttf'],
  ['ibmplexsanskr/IBMPlexSansKR-SemiBold.ttf', 'IBMPlexSansKR-SemiBold.ttf'], ['ibmplexsanskr/IBMPlexSansKR-Bold.ttf', 'IBMPlexSansKR-Bold.ttf'],
  ['ibmplexsanskr/OFL.txt', 'IBMPlexSansKR.OFL.txt'],
];
for (const [src, dst] of FILES) {
  const r = await fetch(BASE + src, { headers: { 'User-Agent': 'font-fetch' } });
  if (!r.ok) { console.log('실패 ' + src + ' ' + r.status); process.exitCode = 1; continue; }
  const buf = Buffer.from(await r.arrayBuffer());
  fs.writeFileSync(path.join(OUT, dst), buf);
  console.log(dst + '  ' + buf.length + ' bytes');
}
