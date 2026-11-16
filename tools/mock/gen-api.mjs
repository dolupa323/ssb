// Roblox API 덤프(ref/Full-API-Dump.json)를 mock 런타임이 읽는 작은 Luau 표(runtime/apidump.luau)로 바꾼다.
//   node tools/mock/gen-api.mjs
// 클래스마다 문자열 한 덩이로 싣고(런타임이 처음 쓸 때 풀어 읽는다) 열거형도 한 줄씩 싣는다.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REF = path.join(HERE, "ref");
export const API_OUT = path.join(HERE, "runtime", "apidump.luau");

export function luaString(s) {
	// Luau 문자열 리터럴 — UTF-8 바이트는 그대로, 제어 문자 · 따옴표 · 역슬래시만 바꾼다
	let out = '"';
	for (let i = 0; i < s.length; i++) {
		const c = s[i];
		const code = s.charCodeAt(i);
		if (c === "\\") out += "\\\\";
		else if (c === '"') out += '\\"';
		else if (c === "\n") out += "\\n";
		else if (c === "\r") out += "\\r";
		else if (c === "\t") out += "\\t";
		else if (code < 32 || code === 127) out += "\\x" + code.toString(16).padStart(2, "0");
		else out += c;
	}
	return out + '"';
}

function typeCode(t) {
	if (!t) return "?";
	switch (t.Category) {
		case "Primitive":
			return t.Name;
		case "DataType":
			return t.Name;
		case "Enum":
			return "E:" + t.Name;
		case "Class":
			return "C:" + t.Name;
		case "Group":
			return "G:" + t.Name;
		default:
			return t.Category + ":" + t.Name;
	}
}

function tagList(tags) {
	const names = [];
	let preferred = "";
	for (const t of tags || []) {
		if (typeof t === "string") names.push(t);
		else if (t && t.PreferredDescriptorName) preferred = t.PreferredDescriptorName;
	}
	return { names, preferred };
}

const KEEP_DEFAULT = new Set(["bool", "int", "int64", "float", "double", "string", "Vector2", "Vector3", "Color3", "UDim", "UDim2", "Rect", "NumberRange", "ContentId"]);

function clean(s) {
	// 한 줄 · 탭 없는 글로
	return String(s).replace(/[\t\r\n]/g, " ");
}

