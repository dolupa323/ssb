#!/usr/bin/env node
/* 규칙 견줌 검사 — 원본 commute-survival/js/sim.js 와 src/shared/Sim.luau 를 같은 난수로 돌려 견준다.
   쓰는 법:  node tools/parity/run.mjs            (전부)
            node tools/parity/run.mjs --only=math,static,self,A,mut,Anative,B,C,perf   (고른 것만)
            node tools/parity/run.mjs --seeds=3    (A · C 의 씨앗 수를 줄여 빨리)
   끝에 PASS/FAIL 요약을 찍는다. 자세한 결과는 tools/parity/work/report.txt */
import {spawn} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const HERE=path.dirname(fileURLToPath(import.meta.url)),ROOT=path.resolve(HERE,'..','..'),WORK=path.join(HERE,'work');
const LUAU=path.join(ROOT,'tools','luau','luau.exe'),SIMSRC=path.join(ROOT,'src','shared','Sim.luau');
const {makeRng,hex,unhex}=require('./js/prng.cjs');
const softmath=require('./js/softmath.cjs');
const SC=require('./scenarios.cjs');

const args=Object.fromEntries(process.argv.slice(2).map(a=>{const m=a.match(/^--([^=]+)(?:=(.*))?$/);return m?[m[1],m[2]===undefined?true:m[2]]:[a,true];}));
const only=args.only?String(args.only).split(','):null;
const want=k=>!only||only.includes(k);
const NSEED=args.seeds?+args.seeds:10;
const JOBS=Math.max(2,Math.min(os.cpus().length-1,args.jobs?+args.jobs:12));

fs.mkdirSync(WORK,{recursive:true});
const report=[];const results=[];
const log=s=>{console.log(s);report.push(s);};
const note=s=>{report.push(s);};
function result(name,ok,detail){results.push({name,ok,detail});log((ok?'  PASS  ':'  FAIL  ')+name+(detail?'  — '+detail:''));}

/* ---------- 실행 도구 ---------- */
function exec(cmd,argv,cwd){return new Promise(res=>{const p=spawn(cmd,argv,{cwd,stdio:['ignore','pipe','pipe']});const o=[],e=[];p.stdout.on('data',d=>o.push(d));p.stderr.on('data',d=>e.push(d));
  p.on('error',err=>res({code:-1,out:'',err:String(err)}));p.on('close',code=>res({code,out:Buffer.concat(o).toString('utf8'),err:Buffer.concat(e).toString('utf8')}));});}
let active=0;const waiting=[];
async function slot(fn){if(active>=JOBS)await new Promise(r=>waiting.push(r));active++;try{return await fn();}finally{active--;const w=waiting.shift();if(w)w();}}
/* JS 값을 Luau 표 글로 */
function toLua(v){
  if(v===null||v===undefined)return 'nil';
  if(typeof v==='number'){if(!Number.isFinite(v))throw new Error('유한하지 않은 수');return String(v);}
  if(typeof v==='boolean')return String(v);
  if(typeof v==='string')return JSON.stringify(v);
  if(Array.isArray(v))return '{'+v.map(toLua).join(',')+'}';
  return '{'+Object.entries(v).filter(([,x])=>x!==null&&x!==undefined).map(([k,x])=>'['+JSON.stringify(k)+']='+toLua(x)).join(',')+'}';
}
/* JS 객체의 키 순서를 Lua 쪽에 알려 줄 순서 목록을 붙인다 */
function addOrders(spec){
  const s=JSON.parse(JSON.stringify(spec));
  const ord=(o,from,to)=>{if(o&&o[from]&&!o[to])o[to]=Object.keys(o[from]);};
  if(s.opts){for(const b of [s.opts.build,s.opts.restore]){ord(b,'weapons','wOrder');ord(b,'passives','pOrder');ord(b,'fus','fOrder');ord(b,'dmg','dmgOrder');}}
  for(const st of s.steps)if(st.op==='build'){ord(st,'weapons','wOrder');ord(st,'passives','pOrder');ord(st,'fus','fOrder');if(!st.passives)st.passives={};}
  return s;
}
let softReady=false;
function prepareSoft(){
  if(softReady)return;
  const src=fs.readFileSync(SIMSRC,'utf8');
  const re=/(--@@MATH-BEGIN[^\n]*\n)([^\n]*\n)(--@@MATH-END)/;
  if(!re.test(src))throw new Error('Sim.luau 에서 --@@MATH 줄을 찾지 못했습니다');
  const patched=src.replace(re,(m,a,b,c)=>a+'local __sm = require("../luau/softmath"); local sin, cos, atan2, exp, pow = __sm.sin, __sm.cos, __sm.atan2, __sm.exp, __sm.pow\n'+c);
  fs.writeFileSync(path.join(WORK,'SimSoft.luau'),patched);
  softReady=true;
}
function splitJobs(text){
  const jobs=new Map();let cur=null;let time=null;const stray=[];
  for(const line of text.split(/\r?\n/)){
    if(!line)continue;
    if(line.startsWith('# ')){cur=[];jobs.set(line.slice(2),cur);}
    else if(line.startsWith('T ')){time=+line.slice(2);}
    else if(line.startsWith('X ')){const nm=line.split(' ')[1];(jobs.get(nm)||stray).push(line);}
    else if(cur)cur.push(line);else stray.push(line);
  }
  return {jobs,time,stray};
}
let idN=0;
async function runJS(specs,soft){
  const id='js'+(++idN),f=path.join(WORK,id+'.json');
  fs.writeFileSync(f,JSON.stringify(specs.map(addOrders)));
  const r=await slot(()=>exec(process.execPath,[path.join(HERE,'js','driver.cjs'),f].concat(soft?['--soft']:[]),HERE));
  fs.rmSync(f,{force:true});
  if(r.code!==0)throw new Error('JS driver 실패: '+r.err.slice(0,2000));
  return splitJobs(r.out);
}
async function runLuau(specs,{soft=false,codegen=true,coverage=false,simPath=null}={}){
  if(soft)prepareSoft();
  const id='lu'+(++idN),dir=path.join(WORK,id);
  fs.mkdirSync(dir,{recursive:true});
  fs.writeFileSync(path.join(dir,'job.luau'),'return '+toLua(specs.map(addOrders))+'\n');
  fs.writeFileSync(path.join(dir,'main.luau'),'local driver = require("../../luau/driver")\nlocal Sim = require("'+(simPath||(soft?'../SimSoft':'../../../../src/shared/Sim'))+'")\ndriver.run(require("./job"), Sim)\n');
  const argv=['-O2'];if(codegen&&!coverage)argv.push('--codegen');if(coverage)argv.push('--coverage');argv.push('main.luau');
  const r=await slot(()=>exec(LUAU,argv,dir));
  let cov=null;
  if(coverage){const cf=path.join(dir,'coverage.out');if(fs.existsSync(cf))cov=fs.readFileSync(cf,'utf8');}
  fs.rmSync(dir,{recursive:true,force:true});
  const sp=splitJobs(r.out);
  sp.err=(r.err||'').trim();sp.code=r.code;sp.cov=cov;
  if(sp.stray.length)sp.err+=(sp.err?'\n':'')+sp.stray.join('\n');
  return sp;
}
const chunk=(a,n)=>{const o=[];for(let i=0;i<a.length;i+=n)o.push(a.slice(i,i+n));return o;};
/* 시나리오 묶음을 양쪽에서 돌려 이름 → {js, lu} */
async function runBoth(specs,{soft,per=1,codegen=true}){
  const groups=chunk(specs,per);
  const outs=await Promise.all(groups.map(async g=>{const [a,b]=await Promise.all([runJS(g,soft),runLuau(g,{soft,codegen})]);return {g,a,b};}));
  const m=new Map();let luErr='';let luTime=0;
  for(const {g,a,b} of outs){if(b.err)luErr+=b.err+'\n';luTime+=b.time||0;for(const s of g)m.set(s.name,{js:a.jobs.get(s.name)||[],lu:b.jobs.get(s.name)||[]});}
  return {m,luErr,luTime};
}

