// 원본 웹게임(commute-survival/index.html)을 화면 없는 Chrome에서 띄워 주어진 크기로 찍는다 — Studio에서 찍은 화면과 나란히 견주려고.
//  tools/ui/ref.mjs와 달리 바깥 통신을 막지 않는다: 원본이 쓰는 웹 글꼴(Google Fonts)이 실제로 내려와, 사람이 브라우저에서 보는 것과 같은 그림이 된다.
//   node tools/studio/orig_shot.mjs 1390x523 [menu hud levelup …]
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..", "..");
const OUT = path.join(HERE, "shots");
const CHROME = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const PORT = 9412;
const [w, h] = (process.argv[2] || "1280x720").split("x").map(Number);
const want = process.argv.slice(3);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
fs.mkdirSync(OUT, { recursive: true });

const url = pathToFileURL(path.join(ROOT, "commute-survival", "index.html")).href + "#dbg";
const proc = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`, `--user-data-dir=${path.join(HERE, "work", "chrome-profile")}`, "--no-first-run", "--no-default-browser-check", "--disable-gpu", "--force-device-scale-factor=1", `--window-size=${w},${h}`, "--allow-file-access-from-files", "--disable-extensions", "--disable-sync", "about:blank"], { stdio: "ignore" });
let ws;
for (let i = 0; i < 60 && !ws; i++) {
	await sleep(250);
	try {
		const list = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
		const page = list.find((t) => t.type === "page");
		if (page) ws = new WebSocket(page.webSocketDebuggerUrl);
	} catch {}
}
await new Promise((r) => ws.addEventListener("open", r, { once: true }));
let id = 0;
const wait = new Map();
ws.addEventListener("message", (e) => {
	const m = JSON.parse(e.data);
	if (m.id && wait.has(m.id)) {
		wait.get(m.id)(m);
		wait.delete(m.id);
	}
});
const send = (method, params = {}) => new Promise((res, rej) => { const i = ++id; wait.set(i, (m) => (m.error ? rej(new Error(m.error.message)) : res(m.result))); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (expr) => (await send("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true })).result.value;

const S = "window.__dbg.sim()";
const start = (diff) => `localStorage.clear();document.getElementById('diff${diff}').click();document.getElementById('btnStart').click();`;
const STATES = {
	menu: ["", 2500],
	hud: [start(1), 8000],
	levelup: [start(1) + `setTimeout(()=>{${S}.S.p.xp=${S}.S.p.xp+12;},3000);`, 5000],
	pause: [start(1) + `setTimeout(()=>document.getElementById('btnPause').click(),3000);`, 4500],
};
await send("Emulation.setDeviceMetricsOverride", { width: w, height: h, deviceScaleFactor: 1, mobile: false });
for (const name of want.length ? want : Object.keys(STATES)) {
	const [script, ms] = STATES[name];
	await send("Page.navigate", { url: "about:blank" });
	await sleep(150);
	await send("Page.navigate", { url });
	for (let i = 0; i < 60; i++) {
		if (await ev("document.readyState==='complete'&&!!window.__dbg&&!!window.__dbg.sim()").catch(() => false)) break;
		await sleep(100);
	}
	await ev("document.fonts.ready.then(()=>true)");
	await sleep(500);
	if (script) await ev(script + "true");
	await sleep(ms);
	const fonts = await ev("JSON.stringify([...document.fonts].filter(f=>f.status==='loaded').map(f=>f.family).filter((v,i,a)=>a.indexOf(v)===i))");
	const shot = await send("Page.captureScreenshot", { format: "png" });
	const file = path.join(OUT, `orig-${name}-${w}x${h}.png`);
	fs.writeFileSync(file, Buffer.from(shot.data, "base64"));
	console.log(`${path.basename(file)}  내려온 글꼴: ${fonts}`);
}
ws.close();
proc.kill();
process.exit(0);
