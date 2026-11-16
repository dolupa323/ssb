// 돌려 보지 않고 하는 검사 두 가지.
//   node tools/mock/analyze.mjs [--project default.project.json] [--solver old|new] [--strict] [--lints] [--all]
//
// (1) luau-analyze: 이 빌드의 luau-analyze에는 Roblox 정의 파일을 읽히는 옵션이 없다(--definitions 없음).
//     그래서 소스를 out/analyze/ 아래에 베껴, 파일마다 첫 줄 앞에 「Roblox 전역 = any」 머리말을 붙이고
//     require(script.Parent.X) · require(ReplicatedStorage.shared.Y) 같은 것을 파일 길(require("../Y"))로 바꿔서 돌린다.
//     → 순수 Luau의 잘못(없는 변수 · 인자 수 · 형 · 모듈에 없는 칸 · 문법)은 잡는다. Roblox 인스턴스의 속성 오타는 여기서 못 잡는다(any).
// (2) API 낱말 검사: 소스의 Enum.X.Y · Instance.new("X") · GetService("X") · IsA("X")를 API 덤프와 견주고,
//     「.이름」 가운데 Roblox API에도 프로젝트 어디에도 없는 이름을 「의심」으로 알린다.
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { loadProject, OUT_DIR } from "./bundle.mjs";
import { ensureApi, API_OUT } from "./gen-api.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..", "..");
const ANALYZE = path.join(ROOT, "tools", "luau", "luau-analyze.exe");

// ---------- API 표 읽기(runtime/apidump.luau) ----------
function unescapeLua(s) {
	return s.replace(/\\(n|t|r|\\|"|x[0-9a-fA-F]{2})/g, (m, c) => (c === "n" ? "\n" : c === "t" ? "\t" : c === "r" ? "\r" : c === "\\" ? "\\" : c === '"' ? '"' : String.fromCharCode(parseInt(c.slice(1), 16))));
}
export function loadApi() {
	ensureApi();
	const text = fs.readFileSync(API_OUT, "utf8");
	const classes = new Map();
	const enums = new Map();
	const members = new Set();
	const re = /^\t\t\["([A-Za-z0-9_]+)"\] = "((?:[^"\\]|\\.)*)",$/gm;
	const enumAt = text.indexOf("\tenums = {");
	let m;
	while ((m = re.exec(text))) {
		const body = unescapeLua(m[2]);
		if (m.index < enumAt) {
			const lines = body.split("\n");
			const head = lines[0].split("\t");
			const names = new Set();
			for (let i = 1; i < lines.length; i++) {
				const f = lines[i].split("\t");
				names.add(f[1]);
				members.add(f[1]);
			}
			classes.set(m[1], { super: head[0], tags: new Set((head[1] || "").split(",").filter(Boolean)), names });
		} else {
			const items = new Set();
			for (const part of body.split(",")) for (const n of part.split("~")) items.add(n.replace(/=.*$/, ""));
			enums.set(m[1], items);
		}
	}
	return { classes, enums, members };
}