/* ---------- 견주기 ---------- */
function parseD(line){const [a,b,c]=line.split(' | ');const ints=a.split(' ');return {tag:ints[0],tick:+ints[1],ints,fl:(b||'').split(' '),hs:(c||'').split(' ')};}
const FL=['t','p.x','p.y','p.hp','p.maxhp','p.xp','p.inv','sumEx','sumEy','sumEhp','zt','spawnAcc'];
const IN=['tag','tick','state','zone','phase','rage','level','kills','pending','pickMode','#enemies','#beans','#bullets','#shots','#items','#zones','#waves','#puddles','#mines','#bosses','rngCalls','evCount','hostCount'];
const HS=['evHash','evKindHash','enemyHash','otherHash','buildHash'];
function describeDiff(a,b){
  if(a===undefined)return 'JS 쪽 줄이 없음 / Luau: '+String(b).slice(0,160);
  if(b===undefined)return 'Luau 쪽 줄이 없음 / JS: '+String(a).slice(0,160);
  if(!/^[DE] /.test(a)||!/^[DE] /.test(b))return 'JS: '+a.slice(0,300)+'  ||  Luau: '+b.slice(0,300);
  const x=parseD(a),y=parseD(b),d=[];
  x.ints.forEach((v,i)=>{if(v!==y.ints[i])d.push(IN[i]+' '+v+'≠'+y.ints[i]);});
  x.fl.forEach((v,i)=>{if(v!==y.fl[i])d.push(FL[i]+' '+unhex(v)+'≠'+unhex(y.fl[i]||'0'));});
  x.hs.forEach((v,i)=>{if(v!==y.hs[i])d.push(HS[i]+' 다름');});
  return 'tick '+x.tick+': '+d.join(', ');
}
function compareExact(js,lu){
  const n=Math.max(js.length,lu.length);
  for(let i=0;i<n;i++)if(js[i]!==lu[i])return {ok:false,idx:i,why:describeDiff(js[i],lu[i])};
  return {ok:n>0,idx:-1,why:n>0?'':'출력이 없음'};
}
const finalOf=lines=>{const f=lines.find(l=>l.startsWith('F|'));if(!f)return null;const p=f.split('|');return {name:p[1],state:p[2],zone:+p[3],tick:+p[4],t:unhex(p[5]),level:+p[6],kills:+p[7],late:p[8]==='1',ended:p[13],build:p[14]};};
/* 떠돌이 소수점 잡음 분석: 처음 실수가 달라지는 tick · 처음 이산값(개수 · 난수 호출 수 · 이벤트 종류)이 달라지는 tick */
function analyzeDrift(js,lu){
  const r={firstFloat:null,firstDisc:null,relAtFirst:null,rngEqualAtFirst:null,growth:[],maxRelBeforeDisc:0};
  const n=Math.min(js.length,lu.length);
  for(let i=0;i<n;i++){
    if(!/^[DE] /.test(js[i])||!/^[DE] /.test(lu[i]))continue;
    const a=parseD(js[i]),b=parseD(lu[i]);
    const disc=a.ints.some((v,k)=>v!==b.ints[k])||a.hs[1]!==b.hs[1]||a.hs[4]!==b.hs[4];
    let rel=0;a.fl.forEach((v,k)=>{if(v!==b.fl[k]){const x=unhex(v),y=unhex(b.fl[k]);const d=Math.abs(x-y)/Math.max(1e-300,Math.abs(x),Math.abs(y),1);if(d>rel)rel=d;}});
    const anyBits=rel>0||a.hs[0]!==b.hs[0]||a.hs[2]!==b.hs[2]||a.hs[3]!==b.hs[3];
    if(r.firstFloat===null&&anyBits&&!disc){r.firstFloat=a.tick;r.relAtFirst=rel;r.rngEqualAtFirst=a.ints[20]===b.ints[20];}
    if(disc){r.firstDisc=a.tick;r.discWhy=describeDiff(js[i],lu[i]);if(r.firstFloat===null){r.firstFloat=a.tick;r.relAtFirst=rel;r.rngEqualAtFirst=a.ints[20]===b.ints[20];r.discFirst=true;}break;}
    if(r.firstFloat!==null){if(rel>r.maxRelBeforeDisc)r.maxRelBeforeDisc=rel;
      /* 500 tick 구간마다 가장 큰 상대 차 */
      const w=Math.floor((a.tick-r.firstFloat)/500);const g=r.growth;if(!g[w]||rel>g[w][1])g[w]=[r.firstFloat+w*500,rel];}
  }
  return r;
}

