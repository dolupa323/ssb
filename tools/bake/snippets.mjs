// 원본 gfx.js의 그리기 반복문 안에 직접 적힌 그림 코드를 「처음 글 ~ 끝 글」로 잘라 낸다.
// 잘라 낸 글은 고치지 않고 그대로 GFX 안쪽 범위에서 돌린다(변수만 바깥에서 넣어 준다).
// start가 원본에 꼭 한 번(또는 nth번째) 나와야 하고, 아니면 굽기가 멈춘다 — 원본이 바뀌면 바로 드러난다.
export const SNIPPETS = [
  { name: 'spark', start: "const sp=Math.hypot(q.vx,q.vy),len=Math.max(3,sp*.045)", end: "ctx.lineTo(q.x-ux*L,q.y-uy*L);ctx.closePath();ctx.fill();" },
  { name: 'shard', start: "ctx.fillStyle=rgba(q.col,1);ctx.beginPath();ctx.moveTo(0,-q.size);", end: "ctx.lineTo(-q.size*.6,q.size*.4);ctx.closePath();ctx.fill();" },
  { name: 'arrowPlat', start: "ctx.fillStyle='rgba(27,33,36,.13)';ctx.beginPath();const ax=x+640,ay=my-120;", end: "ctx.lineTo(ax+10,ay+42);ctx.closePath();ctx.fill();" },
  { name: 'arrowStreet', start: "ctx.beginPath();const ax=x+640,ay=my+124;", end: "ctx.lineTo(ax+10,ay+32);ctx.closePath();ctx.fill();" },
  { name: 'doormark', start: "for(const o of[-26,26]){ctx.beginPath();ctx.moveTo(x+108+o,ey+(up?-14:14));", end: "ctx.lineTo(x+108+o+7,ey+(up?-2:2));ctx.closePath();ctx.fill();}" },
  { name: 'chevron', nth: 2, start: "ctx.beginPath();ctx.moveTo(ax+T.dir*26,ly);", end: "ctx.lineTo(ax-T.dir*4,ly+30);ctx.closePath();ctx.fill();" },
  { name: 'crosswalk', start: "ctx.fillStyle='rgba(255,255,255,.85)';for(let x=Math.floor((x0-300)/1100)*1100;", end: "ctx.fillRect(x+300+j*26,ly-58,13,116);" },
  { name: 'escarrow', start: "ctx.beginPath();ctx.moveTo(x+110,y+dir*46);", end: "ctx.lineTo(x+158,y-dir*10);ctx.closePath();ctx.fill();" },
  { name: 'gatetri', start: "for(const sd of[-1,1]){const ay=ry+sd*52;", end: "ctx.lineTo(gx+9,ay+sd*4);ctx.closePath();ctx.fill();}" },
  { name: 'wallBase', start: "ctx.fillStyle='#d4d9da';ctx.fillRect(x0,wy,vw,OUT-WALL);", end: "ctx.fillRect(x0,sd>0?WALL:-WALL-2,vw,2);" },
  { name: 'wallWin', start: "if(((b%8)+8)%8!==0){ctx.fillStyle=platA>.5?", end: "ctx.fillRect(bx-98,wy+4,60,2);}" },
  { name: 'wallGap', start: "ctx.fillStyle=platA>.3?'#f2efe6':'#0b0f12';ctx.fillRect(dx-35,wy,70,OUT-WALL);", end: "ctx.fillStyle=platA>.3?'#f2efe6':'#0b0f12';ctx.fillRect(dx-35,wy,70,OUT-WALL);" },
  { name: 'doorPanel', start: "for(const hs of[-1,1]){const px=hs<0?dx-35-g2:dx+g2;", end: "ctx.fillRect(px+7,wy+3,21,OUT-WALL-6);}" },
  { name: 'wallSill', start: "ctx.fillStyle='#e9c11a';ctx.fillRect(dx-36,sd>0?WALL-7:-WALL,72,7);", end: "ctx.fillRect(dx+j,sd>0?WALL-5:-WALL+2,4,3);" },
  { name: 'wallLed', start: "ctx.fillStyle='#0a0d0f';rr(ctx,dx-34,sd>0?WALL-21:-WALL+9,68,12,2);ctx.fill();", end: "ctx.fillStyle='#0a0d0f';rr(ctx,dx-34,sd>0?WALL-21:-WALL+9,68,12,2);ctx.fill();" },
  { name: 'joint', start: "ctx.fillStyle='#4b5359';ctx.fillRect(x-24,-OUT,48,OUT*2);", end: "ctx.fillRect(x-24,AISLE,48,OUT-AISLE);" },
  { name: 'pole', start: "ctx.fillStyle='rgba(0,0,0,.25)';ctx.beginPath();ctx.arc(px+2,py+3,6,0,TAU);ctx.fill();", end: "ctx.arc(px-1.5,py-1.5,1.6,0,TAU);ctx.fill();" },
  { name: 'strap', start: "ctx.strokeStyle='rgba(120,130,136,.55)';ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(x,yy);", end: "ctx.lineTo(sx+5.5,yy+18);ctx.closePath();ctx.stroke();" },
  { name: 'sign', start: "ctx.fillStyle='#fbfaf5';rr(ctx,x+60,sy-22,180,44,8);ctx.fill();", end: "ctx.fillRect(x+60,sy+12,180,6);" },
  { name: 'doorlight', start: "const g=ctx.createLinearGradient(0,sd*OUT,0,sd*(AISLE-70));", end: "ctx.lineTo(dx-78,sd*(AISLE-70));ctx.closePath();ctx.fill();" },
  { name: 'leadtie', start: "ctx.fillStyle='#d23338';ctx.beginPath();ctx.moveTo(x-4,mid-14);", end: "ctx.lineTo(x-6,mid+10);ctx.closePath();ctx.fill();ctx.stroke();" },
  { name: 'leadclip', start: "ctx.save();ctx.translate(x+dir*30,mid+6+Math.sin(e.anim*6)*2);ctx.rotate(dir*.18);", end: "ctx.fillRect(-7,-8+k*6,k===3?9:14,1.8);ctx.restore();" },
  { name: 'angerElite', start: "ctx.strokeStyle='#e5484d';ctx.lineWidth=2.4;ctx.lineCap='round';const mx=x+dir*-12*sc,my=top+4;", end: "ctx.quadraticCurveTo(mx+1.5,my+1.5,mx+2,my+5);ctx.stroke();" },
  { name: 'angerLead', start: "ctx.strokeStyle='#e5484d';ctx.lineWidth=2.6;ctx.lineCap='round';const mx=x-dir*24,my=top+12;", end: "ctx.quadraticCurveTo(mx+2,my+2,mx+2,my+6);ctx.stroke();" },
  { name: 'exitsign', start: "const sy=e.y-58+Math.sin(e.anim*5)*2;ctx.strokeStyle=INK;ctx.lineWidth=2;", end: "ctx.lineTo(e.x+17,sy+10);ctx.strokeStyle='#fff';ctx.stroke();" },
  { name: 'soundwave', start: "ctx.lineCap='round';const bx=x+dir*34,by=feet-84;for(let k=0;k<(rage?4:3);k++){", end: "dir>0?.8:Math.PI+.8);ctx.stroke();}" },
  { name: 'spintrail', start: "const a=e.anim*15;ctx.lineCap='round';for(let t=0;t<4;t++){", end: "ctx.arc(x,y,SPIN_R-18,a-t*.3-.35,a-t*.3);ctx.stroke();}" },
  { name: 'slick', start: "const a=Math.min(1,s.life/.6);const h0=(s.x*13+s.y*7)|0;", end: "rr(ctx,rx-4,ry-4,8,8,2);ctx.fill();}" },
  { name: 'puddle', start: "const age=u.dur-u.life,grow=Math.min(1,age/.18),", end: "ctx.restore();ctx.globalAlpha=1;" },
  { name: 'tbcup', start: "ctx.lineJoin='round';ctx.strokeStyle=INK;ctx.lineWidth=1.8;ctx.beginPath();ctx.moveTo(-13,-14);", end: "ctx.fillStyle='#fbfaf5';ctx.beginPath();ctx.arc(0,2,7,0,TAU);ctx.fill();" },
  { name: 'dashring', start: "ctx.strokeStyle=rgba(col,.95);ctx.lineWidth=3;ctx.setLineDash([12,8]);ctx.lineDashOffset=time*60;", end: "ctx.arc(z.x,z.y,z.r,0,TAU);ctx.stroke();ctx.setLineDash([]);" },
  { name: 'heatring', start: "const s=WEAPONS.hotpack.stat(l),ev=l>=EVO,r=s.r*S.M.area*(1+Math.sin(time*7)*.025),gr=ctx.createRadialGradient(p.x,p.y,r*.25,p.x,p.y,r);", end: "ctx.fillStyle=gr;ctx.beginPath();ctx.arc(p.x,p.y,r,0,TAU);ctx.fill();" },
  { name: 'crackdecal', start: "ctx.strokeStyle='rgba(40,30,30,.5)';ctx.lineWidth=2.5;ctx.lineCap='round';for(let k=0;k<7;k++){const an=k*.9+d.rot;", end: "Math.sin(an+.12)*d.r*(.45+.3*((k*7)%5)/5));ctx.stroke();}" },
  { name: 'crack', start: "const al=q<.6?1:1-(q-.6)/.4,g=Math.min(1,q*9);ctx.save();ctx.translate(f.x,f.y+8);ctx.scale(1,.62);ctx.lineCap='round';", end: "ctx.lineTo(mx+Math.cos(a+.9)*L*.24,my+Math.sin(a+.9)*L*.24);ctx.stroke();}", suffix: "ctx.restore();" },
  { name: 'gentip', start: "ctx.fillStyle='#d9b45a';ctx.strokeStyle=INK;ctx.lineWidth=1.6;ctx.beginPath();ctx.moveTo(R+6+fl*5,-3.2);", end: "ctx.lineTo(R+6+fl*5,3.2);ctx.closePath();ctx.fill();ctx.stroke();" },
  { name: 'remote', start: "ctx.fillStyle='#20262b';ctx.strokeStyle=INK;ctx.lineWidth=2;rr(ctx,-15,-11,30,22,4);ctx.fill();ctx.stroke();", end: "ctx.fillStyle='#ff5a5f';ctx.beginPath();ctx.arc(9,-5,1.8,0,TAU);ctx.fill();" },
  { name: 'hazardring', start: "for(let k=0;k<28;k++){ctx.strokeStyle=k%2?rgba('30,30,30',al*.9):rgba('255,201,40',al);", end: "ctx.arc(0,0,R,f.rot+k/28*TAU,f.rot+(k+1)/28*TAU+.01);ctx.stroke();}" },
  { name: 'gentspiral', start: "for(let k=0;k<2;k++){ctx.beginPath();for(let m=0;m<=40;m++){const u=m/40,an=f.rot+k*Math.PI+u*4.6+q*5,rr2=16+(R-16)*u;", end: "ctx.strokeStyle=rgba('255,255,255',al*.55);ctx.lineWidth=13*al+1;ctx.stroke();ctx.setLineDash([]);}" },
  { name: 'routinerays', start: "for(let k=0;k<12;k++){const an=f.rot+k/12*TAU+q*.8;", end: "ctx.lineTo(Math.cos(an+.09)*26,Math.sin(an+.09)*26);ctx.closePath();ctx.fill();}" },
  { name: 'lash', start: "const ext=q<.3?1-Math.pow(1-q/.3,3):1,al=q<.62?1:Math.max(0,1-(q-.62)/.38),", end: "rr(ctx,6,-5,10,10,2.5);ctx.fill();ctx.stroke();ctx.globalAlpha=1;ctx.restore();", suffix: "}" },
  { name: 'shoutburst', start: "const burst=(k,ox,oy)=>{ctx.beginPath();const n=20;", end: "burst(.8,0,0);ctx.strokeStyle=f.evo?'rgba(229,72,77,.6)':'rgba(255,201,40,.8)';ctx.lineWidth=2;ctx.stroke();" },
  { name: 'edgearrow', start: "ctx.fillStyle=col;ctx.strokeStyle=INK;ctx.lineWidth=2;ctx.lineJoin='round';ctx.beginPath();ctx.moveTo(15,0);", end: "ctx.lineTo(-8,11);ctx.closePath();ctx.fill();ctx.stroke();" },
  { name: 'warnsign', start: "ctx.lineJoin='round';ctx.beginPath();ctx.moveTo(0,-26);ctx.lineTo(26,20);ctx.lineTo(-26,20);ctx.closePath();ctx.fillStyle=b?'#ffc928':'#e5484d';ctx.fill();ctx.strokeStyle=INK;ctx.lineWidth=3;ctx.stroke();", end: "ctx.strokeStyle=INK;ctx.lineWidth=3;ctx.stroke();" },
  { name: 'bubbletail', start: "ctx.beginPath();ctx.moveTo(tx-6,by+bh-1);", end: "ctx.lineTo(tx+6,by+bh);ctx.stroke();" },
  { name: 'vigAmb', start: "const st=ZONES[S.zone],g=ctx.createRadialGradient(W/2,H/2,Math.min(W,H)*.22,W/2,H/2,Math.hypot(W,H)*.62);", end: "ctx.fillStyle=g;ctx.fillRect(0,0,W,H);" },
  { name: 'vigHurt', start: "const g2=ctx.createRadialGradient(W/2,H/2,Math.min(W,H)*.3,W/2,H/2,Math.hypot(W,H)*.6);", end: "ctx.fillStyle=g2;ctx.fillRect(0,0,W,H);" },
  { name: 'vigHeal', start: "const g3=ctx.createRadialGradient(W/2,H/2,Math.min(W,H)*.3,W/2,H/2,Math.hypot(W,H)*.6);", end: "ctx.fillStyle=g3;ctx.fillRect(0,0,W,H);" },
  { name: 'speedlines', start: "ctx.globalCompositeOperation='lighter';ctx.lineCap='round';const R=Math.hypot(W,H)/2,rs=srand(9);", end: "ctx.lineTo(W/2+Math.cos(a)*r1,H/2+Math.sin(a)*r1);ctx.stroke();}" },
  { name: 'pringBase', start: "ctx.lineWidth=2.6;ctx.strokeStyle='rgba(0,168,77,.35)';ctx.beginPath();ctx.ellipse(p.x,feet-1,17,7.5,0,0,TAU);ctx.stroke();", end: "ctx.ellipse(p.x,feet-1,17,7.5,0,0,TAU);ctx.stroke();" },
  { name: 'pringArc', start: "ctx.strokeStyle=rdy>=1?'#35e07f':'rgba(255,255,255,.85)';ctx.beginPath();ctx.ellipse(p.x,feet-1,17,7.5,0,-Math.PI/2,-Math.PI/2+TAU*rdy);ctx.stroke();", end: "-Math.PI/2+TAU*rdy);ctx.stroke();" },
];

// 원본 글에서 조각을 잘라 낸다. 돌려주는 것: { 이름: { code, line } }
export function extract(src) {
  const out = {};
  for (const sn of SNIPPETS) {
    let i = -1, n = 0; const want = sn.nth || 1;
    for (let k = src.indexOf(sn.start); k >= 0; k = src.indexOf(sn.start, k + 1)) { n++; if (n === want) i = k; }
    if (i < 0 || (!sn.nth && n !== 1)) throw new Error(`조각 「${sn.name}」: 처음 글이 원본에 ${n}번 나옵니다 (${want}번째가 있어야 하고${sn.nth ? '' : ' 꼭 한 번이어야'} 합니다)`);
    const j = src.indexOf(sn.end, i);
    if (j < 0) throw new Error(`조각 「${sn.name}」: 끝 글을 찾지 못했습니다`);
    const code = src.slice(i, j + sn.end.length) + (sn.suffix || '');
    out[sn.name] = { code, line: src.slice(0, i).split('\n').length, endLine: src.slice(0, j).split('\n').length };
  }
  return out;
}
