// Studio 없이 게임 코드를 돌려 본다.
//   node tools/mock/run.mjs [--project default.project.json] [--viewport 1280x720] [--frames N] [--script 시나리오.luau] [--shot 그림.png …]
// 시나리오가 없으면: 서버 스크립트 → 클라이언트 스크립트를 시작하고 N장(기본 60)을 60fps로 넘긴 뒤, 난 오류 · 경고를 모두 적는다.
// 오류나 확인 실패가 있으면 끝날 때의 코드가 1이다.
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { buildBundle, loadProject, OUT_DIR } from "./bundle.mjs";
import { renderShot, loadAssets } from "./shot.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..", "..");
const LUAU = path.join(ROOT, "tools", "luau", "luau.exe");

const HELP = `쓰는 법: node tools/mock/run.mjs [옵션]
  --project <json>      Rojo 프로젝트 (기본: default.project.json)
  --viewport <WxH>      화면 크기 (기본: 1280x720 · 폰 가로는 844x390)
  --frames <N>          시나리오가 없을 때 넘길 장 수 (기본: 60)
  --fps <N>             한 장의 길이 = 1/N초 (기본: 60)
  --script <luau>       시나리오 파일(harness를 받는다)
  --shot <png>          끝난 뒤의 화면을 찍는다(여러 번 쓸 수 있다). 시나리오 안에서는 harness.shot("이름.png")
  --shot-dir <dir>      harness.shot의 상대 경로가 놓일 폴더 (기본: 지금 폴더)
  --assets <json>       그림 짝: { "rbxassetid://123": "assets/a.png" } (기본: tools/mock/assets.json이 있으면 그것)
  --inset <N>           위쪽 Roblox 띠의 높이 (기본: 58)
  --touch               손가락 기기처럼(TouchEnabled · PreferredInput = Touch · 글쇠판 · 마우스 없음)
  --signals <deferred|immediate>   신호를 부르는 방식 (기본: deferred)
  --lenient-enums       열거형 속성에 문자열 · 수를 받아 준다(Roblox처럼) — 기본은 막는다
  --studio              RunService:IsStudio() = true
  --no-start            시나리오가 harness.start()를 부를 때까지 스크립트를 시작하지 않는다
  --tree                끝난 뒤 화면 나무를 글로 찍는다
  --dump                찍은 화면의 JSON도 그림 옆에 둔다(.json)
  --no-core-overlay     화면 그림에 Roblox 기본 단추 자리를 그리지 않는다
  --user-id <N> / --user-name <이름> / --place-id <N>
  --latency <초> / --ds-latency <초>   원격 이벤트 · DataStore의 늦음
  --seed <N>            math.random의 씨앗 (기본: 정해진 값 — 돌릴 때마다 결과가 같다)
  --timeout <초>        luau가 이만큼 넘게 돌면 멈춘다 (기본: 300)
  --codegen             luau --codegen 으로 돌린다
  --keep                묶음 파일을 지우지 않는다
  --json <파일>         결과를 JSON으로도 적는다
  --quiet               print 줄을 찍지 않는다(오류 · 경고 · 요약만)`;

function parseArgs(argv) {
	const o = { project: "default.project.json", viewport: [1280, 720], frames: 60, fps: 60, shots: [], signals: "deferred", inset: 58, timeout: 300 };
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		const next = () => {
			if (i + 1 >= argv.length) throw new Error(`${a} 뒤에 값이 없다`);
			return argv[++i];
		};
		switch (a) {
			case "--project": o.project = next(); break;
			case "--viewport": {
				const m = /^(\d+)x(\d+)$/.exec(next());
				if (!m) throw new Error("--viewport 는 1280x720 꼴이어야 한다");
				o.viewport = [Number(m[1]), Number(m[2])];
				break;
			}
			case "--frames": o.frames = Number(next()); break;
			case "--fps": o.fps = Number(next()); break;
			case "--script": o.script = next(); break;
			case "--shot": o.shots.push(next()); break;
			case "--shot-dir": o.shotDir = next(); break;
			case "--assets": o.assets = next(); break;
			case "--inset": o.inset = Number(next()); break;
			case "--touch": o.touch = true; break;
			case "--signals": o.signals = next(); break;
			case "--lenient-enums": o.lenientEnums = true; break;
			case "--studio": o.studio = true; break;
			case "--no-start": o.noStart = true; break;
			case "--tree": o.tree = true; break;
			case "--dump": o.dump = true; break;
			case "--no-core-overlay": o.noCoreOverlay = true; break;
			case "--user-id": o.userId = Number(next()); break;
			case "--user-name": o.userName = next(); break;
			case "--place-id": o.placeId = Number(next()); break;
			case "--latency": o.latency = Number(next()); break;
			case "--ds-latency": o.dsLatency = Number(next()); break;
			case "--timeout": o.timeout = Number(next()); break;
			case "--seed": o.seed = Number(next()); break;
			case "--codegen": o.codegen = true; break;
			case "--keep": o.keep = true; break;
			case "--json": o.json = next(); break;
			case "--quiet": o.quiet = true; break;
			case "-h":
			case "--help":
				console.log(HELP);
				process.exit(0);
			default:
				throw new Error(`모르는 옵션 ${a}\n${HELP}`);
		}
	}
	if (!["deferred", "immediate"].includes(o.signals)) throw new Error("--signals 는 deferred 또는 immediate");
	return o;
}

