// 세계 그리기(Gfx) 장면 시험: 같은 장면을 (가) 우리 Luau 코드 + mock, (나) 원본 gfx.js + 화면 없는 Chrome으로 찍는다.
//   node tools/world/run.mjs [--only 이름,이름…] [--viewport 1280x720,844x390] [--no-orig] [--no-mock] [--timeout 초]
// 찍힌 화면: tools/world/shots/<화면 크기>/<장면>.<이름>.png (우리 것) · <장면>.<이름>.orig.png (원본)
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { luaValue } from "../mock/bundle.mjs";
import { SCENES } from "./scenes.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..", "..");
const CHROME = ["C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"].find((p) => fs.existsSync(p));
const args = process.argv.slice(2);
const opt = { only: null, viewports: ["1280x720"], orig: true, mock: true, timeout: 900 };
for (let i = 0; i < args.length; i++) {
	const a = args[i];
	if (a === "--only") opt.only = args[++i].split(",");
	else if (a === "--viewport") opt.viewports = args[++i].split(",");
	else if (a === "--no-orig") opt.orig = false;
	else if (a === "--no-mock") opt.mock = false;
	else if (a === "--timeout") opt.timeout = Number(args[++i]);
	else throw new Error("모르는 옵션: " + a);
}
const work = path.join(HERE, "work");
fs.mkdirSync(path.join(work, "orig"), { recursive: true });
const driver = fs.readFileSync(path.join(HERE, "driver.luau"), "utf8");
let failed = 0;
for (const scene of SCENES) {
	if (opt.only && !opt.only.some((n) => scene.name === n || scene.name.startsWith(n))) continue;
	for (const vp of opt.viewports) {
		const shotDir = path.join(HERE, "shots", vp);
		fs.mkdirSync(shotDir, { recursive: true });
		if (opt.mock) {
			const file = path.join(work, scene.name + ".luau");
			fs.writeFileSync(file, "local SPEC = " + luaValue(scene) + "\n" + driver);
			const t0 = Date.now();
			const r = spawnSync(
				process.execPath,
				[path.join(ROOT, "tools", "mock", "run.mjs"), "--project", path.join(HERE, "world.project.json"), "--viewport", vp, "--script", file, "--shot-dir", shotDir, "--timeout", String(opt.timeout), "--no-core-overlay"],
				{ cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
			);
			const out = (r.stdout || "") + (r.stderr || "");
			const lines = out.split(/\r?\n/).filter((l) => l.trim() && !/^화면: /.test(l));
			console.log(`\n=== ${scene.name} @ ${vp} (mock, ${((Date.now() - t0) / 1000).toFixed(1)}초, 끝 코드 ${r.status}) ===`);
			console.log(lines.slice(-40).join("\n"));
			// mock의 화면 찍기는 Chrome 프로필 하나를 같이 써서, 다른 작업이 동시에 mock을 돌리면 실패하곤 한다.
			// mock이 남긴 HTML(tools/mock/out/shots/<이름>.html)을 우리 프로필로 다시 찍는다.
			let missing = 0;
			for (const st of scene.steps) {
				if (st.op !== "shot") continue;
				const base = `${scene.name}.${st.name}`;
				const png = path.join(shotDir, base + ".png");
				const html = path.join(ROOT, "tools", "mock", "out", "shots", base + ".html");
				const fresh = fs.existsSync(png) && fs.statSync(png).mtimeMs >= t0;
				if (fresh || !fs.existsSync(html) || fs.statSync(html).mtimeMs < t0) {
					if (!fresh) missing++;
					continue;
				}
				const [vw, vh] = vp.split("x");
				spawnSync(
					CHROME,
					[
						"--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run", "--no-default-browser-check", "--disable-extensions", "--disable-background-networking",
						"--disable-component-update", "--disable-sync", "--disable-default-apps", "--disable-domain-reliability", "--no-pings", "--metrics-recording-only", "--allow-file-access-from-files",
						"--host-resolver-rules=MAP * ~NOTFOUND", "--force-device-scale-factor=1", `--user-data-dir=${path.join(work, "chrome-profile-mock")}`, `--window-size=${vw},${vh}`,
						"--virtual-time-budget=3000", `--screenshot=${png}`, pathToFileURL(html).href,
					],
					{ encoding: "utf8", timeout: 180000 },
				);
				if (!fs.existsSync(png) || fs.statSync(png).mtimeMs < t0) missing++;
				else console.log(`  (다시 찍음: ${base}.png)`);
			}
			const m = /오류 (\d+) · 경고 (\d+)/.exec(out);
			const bad = !m || Number(m[1]) > 0 || /확인 실패|실패 [1-9]|[1-9]\d*개 실패/.test(out) || missing > 0;
			if (missing) console.log(`  찍지 못한 화면 ${missing}장`);
			if (bad) failed++;
		}
		if (opt.orig && !scene.noOrig) {
			const [w, h] = vp.split("x").map(Number);
			const rel = (p) => pathToFileURL(path.join(ROOT, p)).href;
			// 한 번 돌려 모든 장면을 세로로 긴 그림 한 장에 담고(큰 캔버스), 그것을 잘라 나눈다
			const shots = scene.steps.filter((st) => st.op === "shot");
			if (shots.length) {
				const html = path.join(work, "orig", `${scene.name}.${vp}.html`);
				fs.writeFileSync(
					html,
					`<!doctype html><meta charset="utf-8"><title>run</title><style>html,body{margin:0;overflow:hidden;background:#000}canvas#cv{position:fixed;left:0;top:0;width:${w}px;height:${h}px;display:block}</style><canvas id="cv"></canvas>
<script>window.SPEC=${JSON.stringify(scene)};window.SHOT=null;</script>
<script src="${rel("commute-survival/js/sim.js")}"></script><script src="${rel("commute-survival/js/gfx.js")}"></script><script src="${rel("tools/world/orig/driver.js")}"></script>`,
				);
				const tall = path.join(work, "orig", `${scene.name}.${vp}.all.png`);
				if (fs.existsSync(tall)) fs.rmSync(tall);
				const r = spawnSync(
					CHROME,
					[
						"--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run", "--no-default-browser-check", "--disable-extensions",
						// 바깥으로 나가는 것을 모두 막는다 — 로컬 파일만 연다
						"--disable-background-networking", "--disable-component-update", "--disable-sync", "--disable-default-apps", "--disable-domain-reliability", "--no-pings",
						"--metrics-recording-only", "--allow-file-access-from-files", "--host-resolver-rules=MAP * ~NOTFOUND", "--force-device-scale-factor=1",
						`--user-data-dir=${path.join(work, "chrome-profile")}`, `--window-size=${w},${h * shots.length}`, "--virtual-time-budget=2000", `--screenshot=${tall}`, pathToFileURL(html).href,
					],
					{ encoding: "utf8", timeout: 600000 },
				);
				if (!fs.existsSync(tall)) {
					console.log(`원본을 찍지 못했다 (${scene.name}): ${(r.stderr || "").slice(0, 300)}`);
					failed++;
				} else {
					const names = shots.map((st) => path.join(shotDir, `${scene.name}.${st.name}.orig.png`));
					const sp = spawnSync("python", [path.join(HERE, "split.py"), tall, String(h), ...names], { encoding: "utf8" });
					console.log(`원본: ${scene.name} ${shots.length}장 (${(sp.stdout || "").trim()}${sp.status ? " · 자르기 실패 " + (sp.stderr || "").slice(0, 200) : ""})`);
					if (sp.status) failed++;
				}
			}
		}
	}
}
process.exit(failed ? 1 : 0);
