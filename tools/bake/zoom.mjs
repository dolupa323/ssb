// 눈으로 견줘 보기: 고른 그림을 「PNG 판(색 줄이기 전)」과 「점 자료 모듈을 풀면 나오는 것(색 줄인 뒤)」에서 잘라 k배로 나란히 놓는다.
//   node tools/bake/zoom.mjs <배율> <이름> [이름…]   →  tools/bake/out/zoom.png   (왼쪽 = PNG, 오른쪽 = 점 자료)
import fs from 'node:fs';
import path from 'node:path';
import { encodePNG, decodePNG } from './lib/png.mjs';
const BAKE = import.meta.dirname, ROOT = path.resolve(BAKE, '..', '..');
const atlas = JSON.parse(fs.readFileSync(path.join(BAKE, 'out', 'atlas.json'), 'utf8'));
const k = +process.argv[2] || 4, names = process.argv.slice(3), outName = process.env.ZOOM_OUT || 'zoom.png';
const cache = {}; const page = f => cache[f] || (cache[f] = decodePNG(fs.readFileSync(f)));
const cells = names.map(n => { const e = atlas.sprites[n]; if (!e) throw new Error('없음: ' + n); const pn = atlas.pages[e.page - 1].name; return { e, a: page(path.join(ROOT, 'assets', pn + '.png')), b: page(path.join(BAKE, 'work', 'q_' + pn + '.png')) }; });
const W = Math.max(...cells.map(c => c.e.w * k * 2 + 12)), H = cells.reduce((a, c) => a + c.e.h * k + 4, 4), out = new Uint8Array(W * H * 4);
for (let i = 0; i < W * H; i++) { out[i * 4] = out[i * 4 + 1] = out[i * 4 + 2] = 128; out[i * 4 + 3] = 255; }
let y0 = 4;
for (const c of cells) {
  [c.a, c.b].forEach((pg, side) => {
    const x0 = 4 + side * (c.e.w * k + 4);
    for (let y = 0; y < c.e.h * k; y++) for (let x = 0; x < c.e.w * k; x++) {
      const s = ((c.e.y + (y / k | 0)) * pg.w + c.e.x + (x / k | 0)) * 4, d = ((y0 + y) * W + x0 + x) * 4, a = pg.rgba[s + 3] / 255;
      for (let j = 0; j < 3; j++) out[d + j] = Math.round(pg.rgba[s + j] * a + 128 * (1 - a));
    }
  });
  y0 += c.e.h * k + 4;
}
fs.writeFileSync(path.join(BAKE, 'out', outName), encodePNG(out, W, H));
console.log('out/' + outName, W + '×' + H);
