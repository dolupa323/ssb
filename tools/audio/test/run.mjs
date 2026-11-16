// src/client/Sound.luau를 Studio 없이 돌려 보는 검사.
//   node tools/audio/test/run.mjs
// tools/mock(공용 검사 도구)이 아직 없어서, 소리에 필요한 만큼만 흉내 낸 작은 가짜 로블록스를 여기 둔다.
// (Sound · SoundGroup · EqualizerSoundEffect의 속성 이름은 tools/mock/ref/API-Dump.json이 있으면 그것과 대조한다)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..', '..');
const WORK = path.join(HERE, '..', 'work');
const read = p => fs.readFileSync(path.join(ROOT, p), 'utf8');
const lstr = s => '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n') + '"';

// 모듈 소스를 함수로 감싼다 (가짜 전역을 매개변수로 넘긴다). `export type`은 함수 안에 둘 수 없어 `type`으로 바꾼다
const wrap = (name, src) => `local function ${name}(game, Instance, NumberRange, os, task, warn, require)\n${src.replace(/^export type/gm, 'type')}\nend\n`;

// 원본이 부르는 효과음 이름 · 인자
const manifest = JSON.parse(fs.readFileSync(path.join(WORK, 'manifest.json'), 'utf8'));
const sim = read('commute-survival/js/sim.js');
const hitSrcs = [...new Set([...sim.matchAll(/,'([a-z]+)'\)/g)].map(m => m[1]).concat(Object.keys(manifest.sfx.hit.sets)))];
const usedNames = Object.keys(manifest.uses);

// 속성 · 메서드 이름 (API 덤프가 있으면 거기서, 없으면 아래 목록)
const CLASSES = ['Sound', 'SoundGroup', 'EqualizerSoundEffect', 'Folder', 'SoundService'];
let members = null, memberSource = '손으로 적은 목록';
const dumpFile = path.join(ROOT, 'tools', 'mock', 'ref', 'API-Dump.json');
if (fs.existsSync(dumpFile)) {
  try {
    const dump = JSON.parse(fs.readFileSync(dumpFile, 'utf8')), by = Object.fromEntries(dump.Classes.map(c => [c.Name, c]));
    members = {};
    for (const cn of CLASSES) { const set = {}; for (let c = by[cn]; c; c = by[c.Superclass]) for (const m of c.Members) if (m.MemberType === 'Property' || m.MemberType === 'Function') set[m.Name] = m.MemberType === 'Property' ? (m.ValueType?.Name || 'any') : 'fn'; members[cn] = set; }
    memberSource = 'tools/mock/ref/API-Dump.json';
  } catch (e) { members = null; }
}
if (!members) {
  const base = { Name: 'string', Parent: 'Instance', ClassName: 'string', FindFirstChild: 'fn', Destroy: 'fn' };
  members = {
    Sound: { ...base, SoundId: 'ContentId', SoundGroup: 'SoundGroup', PlaybackRegionsEnabled: 'bool', PlaybackRegion: 'NumberRange', LoopRegion: 'NumberRange', Looped: 'bool', TimePosition: 'double', PlaybackSpeed: 'float', Volume: 'float', Play: 'fn', Stop: 'fn' },
    SoundGroup: { ...base, Volume: 'float' },
    EqualizerSoundEffect: { ...base, LowGain: 'float', MidGain: 'float', HighGain: 'float', Enabled: 'bool' },
    Folder: { ...base }, SoundService: { ...base },
  };
}
const membersLua = '{\n' + CLASSES.map(c => `\t${c} = { ${Object.entries(members[c]).map(([k, v]) => `[${lstr(k)}] = ${lstr(v)}`).join(', ')} },`).join('\n') + '\n}';

const out = [
  '-- 자동 생성 (tools/audio/test/run.mjs) — 고치지 말 것',
  `local MEMBERS = ${membersLua}`,
  `local USED_NAMES = { ${usedNames.map(lstr).join(', ')} }`,
  `local HIT_SRCS = { ${hitSrcs.map(lstr).join(', ')} }`,
  wrap('mod_SoundMap', read('src/shared/SoundMap.luau')),
  wrap('mod_SoundIds', read('src/shared/SoundIds.luau')),
  wrap('mod_Sound', read('src/client/Sound.luau')),
  fs.readFileSync(path.join(HERE, 'scenario.luau'), 'utf8'),
].join('\n');
// 타입 검사(안쪽만): 이 luau-analyze에는 로블록스 정의를 넣는 옵션이 없어, 로블록스 것은 any로 두고 Sound.luau 안의 타입이 서로 맞는지만 본다
{
  const pre = ['--!strict', 'type Instance = any', 'type Sound = any', 'type SoundGroup = any', 'type EqualizerSoundEffect = any', 'local game: any, Instance: any, NumberRange: any, task: any, warn: any = nil, nil, nil, nil, nil', ''].join('\n');
  const PRE_LINES = 5; // Sound.luau의 첫 줄(--!strict)을 빼고 앞에 6줄을 붙였다
  const f = path.join(WORK, 'analyze_Sound.luau');
  fs.writeFileSync(f, pre + read('src/client/Sound.luau').replace(/^--!strict\r?\n/, ''));
  const a = spawnSync(path.join(ROOT, 'tools', 'luau', 'luau-analyze.exe'), ['--mode=strict', f], { encoding: 'utf8' });
  const outText = ((a.stdout || '') + (a.stderr || '')).trim();
  console.log('타입 검사(luau-analyze, 로블록스 타입은 any): ' + (a.status === 0 && !outText ? '문제 없음' : '\n' + outText + `\n  (줄 번호는 Sound.luau보다 ${PRE_LINES} 크다)`));
  if (a.status !== 0 || outText) process.exitCode = 1;
  for (const m of ['src/shared/SoundMap.luau', 'src/shared/SoundIds.luau', 'src/client/Sound.luau']) {
    const c = spawnSync(path.join(ROOT, 'tools', 'luau', 'luau-compile.exe'), ['--null', path.join(ROOT, m)], { encoding: 'utf8' });
    if (c.status !== 0) { console.log('컴파일 실패: ' + m + '\n' + (c.stdout || '') + (c.stderr || '')); process.exit(1); }
  }
  console.log('컴파일(luau-compile): SoundMap · SoundIds · Sound 문제 없음');
}
const file = path.join(WORK, 'sound_test.luau');
fs.writeFileSync(file, out);
console.log(`속성 이름 대조: ${memberSource}`);
const r = spawnSync(path.join(ROOT, 'tools', 'luau', 'luau.exe'), [file], { encoding: 'utf8' });
process.stdout.write(r.stdout || ''); process.stderr.write(r.stderr || '');
process.exit(r.status === 0 && !process.exitCode ? 0 : 1);
