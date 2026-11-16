// UI 시나리오를 모두 돌리고 결과를 한 줄씩 적는다.
//   node tools/ui/run.mjs            전부 (오래 걸리는 botwin 포함 — 2분쯤)
//   node tools/ui/run.mjs --quick    botwin 빼고
//   node tools/ui/run.mjs flow       이름에 그 글이 든 것만
// 대역(tools/ui/stubs의 Gfx · Sound)으로 도는 것: test.project.json. 진짜 모듈로 도는 것(real): default.project.json.
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const TEST = 'tools/ui/test.project.json';
const SHOTS = 'tools/ui/shots';
const sc = n => `tools/ui/scenarios/${n}.luau`;
const RUNS = [
  ['flow 1280x720', ['--project', TEST, '--script', sc('flow'), '--viewport', '1280x720']],
  ['flow 1920x1080', ['--project', TEST, '--script', sc('flow'), '--viewport', '1920x1080']],
  ['flow 844x390', ['--project', TEST, '--script', sc('flow'), '--viewport', '844x390']],
  ['flow 390x844 (폰 배치)', ['--project', TEST, '--script', sc('flow'), '--viewport', '390x844']],
  ['flow 568x320 (폰 배치)', ['--project', TEST, '--script', sc('flow'), '--viewport', '568x320']],
  ['flow immediate signals', ['--project', TEST, '--script', sc('flow'), '--viewport', '1280x720', '--signals', 'immediate']],
  ['touch 844x390', ['--project', TEST, '--script', sc('touch'), '--viewport', '844x390', '--touch']],
  ['resize', ['--project', TEST, '--script', sc('resize')]],
  ['measure (글 폭 고쳐 놓기)', ['--project', TEST, '--script', sc('measure')]],
  ['server', ['--project', TEST, '--no-start', '--script', sc('server')]],
  ['server_fail', ['--project', TEST, '--no-start', '--script', sc('server_fail')]],
  ['real 1280x720', ['--script', sc('real'), '--viewport', '1280x720']],
  ['real 1920x1080', ['--script', sc('real'), '--viewport', '1920x1080']],
  ['real 844x390 touch', ['--script', sc('real'), '--viewport', '844x390', '--touch']],
  ['botwin 1280x720', ['--project', TEST, '--script', sc('botwin'), '--timeout', '900'], true],
];
const args = process.argv.slice(2);
const quick = args.includes('--quick');
const filter = args.find(a => !a.startsWith('--'));
let bad = 0;
for (const [name, a, slow] of RUNS) {
  if (quick && slow) continue;
  if (filter && !name.includes(filter)) continue;
  const r = spawnSync(process.execPath, ['tools/mock/run.mjs', ...a, '--shot-dir', SHOTS, '--quiet'], { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const out = (r.stdout || '') + (r.stderr || '');
  const last = out.split(/\r?\n/).filter(l => l.startsWith('끝:')).pop() || '(끝 줄 없음)';
  const fails = out.split(/\r?\n/).filter(l => /^(확인 실패|오류 \[)/.test(l));
  const noShot = out.split(/\r?\n/).filter(l => l.startsWith('화면을 찍지 못했다')).length;
  if (r.status !== 0) bad++;
  console.log(`${r.status === 0 ? 'PASS' : 'FAIL'}  ${name.padEnd(28)} ${last}${noShot ? `  (화면 ${noShot}장을 찍지 못했다)` : ''}`);
  for (const f of fails.slice(0, 12)) console.log('        ' + f);
}
process.exit(bad ? 1 : 0);
