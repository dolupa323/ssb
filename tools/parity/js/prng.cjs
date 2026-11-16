'use strict';
/* 씨앗 난수 (mulberry32) — luau/prng.luau 와 비트까지 같은 값을 낸다. 부른 횟수를 센다. */
function makeRng(seed){
  let a=seed>>>0;
  const g=function(){
    g.calls++;
    a=(a+0x6D2B79F5)|0;
    let t=Math.imul(a^(a>>>15),1|a);
    t=(t+Math.imul(t^(t>>>7),61|t))^t;
    return((t^(t>>>14))>>>0)/4294967296;
  };
  g.calls=0;
  return g;
}
/* float64 → 16자리 hex (비트 그대로) */
const _f=new Float64Array(1),_u=new Uint32Array(_f.buffer);
function hex(x){_f[0]=x;return _u[1].toString(16).padStart(8,'0')+_u[0].toString(16).padStart(8,'0');}
function unhex(s){_u[1]=parseInt(s.slice(0,8),16);_u[0]=parseInt(s.slice(8,16),16);return _f[0];}
module.exports={makeRng,hex,unhex};