export function generate() {
	const full = path.join(REF, "Full-API-Dump.json");
	const plain = path.join(REF, "API-Dump.json");
	const src = fs.existsSync(full) ? full : plain;
	if (!fs.existsSync(src)) throw new Error("API 덤프가 없다 — 먼저 `node tools/mock/fetch-ref.mjs` 를 돌린다");
	const dump = JSON.parse(fs.readFileSync(src, "utf8"));
	// rbx-dom의 자료가 있으면: 클래스마다의 기본 속성 값(물려받은 것까지)을 「D」 줄로 싣는다
	const dbPath = path.join(REF, "rbx-dom-database.json");
	const db = fs.existsSync(dbPath) ? JSON.parse(fs.readFileSync(dbPath, "utf8")) : null;
	const byName = new Map(dump.Classes.map((c) => [c.Name, c]));
	const propType = (className, prop) => {
		// 그 클래스(와 윗 클래스)의 속성이면 그 형을
		for (let c = byName.get(className); c; c = byName.get(c.Superclass)) {
			const m = c.Members.find((x) => x.MemberType === "Property" && x.Name === prop);
			if (m) return (m.Tags || []).includes("NotScriptable") ? null : typeCode(m.ValueType);
		}
		return null;
	};
	const num = (v) => (v === null ? "inf" : String(v));
	const encodeDefault = (t, v) => {
		// v = { 종류: 값 } → 런타임의 Types.parseDefault가 읽는 글
		const [kind, val] = Object.entries(v)[0];
		if (t.startsWith("E:")) return kind === "Enum" ? "#" + val : null;
		switch (kind) {
			case "Bool":
				return t === "bool" ? String(val) : null;
			case "Int32":
			case "Int64":
			case "Float32":
			case "Float64":
				return ["int", "int64", "float", "double"].includes(t) ? num(val) : null;
			case "String":
				return t === "string" && !/[\t\r\n]/.test(val) ? val : null;
			case "Vector2":
				return t === "Vector2" ? val.map(num).join(", ") : null;
			case "Vector3":
				return t === "Vector3" ? val.map(num).join(", ") : null;
			case "Color3":
				return t === "Color3" ? val.map(num).join(", ") : null;
			case "UDim":
				return t === "UDim" ? val.map(num).join(", ") : null;
			case "UDim2":
				return t === "UDim2" ? val.flat().map(num).join(", ") : null;
			case "Rect":
				return t === "Rect" ? val.flat().map(num).join(", ") : null;
			case "NumberRange":
				return t === "NumberRange" ? val.map(num).join(" ") : null;
			default:
				return null;
		}
	};
	const lines = [];
	lines.push("-- 자동 생성: tools/mock/gen-api.mjs (" + path.basename(src) + ") — 손으로 고치지 않는다");
	lines.push("return {");
	lines.push("\tclasses = {");
	let nClass = 0;
	for (const c of dump.Classes) {
		const { names: ctags } = tagList(c.Tags);
		const rows = [(c.Superclass === "<<<ROOT>>>" ? "" : c.Superclass) + "\t" + ctags.join(",")];
		for (const m of c.Members) {
			const { names, preferred } = tagList(m.Tags);
			if (names.includes("NotScriptable")) continue;
			let flags = "";
			if (names.includes("Deprecated")) flags += "d";
			if (names.includes("Hidden")) flags += "h";
			if (m.MemberType === "Property") {
				if (names.includes("ReadOnly")) flags += "r";
				if (names.includes("WriteOnly")) flags += "w";
				const t = typeCode(m.ValueType);
				const rs = m.Security.Read === "None" ? "" : m.Security.Read;
				const ws = m.Security.Write === "None" ? "" : m.Security.Write;
				let def = "";
				const base = t.startsWith("E:") ? "E" : t;
				if (typeof m.Default === "string" && !m.Default.startsWith("__api_dump") && (KEEP_DEFAULT.has(base) || base === "E")) {
					flags += "D";
					def = clean(m.Default);
				}
				rows.push(["P", m.Name, t, flags, rs, ws, preferred, def].join("\t"));
			} else {
				if (names.includes("Yields") || names.includes("CanYield")) flags += "y";
				const sec = typeof m.Security === "string" ? (m.Security === "None" ? "" : m.Security) : "";
				const params = (m.Parameters || [])
					.map((p) => clean(p.Name) + ":" + typeCode(p.Type) + (p.Default !== undefined ? "=" : ""))
					.join(",");
				const kind = m.MemberType === "Function" ? "F" : m.MemberType === "Event" ? "E" : "K";
				rows.push([kind, m.Name, flags, sec, params, preferred].join("\t"));
			}
		}
		const defs = db && db.Classes[c.Name] && db.Classes[c.Name].DefaultProperties;
		if (defs) {
			for (const [prop, v] of Object.entries(defs)) {
				const t = propType(c.Name, prop);
				if (!t) continue;
				// 제 속성이고 덤프에 기본값이 있으면 그것을 쓴다(위의 P 줄)
				const own = c.Members.find((x) => x.MemberType === "Property" && x.Name === prop);
				if (own && typeof own.Default === "string" && !own.Default.startsWith("__api_dump")) continue;
				const enc = encodeDefault(t, v);
				if (enc !== null) rows.push(["D", prop, enc].join("\t"));
			}
		}
		lines.push("\t\t[" + luaString(c.Name) + "] = " + luaString(rows.join("\n")) + ",");
		nClass++;
	}
	lines.push("\t},");
	lines.push("\tenums = {");
	let nEnum = 0;
	for (const e of dump.Enums) {
		const items = e.Items.map((it) => it.Name + "=" + it.Value + (it.LegacyNames ? "~" + it.LegacyNames.join("~") : ""));
		lines.push("\t\t[" + luaString(e.Name) + "] = " + luaString(items.join(",")) + ",");
		nEnum++;
	}
	lines.push("\t},");
	lines.push("}");
	fs.mkdirSync(path.dirname(API_OUT), { recursive: true });
	fs.writeFileSync(API_OUT, lines.join("\n") + "\n");
	return { classes: nClass, enums: nEnum, bytes: fs.statSync(API_OUT).size, from: path.basename(src) + (db ? " + rbx-dom-database.json" : " (rbx-dom 자료 없음 — 물려받은 속성의 기본값은 어림)") };
}

// 없거나 덤프보다 낡았으면 다시 만든다
export function ensureApi() {
	const full = path.join(REF, "Full-API-Dump.json");
	const plain = path.join(REF, "API-Dump.json");
	const src = fs.existsSync(full) ? full : plain;
	const dbPath = path.join(REF, "rbx-dom-database.json");
	const newest = Math.max(fs.existsSync(src) ? fs.statSync(src).mtimeMs : 0, fs.existsSync(dbPath) ? fs.statSync(dbPath).mtimeMs : 0);
	if (fs.existsSync(API_OUT) && fs.existsSync(src) && fs.statSync(API_OUT).mtimeMs >= newest) return null;
	if (fs.existsSync(API_OUT) && !fs.existsSync(src)) return null; // 덤프는 없지만 만든 표가 있으면 그것을 쓴다
	return generate();
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	const r = generate();
	console.log(`만듦: ${API_OUT} — 클래스 ${r.classes} · 열거형 ${r.enums} · ${r.bytes} bytes (${r.from})`);
}
