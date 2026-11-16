'use strict';
/* 원본 sim.js 를 시나리오대로 돌리고 요약 줄(digest)을 찍는다. luau/driver.luau 와 한 줄씩 짝이 맞는다.
   쓰는 법: node driver.cjs <jobs.json> [--soft]
   --soft: Math.sin/cos/atan2/exp/pow 를 softmath 로 바꿔 끼운다 (Luau 쪽도 같은 함수를 쓰면 비트까지 같아진다). */
const path=require('path'),fs=require('fs');
const {makeRng,hex}=require('./prng.cjs');
const argv=process.argv.slice(2),soft=argv.includes('--soft'),jobFile=argv.find(a=>!a.startsWith('--'));
if(soft){const sm=require('./softmath.cjs');Math.sin=sm.sin;Math.cos=sm.cos;Math.atan2=sm.atan2;Math.exp=sm.exp;Math.pow=sm.pow;}
const SIM=require(path.join(__dirname,'..','..','..','commute-survival','js','sim.js'));
/* sim.js 가 내보내지 않는 상수는 파일에서 직접 읽지 않는다 — 내보낸 것만 견준다 */

const M32=4294967296;
const mix=(h,v)=>(h*31+v)%M32;
const strCache=new Map();
function strHash(s){let h=strCache.get(s);if(h===undefined){const b=Buffer.from(String(s),'utf8');h=7;for(let i=0;i<b.length;i++)h=mix(h,b[i]);h=mix(h,b.length);strCache.set(s,h);}return h;}
const f64=new Float64Array(1),u32=new Uint32Array(f64.buffer);
function numHash(x){if(x!==x)return 29;f64[0]=x;return mix(mix(11,u32[1]),u32[0]);}
function valHash(v){
  const t=typeof v;
  if(t==='number')return numHash(v);
  if(t==='string')return mix(13,strHash(v));
  if(t==='boolean')return v?17:19;
  if(Array.isArray(v)){let h=23;for(const x of v)h=mix(h,valHash(x));return mix(h,v.length);}
  throw new Error('해시할 수 없는 값: '+t);
}
/* 이벤트 하나: 칸의 순서와 무관하게 (열쇠, 값) 해시의 합 */
function evHash(e){let s=0;for(const k in e){const v=e[k];if(v===undefined||v===null)continue;s=(s+mix(strHash(k),valHash(v)))%M32;}return s;}
const out=[];
const emit=s=>{out.push(s);if(out.length>=2000)flush();};
const flush=()=>{if(out.length){fs.writeSync(1,out.join('\n')+'\n');out.length=0;}};

