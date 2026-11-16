'use strict';
/* 굽기 틀 — 화면 없는 Chrome 안에서 돈다.
   원본 sim.js와 「안쪽을 들여다보는 문 하나(__eval)」만 덧붙인 gfx.js 복사본이 먼저 읽혀 있다.
   여기서는 원본의 그리는 코드를 불러 조각 그림(캔버스)을 만들고, node(bake.mjs)가 점 자료를 가져가 판에 모은다. */
(function () {
  const X = s => GFX.__eval(s);
  /* mk를 바꿔 끼운다: 하는 일은 원본과 같고, 밀도(세계 단위당 점 수)를 window.__OV로 덮어쓸 수 있으며 만든 캔버스에 크기를 적어 둔다 */
  X("mk=function(w,h,fn,ss){ss=window.__OV||ss||SS;const c=document.createElement('canvas');c.width=Math.ceil(w*ss);c.height=Math.ceil(h*ss);const g=c.getContext('2d');g.scale(ss,ss);fn(g);c.__w=w;c.__h=h;c.__ss=ss;window.__lastMk=c;return c;}");
  const setCtx = X('(function(c){ctx=c;})');
  const INK = X('INK'), FD = X('FD'), TAU = Math.PI * 2;
  const SPR = X('SPR');

  const LIST = [], CHARS = {};
  /* name: 아틀라스 이름 · group: 어느 판 묶음 · s: 세계 단위당 점 수 · ox,oy: 기준점(세계 단위 · 그림 왼쪽 위에서)
     o.desc 설명 · o.def/o.use: 원본에서 이 그림을 만드는/그리는 줄을 찾을 글 · o.tile: 'x'|'y' 이어 붙는 방향 · o.clamp: 가장자리 늘이기 */
  function add(name, group, canvas, s, ox, oy, o) { LIST.push(Object.assign({ name, group, canvas, s, ox, oy }, o || {})); }

  /* ---------- 원본이 미리 만들어 두는 캔버스 (ST · FX · WS) ---------- */
  const BUILD = {};
  function build(s) {
    if (BUILD[s]) return BUILD[s];
    window.__OV = s; X('buildStatic()'); X('buildFx()'); X('buildWorld()');
    const b = { ST: X('ST'), FX: X('FX'), WS: X('WS') }; window.__OV = null; return BUILD[s] = b;
  }
  function pre(name, group, path, s, o) {
    const c = path.split('.').reduce((a, k) => a[k], build(s));
    if (!c || !c.getContext) throw new Error('캔버스가 아닙니다: ' + path);
    const m = path.match(/^(\w+)\.(\w+)/);
    add(name, group, c, s, c.__w / 2, c.__h / 2, Object.assign({ def: m[1] + '.' + m[2] + '=', use: m[1] + '.' + m[2] }, o));
  }
  /* 한 방향으로 이어 붙는 그림을 nx×ny번 미리 이어 붙여 둔다 (화면에 놓을 ImageLabel 수를 줄이려고) */
  function tiled(name, group, path, s, nx, ny, o) {
    const src = path.split('.').reduce((a, k) => a[k], build(s)), c = document.createElement('canvas');
    c.width = src.width * nx; c.height = src.height * ny; const g = c.getContext('2d');
    for (let i = 0; i < nx; i++) for (let j = 0; j < ny; j++) g.drawImage(src, i * src.width, j * src.height);
    const m = path.match(/^(\w+)\.(\w+)/);
    add(name, group, c, s, 0, 0, Object.assign({ def: m[1] + '.' + m[2] + '=', use: m[1] + '.' + m[2] }, o));
  }

  /* ---------- 장면 조각: 그리기 반복문 안에 직접 적힌 원본 코드를 잘라 와 빈 캔버스에 돌린다 ---------- */
  function run(sn, vars) {
    if (!SNIP[sn]) throw new Error('조각 없음: ' + sn);
    const k = Object.keys(vars);
    return X('(function(' + k.join(',') + '){' + SNIP[sn].code + '\n})').apply(null, k.map(n => vars[n]));
  }
  /* rect=[x0,y0,x1,y1] 세계 좌표에서 구울 네모 · anchor=[x,y] 기준점(세계 좌표) */
  function piece(name, group, rect, anchor, s, fn, o) {
    o = o || {};
    const w = rect[2] - rect[0], h = rect[3] - rect[1], c = document.createElement('canvas');
    c.width = Math.ceil(w * s); c.height = Math.ceil(h * s);
    const g = c.getContext('2d'); g.scale(s, s); g.translate(-rect[0], -rect[1]);
    g.lineJoin = 'round'; /* 원본은 첫 장면 뒤로 lineJoin이 늘 'round'다 ('miter'로 되돌리는 곳이 없다) */
    if (o.noText) { g.fillText = () => { }; g.strokeText = () => { }; }
    if (o.noLighter) for (const m of ['fill', 'stroke', 'fillRect', 'strokeRect', 'drawImage']) { const f = g[m]; g[m] = function () { if (this.globalCompositeOperation === 'lighter') return; return f.apply(this, arguments); }; }
    setCtx(g); fn(g);
    if (o.snip) { const a = [].concat(o.snip); o.lines = a.map(n => SNIP[n].line + (SNIP[n].endLine !== SNIP[n].line ? '–' + SNIP[n].endLine : '')).join(', '); }
    add(name, group, c, s, anchor[0] - rect[0], anchor[1] - rect[1], o);
  }

  /* ---------- 캐릭터 ---------- */
  const CHAR_S = 2;
  function bakeChars() {
    const sprite = X('sprite');
    window.__OV = CHAR_S; X('cache.clear()');
    for (const type of Object.keys(SPR)) {
      const d = SPR[type]; let remap = null;
      for (let v = 0; v < d.nv; v++) {
        const cs = [0, 1, 2, 3].map(f => sprite(type, v, f, 1, false));
        const px = cs.map(c => c.getContext('2d').getImageData(0, 0, c.width, c.height).data);
        /* 네 걸음 그림 가운데 점 하나까지 같은 것을 찾는다 */
        const rm = [0, 1, 2, 3].map(f => { for (let g = 0; g < f; g++) { let same = true; for (let i = 0; i < px[f].length; i++) if (px[f][i] !== px[g][i]) { same = false; break; } if (same) return g; } return f; });
        if (remap && remap.join() !== rm.join()) throw new Error(type + ': 변형마다 같은 걸음 그림이 다릅니다 ' + remap + ' / ' + rm);
        remap = rm;
        for (let f = 0; f < 4; f++) if (rm[f] === f) {
          add('char/' + type + '/' + v + '/' + f, 'chars', cs[f], CHAR_S, d.ox, d.oy, { ctype: type, trim: true });
          add('mask/' + type + '/' + v + '/' + f, 'mask', sprite(type, v, f, 1, true), CHAR_S, d.ox, d.oy, { ctype: type, trim: true, maskOf: 'char/' + type + '/' + v + '/' + f });
        }
      }
      CHARS[type] = { nv: d.nv, frames: remap, w: d.w, h: d.h, ox: d.ox, oy: d.oy, sc: d.sc || 1, s: CHAR_S };
    }
    window.__OV = null; X('cache.clear()');
  }

  /* ---------- 아이콘 ---------- */
  function bakeIcons() {
    const icon = X('icon'), cache = X('iconCache');
    const one = (key, evo, desc) => { delete cache[key + (evo ? '!' : '')]; window.__OV = 2; icon(key, evo); window.__OV = null;
      add('icon/' + key + (evo ? '/evo' : ''), 'icons', window.__lastMk, 2, 24, 24, { desc, def: 'function icon(', use: 'GFX.icon(' }); };
    for (const k of Object.keys(WEAPONS)) { one(k, false, '무기 ' + WEAPONS[k].name); one(k, true, '무기 진화 ' + (WEAPONS[k].evoName || WEAPONS[k].name) + ' (별 붙음)'); }
    for (const k of Object.keys(PASSIVES)) one(k, false, '장비 ' + PASSIVES[k].name);
    for (const k of Object.keys(FUSIONS)) { one(k, false, '히든 조합 ' + FUSIONS[k].name); one(k, true, '히든 조합 ' + FUSIONS[k].name + ' (카드에 뜰 때 · 별 붙음)'); }
    one('heal', false, '회복 선택지 (삼각김밥)'); one('heal2', false, '회복 선택지 (자양강장제)');
  }

  /* ---------- 바닥 ---------- */
  function bakeFloors(s) {
    const floors = X('floors'), floorTile = X('floorTile');
    ZONES.forEach((Z, i) => {
      if (Z.kind === 'esc') return; /* 에스컬레이터는 바닥 무늬를 쓰지 않는다 (drawEsc) */
      delete floors[i]; window.__OV = s; const c = floorTile(i); window.__OV = null; delete floors[i];
      add('floor/' + Z.key, 'floor_' + Z.key, c, s, 0, 0, { desc: '바닥 무늬 「' + Z.name + '」 (512×512 단위로 가로세로 이어 붙음)', def: 'function floorTile(', use: 'floorTile(', own: true });
    });
  }

  /* ---------- 전부 만든다 ---------- */
  function buildAll(cfg) {
    LIST.length = 0;
    bakeChars();
    const BUL = ['초록 구슬', '빨간 구슬', '분홍 종이', '빨간 도장 찍힌 종이', '보라 구슬', '책', '음표', '결재판', '캐리어', '구두', '봉투'];

    /* ----- ST (buildStatic) ----- */
    pre('st/shadow', 'fx', 'ST.shadow', 1, { desc: '발밑 그림자 (타원 · 부드러운 검정)' });
    pre('st/light', 'world', 'ST.light', 1, { desc: '바닥의 빛 웅덩이 (따뜻한 흰빛 · 240×240으로 늘여 그림)' });
    for (let i = 0; i < 3; i++) pre('st/bean/' + i, 'fx', 'ST.bean.' + i, 2, { desc: '커피콩(경험치) ' + ['작은', '중간', '큰(금빛)'][i] });
    pre('st/kimbap', 'fx', 'ST.kimbap', 2, { desc: '삼각김밥 (회복 아이템)' });
    pre('st/pass', 'fx', 'ST.pass', 2, { desc: '정기권 (자석 아이템)' });
    pre('st/chest', 'fx', 'ST.chest', 2, { desc: '월급봉투 (보스 보상 상자)' });
    for (let i = 0; i < 2; i++) pre('st/card/' + i, 'fx', 'ST.card.' + i, 2, { desc: '교통카드 탄 ' + ['(초록)', '(진화 · 검정 금)'][i] });
    for (let i = 0; i < 2; i++) pre('st/pack/' + i, 'fx', 'ST.pack.' + i, 2, { desc: '백팩 ' + ['(파랑)', '(진화 · 주황 등산 배낭)'][i] });
    pre('st/cup', 'fx', 'ST.cup', 2, { desc: '던지는 커피잔' });
    for (let i = 0; i < 11; i++) pre('st/bul/' + i, 'fx', 'ST.bul.' + i, 2, { desc: '적 탄 ' + i + ' ' + BUL[i] });
    pre('st/stamp', 'fx', 'ST.stamp', 1.5, { desc: '결재 도장 (팀장 공격 예고)' });
    pre('st/doorp', 'fx', 'ST.doorp', 1.5, { desc: '출입문 한 짝 (문지기 공격 예고)' });
    pre('st/table', 'fx', 'ST.table', 1.5, { desc: '회의 탁자 (팀장 공격 예고)' });
    tiled('st/tact', 'world', 'ST.tact', 2, 8, 1, { desc: '노란 점자 블록 띠 (32단위 무늬 8개 = 256×22 · 가로로 이어 붙음)', tile: 'x' });
    pre('st/track', 'world', 'ST.track', cfg.trackS, { desc: '선로 (256×152 · 가로로 이어 붙음)', tile: 'x', q: cfg.noiseQ });
    pre('st/car', 'world', 'ST.car', 2, { desc: '열차 객차 (위에서 본 모습)' });
    pre('st/cab', 'world', 'ST.cab', 2, { desc: '열차 맨 앞 칸' });
    for (let i = 0; i < 7; i++) pre('st/litter/' + i, 'world', 'ST.litter.' + i, 2, { desc: '바닥 쓰레기 ' + ['영수증', '전단지', '껌 자국', '물 얼룩', '배수구', '컵 뚜껑', '쪽지'][i] });

    /* ----- 빛 (glow는 흰색 한 장만 굽는다 — 색은 ImageColor3로 입힌다) ----- */
    { const glows = X('glows'); delete glows['255,255,255']; window.__OV = 1; const c = X('glow')('255,255,255'); window.__OV = null; delete glows['255,255,255'];
      add('fx/glow', 'fx', c, 1, 32, 32, { desc: '둥근 빛 (흰색 · 원본 glow(색) · drawGlow(색,…)은 이것에 색을 입혀 쓴다)', def: 'function glow(', use: 'low(' }); }

    /* ----- FX (buildFx) ----- */
    pre('fx/flare', 'fx', 'FX.flare', 2, { desc: '십자 반짝임 (흰색)' });
    pre('fx/puff', 'fx', 'FX.puff', 1, { desc: '연기 뭉치 (흰색)' });
    pre('fx/flame', 'fx', 'FX.flame', 2, { desc: '불꽃 (핫팩 · 정예 적)' });
    pre('fx/lap', 'fx', 'FX.lap', 2, { desc: '노트북 (광선 쏘는 쪽)' });
    for (let i = 0; i < 2; i++) pre('fx/gstab/' + i, 'fx', 'FX.gstab.' + i, 2, { desc: '진화 장우산 찌르기 ' + ['(남색)', '(검정 금)'][i] });
    pre('fx/gstabT', 'fx', 'FX.gstabT', 2, { desc: '풀정장 신사: 넥타이 감은 검정 금 우산' });
    pre('fx/gcan', 'fx', 'FX.gcan', 2, { desc: '풀정장 신사: 펼친 우산 (위에서 본 모습)' });
    pre('fx/umb', 'fx', 'FX.umb', 2, { desc: '장우산 (접은 모습 · 휘두르기)' });
    pre('fx/scooter', 'fx', 'FX.scooter', 2, { desc: '킥보드' });
    pre('fx/handle', 'fx', 'FX.handle', 2, { desc: '손잡이 (부메랑)' });
    pre('fx/handleG', 'fx', 'FX.handleG', 2, { desc: '프리패스 손잡이 (검정 금)' });
    pre('fx/clock', 'fx', 'FX.clock', 2, { desc: '알람 시계' });
    pre('fx/wake', 'fx', 'FX.wake', 2, { desc: '커피 시한폭탄 (던질 때: 컵 + 알람)' });
    pre('fx/phone', 'fx', 'FX.phone', 2, { desc: '셀카봉 끝의 휴대폰' });

    /* ----- WS (buildWorld) ----- */
    pre('ws/road', 'world', 'WS.road', cfg.trackS, { desc: '차도 (256×152 · 가로로 이어 붙음)', tile: 'x', q: cfg.noiseQ });
    pre('ws/bus', 'world', 'WS.bus', 2, { desc: '버스 (위에서 본 모습 · 2대가 290 간격으로 이어 달림)' });
    pre('ws/gate', 'world', 'WS.gate', 2, { desc: '개찰구 몸통' });
    tiled('ws/esc', 'world', 'WS.esc', 2, 1, 4, { desc: '에스컬레이터 발판 (220×26 무늬 4단 = 220×104 · 세로로 이어 붙음)', tile: 'y' });
    tiled('ws/stair', 'world', 'WS.stair', 2, 1, 4, { desc: '계단 (220×30 무늬 4단 = 220×120 · 세로로 이어 붙음)', tile: 'y' });
    for (let i = 0; i < 2; i++) pre('ws/bench/' + i, 'world', 'WS.bench.' + i, 2, { desc: '열차 긴 의자 ' + ['(청록)', '(분홍 · 배려석)'][i] + ' — 아래쪽 벽의 것은 위아래를 뒤집어 그린다' });
    pre('ws/planter', 'world', 'WS.planter', 2, { desc: '화분 (회사 앞)' });
    for (let i = 0; i < 3; i++) pre('ws/leaf/' + i, 'world', 'WS.leaf.' + i, 2, { desc: '은행잎 ' + i });
    pre('ws/manhole', 'world', 'WS.manhole', 2, { desc: '맨홀 뚜껑' });
    pre('ws/pit', 'world', 'WS.pit', 2, { desc: '가로수 보호판' });
    pre('ws/canopy', 'world', 'WS.canopy', .5, { desc: '가로수 그늘 (200×200 · 240×240으로 늘여 그림)' });

    bakeIcons();
    bakeFloors(cfg.floorS);
    bakePieces();
    build(null); /* 원본 상태(원래 밀도)로 돌려 둔다 */
    return { sprites: LIST.map(e => { const m = Object.assign({}, e); delete m.canvas; m.pw = e.canvas.width; m.ph = e.canvas.height; return m; }), chars: CHARS };
  }

  /* ---------- 장면 조각들 ---------- */
  function bakePieces() {
    const OUT = 132, WALL = 118;
    /* 바닥 표시 */
    piece('sc/arrow/plat', 'world', [-82, -44, 92, 44], [0, 0], 2, () => run('arrowPlat', { x: -640, my: 120 }), { snip: 'arrowPlat', desc: '승강장 바닥의 진행 방향 화살표 (기준점 = 원본의 (ax, ay))' });
    piece('sc/arrow/street', 'world', [-52, -34, 72, 34], [0, 0], 2, g => { g.fillStyle = 'rgba(27,33,36,.16)'; run('arrowStreet', { x: -640, my: -124 }); }, { snip: 'arrowStreet', desc: '역 앞 바닥의 화살표 (기준점 = (ax, ay))' });
    piece('sc/doormark', 'world', [-34, -15, 34, -1], [0, 0], 2, g => { g.fillStyle = 'rgba(27,33,36,.3)'; run('doormark', { x: -108, ey: 0, up: true }); }, { snip: 'doormark', desc: '승강장 타는 곳 세모 두 개 (기준점 = (x+108, ey) · 선로 위쪽 것. 아래쪽 것은 위아래 뒤집기)' });
    piece('sc/chevron', 'world', [-22, -31, 28, 31], [0, 0], 2, g => { g.fillStyle = 'rgba(255,220,90,.75)'; run('chevron', { ax: 0, ly: 0, T: { dir: 1 } }); }, { snip: 'chevron', desc: '열차·버스 진입 경고 갈매기표 (오른쪽 방향 · 기준점 = (ax, ly))' });
    piece('sc/crosswalk', 'world', [300, -58, 521, 58], [300, 0], 2, () => run('crosswalk', { x0: 300, x1: 400, ly: 0 }), { snip: 'crosswalk', desc: '횡단보도 흰 줄 9개 (기준점 = (x+300, ly))' });
    piece('sc/escarrow', 'world', [-50, -48, 50, 48], [0, 0], 2, g => { g.fillStyle = 'rgba(255,255,255,.16)'; run('escarrow', { x: -110, y: 0, dir: 1 }); }, { snip: 'escarrow', desc: '에스컬레이터 진행 방향 화살표 (dir=1 아래쪽 · 기준점 = (x+110, y) · dir=-1은 위아래 뒤집기)' });
    piece('sc/gatetri', 'world', [-10, -57, 10, -41], [0, -49], 2, g => { g.fillStyle = 'rgba(0,168,77,.5)'; run('gatetri', { gx: 0, ry: 0 }); }, { snip: 'gatetri', desc: '개찰구 앞 초록 세모 (위쪽 것 · 중심 = (gx, ry-49) · 아래쪽 것은 위아래 뒤집어 (gx, ry+49))' });

    /* 열차 안 */
    for (const st of [0, 1]) for (const sd of [-1, 1]) {
      const wy = sd > 0 ? WALL : -OUT;
      piece('tr/wall/' + st + '/' + (sd < 0 ? 'top' : 'bot'), 'world', sd < 0 ? [-124, -132, 196, -97] : [-124, 97, 196, 132], [0, 0], 1, () => {
        run('wallBase', { x0: -124, wy, vw: 320, OUT, WALL, sd });
        run('wallGap', { platA: st, dx: 160, wy, OUT, WALL });
        run('wallSill', { dx: 160, sd, WALL });
        run('wallLed', { dx: 160, sd, WALL });
      }, { snip: ['wallBase', 'wallGap', 'wallSill', 'wallLed'], clamp: true, desc: '열차 벽 한 칸(320) ' + (sd < 0 ? '위쪽' : '아래쪽') + ' · ' + (st ? '역에 섰을 때(문 뒤가 밝다)' : '달릴 때(문 뒤가 어둡다)') + ' — 벽 띠 + 문 자리 + 노란 문턱 + 안내판 바탕. 창문 · 문짝 · 글자는 따로. 기준점 = (의자 중심 bx, 0)' });
    }
    for (const st of [0, 1]) piece('tr/window/' + st, 'world', [-104, 0, 104, 9], [0, 4.5], 2, () => run('wallWin', { b: 1, bx: 0, wy: -2.5, OUT, WALL, platA: st }), { snip: 'wallWin', desc: '열차 창문 ' + (st ? '(역에 섰을 때 · 밝음)' : '(달릴 때 · 어두움)') + ' — 벽의 wy+2.5 ~ wy+11.5에 놓는다 (칸 이음매 b%8==0에는 없다)' });
    piece('tr/doorpanel', 'world', [0, 0, 35, 14], [0, 0], 2, () => run('doorPanel', { dx: 0, g2: 0, wy: 0, OUT, WALL }), { snip: 'doorPanel', clamp: true, desc: '열차 문짝 한 장 (35×14 · 기준점 = 왼쪽 위 · 왼짝은 dx-35-31·doorA, 오른짝은 dx+31·doorA에)' });
    piece('tr/joint', 'world', [-24, -132, 24, 132], [0, 0], 1, () => run('joint', { x: 0, OUT }), { snip: 'joint', clamp: true, desc: '객차 이음매 (48×264 · 2560마다)' });
    piece('tr/pole', 'world', [-7, -7, 9, 10], [0, 0], 2, () => run('pole', { px: 0, py: 0 }), { snip: 'pole', desc: '문 옆 손잡이 봉 (위에서 본 동그라미 + 그림자)' });
    piece('tr/strap', 'world', [-8, -2, 8, 21], [0, 0], 2, g => { g.lineCap = 'round'; run('strap', { x: 0, sx: 0, yy: 0 }); }, { snip: 'strap', desc: '천장 손잡이 (흔들리지 않은 모습 · 기준점 = 봉에 매달린 점)' });
    piece('tr/sign', 'world', [-90, -22, 90, 22], [0, 0], 2, () => run('sign', { x: -150, sy: 0 }), { snip: 'sign', desc: '창밖 승강장 역명판 바탕 (글자는 (0,-4)에 24px로 따로)' });
    piece('tr/doorlight', 'world', [-78, -132, 78, -10], [0, 0], 1, () => run('doorlight', { sd: -1, OUT, doorA: 1, dx: 0 }), { snip: 'doorlight', desc: '열린 문으로 드는 빛 (위쪽 문 · doorA=1 · 기준점 = (문 중심 dx, 0) · 아래쪽 문은 위아래 뒤집기 · 원본은 더하기 섞기)' });

    /* 적 · 보스에 덧그리는 것 */
    piece('fx/anger/0', 'fx', [-8, -8, 8, 8], [0, 0], 4, () => run('angerElite', { x: 0, dir: 1, sc: 0, top: -4 }), { snip: 'angerElite', desc: '정예 적 머리의 화남 표시 (기준점 = (mx, my))' });
    piece('fx/anger/1', 'fx', [-9, -9, 9, 9], [0, 0], 4, () => run('angerLead', { x: 0, dir: 0, top: -12 }), { snip: 'angerLead', desc: '김 팀장 화남 표시 (요일 2 이상 · 기준점 = (mx, my))' });
    piece('fx/leadtie', 'fx', [-8, -16, 8, 20], [0, 0], 2, g => { g.lineJoin = 'round'; g.strokeStyle = INK; g.lineWidth = 2; run('leadtie', { x: 0, mid: 0 }); }, { snip: 'leadtie', desc: '김 팀장의 빨간 넥타이 (기준점 = (x, mid))' });
    piece('fx/leadclip', 'fx', [-21, -27, 21, 25], [0, 0], 2, g => { g.lineJoin = 'round'; g.strokeStyle = INK; g.lineWidth = 2; run('leadclip', { x: -30, dir: 1, mid: -6, e: { anim: 0 } }); }, { snip: 'leadclip', desc: '김 팀장이 든 결재판 (dir=1 · 기준점 = (x+dir·30, mid+6) · dir=-1은 좌우 뒤집기)' });
    piece('fx/exitsign', 'fx', [-32, -10, 32, 36], [0, 0], 2, g => { g.lineCap = 'round'; run('exitsign', { e: { x: 0, y: 58, anim: 0 } }); }, { snip: 'exitsign', desc: '하차 인파가 든 「출구」 팻말 (글자 포함 · 기준점 = (e.x, e.y-58))', font: true });
    piece('fx/exitsign/blank', 'fx', [-32, -10, 32, 36], [0, 0], 2, g => { g.lineCap = 'round'; run('exitsign', { e: { x: 0, y: 58, anim: 0 } }); }, { snip: 'exitsign', noText: true, desc: '「출구」 팻말에서 글자만 뺀 것 (글자는 (-9, 11)에 17px 흰색)' });
    piece('fx/soundwave', 'fx', [0, -33, 46, 33], [0, 0], 2, () => run('soundwave', { x: -34, dir: 1, feet: 84, rage: false, time: 0.1 }), { snip: 'soundwave', desc: '스피커 빌런의 소리 물결 (멈춘 한 장면 · dir=1 · 기준점 = (x+dir·34, feet-84))' });
    piece('fx/spintrail', 'fx', [16, -108, 114, 16], [0, 0], 1, () => run('spintrail', { e: { anim: 0 }, x: 0, y: 0 }), { snip: 'spintrail', desc: '백팩 빌런 회전 공격의 붉은 꼬리 (각도 0 · 기준점 = 보스 중심 — 이 점을 축으로 돌린다)' });

    /* 플레이어 발밑 고리 */
    piece('fx/pring/0', 'fx', [-20, -10, 20, 10], [0, 0], 2, g => run('pringBase', { p: { x: 0 }, feet: 1 }), { snip: 'pringBase', desc: '플레이어 발밑 고리 (바탕 · 초록 35%) — 기준점 = (p.x, feet-1)' });
    piece('fx/pring/8', 'fx', [-20, -10, 20, 10], [0, 0], 2, g => { g.lineWidth = 2.6; run('pringArc', { p: { x: 0 }, feet: 1, rdy: 1 }); }, { snip: 'pringArc', desc: '발밑 고리: 대시 준비 끝 (밝은 초록 한 바퀴)' });
    for (let k = 1; k < 8; k++) piece('fx/pring/' + k, 'fx', [-20, -10, 20, 10], [0, 0], 2, g => { g.lineWidth = 2.6; run('pringArc', { p: { x: 0 }, feet: 1, rdy: k / 8 }); }, { snip: 'pringArc', desc: '발밑 고리: 대시 재사용 대기 ' + k + '/8 (흰색 85%)' });

    /* 바닥에 깔리는 것 */
    piece('fx/slick', 'fx', [-44, -36, 44, 36], [0, 0], 2, () => run('slick', { s: { x: 0, y: 0, r: 38, life: 1 }, time: 0 }), { snip: 'slick', desc: '미끄러운 기름 웅덩이 (r=38 기준 · 멈춘 한 장면)' });
    { const rc = WEAPONS.coffee.stat(1).r, rg = WEAPONS.gum.stat(1).r;
      const pud = (name, r, gum, evo, desc) => piece(name, 'fx', [-r * 1.12, -r * .96, r * 1.12, r * .96], [0, 0], 1, () => run('puddle', { u: { x: 0, y: 0, r, dur: 9, life: 5, ph: .56, gum, evo }, time: .3 }), { snip: 'puddle', desc: desc + ' (r=' + r + ' 기준 · 멈춘 한 장면 · 세로 0.84 눌림 포함)', ref: r });
      pud('fx/puddle/coffee', rc, false, false, '커피 웅덩이'); pud('fx/puddle/coffee/evo', rc, false, true, '사약 에스프레소 웅덩이 (진화)');
      pud('fx/puddle/gum', rg, true, false, '껌 자국'); pud('fx/puddle/gum/evo', rg, true, true, '풍선껌 (진화)'); }
    piece('fx/tbcup', 'fx', [-17, -21, 17, 19], [0, 0], 2, () => run('tbcup', { late: 0, time: 0 }), { snip: 'tbcup', desc: '커피 시한폭탄 (바닥에 놓인 컵 · 시곗바늘은 따로 그린다 · 기준점 = (m.x, m.y-6))' });
    piece('fx/dashring', 'fx', [-99, -99, 99, 99], [0, 0], 1, () => run('dashring', { col: '255,255,255', z: { x: 0, y: 0, r: 96 }, time: 0 }), { snip: 'dashring', desc: '점선 고리 (흰색 · 반지름 96 · 선 3 · 점선 12/8) — 공격 예고 원의 테두리. 색을 입히고 크기를 맞춰 쓴다', ref: 96 });
    for (const ev of [0, 1]) { const l = ev ? EVO : 1, r = WEAPONS.hotpack.stat(l).r;
      piece('fx/heatring/' + ev, 'fx', [-r - 2, -r - 2, r + 2, r + 2], [0, 0], .5, () => run('heatring', { l, S: { M: { area: 1 } }, p: { x: 0, y: 0 }, time: 0 }), { snip: 'heatring', desc: '핫팩 열기 바탕 ' + (ev ? '(진화)' : '') + ' — 반지름 ' + r + ' 기준, 실제 반지름에 맞춰 늘인다', ref: r }); }
    piece('fx/crackdecal', 'fx', [-80, -80, 80, 80], [0, 0], 1, () => run('crackdecal', { d: { r: 100, rot: 0 } }), { snip: 'crackdecal', desc: '문 쾅 자국 (r=100 기준 · 원본은 세로 0.86 눌러 그림)', ref: 100 });
    piece('fx/crack', 'fx', [-95, -60, 95, 60], [0, 0], 1, () => run('crack', { q: .3, f: { x: 0, y: -8, r: 100, rot: 0 } }), { snip: 'crack', desc: '배낭 철퇴 내려찍은 자리의 금 (r=100 기준 · 다 벌어진 모습 · 세로 0.62 눌림 포함 · 기준점 = (f.x, f.y+8))', ref: 100 });

    /* 무기 · 조합 */
    piece('fx/gentip', 'fx', [-9, -5, 9, 5], [0, 0], 4, () => run('gentip', { R: -13, fl: 0 }), { snip: 'gentip', desc: '풀정장 신사 우산의 금빛 꼭지 (오른쪽 방향 · 기준점 = 세모 가운데)' });
    for (const k of [0, 1]) piece('fx/remote/' + k, 'fx', [-17, -13, 17, 13], [0, 0], 2, () => run('remote', { k }), { snip: 'remote', desc: '재택근무 모니터 ' + ['(하늘색 화면)', '(보라 화면)'][k] });
    piece('fx/hazardring', 'fx', [-97, -97, 97, 97], [0, 0], 1, () => run('hazardring', { al: 1, th: 12, R: 90, f: { rot: 0 } }), { snip: 'hazardring', desc: '배낭 철퇴 발동: 노랑 검정 줄무늬 고리 (R=90 · 굵기 12 기준 · 원본은 세로 0.8 눌러 그림)', ref: 90 });
    piece('fx/gentspiral', 'fx', [-110, -110, 110, 110], [0, 0], 1, g => { g.lineCap = 'round'; g.lineJoin = 'round'; run('gentspiral', { f: { rot: 0 }, q: .25, R: 100, al: .75 }); }, { snip: 'gentspiral', desc: '풀정장 신사 발동: 넥타이 두 가닥 소용돌이 (R=100 기준 · 멈춘 한 장면 · 원본은 세로 0.82 눌러 그림)', ref: 100 });
    piece('fx/routinerays', 'fx', [-121, -121, 121, 121], [0, 0], 1, () => run('routinerays', { f: { rot: 0 }, q: 0, al: 1, R: 120 }), { snip: 'routinerays', desc: '커피 시한폭탄 터질 때 퍼지는 햇살 12갈래 (R=120 기준 · 원본은 더하기 섞기)', ref: 120 });
    for (const ev of [0, 1]) { const st = WEAPONS.tie.stat(ev ? EVO : 1), len = st.len, w = st.w;
      piece('fx/tie/' + ev, 'fx', [0, -Math.ceil(w * .45 + 3), Math.ceil(len + 16), Math.ceil(w * .45 + 3)], [0, 0], 2, () => run('lash', { q: .5, f: { as: [0], len, w, evo: !!ev }, p: { x: 0, y: 10 } }), { snip: 'lash', noLighter: true, desc: '넥타이 채찍 ' + (ev ? '(진화 · 금빛)' : '(빨강)') + ' — 곧게 편 모습 (길이 ' + len + ' · 폭 ' + w + ' 기준 · 기준점 = 손 (p.x, p.y-10) · 물결은 없다)', ref: len }); }
    for (const ev of [0, 1]) { const txt = ev ? '저 내려요!!!' : '내릴게요!';
      const m = document.createElement('canvas').getContext('2d'); m.font = (ev ? 30 : 26) + 'px ' + FD; const tw = m.measureText(txt).width / 2 + 26;
      piece('fx/shoutburst/' + ev, 'fx', [-Math.ceil(tw * 1.26 + 4), -40, Math.ceil(tw * 1.26 + 10), 46], [0, 0], 2, () => run('shoutburst', { tw, f: { evo: !!ev } }), { snip: 'shoutburst', desc: '「' + txt + '」 말풍선 바탕 (글자 없음 · tw=' + tw.toFixed(1) + ' · 글자는 (0, ' + (ev ? 10 : 9) + ')에 ' + (ev ? 30 : 26) + 'px)', font: true }); }

    /* 화면 표시 */
    piece('ui/edgearrow/boss', 'fx', [-10, -13, 17, 13], [0, 0], 2, () => run('edgearrow', { col: '#b03bd6' }), { snip: 'edgearrow', desc: '화면 밖 보스 방향 화살표 (보라 · 오른쪽 방향)' });
    piece('ui/edgearrow/chest', 'fx', [-10, -13, 17, 13], [0, 0], 2, () => run('edgearrow', { col: '#ffc928' }), { snip: 'edgearrow', desc: '화면 밖 상자 방향 화살표 (노랑)' });
    for (const b of [0, 1]) piece('ui/warn/' + b, 'fx', [-29, -29, 29, 23], [0, 0], 2, () => run('warnsign', { b }), { snip: 'warnsign', desc: '열차·버스 진입 경고 세모 ' + (b ? '(노랑)' : '(빨강)') + ' — 「!」(26px, (0,14))와 「열차 진입」(14px, (0,40)) 글자는 따로' });
    piece('ui/bubbletail', 'fx', [-8, -2, 8, 10], [0, 0], 2, g => { g.fillStyle = '#fbfaf5'; g.strokeStyle = INK; g.lineWidth = 2; g.lineJoin = 'round'; run('bubbletail', { tx: 0, by: 0, bh: 0 }); }, { snip: 'bubbletail', desc: '보스 말풍선 꼬리 (기준점 = (tx, by+bh) 말풍선 아랫변)' });
    piece('ui/vig/amb', 'fx', [0, 0, 960, 540], [480, 270], .25, () => run('vigAmb', { ZONES: [{ tint: '255,255,255', amb: 1 }], S: { zone: 0 }, W: 960, H: 540 }), { snip: 'vigAmb', desc: '화면 가장자리 어둠 (흰색으로 구움 · 16:9 · 장소의 tint 색과 amb 투명도를 입혀 화면 전체에 늘인다)' });
    piece('ui/vig/hurt', 'fx', [0, 0, 960, 540], [480, 270], .25, () => run('vigHurt', { a: 1, W: 960, H: 540 }), { snip: 'vigHurt', desc: '맞았을 때 · 체력 낮을 때 붉은 가장자리 (a=1로 구움)' });
    piece('ui/vig/heal', 'fx', [0, 0, 960, 540], [480, 270], .25, () => run('vigHeal', { healFlash: 2, W: 960, H: 540 }), { snip: 'vigHeal', desc: '회복할 때 초록 가장자리 (투명도 1로 구움)' });
    piece('ui/speedlines', 'fx', [0, 0, 960, 540], [480, 270], .5, g => { run('speedlines', { W: 960, H: 540, speedT: 1 }); g.globalCompositeOperation = 'source-over'; }, { snip: 'speedlines', desc: '대시 · 외침 때의 집중선 (16:9 · speedT=1 · 원본은 더하기 섞기)' });

    /* 입자 모양 */
    piece('fx/spark', 'fx', [-28.5, -4, 5.5, 4], [0, 0], 4, () => run('spark', { q: { x: 0, y: 0, vx: 400, vy: 0, size: 2.4, col: '255,255,255' }, a: 1 }), { snip: 'spark', desc: '불똥 (흰색 · 오른쪽으로 날아가는 모습 · 속도 400 · 크기 2.4 기준 · 가운데 흰 점은 뺐다)' });
    piece('fx/shard', 'fx', [-6, -9, 7, 6], [0, 0], 4, () => run('shard', { q: { size: 8, col: '255,255,255' } }), { snip: 'shard', desc: '파편 세모 (흰색 · size=8 기준)' });
    /* 원본에 없는 도움 그림: 로블록스 GUI에는 세모가 없어서 하나 둔다 */
    piece('prim/tri', 'fx', [-16, 0, 16, 32], [0, 0], 2, g => { g.fillStyle = '#fff'; g.beginPath(); g.moveTo(0, 0); g.lineTo(16, 32); g.lineTo(-16, 32); g.closePath(); g.fill(); }, { desc: '흰 이등변 세모 (꼭짓점이 위 · 원본에 없는 도움 그림 — 레벨 업 빛살 · 상자 빛살 같은 세모를 만들 때)', lines: '(없음)' });
    piece('prim/disc', 'fx', [-16, -16, 16, 16], [0, 0], 2, g => { g.fillStyle = '#fff'; g.beginPath(); g.arc(0, 0, 15.5, 0, TAU); g.fill(); }, { desc: '흰 동그라미 (원본에 없는 도움 그림 — 둥근 입자용)', lines: '(없음)' });
  }

  /* ---------- node로 점 자료를 넘긴다 ---------- */
  function b64(u8) { let s = ''; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000)); return btoa(s); }
  function pixels(i0, i1) {
    let n = 0; for (let i = i0; i < i1; i++) n += LIST[i].canvas.width * LIST[i].canvas.height * 4;
    const out = new Uint8Array(n); let p = 0;
    for (let i = i0; i < i1; i++) { const c = LIST[i].canvas, d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; out.set(d, p); p += d.length; }
    return b64(out);
  }

  window.BAKE = { X, buildAll, pixels, LIST, CHARS, setCtx, b64 };
})();