/* ---------- 1. 난수 · 수학 함수 ---------- */
async function sectionMath(){
  log('\n[math] 난수 · 수학 함수 견줌');
  const N=200000;
  const dir=path.join(WORK,'mathcheck');fs.mkdirSync(dir,{recursive:true});
  fs.writeFileSync(path.join(dir,'main.luau'),`--!optimize 2
local P = require("../../luau/prng")
local SM = require("../../luau/softmath")
local Sim = require("../../../../src/shared/Sim")
local hex = P.hex
local out = {}
local function emit(s) out[#out + 1] = s; if #out >= 4000 then print(table.concat(out, "\\n")); table.clear(out) end end
for _, seed in ipairs({ 1, 12345, 4294967295, 0 }) do
	local r = P.makeRng(seed)
	local t = {}
	for i = 1, 500 do t[i] = hex(r.next()) end
	emit("R " .. table.concat(t, ""))
end
local g = P.makeRng(777)
for i = 1, ${N} do
	local a, b, c, d, e = (g.next() * 2 - 1) * 3000, (g.next() * 2 - 1) * 700, (g.next() * 2 - 1) * 700, -g.next() * 0.9, g.next()
	local n = 1 + math.floor(e * 130)
	emit("M " .. hex(SM.sin(a)) .. hex(SM.cos(a)) .. hex(SM.atan2(b, c)) .. hex(SM.exp(d)) .. hex(SM.pow(e, 2)) .. hex(SM.pow(1.16, n))
		.. hex(math.sin(a)) .. hex(math.cos(a)) .. hex(math.atan2(b, c)) .. hex(math.exp(d)) .. hex(math.pow(e, 2)) .. hex(math.pow(1.16, n))
		.. hex(Sim.hypot(b, c)) .. hex(Sim.round(b)) .. hex(Sim.round(c / 7)) .. hex(Sim.sign(b)) .. hex(Sim.angd(a)) .. hex(math.fmod(a, 6.283185307179586)))
end
local edge = { 0, -0, 0.5, -0.5, 1.5, -1.5, 2.5, -2.5, 0.49999999999999994, -0.49999999999999994, 4503599627370497, -4503599627370497, 1e300, -1e300, 3, -3, 0.3, -0.3, 1e-320, 123456.5, -123456.5 }
for _, x in ipairs(edge) do
	for _, y in ipairs(edge) do
		emit("E " .. hex(Sim.hypot(x, y)) .. hex(Sim.round(x)) .. hex(Sim.sign(x)) .. hex(SM.atan2(x, y)) .. hex(math.atan2(x, y)) .. hex(SM.sin(x)) .. hex(SM.cos(x)))
	end
end
print(table.concat(out, "\\n"))
`);
  const r=await slot(()=>exec(LUAU,['-O2','--codegen','main.luau'],dir));
  fs.rmSync(dir,{recursive:true,force:true});
  if(r.code!==0||r.err.trim()){result('math: Luau 검사 스크립트 실행',false,(r.err||r.out).slice(0,500));return;}
  const lines=r.out.split(/\r?\n/).filter(Boolean);
  const R=lines.filter(l=>l.startsWith('R ')),M=lines.filter(l=>l.startsWith('M ')),E=lines.filter(l=>l.startsWith('E '));
  /* 난수 */
  let ok=true;[1,12345,4294967295,0].forEach((seed,i)=>{const g=makeRng(seed);let s='';for(let k=0;k<500;k++)s+=hex(g());if('R '+s!==R[i])ok=false;});
  result('math: 씨앗 난수(mulberry32) 4씨앗 × 500개가 비트까지 같다',ok);
  const names=['soft sin','soft cos','soft atan2','soft exp','soft pow(x,2)','soft pow(1.16,n)','native sin','native cos','native atan2','native exp','native pow(x,2)','native pow(1.16,n)','hypot','round(b)','round(c/7)','sign','angd','fmod'];
  const diff=new Array(names.length).fill(0);const errSoft=[0,0,0,0];
  const g=makeRng(777);
  for(let i=0;i<N;i++){
    const a=(g()*2-1)*3000,b=(g()*2-1)*700,c=(g()*2-1)*700,d=-g()*0.9,e=g(),n=1+Math.floor(e*130);
    const TAU=Math.PI*2;
    const js=[softmath.sin(a),softmath.cos(a),softmath.atan2(b,c),softmath.exp(d),softmath.pow(e,2),softmath.pow(1.16,n),Math.sin(a),Math.cos(a),Math.atan2(b,c),Math.exp(d),Math.pow(e,2),Math.pow(1.16,n),
      Math.hypot(b,c),Math.round(b),Math.round(c/7),Math.sign(b),((a%TAU)+TAU+Math.PI)%TAU-Math.PI,a%TAU];
    const L=M[i]||'';
    for(let k=0;k<names.length;k++)if(hex(js[k])!==L.substr(2+k*16,16))diff[k]++;
    for(let k=0;k<4;k++){const er=Math.abs(js[k]-js[k+6]);if(er>errSoft[k])errSoft[k]=er;}
  }
  const softOk=diff.slice(0,6).every(v=>v===0);
  result('math: softmath(JS) = softmath(Luau) 비트까지, '+N+'개 입력',softOk,softOk?'':'다른 개수 '+diff.slice(0,6).join('/'));
  result('math: softmath 의 오차가 충분히 작다 (원래 함수와의 최대 차)',errSoft.every(v=>v<4e-15),'sin '+errSoft[0].toExponential(1)+' cos '+errSoft[1].toExponential(1)+' atan2 '+errSoft[2].toExponential(1)+' exp '+errSoft[3].toExponential(1));
  const helpOk=diff.slice(12).every(v=>v===0);
  result('math: Sim.hypot/round/sign/angd · fmod = JS Math.hypot/round/sign · % 비트까지, '+N+'개 입력',helpOk,helpOk?'':'다른 개수 '+diff.slice(12).join('/'));
  /* 모서리 값 */
  const edge=[0,-0,0.5,-0.5,1.5,-1.5,2.5,-2.5,0.49999999999999994,-0.49999999999999994,4503599627370497,-4503599627370497,1e300,-1e300,3,-3,0.3,-0.3,1e-320,123456.5,-123456.5];
  let eBad=0,eA2=0,eSoft=0,idx=0;
  for(const x of edge)for(const y of edge){const L=E[idx++]||'';const f=k=>L.substr(2+k*16,16);
    if(f(0)!==hex(Math.hypot(x,y))||f(1)!==hex(Math.round(x))||f(2)!==hex(Math.sign(x)))eBad++;
    if(f(3)!==hex(softmath.atan2(x,y))||f(5)!==hex(softmath.sin(x))||f(6)!==hex(softmath.cos(x)))eSoft++;
    if(Math.abs(unhex(f(4))-Math.atan2(x,y))>1e-15)eA2++;}
  result('math: 모서리 값(±0, ±0.5, 2^52+1, 1e300 …) '+edge.length*edge.length+'쌍에서 hypot/round/sign 이 JS 와 같다',eBad===0&&eSoft===0&&eA2===0,eBad||eSoft||eA2?'다름: 도움함수 '+eBad+', softmath '+eSoft+', atan2 '+eA2:'');
  log('  참고  V8 과 MSVC 의 원래 수학 함수가 마지막 비트에서 다른 비율 ('+N+'개 입력): '+names.slice(6,12).map((n,k)=>n.replace('native ','')+' '+(diff[6+k]/N*100).toFixed(2)+'%').join(', '));
  return {nativeDiff:diff.slice(6,12).map(v=>v/N)};
}

