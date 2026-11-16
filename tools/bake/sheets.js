'use strict';
/* 견본표(contact sheet) — 구운 판에서 잘라 낸 그림을 중간 회색 바탕에 이름과 함께 늘어놓는다.
   캐릭터는 원본 코드(drawChar)가 같은 크기로 그린 것을 바로 옆에 둔다. */
(function () {
  const X = BAKE.X, GREY = '#808080';
  let PAGES = {}, ATLAS = null;
  function load(url) { return new Promise((res, rej) => { const im = new Image(); im.onload = () => res(im); im.onerror = () => rej(new Error('그림을 읽지 못했습니다')); im.src = url; }); }
  /* pages: { 판 이름: PNG data URL } · atlas: { pages, sprites, chars } */
  async function setPages(pages, atlas) { PAGES = {}; for (const k of Object.keys(pages)) PAGES[k] = await load(pages[k]); ATLAS = atlas; return Object.keys(PAGES).length; }
  function addPage(name, url) { return load(url).then(im => { PAGES[name] = im; return true; }); }
  function setAtlas(a) { ATLAS = a; return true; }
  function cut(g, name, x, y, k) { /* 기준점이 (x,y)에 오게 k배로 그린다 */
    const e = ATLAS.sprites[name]; if (!e) throw new Error('아틀라스에 없음: ' + name);
    const im = PAGES[ATLAS.pages[e.page - 1].name]; g.drawImage(im, e.x, e.y, e.w, e.h, x - e.ox * e.s * k, y - e.oy * e.s * k, e.w * k, e.h * k);
  }
  function cross(g, x, y) { g.save(); g.strokeStyle = 'rgba(255,0,255,.9)'; g.lineWidth = 1; g.beginPath(); g.moveTo(x - 6, y + .5); g.lineTo(x + 6, y + .5); g.moveTo(x + .5, y - 6); g.lineTo(x + .5, y + 6); g.stroke(); g.restore(); }
  function label(g, t, x, y, col) { g.save(); g.font = '10px "Malgun Gothic",sans-serif'; g.fillStyle = col || '#fff'; g.textAlign = 'left'; g.textBaseline = 'top'; g.fillText(t, x, y); g.restore(); }
  function canvas(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; const g = c.getContext('2d'); g.fillStyle = GREY; g.fillRect(0, 0, w, h); return [c, g]; }

  /* 캐릭터 견본표: types의 변형마다 한 줄 — 왼쪽 네 칸은 원본 drawChar(걸음 0~3), 오른쪽 네 칸은 아틀라스(걸음 0~3을 frames로 바꿔 자른 것).
     분홍 십자 = 발 기준점. 두 쪽의 십자와 그림이 같은 자리에 와야 한다. */
  function charSheet(types, withMask) {
    const SPR = X('SPR'), drawChar = X('drawChar'); window.__OV = null; X('cache.clear()');
    const rows = []; for (const t of types) for (let v = 0; v < SPR[t].nv; v++) rows.push([t, v]);
    const cw = Math.max(...types.map(t => SPR[t].w)) * 2 + 8, chs = rows.map(r => SPR[r[0]].h * 2 + 20), n = withMask ? 12 : 8;
    const [c, g] = canvas(cw * n + 16, chs.reduce((a, b) => a + b, 0) + 24);
    label(g, '원본 drawChar (걸음 0 1 2 3)', 4, 2, '#ff0'); label(g, '아틀라스 char/… (걸음 0 1 2 3 → frames)', cw * 4 + 12, 2, '#0ff'); if (withMask) label(g, '아틀라스 mask/…', cw * 8 + 12, 2, '#0ff');
    let y = 16;
    rows.forEach(([t, v], ri) => {
      const d = SPR[t], ch = chs[ri], fy = y + d.oy * 2 + 2, C = ATLAS.chars[t];
      for (let f = 0; f < 4; f++) {
        const fx = 4 + f * cw + d.ox * 2 + 2;
        g.save(); g.translate(fx, fy); g.scale(2, 2); BAKE.setCtx(g); drawChar(t, v, f, 1, false, 0, 0, 1); g.restore(); cross(g, fx, fy);
        const ax = 12 + (4 + f) * cw + d.ox * 2 + 2;
        cut(g, 'char/' + t + '/' + v + '/' + C.frames[f], ax, fy, 1); cross(g, ax, fy);
        if (withMask) { const mx = 12 + (8 + f) * cw + d.ox * 2 + 2; g.fillStyle = '#404040'; g.fillRect(mx - d.ox * 2 - 2, y, cw, ch - 12); cut(g, 'mask/' + t + '/' + v + '/' + C.frames[f], mx, fy, 1); cross(g, mx, fy); }
      }
      label(g, t + ' / ' + v, 4, y + ch - 13); y += ch;
    });
    return c.toDataURL('image/png');
  }
  /* 큰 보스: 위 줄 원본, 아래 줄 아틀라스, (가면 줄) */
  function bossSheet(types) {
    const SPR = X('SPR'), drawChar = X('drawChar'); window.__OV = null; X('cache.clear()');
    const cw = Math.max(...types.map(t => SPR[t].w)) * 2 + 8, ch = Math.max(...types.map(t => SPR[t].h)) * 2 + 18;
    const [c, g] = canvas(cw * 4 + 8, ch * 3 * types.length + 8);
    types.forEach((t, ti) => {
      const d = SPR[t], C = ATLAS.chars[t];
      for (let row = 0; row < 3; row++) for (let f = 0; f < 4; f++) {
        const fx = 4 + f * cw + d.ox * 2 + 2, y = 4 + (ti * 3 + row) * ch, fy = y + d.oy * 2 + 2;
        if (row === 0) { g.save(); g.translate(fx, fy); g.scale(2, 2); BAKE.setCtx(g); drawChar(t, 0, f, 1, false, 0, 0, 1); g.restore(); }
        else if (row === 1) cut(g, 'char/' + t + '/0/' + C.frames[f], fx, fy, 1);
        else { g.fillStyle = '#404040'; g.fillRect(fx - d.ox * 2 - 2, y, cw, ch - 14); cut(g, 'mask/' + t + '/0/' + C.frames[f], fx, fy, 1); }
        cross(g, fx, fy);
        if (f === 0) label(g, t + (row === 0 ? ' — 원본 drawChar' : row === 1 ? ' — 아틀라스 char' : ' — 아틀라스 mask'), 4, y + ch - 14, row ? '#0ff' : '#ff0');
      }
    });
    return c.toDataURL('image/png');
  }
  /* 그 밖의 그림: 이름 목록을 받아 흐르듯 늘어놓는다. maxPx보다 큰 것은 줄여 그리고 배율을 적는다. 분홍 십자 = 기준점 */
  function flowSheet(names, W, maxPx) {
    const cells = names.map(n => { const e = ATLAS.sprites[n], k = Math.min(1, maxPx / Math.max(e.w, e.h)); return { n, e, k, w: Math.max(Math.ceil(e.w * k), 6 * Math.min(n.length, 40) * .92) + 8, h: Math.ceil(e.h * k) + 18 }; });
    let x = 4, y = 4, rh = 0; for (const c of cells) { if (x + c.w > W - 4) { x = 4; y += rh; rh = 0; } c.x = x; c.y = y; x += c.w; rh = Math.max(rh, c.h); }
    const [cv, g] = canvas(W, y + rh + 4);
    for (const c of cells) { const e = c.e, im = PAGES[ATLAS.pages[e.page - 1].name];
      g.fillStyle = '#8c8c8c'; g.fillRect(c.x + 2, c.y + 2, Math.ceil(e.w * c.k), Math.ceil(e.h * c.k));
      g.drawImage(im, e.x, e.y, e.w, e.h, c.x + 2, c.y + 2, e.w * c.k, e.h * c.k);
      const ax = c.x + 2 + e.ox * e.s * c.k, ay = c.y + 2 + e.oy * e.s * c.k; if (ax >= c.x && ay >= c.y && ax < c.x + c.w && ay < c.y + c.h) cross(g, Math.round(ax), Math.round(ay));
      label(g, c.n + (c.k < 1 ? ' ×' + c.k.toFixed(2) : ''), c.x + 2, c.y + c.h - 14); }
    return cv.toDataURL('image/png');
  }
  /* 판 한 장을 통째로 (줄여서) — 배치를 본다 */
  function pageSheet(name, k) { const im = PAGES[name], [c, g] = canvas(Math.ceil(im.width * k), Math.ceil(im.height * k)); g.drawImage(im, 0, 0, c.width, c.height); return c.toDataURL('image/png'); }
  /* 이어 붙는 그림이 솔기 없이 이어지는지: 판에서 자른 것을 nx×ny번 이어 그린다 */
  function tileSheet(name, nx, ny, k) {
    const e = ATLAS.sprites[name], im = PAGES[ATLAS.pages[e.page - 1].name], [c, g] = canvas(Math.ceil(e.w * nx * k), Math.ceil(e.h * ny * k));
    for (let i = 0; i < nx; i++) for (let j = 0; j < ny; j++) g.drawImage(im, e.x, e.y, e.w, e.h, i * e.w * k, j * e.h * k, e.w * k, e.h * k);
    return c.toDataURL('image/png');
  }
  window.SHEETS = { setPages, addPage, setAtlas, charSheet, bossSheet, flowSheet, pageSheet, tileSheet };
})();
