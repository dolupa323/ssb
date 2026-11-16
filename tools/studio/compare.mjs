// 원본 웹게임과 로블록스(ssb Studio 창)를 같은 상태로 만들어 장면마다 나란히 찍는다.
//  웹: 화면 없는 Chrome + 원본의 window.__dbg.  로블록스: Studio MCP + src/client/DebugHook.client.luau(ReplicatedStorage.SsbDebug).
//  결과: tools/studio/shots/cmp/<장면>.png (위 = 원본 웹 · 아래 = 로블록스)
//   node tools/studio/compare.mjs [장면 이름의 앞 글자로 거르기 …]
//  주의: Studio 조작은 플레이스 128125794321191(ssb)인 창에만 보낸다. 그 창이 없으면 아무것도 하지 않는다.
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..", "..");
const OUT = path.join(HERE, "shots", "cmp");
const RAW = path.join(OUT, "raw");
const SSB_PLACE = 128125794321191;
const only = process.argv.slice(2);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
fs.mkdirSync(RAW, { recursive: true });

// ---------- Studio MCP ----------
const mcp = spawn("cmd.exe", ["/c", path.join(process.env.LOCALAPPDATA, "Roblox", "mcp.bat")], { stdio: ["pipe", "pipe", "ignore"] });
let mbuf = "";
const mwait = new Map();
mcp.stdout.on("data", (d) => {
	mbuf += d.toString("utf8");
	let i;
	while ((i = mbuf.indexOf("\n")) >= 0) {
		const line = mbuf.slice(0, i).trim();
		mbuf = mbuf.slice(i + 1);
		if (!line) continue;
		try {
			const m = JSON.parse(line);
			if (m.id !== undefined && mwait.has(m.id)) {
				mwait.get(m.id)(m);
				mwait.delete(m.id);
			}
		} catch {}
	}
});
let mid = 1;
const mrpc = (method, params, timeout = 120000) =>
	new Promise((res, rej) => {
		const id = mid++;
		const t = setTimeout(() => rej(new Error("MCP 시간 초과 " + method)), timeout);
		mwait.set(id, (m) => {
			clearTimeout(t);
			res(m);
		});
		mcp.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
	});