/* ---------- 2. 바뀌지 않는 자료 ---------- */
async function sectionStatic(){
  log('\n[static] 표 · 수치 · 글 (xpNeed 1~150, clockText, 무기 16종 × 1~8레벨 수치, 장비 · 조합 · 적 · 난이도 · 장소)');
  const spec=[{name:'consts',seed:1,opts:{},steps:[{op:'consts'}]}];
  for(const soft of [false,true]){
    const {m,luErr}=await runBoth(spec,{soft});
    const {js,lu}=m.get('consts');const a=js.filter(l=>l.startsWith('C ')),b=lu.filter(l=>l.startsWith('C '));
    let bad=null;for(let i=0;i<Math.max(a.length,b.length);i++)if(a[i]!==b[i]){bad='JS: '+String(a[i]).slice(0,200)+' || Luau: '+String(b[i]).slice(0,200);break;}
    result('static: 자료 '+a.length+'줄이 같다 ('+(soft?'softmath':'원래 수학 함수')+')',!bad&&a.length>100&&!luErr,bad||luErr);
  }
}

/* ---------- 3. A: 똑같은 궤적 ---------- */
const gameSpecs=()=>{const L=[];for(let d=0;d<4;d++)for(let s=1;s<=NSEED;s++)L.push(SC.fullGame(s*7919+d*104729+11,d));return L;};
async function sectionA(){
  log('\n[A] 같은 난수 · 같은 수학 함수(softmath)로 처음부터 끝까지: 봇 조종, dt=1/60, 화면 1280×720, 60 tick 마다 요약 줄');
  const specs=gameSpecs();
  const {m,luErr,luTime}=await runBoth(specs,{soft:true,per:2});
  let bad=0,ticks=0,lines=0;const outcomes={over:0,won:0,run:0};const firstBad=[];
  for(const s of specs){const {js,lu}=m.get(s.name);const c=compareExact(js,lu);const f=finalOf(js);
    if(f){ticks+=f.tick;outcomes[f.state]=(outcomes[f.state]||0)+1;}lines+=js.length;
    if(!c.ok){bad++;if(firstBad.length<5)firstBad.push(s.name+' → '+c.why);}
    note('    '+s.name+': '+(c.ok?'같음':'다름')+' '+(f?f.state+' zone '+f.zone+' t='+f.t.toFixed(1)+' lv'+f.level+' kills '+f.kills+' ticks '+f.tick:''));}
  result('A: '+specs.length+'판(난이도 4 × 씨앗 '+NSEED+') 전부 요약 줄이 비트까지 같다',bad===0&&!luErr,'합계 '+ticks+' tick · 요약 '+lines+'줄 · 끝난 모습 '+JSON.stringify(outcomes)+(bad?' · 다른 판 '+bad+': '+firstBad.join(' ; '):'')+(luErr?' · Luau 오류: '+luErr.slice(0,300):''));
  /* 해석기와 네이티브 코드가 같은 결과를 내는가 (Roblox 는 --!native 로 돈다) */
  const sub=specs.filter((_,i)=>i%NSEED===0);
  const [cg,it]=await Promise.all([runLuau(sub,{soft:true,codegen:true}),runLuau(sub,{soft:true,codegen:false})]);
  let same=true;for(const s of sub){const a=cg.jobs.get(s.name)||[],b=it.jobs.get(s.name)||[];if(a.length===0||a.length!==b.length||a.some((l,i)=>l!==b[i]))same=false;}
  result('A: Luau 해석기(-O2)와 네이티브 코드(--codegen)의 결과가 같다 ('+sub.length+'판)',same&&!cg.err&&!it.err,(cg.err||it.err||'').slice(0,300));
  return {specs,m};
}
async function sectionAnative(){
  log('\n[Anative] 원래 수학 함수(V8 vs MSVC)로 같은 판: 어디서부터, 왜 갈라지는가 (매 tick 요약)');
  const specs=[];for(const d of [1,2])for(const s of [1,2]){const g=SC.fullGame(s*7919+d*104729+11,d);g.name='native.'+g.name;g.denseUntil=1e9;specs.push(g);}
  const {m,luErr}=await runBoth(specs,{soft:false,per:1});
  let ok=!luErr;const rows=[];
  for(const s of specs){const {js,lu}=m.get(s.name);const r=analyzeDrift(js,lu);
    const noise=r.firstFloat!==null&&!r.discFirst&&r.rngEqualAtFirst&&r.relAtFirst<1e-9;
    if(!noise)ok=false;
    const fin=finalOf(js),finL=finalOf(lu);
    rows.push('    '+s.name+': 비트가 처음 달라지는 tick '+r.firstFloat+' (요약 실수의 상대 차 '+(r.relAtFirst===null?'-':r.relAtFirst.toExponential(1))+' · 그때 개수와 난수 호출 수는 '+(r.rngEqualAtFirst?'같음':'다름')+')'
      +' → 개수 · 난수 호출 수가 처음 달라지는 tick '+(r.firstDisc===null?'없음(끝까지 같음)':r.firstDisc+' (게임 시간 '+(r.firstDisc/60).toFixed(0)+'초)'));
    rows.push('        그 사이 500 tick 구간마다 가장 큰 상대 차: '+r.growth.filter(Boolean).map(g=>g[1].toExponential(0)).join(' → '));
    if(r.firstDisc!==null)rows.push('        갈라진 곳: '+r.discWhy.slice(0,330));
    if(fin&&finL)rows.push('        끝: JS '+fin.state+' 장소 '+fin.zone+' '+fin.t.toFixed(0)+'초 lv'+fin.level+' 처치 '+fin.kills+' / Luau '+finL.state+' 장소 '+finL.zone+' '+finL.t.toFixed(0)+'초 lv'+finL.level+' 처치 '+finL.kills);}
  rows.forEach(log);
  result('Anative: 갈라짐이 아주 작은 실수 차(<1e-9, 난수 호출 수 같음)로 시작해서 자란다 = 떠돌이 소수점 잡음',ok,luErr?luErr.slice(0,300):'');
}

