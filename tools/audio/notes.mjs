// AUDIO_NOTES.md 안의 「자동 생성」 부분(파일 목록 · 이름 → 구간 표)을 work/manifest.json으로 새로 쓴다.
// bake.mjs가 끝에 부른다. 따로 돌릴 수도 있다: node tools/audio/notes.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BEGIN = '<!-- 자동 생성 시작: 이 줄과 「자동 생성 끝」 사이는 bake.mjs가 덮어쓴다 -->';
const END = '<!-- 자동 생성 끝 -->';

export function updateNotes() {
  const file = path.join(HERE, 'AUDIO_NOTES.md');
  if (!fs.existsSync(file)) return false;
  const text = fs.readFileSync(file, 'utf8'), a = text.indexOf(BEGIN), b = text.indexOf(END);
  if (a < 0 || b < a) return false;
  const M = JSON.parse(fs.readFileSync(path.join(HERE, 'work', 'manifest.json'), 'utf8'));
  const f3 = v => v.toFixed(3), d1 = v => v.toFixed(1);
  const L = [];
  L.push('', '### 올릴 파일', '', '| 파일 | 길이 | 크기 | 채널 | 담긴 구간 | SoundIds의 키 |', '|---|---|---|---|---|---|');
  for (const f of M.files) L.push(`| \`${f.file}\` | ${f.seconds.toFixed(2)}초 (${Math.floor(Math.round(f.seconds) / 60)}분 ${Math.round(f.seconds) % 60}초) | ${(f.bytes / 1e6).toFixed(2)}MB | ${f.channels === 1 ? '모노' : '스테레오'} | ${f.entries}개 | \`${f.key}\` |`);
  L.push('', '### 음악 구간', '', '| 무엇 | 파일 | 처음(초) | 되풀이 시작(초) | 끝(초) | 되풀이 길이(초) | 최대(dBFS) | 이음매에서 구울 때 잰 차이 |', '|---|---|---|---|---|---|---|---|');
  const mrow = (label, e) => L.push(`| ${label} | ${e.sheet} | ${f3(e.t0)} | ${f3(e.t0 + e.loop0 / M.sampleRate)} | ${f3(e.t1)} | ${f3(e.t1 - e.t0 - e.loop0 / M.sampleRate)} | ${d1(e.peakDb)} | ${e.wrap.max.toExponential(1)} |`);
  mrow(`메뉴 노래 (${M.music.menu.bpm}bpm)`, M.music.menu);
  M.music.songs.forEach((s, k) => mrow(`역 ${k} 「${s.name}」 (${s.bpm}bpm)`, s));
  M.music.songs.forEach((s, k) => L.push(`| 역 ${k} 보스 층 | ${s.boss.sheet} | ${f3(s.boss.t0)} | ${f3(s.boss.t0)} | ${f3(s.boss.t1)} | ${f3(s.boss.t1 - s.boss.t0)} | ${d1(s.boss.peakDb)} | ${s.boss.wrap.max.toExponential(1)} |`));
  const amb = M.music.amb;
  L.push(`| 웅성거림 | ${amb.sheet} | ${f3(amb.t0)} | ${f3(amb.t0)} | ${f3(amb.t1)} | ${f3(amb.t1 - amb.t0)} | ${d1(amb.peakDb)} | ${amb.wrap.max.toExponential(1)} |`);
  L.push('', '### 한 번 울리는 구간 (이름 → 구간)', '', '「갈래」: `one` 인자 없음 · `off`/`on` 진화 전/후 · 무기 이름(hit) · 보스 종류(voice) · `a0`~`a12`/`b0`~`b12` 원두(작은 것/값 3 이상 × 이어 주운 횟수) · `n0`~`n10` 남은 초. `#1`~`#4`는 무작위로 하나를 고르는 갈래.', '', '| 이름 | 최소 간격(초) | 갈래 | 파일 | 시작~끝(초) | 길이(초) | 최대(dBFS) | 원본이 부르나 |', '|---|---|---|---|---|---|---|---|');
  for (const [name, d] of Object.entries(M.sfx)) for (const [k, list] of Object.entries(d.sets)) for (const e of list) {
    L.push(`| ${name} | ${d.gap} | ${k}${list.length > 1 ? ' ' + e.id.slice(e.id.indexOf('#')) : ''} | ${e.sheet} | ${f3(e.t0)}~${f3(e.t1)} | ${f3(e.t1 - e.t0)} | ${d1(e.peakDb)} | ${d.called ? '예' : '아니오'} |`);
  }
  for (const [label, e] of [['(심장 박동 — music이 0.78초마다)', M.music.heart], ['(심벌 — 노래가 바뀔 때)', M.music.crash]]) L.push(`| ${label} | – | – | ${e.sheet} | ${f3(e.t0)}~${f3(e.t1)} | ${f3(e.t1 - e.t0)} | ${d1(e.peakDb)} | 예 |`);
  L.push('');
  fs.writeFileSync(file, text.slice(0, a + BEGIN.length) + '\n' + L.join('\n') + '\n' + text.slice(b));
  return true;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) console.log(updateNotes() ? 'AUDIO_NOTES.md의 표를 새로 썼다' : 'AUDIO_NOTES.md가 없거나 자동 생성 표시가 없다');