function runJob(spec){
  const rng=makeRng(spec.seed>>>0);
  let HA=0,HD=0,evCount=0,hostCount=0,tick=0,ended=null;
  const choicesHash=(ch,mode)=>{HD=mix(HD,strHash(mode));for(const c of ch){for(const f of ['kind','key','name','desc','tag','hint'])HD=mix(HD,strHash(c[f]));HD=mix(HD,valHash(c.to));if(c.wt!==undefined)HA=mix(HA,numHash(c.wt));}};
  const host={
    sfx(name,x,arg){hostCount++;const n=strHash(name);HA=mix(HA,n);HD=mix(HD,n);HA=mix(HA,x===undefined?3:numHash(x));
      if(arg===undefined)HA=mix(HA,5);else{HA=mix(HA,valHash(arg));if(typeof arg!=='number')HD=mix(HD,valHash(arg));}},
    banner(a,b,kind){hostCount++;for(const s of [a,b,kind]){const v=s===undefined?3:strHash(s);HA=mix(HA,v);HD=mix(HD,v);}},
    shake(a){hostCount++;HA=mix(HA,numHash(a));HD=mix(HD,37);},
    levelUp(ch,mode){hostCount++;HD=mix(HD,47);choicesHash(ch,mode);},
    end(won){hostCount++;HD=mix(HD,won?41:43);ended=won;}
  };
  const mkOpts=(extra)=>{
    const o=Object.assign({},spec.opts||{},extra||{});
    if(spec.pick==='auto')o.autoPick=(ch,S)=>{HD=mix(HD,53);choicesHash(ch,S.pickMode);return ch[Math.floor(rng()*ch.length)];};
    return o;
  };
  const view=spec.view||{w:1280,h:720},dt=1/(spec.dtDiv||60),every=spec.digestEvery||60,dense=spec.denseUntil||0;
  /* Math.random 을 씨앗 난수로 바꾼 뒤 만든다 (sim 은 만들 때 Math.random 을 붙잡는다) */
  Math.random=rng;
  let sim=SIM.createSim(host,mkOpts());
  const buildStr=()=>{const S=sim.S;const kv=o=>Object.keys(o).map(k=>k+':'+o[k]).join(',');
    return 'w='+kv(S.weapons)+';p='+kv(S.passives)+';f='+kv(S.fus)+';fs='+Object.keys(S.fsrc).sort().join(',');};
  const LISTS=['beans','bullets','shots','items','zones','waves','puddles','mines','riders','rangs','slicks'];
  function digest(tag){
    const S=sim.S,p=S.p;let sx=0,sy=0,sh=0,eh=0,oh=0;
    for(const e of S.enemies){sx+=e.x;sy+=e.y;sh+=e.hp;eh=mix(mix(mix(mix(mix(eh,e.id),strHash(e.type)),numHash(e.x)),numHash(e.y)),numHash(e.hp));}
    for(const L of LISTS)for(const o of S[L])oh=mix(mix(oh,numHash(o.x)),numHash(o.y));
    for(const o of S.lobs)oh=mix(mix(mix(oh,numHash(o.x1)),numHash(o.y1)),numHash(o.t));
    for(const o of S.beams)oh=mix(mix(oh,numHash(o.a)),numHash(o.life));
    const ints=[tick,S.state,S.zone,S.phase,S.rage,p.level,S.kills,S.pending,S.pickMode,S.enemies.length,S.beans.length,S.bullets.length,S.shots.length,S.items.length,S.zones.length,S.waves.length,S.puddles.length,S.mines.length,S.bosses.length,rng.calls,evCount,hostCount];
    const fl=[S.t,p.x,p.y,p.hp,p.maxhp,p.xp,p.inv,sx,sy,sh,S.zt,S.spawnAcc];
    const hs=[HA,HD,eh,oh,strHash(buildStr())];
    emit(tag+' '+ints.join(' ')+' | '+fl.map(hex).join(' ')+' | '+hs.join(' '));
  }
  function drain(){const S=sim.S;for(const e of S.ev){HA=mix(HA,evHash(e));HD=mix(HD,strHash(e.k));evCount++;}S.ev.length=0;}
  function manualPick(){
    const S=sim.S;let guard=0;
    while(S.state==='levelup'&&guard++<50){
      const pol=spec.manual||'first';
      if(pol==='reroll'){let g=0;while(sim.reroll()&&g++<20){}}
      const n=S.choices.length;
      sim.choose(pol==='rng'?Math.floor(rng()*n):pol==='last'?n-1:0);
    }
  }
  const obj=name=>{const S=sim.S;return name==='S'?S:name==='p'?S.p:name==='boss'?S.boss:name==='gate'?S.gate:name==='M'?S.M:name==='train'?S.train:name==='input'?S.input:null;};
  emit('# '+spec.name);
  for(const st of spec.steps){
    const S=sim.S,p=S.p;
    switch(st.op){
      case 'run':{
        for(let i=0;i<st.ticks;i++){
          if(S.state==='over'||S.state==='won')break;
          if(S.state==='levelup')manualPick();
          if(st.input==='bot'){const b=sim.bot();S.input=b;if(b.dash)sim.dash();}
          else if(st.input&&typeof st.input==='object')S.input={x:st.input.x,y:st.input.y};
          else S.input={x:0,y:0};
          if(st.dashEvery&&tick%st.dashEvery===0)sim.dash();
          if(st.hold!==undefined&&(S.phase==='crowd'||S.phase==='ride')&&S.zt>st.hold)S.zt=st.hold;
          if(st.keepHp)p.hp=p.maxhp;
          sim.update(dt,view);
          drain();
          tick++;
          if(tick%every===0||tick<dense)digest('D');
        }
        break;}
      case 'enterZone':S.zone=st.i;sim.dbg.enterZone(st.i);break;
      case 'boss':sim.dbg.boss(st.type);break;
      case 'spawn':{for(let i=0;i<st.n;i++){const x=p.x+(rng()*2-1)*st.r,y=p.y+(rng()*2-1)*(st.ry===undefined?st.r:st.ry);const e=sim.dbg.spawn(st.type,x,y);
          if(st.hp!==undefined)e.hp=e.maxhp=st.hp;if(st.spd!==undefined)e.spd=st.spd;if(st.dmg!==undefined)e.dmg=st.dmg;if(st.elite)e.elite=true;}break;}
      case 'killAll':for(const e of S.enemies.slice())if(!e.dead){sim.dbg.kill(e,st.src===null?undefined:st.src);if(st.twice)sim.dbg.kill(e,st.src===null?undefined:st.src);}break;
      case 'set':{const o=obj(st.obj);if(o)o[st.key]=st.value===null?undefined:st.value;break;}
      case 'setAll':for(const e of S.enemies)e[st.key]=st.value;break;
      case 'bossHp':for(const e of S.bosses)e.hp=e.maxhp*st.frac;break;
      case 'dash':HD=mix(HD,sim.dash()?59:61);break;
      case 'reroll':HD=mix(HD,sim.reroll()?67:71);break;
      case 'choose':sim.choose(st.i-1);break;
      case 'pending':S.pending+=st.n;S.pickMode=st.mode;break;
      case 'item':S.items.push({kind:st.kind,x:p.x+st.dx,y:p.y+st.dy,t:0});break;
      case 'xp':p.xp+=st.v;break;
      case 'setDiff':sim.dbg.setDiff(st.i);break;
      case 'build':{const fsrc={},fus={};for(const k in st.fus||{}){fus[k]=1;fsrc[SIM.FUSIONS[k].a]=1;fsrc[SIM.FUSIONS[k].b]=1;}
        S.weapons=Object.assign({},st.weapons);S.passives=Object.assign({},st.passives||{});S.fus=fus;S.fsrc=fsrc;S.beams.length=0;S.umbQ=null;sim.dbg.recalc();break;}
      case 'roundtrip':{
        const ser=JSON.parse(JSON.stringify(sim.serialize()));
        let h=0;for(const k of ['diff','zone','t','hp','level','xp','kills','rerolls','x','y'])h=mix(h,numHash(ser[k]));
        for(const m of ['weapons','passives','dmg','fus','fsrc']){const ks=Object.keys(ser[m]);if(m==='fsrc')ks.sort();for(const k of ks)h=mix(mix(h,strHash(k)),numHash(ser[m][k]));h=mix(h,73);}
        emit('R '+h);
        sim=SIM.createSim(host,mkOpts({restore:ser,build:undefined}));
        break;}
      case 'digest':digest('D');break;
      case 'update':sim.update(dt,view);drain();break;
      case 'fus':{const F=SIM.FUSIONS[st.key];if(st.on){S.fus[st.key]=1;S.fsrc[F.a]=1;S.fsrc[F.b]=1;}else{delete S.fus[st.key];delete S.fsrc[F.a];delete S.fsrc[F.b];}sim.dbg.recalc();break;}
      case 'consts':constsDump();break;
      default:throw new Error('모르는 op: '+st.op);
    }
  }
  drain();
  digest('E');
  {const S=sim.S,p=S.p;
    const dm=Object.keys(S.dmg).map(k=>k+':'+hex(S.dmg[k])).join(',');
    const tb=Object.keys(S.takenBy).sort().map(k=>k+':'+hex(S.takenBy[k])).join(',');
    emit(['F',spec.name,S.state,S.zone,tick,hex(S.t),p.level,S.kills,S.late?1:0,S.rerolls,S.dashes,hex(p.hp),hex(S.taken),ended===null?'-':ended?'won':'lost',buildStr(),'dmg='+dm,'by='+tb].join('|'));}
}
/* 바뀌지 않는 자료: 표 · 수치 · 글을 한 줄씩 찍는다 (sim.js 가 내보내는 것만) */
function constsDump(){
  const W=SIM.WEAPONS,P=SIM.PASSIVES,F=SIM.FUSIONS,E=SIM.ENEMIES;
  emit('C xp '+Array.from({length:150},(_,i)=>SIM.xpNeed(i+1)).join(','));
  emit('C clock '+[0,1,8.9,9,59.9,60,269.5,539.99,540,541,600,1079,5400].map(t=>SIM.clockText(t)).join(','));
  emit('C nums '+[SIM.EVO,SIM.GAME_LEN].join(','));
  emit('C worder '+Object.keys(W).join(','));
  for(const k in W){const w=W[k];emit('C w '+k+' '+strHash([w.name,w.evoName,w.pair,w.evoDesc].join('|'))+' '+w.lv.length+' '+strHash(w.lv.join('|')));
    for(let l=1;l<=8;l++){const s=w.stat(l);emit('C stat '+k+' '+l+' '+Object.keys(s).sort().map(f=>f+'='+(typeof s[f]==='number'?hex(s[f]):String(s[f]))).join(','));}}
  emit('C porder '+Object.keys(P).join(','));for(const k in P)emit('C p '+k+' '+strHash(P[k].name+'|'+P[k].desc));
  emit('C forder '+Object.keys(F).join(','));for(const k in F)emit('C f '+k+' '+F[k].a+' '+F[k].b+' '+strHash(F[k].name+'|'+F[k].desc));
  emit('C eorder '+Object.keys(E).join(','));for(const k in E){const d=E[k];emit('C e '+k+' '+Object.keys(d).sort().map(f=>f+'='+(typeof d[f]==='number'?hex(d[f]):typeof d[f]==='string'?strHash(d[f]):String(d[f]))).join(','));}
  SIM.DIFFS.forEach((d,i)=>emit('C diff '+i+' '+Object.keys(d).sort().map(f=>f+'='+(typeof d[f]==='number'?hex(d[f]):strHash(d[f]))).join(',')));
  SIM.ZONES.forEach((z,i)=>emit('C zone '+i+' '+Object.keys(z).sort().map(f=>f+'='+(typeof z[f]==='number'?hex(z[f]):Array.isArray(z[f])?z[f].join('/'):strHash(z[f]))).join(',')));
  for(const k of Object.keys(SIM.GATE).sort()){const g=SIM.GATE[k];emit('C gate '+k+' '+Object.keys(g).sort().map(f=>f+'='+g[f]).join(','));}
}
const jobs=JSON.parse(fs.readFileSync(jobFile,'utf8'));
for(const spec of jobs){
  try{runJob(spec);}catch(e){emit('X '+spec.name+' '+String(e&&e.stack||e).replace(/\s+/g,' '));}
}
flush();