/* ---------- 3-2. 검사 도구가 정말 다른 것을 잡아내는가 ---------- */
/* Sim.luau 의 사본을 한 군데씩 일부러 틀리게 고쳐서, 견줌이 그것을 잡는지 본다 */
const MUTATIONS=[
  ['아이템이 떨어질 확률 .0105 → .0205','elseif r < .0105 * S.M.luck then','elseif r < .0205 * S.M.luck then'],
  ['적 씨앗 floor(R()*1000) → floor(R()*1001)','local seed = floor(R() * 1000)','local seed = floor(R() * 1001)'],
  ['난수 부르는 순서 바꿈 (anim ↔ tm)','\t\tlocal anim = R() * 10\n\t\tlocal tm = if isBoss then 2.5 else 1 + R() * 2\n','\t\tlocal tm = if isBoss then 2.5 else 1 + R() * 2\n\t\tlocal anim = R() * 10\n'],
  ['hypot 을 그냥 sqrt(x*x+y*y) 로 (마지막 비트만 달라진다)','\tx /= m\n\ty /= m\n\treturn sqrt(x * x + y * y) * m\n','\treturn sqrt(x * x + y * y)\n'],
  ['각도 차의 fmod 를 Lua 의 % 로','return fmod(fmod(x, TAU) + TAU + PI, TAU) - PI','return ((x % TAU) + TAU + PI) % TAU - PI','문턱값 견줌에만 쓰여서 마지막 비트가 달라도 결과가 거의 안 바뀐다'],
  ['Math.round 를 Luau 의 math.round 로','\tlocal f = floor(x)\n\tif x - f >= 0.5 then\n\t\tf += 1\n\tend\n\tif f == 0 and x < 0 then\n\t\treturn -0\n\tend\n\treturn f\n','\treturn math.round(x)\n','음수이면서 정확히 .5 로 끝나는 좌표에서만 달라진다'],
  ['적 배열에서 빼는 방식 (끝의 것을 당겨 오기 → 차례대로 당기기)','\t\t\tif e.dead then\n\t\t\t\tlocal n = #E\n\t\t\t\tE[i] = E[n]\n\t\t\t\tE[n] = nil\n\t\t\t\tcontinue\n\t\t\tend\n','\t\t\tif e.dead then\n\t\t\t\ttable.remove(E, i)\n\t\t\t\tcontinue\n\t\t\tend\n'],
  ['가까운 순 정렬에서 같은 거리의 순서 (> → >=)','\t\t\t\t\t\twhile j >= 1 and ds[j] > d do\n\t\t\t\t\t\t\tout[j + 1] = out[j]\n\t\t\t\t\t\t\tds[j + 1] = ds[j]\n\t\t\t\t\t\t\tj -= 1\n\t\t\t\t\t\tend\n\t\t\t\t\t\tout[j + 1] = e\n\t\t\t\t\t\tds[j + 1] = d\n\t\t\t\t\t\tcnt += 1','\t\t\t\t\t\twhile j >= 1 and ds[j] >= d do\n\t\t\t\t\t\t\tout[j + 1] = out[j]\n\t\t\t\t\t\t\tds[j + 1] = ds[j]\n\t\t\t\t\t\t\tj -= 1\n\t\t\t\t\t\tend\n\t\t\t\t\t\tout[j + 1] = e\n\t\t\t\t\t\tds[j + 1] = d\n\t\t\t\t\t\tcnt += 1','거리가 비트까지 같은 두 적이 있을 때만 달라진다'],
  ['곱하는 순서 d *= (a*b…) → d = d*a*b…','d *= M.might * W_SCALE * fm *','d = d * M.might * W_SCALE * fm *'],
  ['경험치 곱하는 순서','p.xp += b.v * M.xp * D.xp * (if truthy(opts.xpMul) then opts.xpMul else 1)','p.xp += b.v * (M.xp * D.xp) * (if truthy(opts.xpMul) then opts.xpMul else 1)'],
  ['선택지 설명 글의 번호 (lv[l+1] → lv[l])','desc = w.lv[l + 1], tag = "무기 강화"','desc = w.lv[l], tag = "무기 강화"'],
  ['이벤트 칸 하나 빠뜨림 (kill 의 seed)','type = e.type, seed = e.seed, sc = e.sc','type = e.type, sc = e.sc'],
  ['넉백 감쇠 exp(-7dt) → exp(-7.000001dt)','local dec = exp(-7 * dt)','local dec = exp(-7.000001 * dt)'],
  ['개찰구에서 runner 조건 (e.st == 3 빠뜨림)','(ty ~= "runner" or e.st == 0 or e.st == 3)','(ty ~= "runner" or e.st == 0)'],
];
async function sectionMut(){
  log('\n[mut] 검사 도구의 민감도: Sim.luau 사본을 한 군데씩 일부러 틀리게 고치면 견줌이 잡아내는가');
  prepareSoft();
  const base=fs.readFileSync(path.join(WORK,'SimSoft.luau'),'utf8');
  /* 짧은 판 몇 개: 보통 · 혼잡 100초씩, 개찰구 걷기, 선택지를 손으로 고르는 판, 장비를 다 갖춘 판, 김 팀장 */
  const cov=SC.coverage();
  const specs=[1,2].map(d=>{const g=SC.fullGame(424242+d,d);g.name='mut.'+g.name;g.steps=[{op:'run',ticks:6000,input:'bot'}];g.digestEvery=30;return g;})
    .concat(cov.filter(s=>['gates.walk','items.rng','evo','w.card.3','all.z0','all.z5','boss.lead'].includes(s.name)).map(s=>Object.assign({},s,{name:'mut.'+s.name})));
  const js=await runJS(specs,true);
  const same=(lu)=>specs.every(s=>{const a=js.jobs.get(s.name)||[],b=lu.jobs.get(s.name)||[];return a.length>0&&a.length===b.length&&a.every((l,i)=>l===b[i]);});
  const ref=await runLuau(specs,{soft:true});
  const refOk=same(ref)&&!ref.err;
  const rows=await Promise.all(MUTATIONS.map(async ([name,from,to,subtle],i)=>{
    if(!base.includes(from))return {name,found:false,subtle};
    const f='SimMut'+i+'.luau';fs.writeFileSync(path.join(WORK,f),base.replace(from,()=>to));
    const lu=await runLuau(specs,{soft:true,simPath:'../SimMut'+i});
    fs.rmSync(path.join(WORK,f),{force:true});
    let where='';for(const s of specs){const a=js.jobs.get(s.name)||[],b=lu.jobs.get(s.name)||[];const c=compareExact(a,b);if(!c.ok){where=s.name+' '+c.why.slice(0,90);break;}}
    return {name,found:true,caught:!same(lu),where,err:lu.err,subtle};
  }));
  for(const r of rows)note('    '+(r.found?(r.caught?'잡음   ':'못 잡음 '):'자리 없음 ')+r.name+(r.subtle?' [드문 경우에만: '+r.subtle+']':'')+(r.where?'  → '+r.where:'')+(r.err?'  (Luau 오류: '+r.err.slice(0,100)+')':''));
  const must=rows.filter(r=>!r.subtle),rare=rows.filter(r=>r.subtle),missing=rows.filter(r=>!r.found);
  const caught=must.filter(r=>r.found&&r.caught).length;
  result('mut: 고치지 않은 사본은 원본과 같다 (기준)',refOk,ref.err?ref.err.slice(0,200):'');
  result('mut: 일부러 틀리게 고친 '+must.length+'가지를 모두 잡아낸다 (짧은 시나리오 '+specs.length+'개만으로)',caught===must.length&&missing.length===0,caught+'/'+must.length+(missing.length?' · 고칠 자리를 못 찾음: '+missing.map(r=>r.name).join(', '):'')+(must.some(r=>r.found&&!r.caught)?' · 못 잡은 것: '+must.filter(r=>r.found&&!r.caught).map(r=>r.name).join(', '):''));
  log('  참고  아주 드문 경우에만 결과가 달라지는 변형 '+rare.length+'가지 ('+rare.map(r=>r.name+(r.caught?' = 잡음':' = 이 짧은 시나리오로는 못 잡음')).join(' · ')+')');
}

