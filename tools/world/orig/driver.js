'use strict';
/* 원본(sim.js + gfx.js)을 같은 SPEC으로 돌려 SHOT이라는 이름의 장면에서 멈춘다 — 화면 없는 Chrome이 그 화면을 찍는다.
   tools/world/driver.luau와 같은 뜻으로 읽는다. 원본 파일은 고치지 않고 불러 쓰기만 한다. */
(function(){
  const SPEC=window.SPEC,SHOT=window.SHOT;
  function makeRng(seed){let a=seed>>>0;return function(){a=(a+0x6D2B79F5)|0;let t=Math.imul(a^(a>>>15),1|a);t=(t+Math.imul(t^(t>>>7),61|t))^t;return((t^(t>>>14))>>>0)/4294967296;};}
  const R0=makeRng(SPEC.seed),RG=makeRng(SPEC.seed+7);let calls=0;const R=()=>{calls++;return R0();};const LOG=[];
  const cv=document.getElementById('cv');GFX.init(cv);
  const NSHOT=SPEC.steps.filter(st=>st.op==='shot').length,big=document.createElement('canvas');big.width=cv.width;big.height=cv.height*Math.max(1,NSHOT);const bg=big.getContext('2d');let nshot=0;
  const host={sfx(){},banner(){},shake(a){GFX.shake(a);},levelUp(){},end(){}};
  const toMap=l=>{const m={};for(const kv of l||[])m[kv[0]]=kv[1];return m;};
  const opts={diff:SPEC.diff===undefined?2:SPEC.diff,autoPick:ch=>ch[Math.floor(R()*ch.length)]};
  if(SPEC.build)opts.build={weapons:toMap(SPEC.build.w),passives:toMap(SPEC.build.p)};
  Math.random=R;
  const sim=createSim(host,opts),S=sim.S,mode=SPEC.mode||'play',dt=1/60;let tick=0;
  function frame(st){
    const p=S.p,input=st.input||'bot';
    if(input==='bot'){const b=sim.bot();S.input=b;if(b.dash)sim.dash();}
    else if(typeof input==='object')S.input={x:input.x,y:input.y};else S.input={x:0,y:0};
    if(st.dashEvery&&tick%st.dashEvery===0)sim.dash();
    if(st.hold!==undefined&&(S.phase==='crowd'||S.phase==='ride')&&S.zt>st.hold)S.zt=st.hold;
    if(st.keepHp)p.hp=p.maxhp;
    if(!GFX.frozen())sim.update(dt,GFX.view());
    Math.random=RG;GFX.render(S,{mode,dt,running:true,fx:false,offX:SPEC.offX||0,offY:0});Math.random=R;
    tick++;
  }
  let done=false;
  for(const st of SPEC.steps){if(done)break;const p=S.p;
    switch(st.op){
      case 'run':case 'steady':for(let i=0;i<st.ticks;i++){if(S.state!=='run')break;frame(st);}break;
      case 'enterZone':S.zone=st.i;sim.dbg.enterZone(st.i);break;
      case 'boss':sim.dbg.boss(st.type);break;
      case 'spawn':for(let i=0;i<st.n;i++){const x=p.x+(R()*2-1)*st.r,y=p.y+(R()*2-1)*(st.ry===undefined?st.r:st.ry);const e=sim.dbg.spawn(st.type,x,y);if(st.hp!==undefined)e.hp=e.maxhp=st.hp;if(st.elite)e.elite=true;}break;
      case 'set':{const o=st.obj==='S'?S:st.obj==='p'?S.p:st.obj==='M'?S.M:st.obj==='train'?S.train:null;if(o)o[st.key]=st.value;break;}
      case 'setAll':for(const e of S.enemies)e[st.key]=st.value;break;
      case 'bossHp':for(const e of S.bosses)e.hp=e.maxhp*st.frac;break;
      case 'build':{const fsrc={},fus={};for(const k of st.fus||[]){fus[k]=1;fsrc[FUSIONS[k].a]=1;fsrc[FUSIONS[k].b]=1;}
        S.weapons=toMap(st.w);S.passives=toMap(st.p);S.fus=fus;S.fsrc=fsrc;S.beams.length=0;S.umbQ=null;sim.dbg.recalc();break;}
      case 'item':S.items.push({kind:st.kind,x:p.x+st.dx,y:p.y+st.dy,t:0});break;
      case 'xp':p.xp+=st.v;break;
      case 'opts':GFX.opts(st);break;
      case 'celebrate':Math.random=RG;GFX.celebrate();Math.random=R;break;
      case 'shot':LOG.push('view '+JSON.stringify(GFX.view())+' size '+JSON.stringify(GFX.size()));LOG.push(st.name+' tick '+tick+' t='+S.t.toFixed(4)+' p=('+S.p.x.toFixed(3)+','+S.p.y.toFixed(3)+') enemies '+S.enemies.length+' kills '+S.kills+' lv '+S.p.level+' rng '+calls);bg.drawImage(cv,0,nshot*cv.height);nshot++;if(st.name===SHOT)done=true;break;
      default:throw new Error('모르는 op: '+st.op);
    }
  }
  if(location.hash==='#info'){const g=cv.getContext('2d');g.setTransform(1,0,0,1,0,0);g.fillStyle='#000';g.fillRect(0,0,900,16*LOG.length+8);g.fillStyle='#fff';g.font='12px monospace';g.textAlign='left';LOG.forEach((l,i)=>g.fillText(l,4,14+i*16));}if(!SHOT){cv.style.display='none';big.style.cssText='position:absolute;left:0;top:0;display:block;width:'+cv.width+'px;height:'+big.height+'px';document.body.appendChild(big);document.documentElement.style.height=big.height+'px';document.body.style.height=big.height+'px';}
  const pre=document.createElement('pre');pre.style.display='none';pre.id='log';pre.textContent=LOG.join(String.fromCharCode(10));document.body.appendChild(pre);document.title='done t='+S.t.toFixed(1)+' zone '+S.zone+' enemies '+S.enemies.length;
})();