// ---------- Luau 낱말 가르기(주석 · 문자열을 가려낸다) ----------
export function lex(src) {
	const toks = [];
	let i = 0, line = 1, col = 1;
	const n = src.length;
	const adv = (k) => {
		for (let j = 0; j < k; j++) {
			if (src[i] === "\n") {
				line++;
				col = 1;
			} else col++;
			i++;
		}
	};
	const longBracket = (at) => {
		// [[ 또는 [=[ 의 '=' 개수(아니면 -1)
		if (src[at] !== "[") return -1;
		let k = at + 1, eq = 0;
		while (src[k] === "=") {
			eq++;
			k++;
		}
		return src[k] === "[" ? eq : -1;
	};
	while (i < n) {
		const c = src[i];
		if (c === " " || c === "\t" || c === "\r" || c === "\n") {
			adv(1);
			continue;
		}
		if (c === "-" && src[i + 1] === "-") {
			const eq = longBracket(i + 2);
			if (eq >= 0) {
				const close = "]" + "=".repeat(eq) + "]";
				const end = src.indexOf(close, i + 4 + eq);
				adv((end < 0 ? n : end + close.length) - i);
			} else {
				const end = src.indexOf("\n", i);
				adv((end < 0 ? n : end) - i);
			}
			continue;
		}
		const l0 = line, c0 = col;
		if (c === '"' || c === "'" || c === "`") {
			let k = i + 1;
			while (k < n && src[k] !== c && src[k] !== "\n") k += src[k] === "\\" ? 2 : 1;
			const raw = src.slice(i + 1, k);
			toks.push({ t: c === "`" ? "istr" : "str", v: raw, line: l0, col: c0 });
			adv(Math.min(n, k + 1) - i);
			continue;
		}
		const eq = longBracket(i);
		if (eq >= 0) {
			const close = "]" + "=".repeat(eq) + "]";
			const start = i + 2 + eq;
			const end = src.indexOf(close, start);
			toks.push({ t: "str", v: src.slice(start, end < 0 ? n : end), line: l0, col: c0 });
			adv((end < 0 ? n : end + close.length) - i);
			continue;
		}
		if (/[A-Za-z_]/.test(c)) {
			let k = i + 1;
			while (k < n && /[A-Za-z0-9_]/.test(src[k])) k++;
			toks.push({ t: "id", v: src.slice(i, k), line: l0, col: c0, at: i, end: k });
			adv(k - i);
			continue;
		}
		if (/[0-9]/.test(c) || (c === "." && /[0-9]/.test(src[i + 1] || ""))) {
			let k = i + 1;
			while (k < n && /[0-9A-Za-z_.]/.test(src[k])) k++;
			toks.push({ t: "num", v: src.slice(i, k), line: l0, col: c0 });
			adv(k - i);
			continue;
		}
		const two = src.slice(i, i + 2);
		if (["==", "~=", "<=", ">=", "..", "::", "->", "+=", "-=", "*=", "/=", "//"].includes(two)) {
			toks.push({ t: "sym", v: two, line: l0, col: c0, at: i });
			adv(2);
			continue;
		}
		toks.push({ t: "sym", v: c, line: l0, col: c0, at: i });
		adv(1);
	}
	return toks;
}

const KEYWORDS = new Set("and break do else elseif end false for function if in local nil not or repeat return then true until while continue export type".split(" "));

// ---------- 비슷한 이름 ----------
function distance(a, b) {
	if (Math.abs(a.length - b.length) > 3) return 99;
	let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
	for (let i = 1; i <= a.length; i++) {
		const cur = [i];
		for (let j = 1; j <= b.length; j++) cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
		prev = cur;
	}
	return prev[b.length];
}
function nearest(name, candidates) {
	let best = null, bd = 99;
	const low = name.toLowerCase();
	for (const c of candidates) {
		const d = distance(low, String(c).toLowerCase());
		if (d < bd) {
			bd = d;
			best = c;
		}
	}
	return best && bd <= Math.max(1, Math.min(3, Math.floor(name.length / 3))) ? best : null;
}

// ---------- 인스턴스 나무(require를 풀 때) ----------
function indexTree(loaded) {
	// 마디마다 부모 · 파일을 단다. 파일(abs) → 마디
	const byFile = new Map();
	const walk = (node, parent) => {
		node.parent = parent;
		if (node.s) {
			const src = loaded.sources[node.s - 1];
			node.file = src.abs;
			byFile.set(path.resolve(src.abs), node);
		}
		for (const k of node.k || []) walk(k, node);
	};
	walk(loaded.tree, null);
	return byFile;
}
function nodePath(node) {
	const parts = [];
	for (let n = node; n && n.parent; n = n.parent) parts.unshift(n.n.replace(/[^A-Za-z0-9_.-]/g, "_"));
	return parts;
}
const child = (node, name) => (node && node.k ? node.k.find((c) => c.n === name) : null) || null;

