// 화면 없는 Chrome을 띄우고 DevTools 프로토콜로 조종한다 (npm 없이 node 내장 기능만 쓴다)
import { spawn } from 'node:child_process';
import fs from 'node:fs';

const sleep = ms => new Promise(r => setTimeout(r, ms));

export async function launch({ chrome, port, userDataDir, url, log = () => {} }) {
  fs.mkdirSync(userDataDir, { recursive: true });
  const args = [
    '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${userDataDir}`,
    '--no-first-run', '--no-default-browser-check', '--disable-gpu', '--force-device-scale-factor=1',
    '--window-size=1280,800', '--allow-file-access-from-files',
    // 바깥으로 아무것도 보내지 않게 한다
    '--disable-background-networking', '--disable-component-update', '--disable-sync', '--disable-default-apps',
    '--disable-extensions', '--disable-client-side-phishing-detection', '--disable-domain-reliability', '--no-pings',
    '--metrics-recording-only', '--disable-features=OptimizationHints,MediaRouter,Translate,AutofillServerCommunication',
    '--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE 127.0.0.1',
    url,
  ];
  const proc = spawn(chrome, args, { stdio: 'ignore' });
  let target = null;
  for (let i = 0; i < 100 && !target; i++) {
    await sleep(150);
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      target = list.find(t => t.type === 'page' && t.url.startsWith('file:'));
    } catch (e) { /* 아직 안 떴다 */ }
  }
  if (!target) { proc.kill(); throw new Error('Chrome DevTools에 붙지 못했습니다 (포트 ' + port + ')'); }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = e => rej(new Error('websocket: ' + (e.message || e.type))); });
  let seq = 0; const waits = new Map();
  ws.onmessage = m => {
    const d = JSON.parse(typeof m.data === 'string' ? m.data : Buffer.from(m.data).toString('utf8'));
    if (d.id && waits.has(d.id)) { const w = waits.get(d.id); waits.delete(d.id); d.error ? w.rej(new Error(d.error.message)) : w.res(d.result); }
    else if (d.method === 'Runtime.exceptionThrown') log('[page exception] ' + (d.params.exceptionDetails.exception?.description || d.params.exceptionDetails.text));
    else if (d.method === 'Runtime.consoleAPICalled') log('[page ' + d.params.type + '] ' + d.params.args.map(a => a.value ?? a.description ?? '').join(' '));
  };
  const send = (method, params = {}) => new Promise((res, rej) => { const id = ++seq; waits.set(id, { res, rej }); ws.send(JSON.stringify({ id, method, params })); });
  await send('Runtime.enable');
  // 식을 페이지에서 돌리고 값을 돌려받는다 (Promise면 끝날 때까지 기다린다)
  const evaluate = async expression => {
    const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) throw new Error('page: ' + (r.exceptionDetails.exception?.description || r.exceptionDetails.text));
    return r.result.value;
  };
  const close = async () => { try { await send('Browser.close'); } catch (e) { /* 이미 닫혔다 */ } try { ws.close(); } catch (e) { } await sleep(200); try { proc.kill(); } catch (e) { } };
  return { evaluate, send, close };
}
