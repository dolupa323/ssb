// ssb Studio 창에서: 메뉴를 굴릴 수 있는지 · 시작 단추를 눌러 시작되는지 · 화면을 끌어 움직이는지(조이스틱)를 본다.
//  마우스로 흉내 낸다(원본도 마우스 끌기와 손가락 끌기를 같은 길로 처리한다). 진짜 손가락 여러 개는 여기서 못 넣는다.
//   node tools/studio/touchtest.mjs
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
const HERE = path.dirname(fileURLToPath(import.meta.url));
const SHOTS = path.join(HERE, "shots");
const SSB_PLACE = 128125794321191;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const mcp = spawn("cmd.exe", ["/c", path.join(process.env.LOCALAPPDATA, "Roblox", "mcp.bat")], { stdio: ["pipe", "pipe", "ignore"] });
let buf = "";
const wait = new Map();
mcp.stdout.on("data", (d) => {
	buf += d.toString("utf8");
	let i;
	while ((i = buf.indexOf("\n")) >= 0) {
		const line = buf.slice(0, i).trim();
		buf = buf.slice(i + 1);
		try {
			const m = JSON.parse(line);
			if (m.id !== undefined && wait.has(m.id)) { wait.get(m.id)(m); wait.delete(m.id); }
		} catch {}
	}
});
let id = 1;
const rpc = (method, params) => new Promise((res) => { const i = id++; wait.set(i, res); mcp.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: i, method, params }) + "\n"); });
await rpc("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "ssb-touch", version: "1" } });
mcp.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized", params: {} }) + "\n");
const studios = JSON.parse((await rpc("tools/call", { name: "list_roblox_studios", arguments: {} })).result.content[0].text).studios.filter((s) => s.placeId === SSB_PLACE);
if (studios.length !== 1) { console.log("ssb 창 없음"); process.exit(1); }
const tool = async (name, args) => { const r = await rpc("tools/call", { name, arguments: { ...args, studio_id: studios[0].id } }); return r.error ? [{ text: "ERROR " + JSON.stringify(r.error) }] : r.result.content ?? []; };
const lit = (v) => JSON.stringify(v);
const dbg = async (cmd, ...a) => (await tool("execute_luau", { datamodel_type: "Client", code: `local f = game:GetService("ReplicatedStorage"):WaitForChild("SsbDebug", 8) if not f then return "SsbDebug 없음" end return f:Invoke(${[cmd, ...a].map(lit).join(", ")})` })).map((x) => x.text ?? "").join(" ").trim();
const mouse = (actions) => tool("user_mouse_input", { datamodel_type: "Client", actions });
const shot = async (name) => { const c = await tool("screen_capture", { capture_id: "t" }); const img = c.find((x) => x.type === "image"); if (img) fs.writeFileSync(path.join(SHOTS, name), Buffer.from(img.data, "base64")); };

await tool("start_stop_play", { is_start: true });
await sleep(9000);
console.log("화면:", (await tool("execute_luau", { datamodel_type: "Client", code: `local v = workspace.CurrentCamera.ViewportSize local u = game:GetService("UserInputService") return string.format("%dx%d touch=%s keyboard=%s mouse=%s preferred=%s", v.X, v.Y, tostring(u.TouchEnabled), tostring(u.KeyboardEnabled), tostring(u.MouseEnabled), tostring(u.PreferredInput))` })).map((x) => x.text).join(""));
// 1) 메뉴: 시작 단추가 화면 안에 있는가 → 없으면 굴려서 찾는다
let at = await dbg("find", "출근");
console.log("메뉴의 시작 단추(굴리기 전):", at);
await mouse([{ action: "moveTo", x: 360, y: 300 }, { action: "scrollDown", x: 360, y: 300 }, { action: "wait", wait_time_ms: 200 }, { action: "scrollDown" }, { action: "wait", wait_time_ms: 200 }, { action: "scrollDown" }, { action: "wait", wait_time_ms: 200 }, { action: "scrollDown" }, { action: "wait", wait_time_ms: 200 }, { action: "scrollDown" }]);
await sleep(600);
at = await dbg("find", "출근");
console.log("메뉴의 시작 단추(굴린 뒤):", at);
await shot("touch-menu-scrolled.jpg");
// 2) 시작 단추를 눌러 시작
if (/^\d+,\d+$/.test(at)) {
	const [x, y] = at.split(",").map(Number);
	await mouse([{ action: "moveTo", x, y }, { action: "wait", wait_time_ms: 150 }, { action: "mouseButtonClick", mouse_button: "left", x, y }]);
	await sleep(2500);
}
let st = await dbg("info");
console.log("시작 단추를 누른 뒤:", st.slice(0, 40));
if (!st.includes("mode=play")) {
	// 마우스 누르기가 먹지 않았으면 Enter로 시작해서 나머지를 본다
	await tool("user_keyboard_input", { datamodel_type: "Client", actions: [{ action: "keyPress", key_code: "Return" }] });
	await sleep(2500);
	st = await dbg("info");
	console.log("Enter로 시작한 뒤:", st.slice(0, 40));
}
await dbg("god");
// 3) 화면을 끌어서 움직이기(조이스틱): 오른쪽으로 70픽셀 끌고 1.5초 유지
const a = await dbg("info");
await mouse([{ action: "moveTo", x: 900, y: 300 }, { action: "wait", wait_time_ms: 100 }, { action: "mouseButtonDown", mouse_button: "left", x: 900, y: 300 }, { action: "wait", wait_time_ms: 150 }, { action: "moveTo", x: 930, y: 300 }, { action: "wait", wait_time_ms: 100 }, { action: "moveTo", x: 970, y: 300 }, { action: "wait", wait_time_ms: 800 }]);
await shot("touch-joystick.jpg");
await mouse([{ action: "wait", wait_time_ms: 700 }, { action: "mouseButtonUp", mouse_button: "left", x: 970, y: 300 }]);
const b = await dbg("info");
console.log("끌기 전:", a.replace(/.*(x=\S+ y=\S+).*/, "$1"), "→ 끈 뒤:", b.replace(/.*(x=\S+ y=\S+).*/, "$1"));
// 4) 단추 누르기: 대시 · 일시정지. find가 준 좌표는 위쪽 띠(58)를 더한 것 — 도구의 좌표가 어느 쪽인지 몰라 둘 다 눌러 본다
async function press(text, pick) {
	const at = await dbg("find", text);
	if (!/^\d+,\d+$/.test(at)) return console.log(`「${text}」 단추 없음: ${at}`);
	const [x, y0] = at.split(",").map(Number);
	for (const [label, y] of [["띠를 뺀 좌표", y0 - 58], ["띠를 더한 좌표", y0]]) {
		const before = pick(await dbg("info"));
		await mouse([{ action: "moveTo", x, y }, { action: "wait", wait_time_ms: 200 }, { action: "mouseButtonClick", mouse_button: "left", x, y }, { action: "wait", wait_time_ms: 300 }]);
		await sleep(600);
		const after = pick(await dbg("info"));
		console.log(`「${text}」 단추 (${x},${y} · ${label}): ${before} → ${after}`);
		if (before !== after) return true;
	}
	return false;
}
await sleep(2800); // 대시 대기 시간이 지나게
await press("대시", (s) => s.replace(/.*(dashes=\d+).*/, "$1"));
if (await press("일시정지", () => "")) {
}
await sleep(500);
await shot("touch-pause.jpg");
await tool("start_stop_play", { is_start: false });
mcp.kill();
process.exit(0);