// require(...)의 인자(낱말 줄)를 나무의 마디로 푼다. 못 풀면 null
function resolveExpr(toks, from, root, aliases) {
	let i = 0;
	let cur = null;
	const t = (k) => toks[k];
	const isSym = (k, v) => t(k) && t(k).t === "sym" && t(k).v === v;
	if (!t(0)) return null;
	if (t(0).t === "id" && t(0).v === "script") {
		cur = from;
		i = 1;
	} else if (t(0).t === "id" && t(0).v === "game") {
		cur = root;
		i = 1;
		if (isSym(1, ":") && t(2) && t(2).v === "GetService" && isSym(3, "(") && t(4) && t(4).t === "str" && isSym(5, ")")) {
			cur = child(root, t(4).v);
			i = 6;
		}
	} else if (t(0).t === "id" && aliases.has(t(0).v)) {
		cur = aliases.get(t(0).v);
		i = 1;
	} else if (t(0).t === "id" && child(root, t(0).v)) {
		cur = child(root, t(0).v); // 서비스 이름과 같은 변수(local ReplicatedStorage = game:GetService("ReplicatedStorage"))
		i = 1;
	} else if (t(0).t === "id" && t(0).v === "workspace") {
		cur = child(root, "Workspace");
		i = 1;
	} else return null;
	while (i < toks.length && cur) {
		if (isSym(i, ".") && t(i + 1) && t(i + 1).t === "id") {
			cur = t(i + 1).v === "Parent" && !child(cur, "Parent") ? cur.parent : child(cur, t(i + 1).v);
			i += 2;
		} else if (isSym(i, "[") && t(i + 1) && t(i + 1).t === "str" && isSym(i + 2, "]")) {
			cur = child(cur, t(i + 1).v);
			i += 3;
		} else if (isSym(i, ":") && t(i + 1) && ["WaitForChild", "FindFirstChild"].includes(t(i + 1).v) && isSym(i + 2, "(") && t(i + 3) && t(i + 3).t === "str") {
			cur = child(cur, t(i + 3).v);
			i += 4;
			while (i < toks.length && !isSym(i, ")")) i++;
			i++;
		} else if (isSym(i, "::")) {
			break; // 형 붙이기는 무시
		} else return null;
	}
	return i >= toks.length || isSym(i, "::") ? cur : null;
}

// ---------- 머리말 ----------
const VALUE_GLOBALS = [
	"game", "workspace", "script", "Instance", "Vector2", "Vector3", "UDim", "UDim2", "Color3", "Rect", "NumberRange", "NumberSequence",
	"NumberSequenceKeypoint", "ColorSequence", "ColorSequenceKeypoint", "TweenInfo", "Font", "Content", "CFrame", "BrickColor", "Random", "DateTime",
	"task", "wait", "delay", "spawn", "tick", "time", "elapsedTime", "warn", "shared", "settings", "UserSettings", "version", "printidentity", "plugin",
	"Ray", "Region3", "Region3int16", "Vector2int16", "Vector3int16", "PhysicalProperties", "RaycastParams", "OverlapParams", "PathWaypoint", "Axes", "Faces",
	"SharedTable", "Secret", "CatalogSearchParams", "DockWidgetPluginGuiInfo", "FloatCurveKey", "RotationCurveKey", "Path2DControlPoint", "ValueCurveKey",
];
const TYPE_ONLY = ["RBXScriptSignal", "RBXScriptConnection", "EnumItem", "Enums", "Tween", "buffer_"];

function buildPrelude(src, api, relEnum) {
	const words = new Set(src.match(/[A-Za-z_][A-Za-z0-9_]*/g) || []);
	const ownTypes = new Set();
	for (const m of src.matchAll(/(?:^|\n)\s*(?:export\s+)?type\s+([A-Za-z_][A-Za-z0-9_]*)/g)) ownTypes.add(m[1]);
	let p = "";
	const values = VALUE_GLOBALS.filter((g) => words.has(g));
	if (words.has("Enum")) p += `local Enum = require(${JSON.stringify(relEnum)});`;
	if (values.length) p += `local ${values.map((v) => v + ": any").join(", ")} = ${values.map(() => "nil :: any").join(", ")};`;
	const types = new Set();
	for (const w of words) if ((api.classes.has(w) || VALUE_GLOBALS.includes(w) || TYPE_ONLY.includes(w)) && !ownTypes.has(w) && w !== "script" && w !== "game" && w !== "workspace") types.add(w);
	for (const tname of types) p += `type ${tname} = any;`;
	return p;
}

