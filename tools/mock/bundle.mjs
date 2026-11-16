// Rojo 프로젝트(json)를 읽어 「가상 DataModel + 모든 스크립트 소스」를 Luau 파일 하나로 묶는다.
//   node tools/mock/bundle.mjs [--project default.project.json] [--out tools/mock/out/bundle.luau]
// Luau CLI는 파일을 읽지 못하므로(io 없음) 소스를 문자열로 실어 주고, 런타임이 loadstring으로 올린다.
// 다른 스크립트에서는 buildBundle()을 불러 쓴다(run.mjs).
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ensureApi, API_OUT, luaString } from "./gen-api.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const OUT_DIR = path.join(HERE, "out");

// 런타임(main.luau의 RT.setup)이 주는 전역의 이름 — 묶음 파일이 제 전역에 넣는다
export const GLOBALS = [
	"game", "Game", "workspace", "Workspace", "Instance", "Enum",
	"Vector2", "Vector3", "UDim", "UDim2", "Color3", "Rect", "NumberRange", "NumberSequence", "NumberSequenceKeypoint",
	"ColorSequence", "ColorSequenceKeypoint", "TweenInfo", "Font", "Content", "CFrame", "BrickColor", "Random", "DateTime",
	"task", "wait", "delay", "spawn", "tick", "time", "elapsedTime", "print", "warn", "os", "debug", "shared",
	"settings", "UserSettings", "version", "printidentity", "loadstring", "gcinfo",
];

