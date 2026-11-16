'use strict';
/* 원본 sim.js 의 update 한 번에 걸리는 시간 (luau/perf.luau 와 같은 상황). 견줄 값으로만 쓴다. */
const path=require('path');
const {makeRng}=require('./prng.cjs');
const SIM=require(path.join(__dirname,'..','..','..','commute-survival','js','sim.js'));
const rng=makeRng(4242);Math.random=rng;
const nop=()=>{};
const sim=SIM.createSim({sfx:nop,banner:nop,shake:nop,levelUp:nop,end:nop},{diff:3,demo:true,build:{weapons:{card:5,backpack:4,anc:4,coffee:3,selfie:3},passives:{shoes:2,will:2,pods:2,tumbler:2,badge:2}}});
const S=sim.S;S.admNoPick=true;S.t=400;
const view={w:1280,h:720},dt=1/60;
function step(){const b=sim.bot();S.input=b;if(b.dash)sim.dash();if((S.phase==='crowd'||S.phase==='ride')&&S.zt>6)S.zt=6;sim.update(dt,view);S.ev.length=0;}
step();S.zone=2;sim.dbg.enterZone(2);S.admRate=8;
let warm=0;while(S.enemies.length<380&&warm<6000){step();warm++;}
const N=1500;let tUpd=0,tBot=0,tMax=0,eSum=0,eMin=1e9,eMax=0;
for(let i=0;i<N;i++){
  const c0=performance.now();const b=sim.bot();const c1=performance.now();
  S.input=b;if(b.dash)sim.dash();if((S.phase==='crowd'||S.phase==='ride')&&S.zt>6)S.zt=6;
  const c2=performance.now();sim.update(dt,view);const c3=performance.now();S.ev.length=0;
  tBot+=c1-c0;tUpd+=c3-c2;if(c3-c2>tMax)tMax=c3-c2;const n=S.enemies.length;eSum+=n;eMin=Math.min(eMin,n);eMax=Math.max(eMax,n);
}
console.log('PERF update 평균 '+(tUpd/N).toFixed(3)+' ms (최대 '+tMax.toFixed(3)+' ms) · bot '+(tBot/N).toFixed(3)+' ms · 적 평균 '+(eSum/N).toFixed(0)+'명 (최소 '+eMin+', 최대 '+eMax+') · '+N+'번 · 준비 '+warm+' tick');