function indent(text, pad = "    ") {
	return String(text).split("\n").filter((l) => l.length).map((l) => pad + l).join("\n");
}

export async function runMock(o) {
	const project = loadProject(path.resolve(o.project));
	const options = {
		viewW: o.viewport[0],
		viewH: o.viewport[1],
		insetTop: o.inset,
		frames: o.frames,
		dt: 1 / o.fps,
		signals: o.signals,
		strictEnums: !o.lenientEnums,
		studio: !!o.studio,
		noStart: !!o.noStart,
		printTree: !!o.tree,
		device: o.touch ? "touch" : undefined,
		userId: o.userId,
		userName: o.userName,
		placeId: o.placeId,
		latency: o.latency,
		dsLatency: o.dsLatency,
		seed: o.seed,
		gameName: project.name,
		finalShot: o.shots.length ? o.shots : undefined,
	};
	for (const k of Object.keys(options)) if (options[k] === undefined) delete options[k];
	let scenario = null;
	if (o.script) {
		const abs = path.resolve(o.script);
		if (!fs.existsSync(abs)) throw new Error(`시나리오 파일이 없다: ${abs}`);
		const rel = path.relative(project.rootDir, abs);
		scenario = { file: (rel.startsWith("..") || path.isAbsolute(rel) ? abs : rel).replace(/\\/g, "/"), src: fs.readFileSync(abs, "utf8").replace(/^﻿/, "").replace(/\r\n/g, "\n") };
	}
	const outFile = path.join(OUT_DIR, `bundle-${process.pid}.luau`);
	const built = buildBundle({ project, options, scenario, outFile });
	const log = (s) => console.log(s);
	for (const w of project.warnings) log("주의: " + w);

	const result = { errors: [], warns: [], fails: [], notes: [], shots: [], done: null, out: [], crashed: null };
	const images = {};
	const pendingShots = [];
	const handle = (kind, p) => {
		switch (kind) {
			case "out":
				result.out.push(p);
				if (!o.quiet) log(`[${p.ctx}] ${p.text}`);
				break;
			case "warn":
				result.warns.push(p);
				log(`경고 [${p.ctx}] ${p.text}` + (p.trace ? "\n" + indent(p.trace) : ""));
				break;
			case "err":
				result.errors.push(p);
				log(`오류 [${p.ctx}]${p.note ? " (" + p.note + ")" : ""} ${p.text}` + (p.trace ? "\n" + indent(p.trace) : "") + `\n    (가상 ${p.time?.toFixed?.(3) ?? "?"}초 · ${p.frame ?? "?"}번째 장)`);
				break;
			case "fail":
				result.fails.push(p);
				log(`확인 실패: ${p.text}` + (p.trace ? "\n" + indent(p.trace) : ""));
				break;
			case "forgive":
				// 시나리오가 알고 낸 오류를 거둬 갔다
				result.forgiven = (result.forgiven || 0) + p.count;
				result.errors.splice(Math.max(0, result.errors.length - p.count), p.count);
				if (p.count > 0) log(`    (위의 오류 ${p.count}개는 시나리오가 알고 낸 것이다 — 세지 않는다)`);
				break;
			case "note":
				result.notes.push(p);
				break;
			case "img":
				images[`ei:${p.id}:${p.ver}`] = p;
				break;
			case "shot":
				pendingShots.push(p);
				break;
			case "done":
				result.done = p;
				break;
		}
	};

	const t0 = Date.now();
	const args = [];
	if (o.codegen) args.push("--codegen");
	args.push("-O1", outFile); // (-O2는 함수를 끼워 넣어 역추적의 줄이 빠진다)
	const code = await new Promise((resolve) => {
		const child = spawn(LUAU, args, { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"] });
		let buf = "";
		let err = "";
		const timer = setTimeout(() => {
			result.crashed = `luau가 ${o.timeout}초 넘게 돌아 멈췄다(스크립트가 장을 넘기지 않고 끝없이 도는 것일 수 있다)`;
			child.kill();
		}, o.timeout * 1000);
		child.stdout.setEncoding("utf8");
		child.stdout.on("data", (d) => {
			buf += d;
			let nl;
			while ((nl = buf.indexOf("\n")) >= 0) {
				const line = buf.slice(0, nl).replace(/\r$/, "");
				buf = buf.slice(nl + 1);
				if (line.startsWith("@@M")) {
					const sp = line.indexOf(" ");
					try {
						handle(line.slice(3, sp), JSON.parse(line.slice(sp + 1)));
					} catch (e) {
						log("(읽지 못한 줄) " + line.slice(0, 200));
					}
				} else if (line.length) log(line);
			}
		});
		child.stderr.setEncoding("utf8");
		child.stderr.on("data", (d) => (err += d));
		child.on("close", (c) => {
			clearTimeout(timer);
			if (buf.trim().length) log(buf.trim());
			if (err.trim().length) result.stderr = err.trim();
			resolve(c);
		});
	});
	const wall = (Date.now() - t0) / 1000;
	if (!result.done && !result.crashed) result.crashed = `luau가 끝까지 돌지 못했다(끝난 코드 ${code})` + (result.stderr ? "\n" + result.stderr : "");
	if (result.crashed) log("mock이 멈췄다: " + result.crashed);
	else if (result.stderr) log("luau stderr:\n" + indent(result.stderr));

	// 화면 찍기
	const assets = loadAssets(o.assets ?? (fs.existsSync(path.join(HERE, "assets.json")) ? path.join(HERE, "assets.json") : null));
	for (const shot of pendingShots) {
		const file = path.resolve(o.shotDir || ".", shot.file);
		try {
			const r = renderShot(shot, images, file, { assets, coreOverlay: !o.noCoreOverlay });
			if (o.dump) {
				const used = {};
				for (const it of shot.items) if (it.img && it.img.ei !== undefined) used[`ei:${it.img.ei}:${it.img.ver}`] = images[`ei:${it.img.ei}:${it.img.ver}`];
				fs.writeFileSync(file.replace(/\.png$/i, ".json"), JSON.stringify({ shot, images: used }));
			}
			const sz = r.size ? `${r.size.w}x${r.size.h}` : "?";
			const mismatch = r.size && (r.size.w !== shot.w || r.size.h !== shot.h) ? ` — 주의: 화면 크기(${shot.w}x${shot.h})와 다르다` : "";
			log(`화면: ${file} (${sz} · 마디 ${shot.items.length}개 · 가상 ${shot.time.toFixed(2)}초)${mismatch}`);
			result.shots.push({ file, size: r.size, items: shot.items.length });
		} catch (e) {
			log(`화면을 찍지 못했다(${shot.file}): ${e.message}`);
			result.shotErrors = (result.shotErrors || 0) + 1;
		}
	}

	if (result.notes.length) {
		log(`\nmock이 흉내 내지 않거나 어림한 것 (${result.notes.length}):`);
		for (const n of result.notes) log("  - " + n.text);
	}
	const d = result.done;
	const nErr = result.errors.length, nFail = result.fails.length;
	if (d) {
		log(`\n끝: ${d.frames}장 · 가상 ${d.time.toFixed(2)}초 · luau ${d.wall.toFixed(2)}초(모두 ${wall.toFixed(2)}초) · 스크립트 ${project.sources.length}개 · 오류 ${nErr} · 경고 ${result.warns.length} · 확인 ${d.checks}개 통과${nFail ? " / " + nFail + "개 실패" : ""}`);
	}
	if (!o.keep) fs.rmSync(outFile, { force: true });
	else log("묶음 파일: " + built.outFile);
	const ok = !result.crashed && nErr === 0 && nFail === 0 && !result.shotErrors;
	if (o.json) fs.writeFileSync(path.resolve(o.json), JSON.stringify({ ok, errors: result.errors, warns: result.warns, fails: result.fails, notes: result.notes, shots: result.shots, done: d, crashed: result.crashed }, null, 1));
	return { ok, result };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	let o;
	try {
		o = parseArgs(process.argv.slice(2));
	} catch (e) {
		console.error(e.message);
		process.exit(2);
	}
	try {
		const { ok } = await runMock(o);
		process.exit(ok ? 0 : 1);
	} catch (e) {
		console.error("mock을 돌리지 못했다: " + (e.stack || e.message));
		process.exit(2);
	}
}
