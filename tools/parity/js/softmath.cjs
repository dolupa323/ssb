'use strict';
/* 견줌용 수학 함수 — luau/softmath.luau 와 "같은 순서의 +,-,*,/" 만으로 쓴 sin/cos/atan2/exp/pow.
   IEEE 사칙연산은 JS(V8)와 Luau 가 비트까지 같으므로, 양쪽이 이 함수를 쓰면 게임 전체가 비트까지 같아진다.
   (V8 의 Math.sin 등과 MSVC 의 sin 등은 마지막 비트가 가끔 다르다 — 그것을 없애려는 것.)
   식은 fdlibm 의 것을 단순하게 줄였다. 정확도는 1e-15 안팎이면 충분하다. */
const floor=Math.floor;
const INV_PIO2=0.6366197723675814,PIO2_1=1.5707963267341256,PIO2_2=6.077100506303966e-11,PIO2_3=2.0222662487111665e-21;
const S1=-0.16666666666666632,S2=0.00833333333332249,S3=-0.0001984126982985795,S4=0.0000027557313707070068,S5=-2.5050760253406863e-8,S6=1.58969099521155e-10;
const C1=0.0416666666666666,C2=-0.001388888888887411,C3=0.00002480158728947673,C4=-2.7557314351390663e-7,C5=2.087572321298175e-9,C6=-1.1359647557788195e-11;
const AH0=0.4636476090008061,AH1=0.7853981633974483,AH2=0.982793723247329,AH3=1.5707963267948966;
const AL0=2.2698777452961687e-17,AL1=3.061616997868383e-17,AL2=1.3903311031230998e-17,AL3=6.123233995736766e-17;
const T0=0.3333333333333293,T1=-0.19999999999876483,T2=0.14285714272503466,T3=-0.11111110405462356,T4=0.09090887133436507,T5=-0.0769187620504483,T6=0.06661073137387531,T7=-0.058335701337905735,T8=0.049768779946159324,T9=-0.036531572744216916,T10=0.016285820115365782;
const PI=3.141592653589793,PIO2=1.5707963267948966,PI_LO=1.2246467991473532e-16;
const LN2HI=0.6931471803691238,LN2LO=1.9082149292705877e-10,INVLN2=1.4426950408889634;
const P1=0.16666666666666602,P2=-0.0027777777777015593,P3=0.00006613756321437934,P4=-0.0000016533902205465252,P5=4.1381367970572385e-8;
const TINY=1.862645149230957e-9,BIG=7.378697629483821e19;

function ksin(r){
  const z=r*r;
  const v=z*r;
  const rr=S2+z*(S3+z*(S4+z*(S5+z*S6)));
  return r+v*(S1+z*rr);
}
function kcos(r){
  const z=r*r;
  const rr=z*(C1+z*(C2+z*(C3+z*(C4+z*(C5+z*C6)))));
  return 1-(0.5*z-z*rr);
}
function sin(x){
  if(x!==x||x===Infinity||x===-Infinity)return NaN;
  if(x===0)return x;
  const n=floor(x*INV_PIO2+0.5);
  const r=((x-n*PIO2_1)-n*PIO2_2)-n*PIO2_3;
  const q=n-4*floor(n/4);
  if(q===0)return ksin(r);
  if(q===1)return kcos(r);
  if(q===2)return -ksin(r);
  return -kcos(r);
}
function cos(x){
  if(x!==x||x===Infinity||x===-Infinity)return NaN;
  const n=floor(x*INV_PIO2+0.5);
  const r=((x-n*PIO2_1)-n*PIO2_2)-n*PIO2_3;
  const q=n-4*floor(n/4);
  if(q===0)return kcos(r);
  if(q===1)return -ksin(r);
  if(q===2)return -kcos(r);
  return ksin(r);
}
function atan(x){
  if(x!==x)return NaN;
  const neg=x<0;
  if(neg)x=-x;
  let id;
  if(x<0.4375){
    if(x<TINY)return neg?-x:x;
    id=-1;
  }else if(x<1.1875){
    if(x<0.6875){id=0;x=(2*x-1)/(2+x);}
    else{id=1;x=(x-1)/(x+1);}
  }else if(x<2.4375){id=2;x=(x-1.5)/(1+1.5*x);}
  else if(x>BIG)return neg?-AH3:AH3;
  else{id=3;x=-1/x;}
  const z=x*x;
  const w=z*z;
  const s1=z*(T0+w*(T2+w*(T4+w*(T6+w*(T8+w*T10)))));
  const s2=w*(T1+w*(T3+w*(T5+w*(T7+w*T9))));
  let r;
  if(id<0)r=x-x*(s1+s2);
  else if(id===0)r=AH0-((x*(s1+s2)-AL0)-x);
  else if(id===1)r=AH1-((x*(s1+s2)-AL1)-x);
  else if(id===2)r=AH2-((x*(s1+s2)-AL2)-x);
  else r=AH3-((x*(s1+s2)-AL3)-x);
  return neg?-r:r;
}
function atan2(y,x){
  if(x!==x||y!==y)return NaN;
  if(y===0){
    if(x>0||(x===0&&1/x>0))return y;
    return 1/y>0?PI:-PI;
  }
  if(x===0)return y>0?PIO2:-PIO2;
  let q=y/x;
  if(q<0)q=-q;
  const z=atan(q);
  if(x>0)return y>0?z:-z;
  return y>0?PI-(z-PI_LO):(z-PI_LO)-PI;
}
function exp(x){
  if(x!==x)return NaN;
  if(x>709.782712893384)return Infinity;
  if(x<-745.1332191019411)return 0;
  const k=floor(x*INVLN2+0.5);
  const hi=x-k*LN2HI;
  const lo=k*LN2LO;
  const r=hi-lo;
  const t=r*r;
  const c=r-t*(P1+t*(P2+t*(P3+t*(P4+t*P5))));
  const y=1-((lo-(r*c)/(2-c))-hi);
  if(k===0)return y;
  let p=1;
  if(k>0){for(let i=0;i<k;i++)p=p*2;}
  else{for(let i=0;i<-k;i++)p=p*0.5;}
  return y*p;
}
/* 게임은 정수 지수만 쓴다 (x^2, 1.16^n) */
function pow(x,y){
  if(y!==floor(y)||y>1024||y<-1024)throw new Error('softmath.pow: 정수 지수만 지원 ('+y+')');
  let n=y<0?-y:y;
  let r=1,b=x;
  while(n>0){
    if(n-2*floor(n/2)===1)r=r*b;
    n=floor(n/2);
    if(n>0)b=b*b;
  }
  return y<0?1/r:r;
}
module.exports={sin,cos,atan2,exp,pow};