// ---------- 클래스 이름(프로젝트 json에서 클래스를 짐작할 때) ----------
let classInfo = null;
function classes() {
	if (classInfo) return classInfo;
	ensureApi();
	const text = fs.readFileSync(API_OUT, "utf8");
	classInfo = new Map();
	const re = /^\t\t\["([A-Za-z0-9_]+)"\] = "([^\\"]*)\\t([^\\"]*)/gm;
	let m;
	while ((m = re.exec(text))) classInfo.set(m[1], { super: m[2], service: m[3].split(",").includes("Service") });
	return classInfo;
}

// ---------- JSON 값 → Luau 리터럴 ----------
export function luaValue(v, indent = "") {
	if (v === null || v === undefined) return "nil";
	if (typeof v === "boolean") return v ? "true" : "false";
	if (typeof v === "number") return Number.isFinite(v) ? String(v) : v > 0 ? "math.huge" : v < 0 ? "-math.huge" : "(0/0)";
	if (typeof v === "string") return luaString(v);
	const inner = indent + "\t";
	if (Array.isArray(v)) {
		if (v.length === 0) return "{}";
		return "{\n" + v.map((x) => inner + luaValue(x, inner) + ",").join("\n") + "\n" + indent + "}";
	}
	const keys = Object.keys(v);
	if (keys.length === 0) return "{}";
	return "{\n" + keys.map((k) => inner + "[" + luaString(k) + "] = " + luaValue(v[k], inner) + ",").join("\n") + "\n" + indent + "}";
}

// ---------- 파일 → 인스턴스 ----------
const SCRIPT_EXT = [
	[".server.luau", "Script"],
	[".server.lua", "Script"],
	[".client.luau", "LocalScript"],
	[".client.lua", "LocalScript"],
	[".luau", "ModuleScript"],
	[".lua", "ModuleScript"],
];

function scriptKind(fileName) {
	for (const [ext, cls] of SCRIPT_EXT) if (fileName.endsWith(ext)) return { cls, base: fileName.slice(0, -ext.length) };
	return null;
}

class Builder {
	constructor(rootDir) {
		this.rootDir = rootDir;
		this.sources = []; // { file, src, abs }
		this.warnings = [];
		this.files = []; // 읽은 스크립트 파일(분석 도구가 쓴다): { abs, file, instPath, cls }
	}
	label(abs) {
		const rel = path.relative(this.rootDir, abs);
		return (rel.startsWith("..") || path.isAbsolute(rel) ? abs : rel).replace(/\\/g, "/");
	}
	addSource(abs, text) {
		// BOM 떼기 · 줄 끝 맞추기(줄 번호는 그대로)
		let src = text.replace(/^﻿/, "").replace(/\r\n/g, "\n");
		this.sources.push({ file: this.label(abs), src, abs });
		return this.sources.length; // Luau는 1부터
	}
	meta(metaPath, node) {
		if (!fs.existsSync(metaPath)) return;
		try {
			const meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
			if (meta.className && node.c === "Folder") node.c = meta.className;
			if (meta.properties) node.p = { ...(node.p || {}), ...meta.properties };
			if (meta.attributes) node.a = { ...(node.a || {}), ...meta.attributes };
		} catch (e) {
			this.warnings.push(`${this.label(metaPath)}: meta.json을 읽지 못했다 — ${e.message}`);
		}
	}
	fromFile(name, abs) {
		const fileName = path.basename(abs);
		const kind = scriptKind(fileName);
		if (kind) {
			const node = { n: name ?? kind.base, c: kind.cls, s: this.addSource(abs, fs.readFileSync(abs, "utf8")), k: [] };
			this.meta(path.join(path.dirname(abs), kind.base + ".meta.json"), node);
			return node;
		}
		if (fileName.endsWith(".project.json")) return this.fromProject(abs, name);
		if (fileName.endsWith(".meta.json")) return null;
		if (fileName.endsWith(".model.json") || fileName.endsWith(".rbxm") || fileName.endsWith(".rbxmx")) {
			this.warnings.push(`${this.label(abs)}: 모델 파일은 mock이 읽지 못한다 — 건너뛴다`);
			return null;
		}
		if (fileName.endsWith(".json")) {
			// Rojo: json 파일 = 그 자료를 돌려주는 ModuleScript
			let data;
			try {
				data = JSON.parse(fs.readFileSync(abs, "utf8"));
			} catch (e) {
				this.warnings.push(`${this.label(abs)}: JSON을 읽지 못했다 — ${e.message}`);
				return null;
			}
			const idx = this.addSource(abs, "return " + luaValue(data) + "\n");
			return { n: name ?? fileName.slice(0, -5), c: "ModuleScript", s: idx, k: [] };
		}
		if (fileName.endsWith(".txt")) {
			return { n: name ?? fileName.slice(0, -4), c: "StringValue", p: { Value: fs.readFileSync(abs, "utf8") }, k: [] };
		}
		if (fileName.endsWith(".csv")) {
			this.warnings.push(`${this.label(abs)}: csv(LocalizationTable)는 빈 껍데기로만 만든다`);
			return { n: name ?? fileName.slice(0, -4), c: "LocalizationTable", k: [] };
		}
		return null; // 그 밖의 파일은 Rojo도 무시한다
	}
	fromDir(name, abs) {
		const proj = path.join(abs, "default.project.json");
		if (fs.existsSync(proj)) return this.fromProject(proj, name);
		const entries = fs.readdirSync(abs, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
		let node = { n: name ?? path.basename(abs), c: "Folder", k: [] };
		for (const e of entries) {
			if (!e.isFile()) continue;
			const k = scriptKind(e.name);
			if (k && k.base === "init") {
				const f = path.join(abs, e.name);
				node = { n: node.n, c: k.cls, s: this.addSource(f, fs.readFileSync(f, "utf8")), k: [] };
				this.files.push({ abs: f, file: this.label(f), cls: k.cls, init: true });
				break;
			}
		}
		this.meta(path.join(abs, "init.meta.json"), node);
		for (const e of entries) {
			const full = path.join(abs, e.name);
			let child = null;
			if (e.isDirectory()) child = this.fromDir(null, full);
			else if (e.isFile()) {
				const k = scriptKind(e.name);
				if (k && k.base === "init") continue;
				if (e.name === "init.meta.json") continue;
				child = this.fromFile(null, full);
				if (child && k) this.files.push({ abs: full, file: this.label(full), cls: k.cls });
			}
			if (child) node.k.push(child);
		}
		return node;
	}
	fromPath(name, abs) {
		if (!fs.existsSync(abs)) {
			this.warnings.push(`${this.label(abs)}: 프로젝트가 가리키는 길이 없다(아직 만들지 않았다) — 빈 Folder로 둔다`);
			return { n: name, c: "Folder", k: [] };
		}
		const st = fs.statSync(abs);
		if (st.isDirectory()) return this.fromDir(name, abs);
		const node = this.fromFile(name, abs);
		if (node && scriptKind(path.basename(abs))) this.files.push({ abs, file: this.label(abs), cls: node.c });
		return node ?? { n: name, c: "Folder", k: [] };
	}
	fromProjectNode(name, pnode, baseDir, parentClass) {
		const cls = classes();
		let node;
		if (pnode.$path !== undefined) {
			const p = typeof pnode.$path === "string" ? pnode.$path : pnode.$path.optional;
			node = this.fromPath(name, path.resolve(baseDir, p));
			if (pnode.$className && node.c === "Folder") node.c = pnode.$className;
		} else {
			let className = pnode.$className;
			if (!className) {
				if (cls.has(name) && (parentClass === "DataModel" ? cls.get(name).service : true)) className = name;
				else {
					className = "Folder";
					if (parentClass === "DataModel") this.warnings.push(`프로젝트: "${name}" 은 서비스 이름이 아니다 — Folder로 둔다`);
				}
			} else if (!cls.has(className)) {
				throw new Error(`프로젝트: "${name}" 의 $className "${className}" 은 없는 클래스다`);
			}
			node = { n: name, c: className, k: [] };
		}
		if (pnode.$properties) node.p = { ...(node.p || {}), ...pnode.$properties };
		if (pnode.$attributes) node.a = { ...(node.a || {}), ...pnode.$attributes };
		for (const [k, v] of Object.entries(pnode)) {
			if (k.startsWith("$")) continue;
			const child = this.fromProjectNode(k, v, baseDir, node.c);
			// 같은 이름이 파일에서도 왔으면 프로젝트의 것으로 바꾼다
			const at = node.k.findIndex((c) => c.n === child.n);
			if (at >= 0) node.k[at] = child;
			else node.k.push(child);
		}
		return node;
	}
	fromProject(projectPath, nameOverride) {
		const proj = JSON.parse(fs.readFileSync(projectPath, "utf8"));
		if (!proj.tree) throw new Error(`${projectPath}: "tree" 가 없다`);
		const node = this.fromProjectNode(nameOverride ?? proj.name ?? "project", proj.tree, path.dirname(projectPath), null);
		return node;
	}
}

// 프로젝트를 읽는다 → { tree, sources, warnings, files, rootDir, name }
export function loadProject(projectPath) {
	const abs = path.resolve(projectPath);
	if (!fs.existsSync(abs)) throw new Error(`프로젝트 파일이 없다: ${abs}`);
	const rootDir = path.dirname(abs);
	const b = new Builder(rootDir);
	const proj = JSON.parse(fs.readFileSync(abs, "utf8"));
	const tree = b.fromProject(abs, null);
	if (tree.c !== "DataModel") {
		// 플레이스가 아닌 프로젝트(모델 · 라이브러리): ReplicatedStorage 아래에 둔다
		b.warnings.push(`프로젝트의 뿌리가 DataModel이 아니다(${tree.c}) — ReplicatedStorage 아래에 넣어 돌린다`);
		return { tree: { n: "game", c: "DataModel", k: [{ n: "ReplicatedStorage", c: "ReplicatedStorage", k: [tree] }] }, sources: b.sources, warnings: b.warnings, files: b.files, rootDir, name: proj.name };
	}
	return { tree, sources: b.sources, warnings: b.warnings, files: b.files, rootDir, name: proj.name };
}

function emitNode(node, indent) {
	const inner = indent + "\t";
	let s = "{ n = " + luaString(node.n) + ", c = " + luaString(node.c);
	if (node.s) s += ", s = " + node.s;
	if (node.p && Object.keys(node.p).length) s += ", p = " + luaValue(node.p, inner);
	if (node.a && Object.keys(node.a).length) s += ", a = " + luaValue(node.a, inner);
	if (node.k && node.k.length) s += ", k = {\n" + node.k.map((c) => inner + emitNode(c, inner) + ",").join("\n") + "\n" + indent + "}";
	return s + " }";
}

// 묶음 파일을 만든다. options = 런타임 옵션(viewW · viewH · frames …) · scenario = { file, src }?
export function buildBundle({ project, options = {}, scenario = null, outFile }) {
	ensureApi();
	const loaded = typeof project === "string" ? loadProject(project) : project;
	fs.mkdirSync(path.dirname(outFile), { recursive: true });
	const rel = path.relative(path.dirname(outFile), path.join(HERE, "runtime", "main")).replace(/\\/g, "/");
	const req = rel.startsWith(".") ? rel : "./" + rel;
	const lines = [];
	lines.push("-- 자동 생성: tools/mock/bundle.mjs — 손으로 고치지 않는다");
	lines.push(`local RT = require(${luaString(req)})`);
	lines.push("local G = RT.setup(" + luaValue(options) + ")");
	lines.push(GLOBALS.join(", ") + " = " + GLOBALS.map((g) => "G." + g).join(", "));
	lines.push("RT.run({");
	lines.push("\tglobals = { " + GLOBALS.map((g) => luaString(g)).join(", ") + " },");
	lines.push("\ttree = " + emitNode(loaded.tree, "\t") + ",");
	lines.push("\tsources = {");
	for (const s of loaded.sources) lines.push("\t\t{ file = " + luaString(s.file) + ", src = " + luaString(s.src) + " },");
	lines.push("\t},");
	if (scenario) lines.push("\tscenario = { file = " + luaString(scenario.file) + ", src = " + luaString(scenario.src) + " },");
	lines.push("})");
	fs.writeFileSync(outFile, lines.join("\n") + "\n");
	return { outFile, loaded, bytes: fs.statSync(outFile).size };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	const args = process.argv.slice(2);
	let project = "default.project.json";
	let out = path.join(OUT_DIR, "bundle.luau");
	for (let i = 0; i < args.length; i++) {
		if (args[i] === "--project") project = args[++i];
		else if (args[i] === "--out") out = args[++i];
		else {
			console.error("쓰는 법: node tools/mock/bundle.mjs [--project default.project.json] [--out 파일.luau]");
			process.exit(2);
		}
	}
	const r = buildBundle({ project, outFile: path.resolve(out) });
	for (const w of r.loaded.warnings) console.log("주의: " + w);
	console.log(`묶음: ${r.outFile} — 스크립트 ${r.loaded.sources.length}개 · ${r.bytes} bytes`);
}