/* ---------- 4. B: 모든 갈래 ---------- */
async function sectionB(){
  log('\n[B] 모든 갈래: 무기 16종 × 1~7레벨, 조합 5종, 보스 7종 × 폭주 0~4단계, 장소 7곳, 차선 · 아이템 · 상자 · 저장/복원 · 죽음 · 승리');
  const specs=SC.coverage();
  /* (가) softmath 로 양쪽이 비트까지 같은가 */
  const {m,luErr}=await runBoth(specs,{soft:true,per:14});
  let bad=0;const firstBad=[];let ticks=0;const states={};
  for(const s of specs){const {js,lu}=m.get(s.name);const c=compareExact(js,lu);const f=finalOf(js);if(f){ticks+=f.tick;states[f.state]=(states[f.state]||0)+1;}
    const x=js.concat(lu).find(l=>l.startsWith('X '));
    if(!c.ok||x){bad++;if(firstBad.length<6)firstBad.push(s.name+' → '+(x||c.why));}
    note('    '+s.name+': '+(c.ok&&!x?'같음':'다름')+' '+(f?f.state+' zone '+f.zone+' t='+f.t.toFixed(1)+' lv'+f.level+' kills '+f.kills+' ticks '+f.tick+' '+f.build:''));}
  result('B: 시나리오 '+specs.length+'개가 원본과 비트까지 같다 (softmath)',bad===0&&!luErr,'합계 '+ticks+' tick · 끝난 모습 '+JSON.stringify(states)+(bad?' · 다른 것 '+bad+': '+firstBad.join(' ; '):'')+(luErr?' · Luau 오류: '+luErr.slice(0,400):''));
  /* (나) 고치지 않은 Sim.luau 가 오류 없이 도는가 + 밟은 줄 */
  const groups=chunk(specs,14);
  const [covs,selfCov]=await Promise.all([Promise.all(groups.map(g=>runLuau(g,{soft:false,coverage:true}))),runSelf(true)]);
  covs.push({err:'',jobs:new Map(),cov:selfCov.cov}); /* Luau 단독 검사가 밟은 줄도 합친다 */
  let errs='';let xs=0;const hits=new Map();let total=0;
  for(const c of covs){if(c.err)errs+=c.err+'\n';for(const [,ls] of c.jobs)for(const l of ls)if(l.startsWith('X ')){xs++;errs+=l+'\n';}
    if(c.cov){let inSim=false;for(const l of c.cov.split(/\r?\n/)){if(l.startsWith('SF:'))inSim=/Sim\.luau$/.test(l);else if(inSim&&l.startsWith('DA:')){const [ln,n]=l.slice(3).split(',').map(Number);hits.set(ln,(hits.get(ln)||0)+n);}}}}
  result('B: 고치지 않은 Sim.luau 가 '+specs.length+'개 시나리오를 실행 오류 없이 마친다 (원래 수학 함수)',!errs&&xs===0,errs.slice(0,600));
  const src=fs.readFileSync(SIMSRC,'utf8').split(/\r?\n/);
  const miss=[];for(const [ln,n] of [...hits].sort((a,b)=>a[0]-b[0])){total++;if(n===0)miss.push(ln);}
  /* 밟지 않아도 되는 줄:
     (1) Sim.luau 에 --@unreachable-begin / --@unreachable-end 로 표시한 가지 (원본에서도 닿지 않거나, 반올림 오차로만 닿는 곳)
     (2) JS 의 `x||1` 을 옮긴 0-가드 (`if d == 0 then d = 1`) — 두 점이 비트까지 같은 자리일 때만 탄다 */
  const tagged=new Set();{let on=false;src.forEach((l,i)=>{if(/--@unreachable-begin/.test(l))on=true;if(on)tagged.add(i+1);if(/--@unreachable-end/.test(l))on=false;});}
  const isGuard=ln=>/^\s*(d|dd|bl|n|sp) = (1|e\.spd)$/.test(src[ln-1]||'')&&/^\s*if (d|dd|bl|n|sp) == 0 then$/.test(src[ln-2]||'');
  const mTag=miss.filter(ln=>tagged.has(ln)),mGuard=miss.filter(ln=>!tagged.has(ln)&&isGuard(ln)),real=miss.filter(ln=>!tagged.has(ln)&&!isGuard(ln));
  let guardTotal=0;src.forEach((l,i)=>{if(isGuard(i+1))guardTotal++;});
  note('    밟지 않은 줄 — 표시해 둔 닿지 않는 가지('+mTag.length+'):\n        '+mTag.map(ln=>ln+': '+(src[ln-1]||'').trim()).join('\n        '));
  note('    밟지 않은 줄 — 거리 0 가드('+mGuard.length+'/'+guardTotal+'): '+mGuard.join(', '));
  note('    밟지 않은 줄 — 그 밖('+real.length+'):\n        '+real.map(ln=>ln+': '+(src[ln-1]||'').trim()).join('\n        '));
  log('  참고  실행 줄 '+total+'개 · 밟은 줄 '+(total-miss.length)+'개 · 밟지 않은 줄 '+miss.length+'개 = 표시해 둔 닿지 않는 가지 '+mTag.length+'줄 + 거리 0 가드 '+mGuard.length+'줄(가드 '+guardTotal+'개 가운데) + 그 밖 '+real.length+'줄');
  result('B: Sim.luau 의 실행 줄을 모두 밟았다 (표시해 둔 닿지 않는 가지와 거리 0 가드는 빼고)',total>1000&&real.length===0,real.length?real.length+'줄: '+real.slice(0,12).map(ln=>ln+' «'+(src[ln-1]||'').trim().slice(0,60)+'»').join(' · '):'');
}

