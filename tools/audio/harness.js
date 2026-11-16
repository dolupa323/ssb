'use strict';
/* 굽는 쪽(페이지). 원본 audio.js의 복사본(work/audio.patched.js)을 OfflineAudioContext에서 돌려
   소리를 그대로 받아 낸다. node 쪽(bake.mjs)이 B.* 를 불러 쓴다. */
const SR = 44100;
// Chrome은 128표본(렌더 단위)씩 소리를 만들고, 음이 그 단위 안의 어디에서 시작하느냐에 따라 결과가 조금 달라진다.
// 그래서 원본이 실제로 쓰는 자리를 그대로 따른다:
const QT = 172 * 128;                // 22016표본 ≈ 0.499초. 앞부분은 게인이 자리 잡는 시간
const T0 = QT / SR;                  // 효과음: 원본은 now(= currentTime = 렌더 단위의 경계)에 낸다
const M0 = QT + 3528;                // 음악 첫 스텝: 원본은 now + 0.08초(3528표본)에 시작한다
const frac = x => x - Math.floor(x);
const BASE_SEED = 0x5eed1234;        // 잡음 버퍼 · 잔향 임펄스가 늘 같게
const AT = AudioSys._test;
const B = { store: {}, nextId: 1 };

async function render(lenSamples, setup) {
  AudioSys.vol(1, 1);                // 원본의 음량 100% 상태(효과음 게인 1.5 · 음악 게인 0.45)
  const ctx = new OfflineAudioContext(2, lenSamples, SR);
  __seed(BASE_SEED); AT.build(ctx);
  await setup(ctx);
  const buf = await ctx.startRendering();
  return [buf.getChannelData(0), buf.getChannelData(1)];
}
function keep(ch) { const id = B.nextId++; B.store[id] = ch; return id; }
function b64(f32) {
  const u = new Uint8Array(f32.buffer, f32.byteOffset, f32.byteLength); let s = '';
  for (let i = 0; i < u.length; i += 32768) s += String.fromCharCode.apply(null, u.subarray(i, i + 32768));
  return btoa(s);
}
B.take = (id, c, off, n) => b64(B.store[id][c].subarray(off, off + n));
B.len = id => B.store[id][0].length;
B.drop = id => { delete B.store[id]; return true; };

