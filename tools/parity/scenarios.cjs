'use strict';
/* 견줌 시나리오 모음. 시나리오 하나 = { name, seed, opts, pick, manual, digestEvery, denseUntil, steps:[...] }
   두 driver(js/driver.cjs · luau/driver.luau)가 같은 뜻으로 읽는다.
   op: run{ticks,input:'bot'|'none'|{x,y},dashEvery,hold,keepHp} · enterZone{i} · boss{type} · spawn{type,n,r,ry,hp,spd,dmg,elite}
       killAll{src,twice} · set{obj,key,value} · setAll{key,value} · bossHp{frac} · dash · reroll · choose{i(1부터)} · pending{n,mode}
       item{kind,dx,dy} · xp{v} · setDiff{i} · build{weapons,passives,fus} · fus{key,on} · roundtrip · update · digest · consts
     (hold: 인파/탑승 단계의 zt 를 그 값에 묶어 보스가 저절로 나오지 않게 한다 · keepHp: 매 tick 멘탈을 가득 채운다)
   그 밖: seed · dtDiv(dt = 1/dtDiv, 기본 60) · view{w,h}(기본 1280×720) · digestEvery · denseUntil · manual('first'|'last'|'rng'|'reroll')
   pick: 'auto'(opts.autoPick 이 씨앗 난수로 고름) · 'demo'(opts.demo 의 자체 무작위) · 'manual'(host.levelUp 뒤 driver 가 choose) */
const path=require('path');
const SIM=require(path.join(__dirname,'..','..','commute-survival','js','sim.js'));
const W=Object.keys(SIM.WEAPONS),PA=Object.keys(SIM.PASSIVES),FU=Object.keys(SIM.FUSIONS);
const BOSS_ZONE={flyboss:0,bagman:1,doorman:2,speaker:3,crowd:4,carrierboss:5,lead:6};
const CAP=60*900; /* 한 판의 한도: 게임 시간 15분 */
let seedN=1000;
const nextSeed=()=>++seedN;
const run=(ticks,input,extra)=>Object.assign({op:'run',ticks,input:input===undefined?'bot':input},extra||{});
const set=(obj,key,value)=>({op:'set',obj,key,value});

/* A · C: 처음부터 끝까지 봇이 하는 판 */
function fullGame(seed,diff,extra){
  return Object.assign({name:'game.d'+diff+'.s'+seed,seed,opts:{diff},pick:'auto',digestEvery:60,steps:[run(CAP)]},extra||{});
}

