// 조각 그림을 판(아틀라스)에 채운다 — 스카이라인 방식(왼쪽 아래부터 채움)

// items: [{ w, h }] (여백을 이미 더한 크기) → 각 item에 page(0부터), x, y를 적는다. 돌려주는 값: 판 수
export function pack(items, W, H) {
  const order = items.map((it, i) => i).sort((a, b) => items[b].h - items[a].h || items[b].w - items[a].w || a - b);
  const pages = [];
  for (const i of order) {
    const it = items[i];
    if (it.w > W || it.h > H) throw new Error(`판(${W}×${H})보다 큰 그림: ${it.name || i} ${it.w}×${it.h}`);
    let placed = false;
    for (let p = 0; p <= pages.length && !placed; p++) {
      if (p === pages.length) pages.push([{ x: 0, y: 0, w: W }]);
      const sky = pages[p]; let best = null;
      for (let s = 0; s < sky.length; s++) {
        const x = sky[s].x; if (x + it.w > W) break;
        // 이 자리에서 그림 폭만큼 걸치는 구간들 가운데 가장 높은 곳
        let y = 0, rem = it.w, k = s;
        while (rem > 0) { y = Math.max(y, sky[k].y); rem -= sky[k].w; k++; }
        if (y + it.h > H) continue;
        if (!best || y < best.y || (y === best.y && x < best.x)) best = { x, y, s };
      }
      if (!best) continue;
      it.page = p; it.x = best.x; it.y = best.y; placed = true;
      // 스카이라인을 고친다
      const nx = best.x + it.w, add = { x: best.x, y: best.y + it.h, w: it.w }; let k = best.s;
      while (k < sky.length && sky[k].x + sky[k].w <= nx) sky.splice(k, 1);
      if (k < sky.length && sky[k].x < nx) { const cut = nx - sky[k].x; sky[k].x = nx; sky[k].w -= cut; }
      sky.splice(k, 0, add);
      for (let m = 0; m + 1 < sky.length; m++) if (sky[m].y === sky[m + 1].y) { sky[m].w += sky[m + 1].w; sky.splice(m + 1, 1); m--; }
    }
  }
  return pages.length;
}