/* 원본에 무엇이 있는지 */
B.info = () => {
  const names = Object.keys(AT.SFX);
  return {
    QT, M0,
    names,
    gap: Object.fromEntries(names.map(k => [k, AT.SFX[k][0]])),
    // 세 번째 매개변수 이름(evo · src · v · n · who) — 인자에 따라 소리가 바뀌는 효과음
    argName: Object.fromEntries(names.map(k => { const m = AT.SFX[k][1].toString().match(/^\(t,d(?:,(\w+))?\)/); return [k, m ? (m[1] || '') : '?']; })),
    // 부를 때마다 높이 · 음색을 무작위로 바꾸는 효과음
    rnd: names.filter(k => /\brnd\(/.test(AT.SFX[k][1].toString())),
    hit: Object.keys(AT.HIT), voice: Object.keys(AT.VOICE), vol: AT.VOL,
    songs: AT.SONGS.map(s => ({ name: s.name, bpm: s.bpm })), menu: { name: AT.MENU.name, bpm: AT.MENU.bpm },
  };
};

/* 한 번 울리는 소리: 앞뒤 무음을 잘라 모노로 돌려준다 (좌우 차이도 재서 알려 준다) */
function trimMono(ch, opt) {
  const L = ch[0], R = ch[1], n = L.length;
  let peak = 0, mid = 0, side = 0, first = -1;
  for (let i = 0; i < n; i++) {
    const m = (L[i] + R[i]) / 2, s = (L[i] - R[i]) / 2, a = Math.max(Math.abs(L[i]), Math.abs(R[i]));
    if (a > peak) peak = a; mid += m * m; side += s * s;
    if (first < 0 && a > 2e-5) first = i;
  }
  if (first < 0) return { silent: true, peak };
  const thr = Math.max(1e-4, Math.min(1e-3, peak * 0.01));
  let last = first;
  for (let i = n - 1; i > first; i--) if (Math.max(Math.abs(L[i]), Math.abs(R[i])) > thr) { last = i; break; }
  const a = Math.max(0, first - opt.pre), b = Math.min(n, last + 1 + opt.post), out = new Float32Array(b - a);
  for (let i = a; i < b; i++) out[i - a] = (L[i] + R[i]) / 2;
  return { silent: false, peak, first, last, start: a, n: out.length, hitEnd: last >= n - 2, sideRatio: side / (mid + 1e-20), thr, data: b64(out) };
}

B.sfx = async o => {
  const ch = await render(Math.round((o.len || 6.5) * SR), () => {
    __seed(o.seed);
    if (o.name === 'pick') { if (o.streak > 0) AT.setPick(o.streak - 1, T0 - 0.1); else AT.setPick(0, -9); }
    AT.sfxAt(o.name, T0, o.arg);
  });
  return trimMono(ch, o);
};

/* 체력이 낮을 때의 심장 박동: 원본 music()을 그대로 부른다(음악은 꺼 둔 상태로). 페이지를 연 뒤 한 번만 부를 것 */
B.heart = async o => {
  const ch = await render(Math.round(2.5 * SR), ctx => {
    // 멈추는 시각은 렌더 단위의 경계로 올림된다 → QT에서 멈춘다 (그때의 currentTime = T0)
    ctx.suspend((QT - 64) / SR).then(() => { AudioSys.vol(0, 1); AudioSys.music({ scene: 'play', lowhp: true, muffled: false, crowd: 0 }); ctx.resume(); });
  });
  return trimMono(ch, o);
};

/* 노래가 바뀔 때의 심벌: 원본 music()의 I.crash(nextT,.3) */
B.crash = async o => {
  const ch = await render(Math.round(5 * SR), () => { __seed(o.seed); AT.I.crash(M0 / SR, .3); });
  return trimMono(ch, o);
};

/* 승강장 웅성거림: 원본 music()이 ambGain을 올린다(최대 0.05 = 적 400마리 이상). 자리 잡은 뒤의 소리를 통째로 보관 */
B.amb = async o => {
  const ch = await render(Math.round(o.len * SR), () => { AudioSys.vol(0, 1); AudioSys.music({ scene: 'play', crowd: o.crowd }); });
  return { id: keep(ch) };
};

/* I.* 호출을 소리 없이 적기만 한다 */
function record(fn) {
  const I = AT.I, orig = {}, log = [];
  for (const k in I) { orig[k] = I[k]; I[k] = (...a) => { log.push([k, a]); }; }
  try { fn(); } finally { Object.assign(I, orig); }
  return log;
}
// 보스가 있을 때만 더해지는 호출 = (boss:true의 호출) − (boss:false의 호출)
function bossExtra(song, i, t) {
  const a = record(() => AT.playStep(song, i, t, {})), b = record(() => AT.playStep(song, i, t, { boss: true }));
  const left = a.map(c => JSON.stringify(c)), extra = [];
  for (const c of b) { const k = JSON.stringify(c), j = left.indexOf(k); if (j >= 0) left.splice(j, 1); else extra.push(c); }
  if (left.length) throw new Error('보스 상태에서 빠지는 소리가 있다: ' + left.join(' '));
  return extra;
}
const songOf = k => k === 'menu' ? AT.MENU : AT.SONGS[k];

/* 노래: playStep을 i0부터 n스텝 부른다. p64 = 64스텝의 표본 수(128의 배수 → 한 스텝은 정수 표본, 주기는 렌더 단위의 배수).
   스텝 시각 = (M0 + j·p64/64 + 소수)/SR. 소수 = 원본의 박자대로 갔을 때 그 스텝이 표본 사이의 어디에 놓이는가
   (원본은 스텝마다 60/bpm/4초씩 더하므로 표본 경계에서 조금씩 벗어난다 — 잡음 악기의 밝기가 그에 따라 달라진다).
   reseed 스텝마다 난수를 같은 씨앗으로 되돌리고 소수도 처음부터 다시 세어, 잡음까지 정확히 주기적으로 만든다. boss:'only'면 보스 층만. */
B.song = async o => {
  const song = songOf(o.song), dS = 60 / song.bpm / 4 * SR;
  const tOf = j => (M0 + j * o.p64 / 64 + frac(((o.i0 + j) % o.reseed) * dS) + 1e-6) / SR;
  const ch = await render(o.lenSamples, ctx => {
    // 한꺼번에 예약하면 대기 중인 노드 수만 개가 렌더를 몹시 느리게 한다 → 원본처럼 조금씩 앞서 예약한다(1초 단위로 멈췄다가 다음 1초어치)
    let j = 0;
    const upTo = limit => {
      for (; j < o.n && tOf(j) < limit; j++) {
        const i = o.i0 + j, t = tOf(j);
        if (i % o.reseed === 0) __seed(o.seed);
        if (o.boss === 'only') { for (const [k, a] of bossExtra(song, i, t)) AT.I[k](...a); }
        else AT.playStep(song, i, t, o.boss === 'on' ? { boss: true } : {});
      }
    };
    upTo(1.05);
    for (let k = 1; k < o.lenSamples / SR - 0.01; k++) ctx.suspend(k).then(() => { upTo(k + 1.05); ctx.resume(); });
  });
  return { id: keep(ch) };
};

/* 검사용: 스텝마다 어떤 악기를 부르는지(시각은 스텝 기준으로) — 주기가 맞는지 node 쪽에서 견준다 */
B.calls = o => {
  const song = songOf(o.song), out = [];
  for (let j = 0; j < o.n; j++) {
    const i = o.i0 + j;
    const log = o.boss === 'only' ? bossExtra(song, i, 1000) : record(() => AT.playStep(song, i, 1000, o.boss === 'on' ? { boss: true } : {}));
    out.push(log.map(([k, a]) => k + '(' + a.map((v, q) => q === 0 ? 't' : JSON.stringify(v)).join(',') + ')').join(' '));
  }
  return out;
};
B.ready = true;