/* ---------- 5. C: 통계 ---------- */
async function sectionC(softM){
  log('\n[C] 통계: 난이도마다 씨앗 '+NSEED+'개, 무적 아님, 봇 조종, 원래 수학 함수 (JS 와 Luau 는 잡음 때문에 판마다는 달라지고 분포가 같아야 한다)');
  const specs=gameSpecs().map(s=>Object.assign({},s,{name:'stat.'+s.name,digestEvery:600}));
  const {m,luErr}=await runBoth(specs,{soft:false,per:2});
  const stat=a=>{const n=a.length,mean=a.reduce((x,y)=>x+y,0)/n,sd=Math.sqrt(a.reduce((x,y)=>x+(y-mean)*(y-mean),0)/Math.max(1,n-1));return {n,mean,sd};};
  let ok=!luErr;const rows=[];
  for(let d=0;d<4;d++){
    const F={js:[],lu:[]};
    for(const s of specs.filter(s=>s.opts.diff===d)){const o=m.get(s.name);const a=finalOf(o.js),b=finalOf(o.lu);if(!a||!b){ok=false;continue;}F.js.push(a);F.lu.push(b);}
    const line=[];
    for(const [key,label,scale] of [['zone','도착 장소',1],['t','시간(초)',1],['level','레벨',1],['kills','처치',1]]){
      const a=stat(F.js.map(f=>f[key])),b=stat(F.lu.map(f=>f[key]));
      /* 두 평균의 차를 합친 표준오차로 나눈 값. 4 를 넘으면 분포가 다르다고 본다 */
      const se=Math.sqrt(a.sd*a.sd/a.n+b.sd*b.sd/b.n),z=se>0?Math.abs(a.mean-b.mean)/se:(a.mean===b.mean?0:99);
      if(z>4)ok=false;
      line.push(label+' JS '+a.mean.toFixed(1)+'±'+a.sd.toFixed(1)+' / Luau '+b.mean.toFixed(1)+'±'+b.sd.toFixed(1)+' (z='+z.toFixed(2)+')');}
    const won=x=>x.filter(f=>f.state==='won').length,over=x=>x.filter(f=>f.state==='over').length;
    rows.push('    난이도 '+d+' ('+SC.SIM.DIFFS[d].name+', '+F.js.length+'판): '+line.join(' · ')+' · 승리 JS '+won(F.js)+' / Luau '+won(F.lu)+' · 사망 JS '+over(F.js)+' / Luau '+over(F.lu));
  }
  rows.forEach(log);
  result('C: 난이도 4단의 평균(도착 장소 · 시간 · 레벨 · 처치)이 JS 와 Luau 에서 통계적으로 같다 (|z|≤4)',ok,luErr?luErr.slice(0,300):'');
  if(softM){
    /* 같은 씨앗의 softmath 판(A)은 판마다 결과가 완전히 같다 — 요약 표 */
    const rows2=[];for(let d=0;d<4;d++){const fs_=softM.specs.filter(s=>s.opts.diff===d).map(s=>finalOf(softM.m.get(s.name).js)).filter(Boolean);
      const st=k=>{const a=stat(fs_.map(f=>f[k]));return a.mean.toFixed(1)+'±'+a.sd.toFixed(1);};
      rows2.push('    (softmath, 양쪽 동일) 난이도 '+d+': 도착 장소 '+st('zone')+' · 시간 '+st('t')+' · 레벨 '+st('level')+' · 처치 '+st('kills')+' · 승리 '+fs_.filter(f=>f.state==='won').length+'/'+fs_.length);}
    rows2.forEach(log);
  }
}