/* B: 모든 갈래를 밟는 시나리오 */
function coverage(){
  seedN=1000; /* 몇 번을 불러도 같은 씨앗이 나오게 */
  const L=[];
  const crowd=[{op:'spawn',type:'pass',n:36,r:240},{op:'spawn',type:'stud',n:8,r:200},{op:'spawn',type:'intern',n:8,r:220},{op:'spawn',type:'uncle',n:3,r:160,hp:6000},{op:'spawn',type:'flyer',n:6,r:300}];
  /* 플레이어와 정확히 같은 자리에 선 허수아비(boss() 를 거치지 않은 보스: 밀리지도 움직이지도 않는다) — 거리 0 일 때의 갈래를 밟는다 */
  const DUMMY={op:'spawn',type:'crowd',n:1,r:0,hp:1e9};
  /* 무기마다 1~7레벨 (거리). 레벨업 창은 꺼 둔다(admNoPick). 처음에는 가만히 서 있고, 그 뒤 봇이 움직인다 */
  for(const w of W)for(let l=1;l<=7;l++){
    L.push({name:'w.'+w+'.'+l,seed:nextSeed(),opts:{diff:1,demo:true,build:{weapons:{[w]:l},passives:{[SIM.WEAPONS[w].pair]:1,tumbler:2}}},pick:'demo',digestEvery:20,
      steps:[set('S','admNoPick',true),run(2,'none'),DUMMY,...crowd,run(150,'none',{hold:6}),run(300,'bot',{dashEvery:70,hold:6})]});
  }
  /* 무기마다 3 · 7레벨을 열차 안 · 개찰구 · 에스컬레이터에서 */
  for(const w of W)for(const l of [3,7])for(const z of [1,3,5]){
    L.push({name:'wz.'+w+'.'+l+'.z'+z,seed:nextSeed(),opts:{diff:2,demo:true,build:{weapons:{[w]:l},passives:{[SIM.WEAPONS[w].pair]:2}}},pick:'demo',digestEvery:20,
      steps:[set('S','admNoPick',true),run(2,'none'),{op:'enterZone',i:z},...crowd.map(c=>Object.assign({},c,{ry:z===3?60:c.r})),run(300,'bot',{dashEvery:55,hold:6})]});
  }
  /* 히든 조합: 재료 둘을 진화시켜 두고 레벨업 → 맨 앞 선택지(조합)를 고른다. 죽지 않게 체력을 채운다 */
  for(const f of FU){const F=SIM.FUSIONS[f];
    L.push({name:'fuse.'+f,seed:nextSeed(),opts:{diff:1,build:{weapons:{[F.a]:7,[F.b]:7,gum:2},passives:{tumbler:1,pods:1}}},pick:'manual',manual:'first',digestEvery:20,
      steps:[run(2,'none'),{op:'xp',v:30},run(3,'none'),DUMMY,...crowd,run(200,'none',{hold:6,keepHp:true}),run(40,{x:1,y:0},{hold:6,keepHp:true,dashEvery:13}),{op:'boss',type:'bagman'},run(900,'bot',{dashEvery:50,hold:6,keepHp:true}),{op:'roundtrip'},...crowd,run(300,'bot',{dashEvery:50,hold:6,keepHp:true})]});
    for(const z of [3,5])L.push({name:'fusez.'+f+'.z'+z,seed:nextSeed(),opts:{diff:2,demo:true,restore:{diff:2,zone:z,t:200,hp:80,level:20,xp:3,kills:500,weapons:{gum:3},passives:{tumbler:2},dmg:{card:10,gum:20},rerolls:2,fus:{[f]:1},fsrc:{[F.a]:1,[F.b]:1}}},pick:'demo',digestEvery:20,
      steps:[set('S','admNoPick',true),run(2,'none'),...crowd.map(c=>Object.assign({},c,{ry:z===3?60:c.r})),run(500,'bot',{dashEvery:45,hold:6})]});
  }
  /* 조합 다섯 가지 + 남은 무기 전부 진화 (실험실 방식으로 갈아 끼움) */
  {const fus={};for(const f of FU)fus[f]=1;const src={};for(const f of FU){src[SIM.FUSIONS[f].a]=1;src[SIM.FUSIONS[f].b]=1;}
    const ws={};for(const w of W)if(!src[w])ws[w]=7;const ps={};for(const k of PA)ps[k]=5;
    for(const z of [0,1,3,5,6])L.push({name:'all.z'+z,seed:nextSeed(),opts:{diff:3},pick:'manual',manual:'rng',digestEvery:20,
      steps:[run(2,'none'),{op:'enterZone',i:z},{op:'build',weapons:ws,passives:ps,fus},...crowd,{op:'boss',type:'doorman'},run(700,'bot',{dashEvery:40,hold:6,keepHp:true}),{op:'build',weapons:{card:7,handle:7,umbrella:7,tie:7,laptop:7},passives:{},fus:{}},run(200,'bot',{hold:6,keepHp:true})]});
  }
  /* 보스마다: 제 장소에서 불러내 폭주 0~4단계를 차례로. 맞기는 하지만 죽지는 않게 */
  for(const b in BOSS_ZONE){const z=BOSS_ZONE[b];const st=[run(2,'none'),{op:'enterZone',i:z},run(20),{op:'boss',type:b},run(140)];
    for(let rg=0;rg<=4;rg++){st.push(set('S','rage',rg));if(b==='lead')st.push({op:'bossHp',frac:[.95,.75,.55,.35,.15][rg]});else st.push({op:'bossHp',frac:rg===3?.4:1});st.push(run(b==='lead'?900:700,'bot',{hold:6,keepHp:true}));}
    st.push({op:'bossHp',frac:.0001},run(240,'bot',{keepHp:true}),run(200,'bot',{keepHp:true}));
    L.push({name:'boss.'+b,seed:nextSeed(),opts:{diff:2,build:{weapons:{card:2,hotpack:1},passives:{shoes:2}}},pick:'manual',manual:'rng',digestEvery:20,steps:st});
    /* 가만히 서서 맞는 판(난이도 지옥철): 탄 · 음파 · 장판 · 몸통에 맞는 갈래 */
    L.push({name:'bossstand.'+b,seed:nextSeed(),opts:{diff:3,build:{weapons:{gum:1},passives:{}}},pick:'manual',manual:'first',digestEvery:20,
      steps:[run(2,'none'),{op:'enterZone',i:z},{op:'boss',type:b},set('S','rage',2),run(900,'none',{hold:6,keepHp:true}),set('S','rage',4),run(900,{x:.6,y:.2},{hold:6,keepHp:true})]});
    /* 제 장소가 아닌 곳에서 잡으면 상자를 떨어뜨린다 → 상자를 주워 'chest' 선택 */
    L.push({name:'bosschest.'+b,seed:nextSeed(),opts:{diff:0,build:{weapons:{anc:7,hotpack:7},passives:{will:5}}},pick:'manual',manual:'reroll',digestEvery:20,
      steps:[run(2,'none'),{op:'enterZone',i:(z+2)%7===3?1:(z+2)%7},{op:'boss',type:b},run(100,'none',{hold:6,keepHp:true}),{op:'bossHp',frac:.001},run(600,'bot',{hold:6,keepHp:true})]});
  }
  /* boss() 를 거치지 않고 만든 보스 (JS 에서는 타이머가 NaN 이 된다) */
  for(const b in BOSS_ZONE)L.push({name:'rawboss.'+b,seed:nextSeed(),opts:{diff:1,demo:true,build:{weapons:{card:1},passives:{}}},pick:'demo',digestEvery:20,
    steps:[set('S','admNoPick',true),run(2,'none'),{op:'enterZone',i:BOSS_ZONE[b]},{op:'spawn',type:b,n:1,r:200,ry:40},set('S','rage',3),run(600,'bot',{hold:6})]});
  /* 장소마다 자연스럽게 흘러가는 판: 무적(demo)으로 끝까지 → 승리 */
  for(const d of [0,2])L.push({name:'demo.full.d'+d,seed:nextSeed(),opts:{diff:d,demo:true},pick:'demo',digestEvery:60,steps:[run(CAP)]});
  L.push({name:'demo.menu',seed:nextSeed(),opts:{demo:true,diff:1,build:{weapons:{card:3,backpack:2,battery:2,coffee:1},passives:{}}},pick:'demo',digestEvery:60,steps:[set('S','t',18),set('S','nextRow',24),run(60*80)]});
  /* 죽는 판 · 이기는 판 (무적 아님) */
  L.push({name:'die.hell',seed:nextSeed(),opts:{diff:3},pick:'auto',digestEvery:60,steps:[run(CAP,'none')]});
  L.push({name:'win.easy.xp',seed:nextSeed(),opts:{diff:0,xpMul:4,botRange:1.3},pick:'auto',digestEvery:60,steps:[run(CAP)]});
  L.push({name:'win.late',seed:nextSeed(),opts:{diff:0,xpMul:5,restore:{diff:0,zone:6,t:520,hp:170,level:40,xp:0,kills:900,weapons:{anc:7,hotpack:7,shout:7,battery:7,scooter:7},passives:{will:5,tumbler:5,pods:5,gym:5,armor:5},dmg:{},rerolls:1,fus:{},fsrc:{}}},pick:'manual',manual:'last',digestEvery:60,steps:[run(CAP)]});
  /* 차선: 버스 · 열차에 치이는 플레이어 · 진상 승객 · 보스 */
  for(const z of [0,2,4])L.push({name:'hazard.z'+z,seed:nextSeed(),opts:{diff:1,build:{weapons:{gum:1},passives:{}}},pick:'manual',manual:'first',digestEvery:10,
    steps:[run(2,'none'),{op:'enterZone',i:z},set('p','y',10),set('S','trainT',.3),{op:'spawn',type:'pass',n:30,r:400,ry:40},{op:'spawn',type:'carrier',n:4,r:300,ry:30,elite:true},{op:'spawn',type:'bagman',n:1,r:200,ry:20},
      run(240,'none',{hold:6,keepHp:true}),set('S','admRate',0),set('S','nextRow',1e9),set('S','nextElite',1e9),{op:'killAll'},set('p','y',10),set('S','trainT',.2),set('p','maxhp',5),set('p','hp',5),run(300,'none',{hold:6}),set('p','y',700),set('S','trainT',.2),run(300,'bot',{hold:6,keepHp:true})]});
  /* 아이템 · 상자 · 선택 방식 */
  for(const pol of ['first','last','rng','reroll'])L.push({name:'items.'+pol,seed:nextSeed(),opts:{diff:1},pick:'manual',manual:pol,digestEvery:10,
    steps:[run(2,'none'),set('p','hp',40),{op:'item',kind:'kimbap',dx:5,dy:5},run(5,'none'),{op:'spawn',type:'pass',n:30,r:300},run(200,'bot',{hold:6,keepHp:true}),{op:'item',kind:'pass',dx:8,dy:-4},run(60,'none',{hold:6,keepHp:true}),
      {op:'item',kind:'chest',dx:3,dy:3},run(30,'none',{hold:6,keepHp:true}),{op:'item',kind:'kimbap',dx:900,dy:0},{op:'item',kind:'chest',dx:1200,dy:0},run(60*47,'none',{hold:6,keepHp:true}),
      {op:'pending',n:1,mode:'start'},run(3,'none',{hold:6}),{op:'reroll'},{op:'dash'},{op:'choose',i:9},{op:'xp',v:400},run(30,'bot',{hold:6,keepHp:true}),{op:'dash'},{op:'dash'},run(40,{x:0,y:0},{hold:6,keepHp:true})]});
  /* 시작 무기 고르기를 손으로 (levelUp 창에서 reroll 은 거절된다) */
  L.push({name:'start.manual',seed:nextSeed(),opts:{diff:2,build:{weapons:{},passives:{}}},pick:'manual',manual:'reroll',digestEvery:10,steps:[{op:'pending',n:1,mode:'start'},run(300,'bot')]});
  L.push({name:'start.step',seed:nextSeed(),opts:{diff:2,build:{weapons:{},passives:{}}},pick:'manual',manual:'first',digestEvery:10,steps:[{op:'pending',n:2,mode:'start'},{op:'run',ticks:1,input:'none'},{op:'update'},{op:'reroll'},{op:'choose',i:2},{op:'reroll'},{op:'choose',i:3},{op:'choose',i:1},run(200,'bot')]});
  /* 더 올릴 것이 없을 때의 간식 선택지 · 진화 선택지 */
  {const ws={card:7,anc:7,shout:7,gum:7,hotpack:7},ps={shoes:5,payday:5,tumbler:5,lotto:5,vitamin:5};
    L.push({name:'heals',seed:nextSeed(),opts:{diff:1,build:{weapons:ws,passives:ps}},pick:'manual',manual:'last',digestEvery:10,steps:[run(2,'none'),set('p','hp',20),{op:'xp',v:2000},run(40,'bot',{hold:6}),{op:'roundtrip'},{op:'xp',v:900},run(60,'bot',{hold:6})]});
    L.push({name:'evo',seed:nextSeed(),opts:{diff:1,build:{weapons:{card:6,anc:6,shout:6,gum:5,hotpack:6},passives:{shoes:1,payday:1,tumbler:1,lotto:4,vitamin:1}}},pick:'manual',manual:'first',digestEvery:10,steps:[run(2,'none'),{op:'xp',v:3000},run(120,'bot',{hold:6,keepHp:true})]});
    L.push({name:'gym',seed:nextSeed(),opts:{diff:1,xpMul:6,build:{weapons:{shoulder:5},passives:{gym:1,snack:2,overtime:3,report:2,mask:2,}}},pick:'manual',manual:'rng',digestEvery:10,steps:[run(2,'none'),...crowd,set('p','hp',30),run(1500,'bot',{hold:6})]});
  }
  /* 원두가 380개를 넘을 때 · 탄이 260개를 넘을 때 · 한 프레임 이벤트가 400개를 넘을 때 */
  L.push({name:'cap.beans',seed:nextSeed(),opts:{diff:0,build:{weapons:{shout:7,anc:7},passives:{will:5,tumbler:5}}},pick:'manual',manual:'first',digestEvery:10,
    steps:[run(2,'none'),{op:'spawn',type:'pass',n:450,r:560},run(500,'none',{hold:6,keepHp:true}),{op:'spawn',type:'zomb',n:300,r:500},run(400,'none',{hold:6,keepHp:true}),run(400,'bot',{hold:6,keepHp:true})]});
  L.push({name:'cap.bullets',seed:nextSeed(),opts:{diff:3,build:{weapons:{gum:1},passives:{}}},pick:'manual',manual:'first',digestEvery:10,
    steps:[run(2,'none'),{op:'spawn',type:'flyer',n:420,r:380,hp:1e6},run(500,'bot',{hold:6,keepHp:true})]});
  /* 난이도 바꾸기 · 적 생성 배율 · 0레벨 항목 · src 없는 kill */
  L.push({name:'misc.diff',seed:nextSeed(),opts:{diff:9,build:{weapons:{card:0,umbrella:2,tie:3},passives:{armor:0,report:1}}},pick:'manual',manual:'rng',digestEvery:10,
    steps:[run(60),{op:'setDiff',i:0},run(60),set('p','hp',5),{op:'enterZone',i:1},run(30),{op:'setDiff',i:3.7},set('S','admRate',3),run(200),{op:'killAll',twice:true},run(5),set('S','admRate',0),run(120),{op:'killAll',src:'train'},set('S','admRate',null),{op:'setDiff',i:-2},run(300),{op:'roundtrip'},run(300)]});
  L.push({name:'misc.restore.early',seed:nextSeed(),opts:{restore:{diff:1,zone:2,t:95,hp:500,level:9,xp:4,kills:140,weapons:{backpack:4,coffee:3,selfie:2},passives:{snack:2,pods:1},dmg:{backpack:900,coffee:400.5},rerolls:3,fus:{},fsrc:{}}},pick:'auto',digestEvery:30,steps:[run(60*120),{op:'roundtrip'},run(60*60)]});
  /* 열차 안을 무적 아님으로: 문 앞에서 떠밀림 · 스피커 빌런 */
  L.push({name:'train.ride',seed:nextSeed(),opts:{diff:1,build:{weapons:{anc:5,card:5,hotpack:4},passives:{will:3,gym:3}}},pick:'auto',digestEvery:30,
    steps:[run(2,'none'),{op:'enterZone',i:3},run(60*20),set('p','y',70),run(60*30,{x:0,y:1},{keepHp:true}),run(60*45,'bot',{keepHp:true}),run(60*20,'bot',{keepHp:true})]});
  /* 개찰구 · 에스컬레이터를 손 입력으로 */
  L.push({name:'gates.walk',seed:nextSeed(),opts:{diff:2,build:{weapons:{selfie:4,scooter:4,handle:3},passives:{energy:3,badge:2}}},pick:'auto',digestEvery:30,
    steps:[run(2,'none'),{op:'enterZone',i:1},{op:'spawn',type:'runner',n:12,r:500},run(400,{x:.3,y:1},{keepHp:true,dashEvery:90}),run(400,{x:-1,y:-.2},{keepHp:true}),run(600,{x:.2,y:-1},{keepHp:true,dashEvery:120}),{op:'enterZone',i:5},run(500,{x:1,y:.1},{keepHp:true}),run(500,{x:-1,y:0},{keepHp:true,dashEvery:60}),run(2400,'bot',{keepHp:true})]});
  /* ---- 그 밖의 갈래 ---- */
  /* 열차 안에서의 포위(ring): 원래는 열차에 '보스 단계'가 없어 일어나지 않는다. 상태를 손으로 바꿔 밟는다 */
  L.push({name:'ring.train',seed:nextSeed(),opts:{diff:2,demo:true},pick:'demo',digestEvery:10,steps:[run(2,'none'),{op:'enterZone',i:3},set('S','phase','boss'),set('S','rageT',.05),run(90),set('S','t',300),set('S','rageT',.05),run(60),set('S','t',450),set('S','rageT',.05),run(120)]});
  /* 스피커 빌런을 열차 밖에서 */
  {const st=[run(2,'none'),{op:'boss',type:'speaker'},run(140)];for(let rg=0;rg<=4;rg++){st.push(set('S','rage',rg),{op:'bossHp',frac:rg>=3?.3:1},run(800,'bot',{hold:6,keepHp:true}));}
    L.push({name:'boss.speaker.out',seed:nextSeed(),opts:{diff:2,build:{weapons:{card:2},passives:{shoes:2}}},pick:'manual',manual:'rng',digestEvery:20,steps:st});
    L.push({name:'bossstand.speaker.out',seed:nextSeed(),opts:{diff:3,build:{weapons:{gum:1},passives:{}}},pick:'manual',manual:'first',digestEvery:20,steps:[run(2,'none'),{op:'enterZone',i:6},{op:'boss',type:'speaker'},run(1500,'none',{hold:6,keepHp:true}),set('S','rage',3),run(1500,{x:-.5,y:.5},{hold:6,keepHp:true})]});}
  /* 조합을 켰다 껐다: 커피가 날아가는 중 · 알람이 울리기 전에 '커피 시한폭탄'이 켜지는 경우, 광선이 떠 있을 때 '재택근무'가 꺼지는 경우 */
  {const st=[set('S','admNoPick',true),run(2,'none'),...crowd];for(let i=0;i<36;i++){st.push({op:'fus',key:'routine',on:true},{op:'fus',key:'remote',on:i%3===0},run(7+i%5,'bot',{hold:6}),{op:'fus',key:'routine',on:false},{op:'fus',key:'remote',on:false},run(9+i%7,'bot',{hold:6}));if(i%9===4)st.push(...crowd);}
    L.push({name:'fus.toggle',seed:nextSeed(),opts:{diff:1,demo:true,build:{weapons:{coffee:7,alarm:7,laptop:7,battery:7},passives:{pods:5,tumbler:3}}},pick:'demo',digestEvery:5,steps:st});}
  /* 아주 큰 dt (2초): 대기 시간이 한 번에 여러 번 지나는 경우 */
  L.push({name:'bigdt',seed:nextSeed(),dtDiv:.5,opts:{diff:1,demo:true,build:{weapons:{card:7,gum:7,coffee:7,alarm:7,umbrella:5,tie:7,anc:7,shout:7},passives:{pods:5}}},pick:'demo',digestEvery:1,steps:[set('S','admNoPick',true),run(40,'bot',{hold:6})]});
  /* 보스 셋을 한꺼번에: 하나가 죽어도 나머지가 남는다 */
  L.push({name:'boss.three',seed:nextSeed(),opts:{diff:1,build:{weapons:{anc:7,hotpack:7,card:7},passives:{will:5}}},pick:'manual',manual:'rng',digestEvery:10,steps:[run(2,'none'),{op:'boss',type:'flyboss'},{op:'boss',type:'bagman'},{op:'boss',type:'doorman'},run(100,'none',{hold:6,keepHp:true}),{op:'bossHp',frac:.002},run(900,'bot',{hold:6,keepHp:true})]});
  /* 거리 0: 플레이어와 정확히 같은 자리의 적 · 원두 · 미끄러운 바닥 · 상자 */
  L.push({name:'zero',seed:nextSeed(),opts:{diff:1,demo:true,build:{weapons:{anc:3,shout:2,alarm:3,handle:2,hotpack:2},passives:{}}},pick:'demo',digestEvery:1,
    steps:[set('S','admNoPick',true),set('S','admRate',0),set('S','nextRow',1e9),set('S','nextElite',1e9),run(2,'none'),{op:'spawn',type:'intern',n:1,r:0},run(160,'none',{hold:6}),run(1,'bot',{hold:6}),{op:'item',kind:'chest',dx:0,dy:0},run(1,'bot',{hold:6}),
      {op:'spawn',type:'crowd',n:1,r:0,hp:1e9},run(400,'none',{hold:6}),run(3,'bot',{hold:6}),run(100,'none',{hold:6})]});
  /* 죽는 까닭마다: 장판 · 음파 · 탄 · 회전 … (다른 적은 치우고 멘탈을 5로) */
  {const after=[set('S','admRate',0),set('S','nextRow',1e9),set('S','nextElite',1e9),{op:'killAll'},set('p','maxhp',5),set('p','hp',5)];
    for(const [nm,z,b] of [['zone',6,'lead'],['wave',0,'speaker'],['bullet',0,'flyboss'],['spin',1,'bagman'],['zone2',2,'doorman'],['crowd',4,'crowd'],['carrier',5,'carrierboss']])
      L.push({name:'die.'+nm,seed:nextSeed(),opts:{diff:2,build:{weapons:{gum:1},passives:{}}},pick:'manual',manual:'first',digestEvery:10,steps:[run(2,'none'),{op:'enterZone',i:z},...after,{op:'boss',type:b},set('S','rage',nm==='bullet'?1:0),run(1800,'none',{hold:6})]});}
  /* 알람이 마지막으로 울릴 때 '커피 시한폭탄'이 켜져 있는 경우 (첫 알람은 0.72초에 던져 2.8초쯤 마지막으로 울린다) */
  L.push({name:'fus.late',seed:nextSeed(),opts:{diff:1,demo:true,build:{weapons:{coffee:7,alarm:7},passives:{}}},pick:'demo',digestEvery:5,
    steps:[set('S','admNoPick',true),run(2,'none'),...crowd,run(148,'bot',{hold:6}),{op:'fus',key:'routine',on:true},run(60,'bot',{hold:6}),{op:'fus',key:'routine',on:false},run(200,'bot',{hold:6}),{op:'fus',key:'routine',on:true},run(120,'bot',{hold:6})]});
  /* 걸음 길이 · 화면 크기가 다른 판 (144Hz, 40Hz, 세로로 긴 휴대폰 화면, 아주 넓은 화면) */
  L.push({name:'dt.144',seed:nextSeed(),dtDiv:144,opts:{diff:1},pick:'auto',digestEvery:144,steps:[run(144*150)]});
  L.push({name:'dt.40',seed:nextSeed(),dtDiv:40,opts:{diff:2},pick:'auto',digestEvery:40,steps:[run(40*150)]});
  L.push({name:'view.phone',seed:nextSeed(),view:{w:420,h:900},opts:{diff:1},pick:'auto',digestEvery:60,steps:[run(60*200)]});
  L.push({name:'view.wide',seed:nextSeed(),view:{w:2560,h:1080},opts:{diff:2},pick:'auto',digestEvery:60,steps:[run(60*200)]});
  L.push({name:'consts.cov',seed:1,opts:{},pick:'auto',steps:[{op:'consts'},run(30)]});
  return L;
}
module.exports={SIM,W,PA,FU,CAP,fullGame,coverage};
