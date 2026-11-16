// 공개 참고 자료를 받아 tools/mock/ref/ 에 둔다 (Roblox API 덤프 · luau-lsp의 Roblox 타입 정의).
//   node tools/mock/fetch-ref.mjs [--force]
// 보내는 것은 없다 — 공개 파일을 받기만 한다.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REF = path.join(HERE, "ref");
const FILES = [
	["API-Dump.json", "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json"],
	// 같은 저장소의 「기본값이 적힌」 덤프 — Instance.new 때의 속성 기본값을 여기서 읽는다
	["Full-API-Dump.json", "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Full-API-Dump.json"],
	// rbx-dom(Rojo 쪽)의 반사 자료 — 클래스마다 Instance.new 때의 속성 값(물려받은 속성까지)이 들어 있다
	["rbx-dom-database.json", "https://raw.githubusercontent.com/rojo-rbx/rbx-dom/master/rbx_dom_lua/src/database.json"],
	// luau-lsp의 Roblox 형 정의 — 이 빌드의 luau-analyze로는 읽히지 못한다(README). luau-lsp를 따로 쓸 때를 위해 받아 둔다
	["globalTypes.d.luau", "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"],
];
const force = process.argv.includes("--force");
fs.mkdirSync(REF, { recursive: true });
for (const [name, url] of FILES) {
	const dst = path.join(REF, name);
	if (fs.existsSync(dst) && !force) {
		console.log(`있음: ${name} (${fs.statSync(dst).size} bytes)`);
		continue;
	}
	const res = await fetch(url);
	if (!res.ok) {
		console.error(`받지 못함: ${name} — HTTP ${res.status}`);
		process.exitCode = 1;
		continue;
	}
	const buf = Buffer.from(await res.arrayBuffer());
	fs.writeFileSync(dst, buf);
	console.log(`받음: ${name} (${buf.length} bytes)`);
}