/* ---------- 6. 속도 ---------- */
async function sectionPerf(){
  log('\n[perf] update 한 번에 걸리는 시간 (적 300~450명, 무기 5종 · 장비 5종, 무적, 봇 조종)');
  const dir=path.join(WORK,'perf');fs.mkdirSync(dir,{recursive:true});
  fs.writeFileSync(path.join(dir,'main.luau'),'local perf = require("../../luau/perf")\nperf(require("../../../../src/shared/Sim"))\n');
  const rows=[];let ok=true;
  for(const [label,argv] of [['luau -O2 (해석기)',['-O2','main.luau']],['luau -O2 --codegen (네이티브)',['-O2','--codegen','main.luau']]]){
    const r=await exec(LUAU,argv,dir);
    const line=(r.out.split(/\r?\n/).find(l=>l.startsWith('PERF '))||'').slice(5);
    if(!line||r.err.trim()){ok=false;rows.push('    '+label+': 실패 '+(r.err||r.out).slice(0,300));}else rows.push('    '+label+': '+line);
  }
  fs.rmSync(dir,{recursive:true,force:true});
  /* 견줄 값: 원본 JS (node) */
  {const r=await exec(process.execPath,[path.join(HERE,'js','perf.cjs')],HERE);const line=(r.out.split(/\r?\n/).find(l=>l.startsWith('PERF '))||'').slice(5);rows.push('    원본 JS (node '+process.version+'): '+(line||'실패 '+r.err.slice(0,200)));}
  rows.forEach(log);
  result('perf: 측정을 마쳤다',ok);
}

/* ---------- 7. Lua 쪽에만 있는 것 ---------- */
async function runSelf(coverage){
  const dir=path.join(WORK,coverage?'selfcov':'self');fs.mkdirSync(dir,{recursive:true});
  fs.writeFileSync(path.join(dir,'main.luau'),'local t = require("../../luau/selftest")\nt(require("../../../../src/shared/Sim"))\n');
  const r=await slot(()=>exec(LUAU,coverage?['-O2','--coverage','main.luau']:['-O2','--codegen','main.luau'],dir));
  const cf=path.join(dir,'coverage.out');r.cov=coverage&&fs.existsSync(cf)?fs.readFileSync(cf,'utf8'):null;
  fs.rmSync(dir,{recursive:true,force:true});
  return r;
}
async function sectionSelf(){
  log('\n[self] Lua 쪽에만 있는 것: 순서 목록(wOrder · pOrder · fOrder · dmgOrder), 순서 목록 없는 복원, syncOrder, math.random 기본값');
  const r=await runSelf(false);
  const lines=r.out.split(/\r?\n/).filter(Boolean);
  const fails=lines.filter(l=>l.startsWith('FAIL')),oks=lines.filter(l=>l.startsWith('ok'));
  fails.forEach(l=>log('    '+l));
  result('self: Luau 단독 검사 '+oks.length+'개',r.code===0&&!r.err.trim()&&fails.length===0&&oks.length>0,(r.err||'').slice(0,400));
}

/* ---------- 실행 ---------- */
const t0=Date.now();
log('출근길 서바이벌 — 규칙 견줌 검사 ('+new Date().toISOString()+')');
log('원본 '+path.relative(ROOT,path.join(ROOT,'commute-survival','js','sim.js'))+'  ↔  '+path.relative(ROOT,SIMSRC)+'   · 동시에 '+JOBS+'개 · node '+process.version);
if(!fs.existsSync(LUAU)){console.error('luau.exe 가 없습니다: '+LUAU);process.exit(2);}
let softM=null;
try{
  if(want('math'))await sectionMath();
  if(want('static'))await sectionStatic();
  if(want('self'))await sectionSelf();
  if(want('A'))softM=await sectionA();
  if(want('mut'))await sectionMut();
  if(want('Anative'))await sectionAnative();
  if(want('B'))await sectionB();
  if(want('C'))await sectionC(softM);
  if(want('perf'))await sectionPerf();
}catch(e){result('검사 도구가 끝까지 돌았다',false,String(e&&e.stack||e).slice(0,1500));}
const fails=results.filter(r=>!r.ok);
log('\n==================== 요약 ====================');
for(const r of results)log((r.ok?'PASS  ':'FAIL  ')+r.name);
log('----------------------------------------------');
log((fails.length?'FAIL':'PASS')+'  — '+(results.length-fails.length)+'/'+results.length+' 통과 · '+((Date.now()-t0)/1000).toFixed(0)+'초');
fs.writeFileSync(path.join(WORK,'report.txt'),report.join('\n')+'\n');
process.exit(fails.length?1:0);