// ---------- 본체 ----------
export function analyze(o) {
	const api = loadApi();
	const loaded = loadProject(path.resolve(o.project));
	const byFile = indexTree(loaded);
	const scripts = [...byFile.values()];
	const mirror = path.join(OUT_DIR, "analyze", String(process.pid));
	fs.rmSync(mirror, { recursive: true, force: true });
	fs.mkdirSync(mirror, { recursive: true });
	// Enum: 형 이름(Enum.KeyCode)을 받아 주는 모듈
	fs.writeFileSync(path.join(mirror, "__enum.luau"), [...api.enums.keys()].map((e) => `export type ${e} = any`).join("\n") + "\nreturn (nil :: any) :: any\n");

	const mirrorOf = new Map(); // 마디 → 베낀 파일(확장자 없이, mirror 기준)
	for (const node of scripts) mirrorOf.set(node, nodePath(node).join("/"));
	const info = new Map(); // 베낀 파일(상대) → { label, prelude 길이, 그 줄 }
	const unresolved = [];
	const wordIssues = [];
	const projectNames = new Set();
	const weakDefs = new Map(); // 이름 → 「x.이름 = 값」 자리들
	const wordCount = new Map(); // 이름 → 프로젝트에 나오는 횟수
	const usages = [];
	const instanceNames = new Set();
	const collectNames = (n) => {
		instanceNames.add(n.n);
		for (const k of n.k || []) collectNames(k);
	};
	collectNames(loaded.tree);

	for (const node of scripts) {
		const label = loaded.sources[node.s - 1].file;
		const src = loaded.sources[node.s - 1].src;
		const toks = lex(src);
		const rel = mirrorOf.get(node);
		const dir = path.posix.dirname(rel);
		const relTo = (target) => {
			let r = path.posix.relative(dir, target);
			if (!r.startsWith(".")) r = "./" + r;
			return r;
		};
		// 별명: local X = <나무의 마디를 가리키는 식>
		const aliases = new Map();
		const edits = []; // { at, end, text }
		for (let i = 0; i < toks.length; i++) {
			const tk = toks[i];
			// local NAME = expr (줄 끝까지)
			if (tk.t === "id" && tk.v === "local" && toks[i + 1] && toks[i + 1].t === "id" && toks[i + 2] && toks[i + 2].v === "=") {
				const expr = [];
				let k = i + 3;
				const ln = toks[k] ? toks[k].line : -1;
				while (toks[k] && toks[k].line === ln) expr.push(toks[k++]);
				if (expr.length && !(expr[0].t === "id" && expr[0].v === "require")) {
					const target = resolveExpr(expr, node, loaded.tree, aliases);
					if (target) aliases.set(toks[i + 1].v, target);
				}
			}
			if (tk.t === "id" && tk.v === "require" && toks[i + 1] && toks[i + 1].v === "(" && !(toks[i - 1] && (toks[i - 1].v === "." || toks[i - 1].v === ":"))) {
				// 괄호 짝
				let depth = 0, k = i + 1;
				for (; k < toks.length; k++) {
					if (toks[k].v === "(") depth++;
					else if (toks[k].v === ")" && --depth === 0) break;
				}
				const inner = toks.slice(i + 2, k);
				if (inner.length === 1 && inner[0].t === "str") {
					// 문자열 길: 인스턴스 나무에서 풀어 베낀 파일 길로
					const s = inner[0].v;
					let base = null, rest = s;
					if (s.startsWith("@self/")) (base = node), (rest = s.slice(6));
					else if (s.startsWith("@game/")) (base = loaded.tree), (rest = s.slice(6));
					else if (s.startsWith("./") || s.startsWith("../")) base = node.parent;
					let cur = base;
					if (cur) for (const part of rest.split("/")) cur = part === "." || part === "" ? cur : part === ".." ? cur && cur.parent : child(cur, part.replace(/\.luau?$/, ""));
					if (cur && mirrorOf.has(cur) && toks[i + 2].at === undefined) {
						// 문자열 낱말의 자리를 원문에서 찾는다
						const open = toks[i + 1].at, close = toks[k].at;
						edits.push({ at: open + 1, end: close, text: JSON.stringify(relTo(mirrorOf.get(cur))) });
					} else unresolved.push({ label, line: tk.line, text: `require("${s}")` });
				} else if (inner.length) {
					const target = resolveExpr(inner, node, loaded.tree, aliases);
					const open = toks[i + 1].at, close = toks[k] ? toks[k].at : undefined;
					if (target && mirrorOf.has(target) && close !== undefined) edits.push({ at: open + 1, end: close, text: JSON.stringify(relTo(mirrorOf.get(target))) });
					else unresolved.push({ label, line: tk.line, text: src.slice(tk.at, close !== undefined ? close + 1 : tk.end).replace(/\s+/g, " ").slice(0, 100) });
				}
			}
		}
		// ---- API 낱말 검사 ----
		const isSym = (k, v) => toks[k] && toks[k].t === "sym" && toks[k].v === v;
		for (let i = 0; i < toks.length; i++) {
			const tk = toks[i];
			if (tk.t === "str" && /^[A-Za-z_][A-Za-z0-9_]*$/.test(tk.v)) projectNames.add(tk.v);
			if (tk.t === "sym" && tk.v === "=") {
				// a.b, c.d = … : '=' 앞의 이름들을 모두 「정의된 이름」으로
				//   「x.이름 = 값」(칸에 넣기)은 약한 정의다 — 프로젝트의 표일 수도, 인스턴스의 속성(오타일 수 있다)일 수도 있다
				//   뒤로 가며 「이름 (. 이름)* (, …)*」 꼴만 따라간다(앞 문장으로 넘어가지 않게)
				let expectId = true;
				for (let j = i - 1; j >= 0; j--) {
					const b = toks[j];
					if (expectId) {
						if (b.t !== "id" || KEYWORDS.has(b.v)) break;
						const field = toks[j - 1] && toks[j - 1].t === "sym" && toks[j - 1].v === ".";
						if (field) {
							if (!weakDefs.has(b.v)) weakDefs.set(b.v, []);
							weakDefs.get(b.v).push({ label, line: b.line, col: b.col, name: b.v });
						} else projectNames.add(b.v);
						expectId = false;
					} else {
						if (!(b.t === "sym" && (b.v === "." || b.v === ","))) break;
						expectId = true;
					}
				}
			}
			if (tk.t !== "id") continue;
			wordCount.set(tk.v, (wordCount.get(tk.v) || 0) + 1);
			const prev = toks[i - 1], next = toks[i + 1];
			// 정의하는 자리: 이름 = (칸에 넣기가 아닌 것) · function a.b · 형의 칸(이름:)
			if (next && next.t === "sym" && next.v === "=" && !(prev && prev.t === "sym" && prev.v === ".")) projectNames.add(tk.v);
			if (next && next.t === "sym" && next.v === ":" && prev && prev.t === "sym" && (prev.v === "{" || prev.v === "," || prev.v === ";" || prev.v === "(")) projectNames.add(tk.v);
			if (tk.v === "function") {
				let k = i + 1;
				while (toks[k] && (toks[k].t === "id" || isSym(k, ".") || isSym(k, ":"))) {
					if (toks[k].t === "id") projectNames.add(toks[k].v);
					k++;
				}
			}
			if (tk.v === "Enum" && isSym(i + 1, ".") && toks[i + 2] && toks[i + 2].t === "id" && !(prev && prev.t === "sym" && (prev.v === "." || prev.v === ":"))) {
				const en = toks[i + 2].v;
				if (en !== "GetEnums") {
					if (!api.enums.has(en)) {
						const near = nearest(en, api.enums.keys());
						wordIssues.push({ label, line: tk.line, col: tk.col, sure: true, text: `Enum.${en} — 없는 열거형` + (near ? ` (혹시 ${near}?)` : "") });
					} else if (isSym(i + 3, ".") && toks[i + 4] && toks[i + 4].t === "id") {
						const item = toks[i + 4].v;
						if (!api.enums.get(en).has(item) && !["GetEnumItems", "FromName", "FromValue"].includes(item)) {
							const near = nearest(item, api.enums.get(en));
							wordIssues.push({ label, line: tk.line, col: tk.col, sure: true, text: `Enum.${en}.${item} — Enum.${en}에 없는 값` + (near ? ` (혹시 ${near}?)` : "") });
						}
					}
				}
			}
			if (tk.v === "Instance" && isSym(i + 1, ".") && toks[i + 2] && toks[i + 2].v === "new" && isSym(i + 3, "(") && toks[i + 4] && toks[i + 4].t === "str") {
				const cn = toks[i + 4].v;
				const c = api.classes.get(cn);
				if (!c) {
					const near = nearest(cn, api.classes.keys());
					wordIssues.push({ label, line: tk.line, col: tk.col, sure: true, text: `Instance.new("${cn}") — 없는 클래스` + (near ? ` (혹시 ${near}?)` : "") });
				} else if (c.tags.has("NotCreatable") || c.tags.has("Service")) wordIssues.push({ label, line: tk.line, col: tk.col, sure: true, text: `Instance.new("${cn}") — 만들 수 없는 클래스` });
			}
			if (prev && prev.t === "sym" && prev.v === ":" && isSym(i + 1, "(") && toks[i + 2] && toks[i + 2].t === "str" && isSym(i + 3, ")")) {
				const arg = toks[i + 2].v;
				if (tk.v === "GetService") {
					const c = api.classes.get(arg);
					if (!c || !c.tags.has("Service")) {
						const near = nearest(arg, [...api.classes].filter(([, v]) => v.tags.has("Service")).map(([k]) => k));
						wordIssues.push({ label, line: tk.line, col: tk.col, sure: true, text: `GetService("${arg}") — 없는 서비스` + (near ? ` (혹시 ${near}?)` : "") });
					}
				} else if (["IsA", "FindFirstChildOfClass", "FindFirstChildWhichIsA", "FindFirstAncestorOfClass", "FindFirstAncestorWhichIsA"].includes(tk.v)) {
					if (!api.classes.has(arg)) {
						const near = nearest(arg, api.classes.keys());
						wordIssues.push({ label, line: tk.line, col: tk.col, sure: true, text: `${tk.v}("${arg}") — 없는 클래스 이름` + (near ? ` (혹시 ${near}?)` : "") });
					}
				}
			}
			// 「.이름」 · 「:이름」 쓰는 자리
			if (prev && prev.t === "sym" && (prev.v === "." || prev.v === ":") && !(toks[i - 2] && toks[i - 2].t === "num")) {
				const before = toks[i - 2];
				const afterEnum = toks[i - 2] && toks[i - 2].v === "Enum" || (toks[i - 4] && toks[i - 4].v === "Enum" && isSym(i - 3, "."));
				// 「:이름」은 뒤에 부르는 꼴이 올 때만 메서드다(아니면 형 적기: local a: number)
				const isCall = prev.v === ":" && next && (next.v === "(" || next.t === "str" || next.v === "{");
				if (!afterEnum && (prev.v === "." || isCall) && !(next && next.t === "sym" && next.v === "=")) usages.push({ label, line: tk.line, col: tk.col, name: tk.v, call: prev.v === ":", before: before ? before.v : "" });
			}
		}
		// ---- 베낀 파일 ----
		let out = src;
		edits.sort((a, b) => b.at - a.at);
		for (const e of edits) out = out.slice(0, e.at) + e.text + out.slice(e.end);
		let at = 0, lineNo = 1;
		while (out.startsWith("--!", at)) {
			const nl = out.indexOf("\n", at);
			if (nl < 0) {
				at = out.length;
				break;
			}
			at = nl + 1;
			lineNo++;
		}
		const depth = dir === "." ? 0 : dir.split("/").length;
		const prelude = buildPrelude(src, api, (depth === 0 ? "./" : "../".repeat(depth)) + "__enum");
		out = out.slice(0, at) + prelude + out.slice(at);
		// 아이가 있는 스크립트(init 꼴)는 「폴더/init.luau」로 둔다(같은 이름의 파일과 폴더가 나란히 있으면 luau-analyze가 require를 풀지 못한다)
		const relFile = node.k && node.k.length ? rel + "/init.luau" : rel + ".luau";
		const file = path.join(mirror, relFile);
		fs.mkdirSync(path.dirname(file), { recursive: true });
		fs.writeFileSync(file, out);
		info.set(relFile, { label, preLen: prelude.length, preLine: lineNo });
	}

	// ---- luau-analyze ----
	const files = [...info.keys()];
	const diags = [];
	let analyzerNote = null;
	if (files.length) {
		const args = [`--solver=${o.solver}`, `--mode=${o.strict ? "strict" : "nonstrict"}`, ...files];
		const r = spawnSync(ANALYZE, args, { cwd: mirror, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
		if (r.error) analyzerNote = "luau-analyze를 돌리지 못했다: " + r.error.message;
		const text = (r.stdout || "") + "\n" + (r.stderr || "");
		let last = null;
		for (const raw of text.split(/\r?\n/)) {
			const m = /^(?:\.\/)?(.+?)\((\d+),(\d+)\): (\w+): (.*)$/.exec(raw);
			if (m) {
				const inf = info.get(m[1].replace(/\\/g, "/"));
				if (!inf) {
					last = null;
					continue;
				}
				let line = Number(m[2]), col = Number(m[3]);
				if (line === inf.preLine) {
					if (col <= inf.preLen) {
						last = null; // 머리말 안의 것(쓰지 않은 전역 같은 것)
						continue;
					}
					col -= inf.preLen;
				}
				last = { label: inf.label, line, col, kind: m[4], text: m[5] };
				diags.push(last);
			} else if (last && raw.trim().length) last.text += "\n      " + raw.trim();
		}
	}
	if (!o.keep) fs.rmSync(mirror, { recursive: true, force: true });
	if (o.sourcemap) {
		// Rojo의 sourcemap.json 꼴(luau-lsp 같은 다른 도구가 읽는다)
		const toMap = (node) => {
			const m = { name: node.n, className: node.c };
			if (node.file) m.filePaths = [path.relative(loaded.rootDir, node.file).replace(/\\/g, "/")];
			if (node.k && node.k.length) m.children = node.k.map(toMap);
			return m;
		};
		fs.writeFileSync(path.resolve(o.sourcemap), JSON.stringify(toMap(loaded.tree)));
	}

	// ---- 「.이름」 가운데 어디에도 없는 것 ----
	const STD = new Set("byte char find format gmatch gsub len lower match rep reverse sub upper split pack unpack packsize concat insert remove sort create clear clone freeze isfrozen find move maxn foreach foreachi getn abs acos asin atan atan2 ceil cos cosh deg exp floor fmod frexp ldexp log log10 max min modf pow rad random randomseed sin sinh sqrt tan tanh pi huge clamp sign round noise lerp map isnan isinf isfinite band bor bxor bnot lshift rshift arshift lrotate rrotate extract replace btest countlz countrz byteswap readu8 readi8 readu16 readi16 readu32 readi32 readf32 readf64 writeu8 writei8 writeu16 writei16 writeu32 writei32 writef32 writef64 readstring writestring tostring fromstring copy fill readbits writebits wrap yield resume running status isyieldable close create cancel defer delay spawn wait synchronize desynchronize clock time date difftime traceback info profilebegin profileend setmemorycategory resetmemorycategory codepoint codes offset charpattern nfcnormalize nfdnormalize graphemes n __index __newindex __call __eq __lt __le __add __sub __mul __div __mod __pow __unm __concat __len __tostring __metatable __mode __iter __idiv new zero one xAxis yAxis zAxis identity none fromScale fromOffset fromRGB fromHSV fromHex fromEnum fromName fromId fromUri fromObject fromAssetId now fromUnixTimestamp fromUnixTimestampMillis X Y Z x y z R G B r g b Scale Offset Width Height Min Max Magnitude Unit Lerp Dot Cross Abs Ceil Floor Sign Angle FuzzyEq ToHSV ToHex Keypoints Time Value Envelope EasingStyle EasingDirection RepeatCount Reverses DelayTime Family Weight Style Bold SourceType Uri Object Position Name EnumType GetEnumItems FromName FromValue IsA Connect Once Wait Disconnect Connected ConnectParallel connect wait disconnect NextNumber NextInteger NextUnitVector Shuffle Clone UnixTimestamp UnixTimestampMillis ToIsoDate ToUniversalTime ToLocalTime FormatLocalTime FormatUniversalTime Parent".split(" "));
	const suspects = new Map();
	const known = (nm) => api.members.has(nm) || STD.has(nm) || projectNames.has(nm) || instanceNames.has(nm) || api.classes.has(nm) || api.enums.has(nm);
	for (const u of usages) {
		const nm = u.name;
		if (known(nm) || weakDefs.has(nm)) continue;
		const key = u.label + ":" + u.line + ":" + nm;
		if (!suspects.has(key)) suspects.set(key, u);
	}
	// 값을 넣기만 하고 어디서도 읽지 않는 칸(프로젝트 전체에 그 넣는 자리뿐): 인스턴스 속성의 오타일 수 있다
	for (const [nm, sites] of weakDefs) {
		if (known(nm) || sites.length > 2 || (wordCount.get(nm) || 0) > sites.length) continue;
		for (const s of sites) suspects.set(s.label + ":" + s.line + ":" + nm, { ...s, assign: true });
	}

	return { loaded, diags, unresolved, wordIssues, suspects: [...suspects.values()], api, projectNames, analyzerNote, files: files.length };
}

function main() {
	const o = { project: "default.project.json", solver: "old", strict: false, lints: false, all: false };
	const argv = process.argv.slice(2);
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a === "--project") o.project = argv[++i];
		else if (a === "--solver") o.solver = argv[++i];
		else if (a === "--strict") o.strict = true;
		else if (a === "--lints") o.lints = true;
		else if (a === "--all") o.all = true;
		else if (a === "--keep") o.keep = true;
		else if (a === "--sourcemap") o.sourcemap = argv[++i];
		else {
			console.error("쓰는 법: node tools/mock/analyze.mjs [--project default.project.json] [--solver old|new] [--strict] [--lints] [--all] [--keep] [--sourcemap 파일.json]\n  --strict  모든 파일을 strict로(기본은 파일의 --! 줄을 따르고, 없으면 nonstrict)\n  --lints   린트(쓰지 않는 변수 같은 것)도 다 적는다\n  --all     풀지 못한 require도 다 적는다\n  --keep    베낀 파일(out/analyze/)을 지우지 않는다\n  --sourcemap  Rojo의 sourcemap.json 꼴로 인스턴스 나무를 적는다(다른 도구용)");
			process.exit(2);
		}
	}
	const r = analyze(o);
	for (const w of r.loaded.warnings) console.log("주의: " + w);
	if (r.analyzerNote) console.log(r.analyzerNote);
	// 같은 것은 한 번만
	const seen = new Set();
	const errors = [], lints = [];
	const NOISE = [/^Unknown require: /, /^Unknown type '[A-Za-z_]+'$/];
	let noise = 0;
	for (const d of r.diags) {
		const key = d.label + "|" + d.line + "|" + d.kind + "|" + d.text;
		if (seen.has(key)) continue;
		seen.add(key);
		if (d.kind === "TypeError" || d.kind === "SyntaxError") {
			if (/^Unknown require: /.test(d.text)) {
				noise++;
				continue;
			}
			errors.push(d);
		} else lints.push(d);
	}
	const byLine = (a, b) => (a.label < b.label ? -1 : a.label > b.label ? 1 : a.line - b.line || a.col - b.col);
	errors.sort(byLine);
	lints.sort(byLine);
	console.log(`luau-analyze (solver ${o.solver} · ${o.strict ? "strict" : "파일의 --! 줄을 따름(없으면 nonstrict)"}) — 파일 ${r.files}개: 오류 ${errors.length} · 린트 ${lints.length}`);
	console.log("  (이 빌드의 luau-analyze는 Roblox 정의 파일을 읽지 못한다 — game · Instance · Enum 같은 Roblox 값은 any로 본다)");
	for (const d of errors) console.log(`${d.label}(${d.line},${d.col}): ${d.kind}: ${d.text}`);
	if (lints.length) {
		const kinds = {};
		for (const d of lints) (kinds[d.kind] ||= []).push(d);
		console.log(`린트 ${lints.length}개: ` + Object.entries(kinds).map(([k, v]) => `${k} ${v.length}`).join(" · ") + (o.lints ? "" : "  (다 보려면 --lints)"));
		const show = o.lints ? lints : lints.filter((d) => ["GlobalUsedAsLocal", "DuplicateLocal", "DuplicateFunction", "UnreachableCode", "UninitializedLocal", "DuplicateCondition", "MisleadingAndOr", "ForRange", "UnbalancedAssignment", "ImplicitReturn", "TableLiteral", "ComparisonPrecedence", "IntegerParsing", "FormatString"].includes(d.kind));
		for (const d of show) console.log(`${d.label}(${d.line},${d.col}): ${d.kind}: ${d.text}`);
	}
	if (r.unresolved.length || noise) {
		console.log(`\n풀지 못한 require ${r.unresolved.length}개 — 그 모듈의 값은 any로 본다` + (o.all ? "" : "  (다 보려면 --all)"));
		for (const u of o.all ? r.unresolved : r.unresolved.slice(0, 5)) console.log(`  ${u.label}(${u.line}): ${u.text}`);
	}
	const sure = r.wordIssues.filter((w) => w.sure).sort(byLine);
	console.log(`\nAPI 낱말 검사 — 틀린 것 ${sure.length} · 의심 ${r.suspects.length}`);
	for (const w of sure) console.log(`${w.label}(${w.line},${w.col}): ${w.text}`);
	if (r.suspects.length) {
		console.log("의심(Roblox API에도, 프로젝트의 다른 곳에도 없는 이름 — 오타일 수 있다):");
		const names = new Set([...r.api.members, ...r.projectNames]);
		for (const u of r.suspects.sort(byLine)) {
			const near = nearest(u.name, names);
			console.log(`  ${u.label}(${u.line},${u.col}): ${u.call ? ":" : "."}${u.name}${u.assign ? " = …  (넣기만 하고 읽는 곳이 없다)" : ""}` + (near ? `  (혹시 ${near}?)` : ""));
		}
	}
	const bad = errors.length + sure.length;
	console.log(`\n끝: ${bad === 0 ? "틀린 것 없음" : "틀린 것 " + bad + "개"}${r.suspects.length ? " · 의심 " + r.suspects.length + "개" : ""}`);
	process.exit(bad ? 1 : 0);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