await mrpc("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "ssb-compare", version: "1" } });
mcp.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized", params: {} }) + "\n");
const studios = JSON.parse((await mrpc("tools/call", { name: "list_roblox_studios", arguments: {} })).result.content[0].text).studios;
const mine = studios.filter((s) => s.placeId === SSB_PLACE);
if (mine.length !== 1) {
	console.log("ssb 창을 찾지 못했다 — 멈춘다:", studios.map((s) => s.name).join(" / "));
	process.exit(1);
}
const STUDIO = mine[0].id;
async function tool(name, args) {
	const r = await mrpc("tools/call", { name, arguments: { ...args, studio_id: STUDIO } });
	if (r.error) throw new Error(name + ": " + JSON.stringify(r.error));
	return r.result.content ?? [];
}
const lit = (v) => (v === null || v === undefined ? "nil" : Array.isArray(v) ? "{" + v.map(lit).join(",") + "}" : typeof v === "object" ? "{" + Object.entries(v).map(([k, x]) => `[${JSON.stringify(k)}]=${lit(x)}`).join(",") + "}" : JSON.stringify(v));
async function rbx(cmd, ...args) {
	const code = `local f = game:GetService("ReplicatedStorage"):WaitForChild("SsbDebug", 8)\nif not f then return "SsbDebug 없음" end\nreturn f:Invoke(${[cmd, ...args].map(lit).join(", ")})`;
	const c = await tool("execute_luau", { datamodel_type: "Client", code });
	return c.map((x) => x.text ?? "").join(" ").trim();
}
const rbxKey = (key) => tool("user_keyboard_input", { datamodel_type: "Client", actions: [{ action: "keyPress", key_code: key }] });
const rbxClick = (x, y) => tool("user_mouse_input", { datamodel_type: "Client", actions: [{ action: "moveTo", x, y }, { action: "wait", wait_time_ms: 150 }, { action: "mouseButtonClick", mouse_button: "left", x, y }] });
async function rbxShot(file) {
	const c = await tool("screen_capture", { capture_id: "cmp" });
	const img = c.find((x) => x.type === "image");
	if (!img) throw new Error("화면을 받지 못했다");
	const buf = Buffer.from(img.data, "base64");
	fs.writeFileSync(file, buf);
	return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

// ---------- 웹(Chrome) ----------
const PORT = 9413;
const url = pathToFileURL(path.join(ROOT, "commute-survival", "index.html")).href + "#dbg";
const chrome = spawn("C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", ["--headless=new", `--remote-debugging-port=${PORT}`, `--user-data-dir=${path.join(HERE, "work", "chrome-profile-cmp")}`, "--no-first-run", "--no-default-browser-check", "--disable-gpu", "--force-device-scale-factor=1", "--window-size=1390,523", "--allow-file-access-from-files", "--disable-extensions", "--disable-sync", "--autoplay-policy=no-user-gesture-required", "--mute-audio", "about:blank"], { stdio: "ignore" });
let ws;
for (let i = 0; i < 60 && !ws; i++) {
	await sleep(250);
	try {
		const page = (await (await fetch(`http://127.0.0.1:${PORT}/json`)).json()).find((t) => t.type === "page");
		if (page) ws = new WebSocket(page.webSocketDebuggerUrl);
	} catch {}
}
await new Promise((r) => ws.addEventListener("open", r, { once: true }));
let cid = 0;
const cwait = new Map();
ws.addEventListener("message", (e) => {
	const m = JSON.parse(e.data);
	if (m.id && cwait.has(m.id)) {
		cwait.get(m.id)(m);
		cwait.delete(m.id);
	}
});
const csend = (method, params = {}) => new Promise((res, rej) => { const i = ++cid; cwait.set(i, (m) => (m.error ? rej(new Error(m.error.message)) : res(m.result))); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (expr) => (await csend("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true })).result.value;
const webShot = async (file) => fs.writeFileSync(file, Buffer.from((await csend("Page.captureScreenshot", { format: "png" })).data, "base64"));
const J = JSON.stringify;
// 웹 쪽의 같은 명령
function webCmd(cmd, a, b, c) {
	const pre = "(()=>{const s=window.__dbg.sim(),S=s.S,p=S.p;";
	const body = {
		god: `S.admNoPick=${a !== false};p.inv=${a !== false ? 1e9 : 0};p.hp=p.maxhp;`,
		zone: `s.dbg.enterZone(${a});p.hp=p.maxhp;`,
		boss: `s.dbg.boss(${J(a)});`,
		set: `S[${J(a)}]=${J(b)};`,
		pset: `p[${J(a)}]=${J(b)};`,
		build: `S.weapons={};S.passives={};S.fus={};S.fsrc={};S.wt={};S.mace=S.gent=S.umbQ=undefined;S.beams.length=0;for(const w of ${J(a || [])})S.weapons[w[0]]=w[1];for(const q of ${J(b || [])})S.passives[q[0]]=q[1];for(const k of ${J(c || [])}){S.fus[k]=1;S.fsrc[FUSIONS[k].a]=S.fsrc[FUSIONS[k].b]=1;}s.dbg.recalc();p.hp=p.maxhp;`,
		killgate: `if(S.gate)s.dbg.kill(S.gate,'card');`,
		die: `S.admNoPick=false;p.inv=0;p.hp=0.01;for(let i=0;i<12;i++)s.dbg.spawn('pass',p.x+i,p.y);`,
		info: `return 'state='+S.state+' zone='+S.zone+' t='+S.t.toFixed(1)+' zt='+S.zt.toFixed(1)+' lv='+p.level+' enemies='+S.enemies.length+' phase='+S.phase;`,
	}[cmd];
	if (!body) throw new Error("웹에 없는 명령 " + cmd);
	return ev(pre + body + "return 'ok';})()");
}
// 양쪽에 같은 명령
async function both(cmd, ...args) {
	const [r, w] = await Promise.all([rbx(cmd, ...args), webCmd(cmd, ...args)]);
	if (cmd === "info") console.log(`     로블록스: ${r}\n     웹      : ${w}`);
	else if (r !== "ok") console.log(`     [로블록스] ${cmd} → ${r}`);
}
const webClick = (id) => ev(`document.getElementById(${J(id)}).click();true`);
const webKey = (code, key) => ev(`window.dispatchEvent(new KeyboardEvent('keydown',{code:${J(code)},key:${J(key)},bubbles:true}));window.dispatchEvent(new KeyboardEvent('keyup',{code:${J(code)},key:${J(key)},bubbles:true}));true`);
async function rbxClickText(text) {
	const at = await rbx("find", text);
	if (!/^\d+,\d+$/.test(at)) {
		console.log(`     [로블록스] 「${text}」 단추를 찾지 못함: ${at}`);
		return false;
	}
	const [x, y] = at.split(",").map(Number);
	await rbxClick(x, y);
	return true;
}

const names = [];
let wantPause = false; // 일시정지 화면을 찍는 동안만 true
async function shot(name) {
	if (only.length && !only.some((o) => name.startsWith(o))) return;
	// Studio 창이 뒤로 가면 게임이 스스로 일시정지한다(원본도 그렇다) → 찍기 전에 풀어 둔다
	if (!wantPause && (await rbx("info")).includes("paused=true")) {
		console.log("     [로블록스] 창이 뒤로 가서 일시정지돼 있었다 — 풀고 찍는다");
		await rbxKey("P");
		await sleep(1200);
	}
	await Promise.all([rbxShot(path.join(RAW, name + "-rbx.png")), webShot(path.join(RAW, name + "-web.png"))]);
	names.push(name);
	console.log("찍음 " + name);
}
const L = (keys, lv) => keys.map((k) => [k, lv]);

try {
	// ---- 준비: 로블록스 Play · 화면 크기 맞추기 ----
	// 사용자가 그 창에서 직접 플레이 중이면 끼어들지 않는다(끝에 Play를 멈추므로 하던 판이 끊긴다)
	const state = (await tool("get_studio_state", {})).map((x) => x.text ?? "").join(" ");
	if (!/Current Studio Mode: Edit/.test(state)) {
		console.log("ssb 창이 편집 상태가 아니다(누가 플레이 중) — 아무것도 하지 않고 끝낸다: " + state.slice(0, 80));
		process.exit(2);
	}
	await tool("start_stop_play", { is_start: true });
	await sleep(9000);
	// 화면 크기는 게임에 물어본다(찍은 그림은 PNG가 아닐 수 있어 머리글로 재지 않는다)
	const vs = (await tool("execute_luau", { datamodel_type: "Client", code: `local v = workspace.CurrentCamera.ViewportSize return string.format("%dx%d", v.X, v.Y)` })).map((x) => x.text ?? "").join("");
	const mm = /(\d+)x(\d+)/.exec(vs);
	const size = { w: Number(mm[1]), h: Number(mm[2]) };
	console.log(`로블록스 화면 ${size.w}x${size.h}`);
	await csend("Emulation.setDeviceMetricsOverride", { width: size.w, height: size.h, deviceScaleFactor: 1, mobile: false });
	await csend("Page.navigate", { url });
	for (let i = 0; i < 80; i++) {
		if (await ev("document.readyState==='complete'&&!!window.__dbg&&!!window.__dbg.sim()").catch(() => false)) break;
		await sleep(100);
	}
	await ev("document.fonts.ready.then(()=>true)");
	await ev("localStorage.clear();true");
	await sleep(2500);
	await shot("01-menu");

	if (process.env.SSB_PART === "2") {
		// 2부(따로 돌린다): 패배 화면 → 새 판에서 레벨 업 카드
		await webClick("diff1");
		await webClick("btnStart");
		await rbxKey("Return");
		await sleep(2500);
		await both("die");
		await sleep(4500);
		await both("info");
		await shot("80-lose");
		await csend("Page.navigate", { url: "about:blank" });
		await sleep(200);
		await csend("Page.navigate", { url });
		for (let i = 0; i < 80; i++) {
			if (await ev("document.readyState==='complete'&&!!window.__dbg&&!!window.__dbg.sim()").catch(() => false)) break;
			await sleep(100);
		}
		await tool("start_stop_play", { is_start: false });
		await sleep(2500);
		await tool("start_stop_play", { is_start: true });
		await sleep(9000);
		await webClick("diff1");
		await webClick("btnStart");
		await rbxKey("Return");
		await sleep(3000);
		await both("pset", "xp", 1e6);
		await sleep(2000);
		await both("info");
		await shot("60-levelup");
		throw new Error("2부 끝");
	}

	// ---- 시작 ----
	await webClick("diff1");
	await webClick("btnStart");
	await rbxKey("Return");
	await sleep(1500);
	const t0 = Date.now();
	await both("god");
	console.log(`명령 한 번 왕복 ${Date.now() - t0}ms`);
	await sleep(5000);
	await both("info");
	await shot("02-start");

	// ---- 무기 16종: 5레벨(진화 전) · 7레벨(진화) ----
	await both("set", "admRate", 5);
	const G = { A: ["card", "umbrella", "backpack", "coffee"], B: ["anc", "shout", "battery", "hotpack"], C: ["scooter", "selfie", "handle", "alarm"], D: ["tie", "laptop", "gum", "shoulder"] };
	for (const [g, keys] of Object.entries(G)) {
		for (const lv of [5, 7]) {
			await both("build", L(keys, lv), [], []);
			await sleep(6500);
			await shot(`3${g}${lv}-${keys.join("+")}`);
		}
	}
	// ---- 히든 조합 5종 ----
	await both("build", [], [], ["remote", "bulldozer"]);
	await sleep(6500);
	await shot("4F1-remote+bulldozer");
	await both("build", [], [], ["gentleman", "routine", "freepass"]);
	await sleep(6500);
	await shot("4F2-gentleman+routine+freepass");
	await both("set", "admRate", 1);
	await both("build", L(["card", "backpack", "anc"], 5), L(["shoes"], 1), []);

	// ---- 버스 ----
	await both("set", "trainT", 0.2);
	await sleep(900);
	await shot("05-bus-warn");
	await sleep(700);
	await shot("06-bus-pass");

	// ---- 장소 7곳과 그곳의 보스 ----
	const ZN = ["street", "gates", "platA", "train", "platB", "esc", "office"];
	for (let i = 0; i < 7; i++) {
		if (i > 0) await both("zone", i);
		await sleep(6000);
		await shot(`1${i}-zone-${ZN[i]}`);
		if (i === 2) {
			await both("set", "trainT", 0.2);
			await sleep(1700);
			await shot("12b-train-pass");
		}
		await both("set", "zt", i === 3 ? 46 : 999);
		await sleep(7500);
		await both("info");
		await shot(`2${i}-boss-${ZN[i]}`);
	}

	// ---- 일시정지 ----
	await both("zone", 1);
	await sleep(1500);
	await webClick("btnPause");
	if (!(await rbx("info")).includes("paused=true")) await rbxKey("P");
	await sleep(1200);
	wantPause = true;
	await shot("50-pause");
	wantPause = false;
	await webClick("btnResume");
	await rbxKey("P");
	await sleep(600);

	// ---- 레벨 업 카드 ----
	await both("set", "admNoPick", false);
	await both("pset", "xp", 8);
	await sleep(1800);
	await shot("60-levelup");
	for (let k = 0; k < 4; k++) {
		await webKey("Digit1", "1");
		await rbxKey("One");
		await sleep(700);
	}
	await both("god");

	// ---- 정시 출근(승리) ----
	await both("zone", 6);
	await both("set", "zt", 999);
	await sleep(3500);
	await both("killgate");
	await sleep(4500);
	await both("info");
	await shot("70-win");

	// ---- 다시 → 멘탈 0(패배) ----
	await webClick("btnRetry");
	if (await rbxClickText("다시")) {
		await sleep(2500);
		await both("die");
		await sleep(4000);
		await both("info");
		await shot("80-lose");
	}
} catch (e) {
	console.log("중단: " + (e.stack || e));
}

// ---- 위 · 아래로 붙인 그림 만들기 ----
try {
	await tool("start_stop_play", { is_start: false });
} catch {}
for (const name of names) {
	const a = pathToFileURL(path.join(RAW, name + "-web.png")).href, b = pathToFileURL(path.join(RAW, name + "-rbx.png")).href;
	const html = `<body style="margin:0;background:#222;font:700 15px 'Malgun Gothic'"><div style="position:relative"><img src="${a}" style="display:block;width:1000px"><b style="position:absolute;left:6px;top:4px;background:#fff;color:#000;padding:1px 8px">원본(웹)</b></div><div style="position:relative;margin-top:4px"><img src="${b}" style="display:block;width:1000px"><b style="position:absolute;left:6px;top:4px;background:#ffd400;color:#000;padding:1px 8px">로블록스</b></div></body>`;
	const f = path.join(RAW, "_pair.html");
	fs.writeFileSync(f, html);
	await csend("Page.navigate", { url: pathToFileURL(f).href });
	await sleep(500);
	const hgt = await ev("document.body.scrollHeight");
	await csend("Emulation.setDeviceMetricsOverride", { width: 1000, height: hgt, deviceScaleFactor: 1, mobile: false });
	await sleep(200);
	fs.writeFileSync(path.join(OUT, name + ".png"), Buffer.from((await csend("Page.captureScreenshot", { format: "png" })).data, "base64"));
}
console.log(`끝 — ${names.length}장: ${OUT}`);
ws.close();
chrome.kill();
mcp.kill();
process.exit(0);
