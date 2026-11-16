// Studio MCP(StudioMCP.exe · stdio)를 한 번 불러 본다 — Studio가 여럿 열려 있을 때 어느 창인지 먼저 확인하고 쓰려고.
//  쓰기: node tools/studio/mcp.mjs list                      → 도구 이름
//        node tools/studio/mcp.mjs call <도구> '<JSON 인자>'  → 한 번 부른다
//  주의: 「달의 계승자」 창(플레이스 96192775933291)에는 아무것도 하지 않는다. 창을 고르는 도구가 있으면 반드시 ssb(128125794321191)를 고른 뒤에만 쓴다.
import { spawn } from "node:child_process";
import path from "node:path";

const bat = path.join(process.env.LOCALAPPDATA, "Roblox", "mcp.bat");
const child = spawn("cmd.exe", ["/c", bat], { stdio: ["pipe", "pipe", "pipe"] });
let buf = "";
const waiters = new Map();
child.stdout.on("data", (d) => {
	buf += d.toString("utf8");
	let i;
	while ((i = buf.indexOf("\n")) >= 0) {
		const line = buf.slice(0, i).trim();
		buf = buf.slice(i + 1);
		if (!line) continue;
		try {
			const m = JSON.parse(line);
			if (m.id !== undefined && waiters.has(m.id)) {
				waiters.get(m.id)(m);
				waiters.delete(m.id);
			}
		} catch {}
	}
});
child.stderr.on("data", (d) => process.stderr.write("[mcp-err] " + d.toString("utf8").slice(0, 400)));
let nextId = 1;
function rpc(method, params, timeout = 60000) {
	const id = nextId++;
	return new Promise((resolve, reject) => {
		const t = setTimeout(() => reject(new Error("시간 초과: " + method)), timeout);
		waiters.set(id, (m) => {
			clearTimeout(t);
			resolve(m);
		});
		child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
	});
}
function notify(method, params) {
	child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method, params }) + "\n");
}

try {
	const init = await rpc("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "ssb-tools", version: "1" } }, 20000);
	notify("notifications/initialized", {});
	let [cmd, tool, argJson] = process.argv.slice(2);
	if (argJson && argJson.startsWith("@")) {
		// 「@파일」이면 그 파일의 JSON을 인자로 쓴다(셸에서 따옴표가 깨지지 않게)
		argJson = (await import("node:fs")).readFileSync(argJson.slice(1), "utf8");
	}
	if (cmd === "list" || !cmd) {
		console.log("server:", JSON.stringify(init.result?.serverInfo));
		const r = await rpc("tools/list", {});
		for (const t of r.result?.tools ?? []) {
			console.log("-", t.name, "::", (t.description || "").replace(/\s+/g, " ").slice(0, 160), "| args:", Object.keys(t.inputSchema?.properties ?? {}).join(","));
		}
	} else if (cmd === "desc") {
		// 도구 하나의 설명과 인자 틀을 통째로 본다
		const r = await rpc("tools/list", {});
		const t = (r.result?.tools ?? []).find((x) => x.name === tool);
		console.log(t ? t.description + "\n" + JSON.stringify(t.inputSchema, null, 1) : "없는 도구");
	} else if (cmd === "ssb") {
		// ssb 창에만: 창 목록에서 플레이스 128125794321191인 창을 찾아 그 studio_id로 부른다. 없으면 아무것도 하지 않는다.
		const SSB = 128125794321191;
		const ls = await rpc("tools/call", { name: "list_roblox_studios", arguments: {} }, 30000);
		const studios = JSON.parse(ls.result.content[0].text).studios;
		const mine = studios.filter((s) => s.placeId === SSB);
		if (mine.length !== 1) {
			console.log(`ssb 창(플레이스 ${SSB})을 찾지 못했다 — 열린 창: ${studios.map((s) => s.name).join(" / ")}`);
		} else {
			const args = argJson ? JSON.parse(argJson) : {};
			args.studio_id = mine[0].id;
			const r = await rpc("tools/call", { name: tool, arguments: args }, 300000);
			if (r.error) console.log("ERROR", JSON.stringify(r.error));
			else for (const c of r.result?.content ?? []) {
				if (c.type === "text") console.log(c.text);
				else if (c.type === "image" && process.env.SSB_SHOT) {
					const fs = await import("node:fs");
					fs.writeFileSync(process.env.SSB_SHOT, Buffer.from(c.data, "base64"));
					console.log("[image saved] " + process.env.SSB_SHOT);
				} else console.log(`[${c.type}]`);
			}
		}
	} else if (cmd === "call") {
		const r = await rpc("tools/call", { name: tool, arguments: argJson ? JSON.parse(argJson) : {} }, 180000);
		if (r.error) console.log("ERROR", JSON.stringify(r.error));
		else for (const c of r.result?.content ?? []) console.log(c.type === "text" ? c.text : `[${c.type}]`);
	}
} catch (e) {
	console.log("실패:", e.message);
} finally {
	child.stdin.end();
	setTimeout(() => {
		child.kill();
		process.exit(0);
	}, 300);
}
