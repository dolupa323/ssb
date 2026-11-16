// mock 자체 시험을 한꺼번에 돌린다.
//   node tools/mock/test.mjs
// 견본 프로젝트(sample/) · 일부러 틀린 프로젝트(sample/broken/) · 달의 계승자에서 베껴 온 화면 코드(work/lune-check/)를 돌려,
// 끝날 때의 코드와 나와야 하는 글을 본다. 화면 그림은 sample/shots/ 에 남는다.
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { pngSize } from "./shot.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..", "..");
const S = "tools/mock/sample";
const P = ["--project", `${S}/default.project.json`];
const SHOTS = ["--shot-dir", `${S}/shots`];

function run(script, args) {
	const t0 = Date.now();
	const r = spawnSync(process.execPath, [path.join(HERE, script), ...args], { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
	return { code: r.status, out: (r.stdout || "") + (r.stderr || ""), ms: Date.now() - t0 };
}

const cases = [
	{ name: "validate — 오타 · 틀린 형 · 자료형", script: "run.mjs", args: [...P, "--script", `${S}/scenarios/validate.luau`], code: 0, has: ["끝: validate", "오류 0"] },
	{ name: "sched — 차례지기 · 가상 시계 · 트윈 · 소리", script: "run.mjs", args: [...P, "--script", `${S}/scenarios/sched.luau`], code: 0, has: ["끝: sched", "Infinite yield possible"] },
	{ name: "layout — 자리 셈 · 누른 자리 · 글 칸", script: "run.mjs", args: [...P, "--script", `${S}/scenarios/layout.luau`], code: 0, has: ["끝: layout"] },
	{ name: "net — 원격 이벤트 · DataStore", script: "run.mjs", args: [...P, "--no-start", "--script", `${S}/scenarios/net.luau`], code: 0, has: ["끝: net", "[server] 서버: 닫는다", "기록을 저장하지 못했다"] },
	{ name: "ui 1280x720 — 견본 게임 · 화면 찍기", script: "run.mjs", args: [...P, "--script", `${S}/scenarios/ui.luau`, ...SHOTS], code: 0, has: ["끝: ui 1280x720"], png: [["ui-1280x720-1.png", 1280, 720], ["ui-1280x720-2.png", 1280, 720]] },
	{ name: "ui 844x390 — 폰 가로", script: "run.mjs", args: [...P, "--viewport", "844x390", "--script", `${S}/scenarios/ui.luau`, ...SHOTS], code: 0, has: ["끝: ui 844x390"], png: [["ui-844x390-1.png", 844, 390], ["ui-844x390-2.png", 844, 390]] },
	{ name: "ui — 신호를 바로 부르기(--signals immediate)", script: "run.mjs", args: [...P, "--signals", "immediate", "--script", `${S}/scenarios/ui.luau`, "--shot-dir", "tools/mock/out"], code: 0, has: ["끝: ui 1280x720"] },
	{ name: "gallery — 화면 그림이 받는 것들", script: "run.mjs", args: [...P, "--script", `${S}/scenarios/gallery.luau`, "--assets", `${S}/assets.json`, ...SHOTS], code: 0, has: ["끝: gallery"], png: [["gallery-1280x720.png", 1280, 720]] },
	{ name: "misc — 그 밖의 서비스(--touch)", script: "run.mjs", args: [...P, "--touch", "--script", `${S}/scenarios/misc.luau`], code: 0, has: ["끝: misc"] },
	{ name: "perf — 움직이는 ImageLabel 300개 · 600장", script: "run.mjs", args: [...P, "--script", `${S}/scenarios/perf.luau`, "--shot-dir", "tools/mock/out"], code: 0, has: ["600장:"], show: /움직이는 ImageLabel.*/ },
	{ name: "시나리오 없이 — 견본 60장", script: "run.mjs", args: [...P, "--frames", "60"], code: 0, has: ["끝: 60장", "오류 0"] },
	{ name: "fail — 일부러 실패(코드 1이어야 한다)", script: "run.mjs", args: [...P, "--script", `${S}/scenarios/fail.luau`], code: 1, has: ["확인 실패: 일부러 틀린 확인: 3 이어야 하는데 2 이다", "확인 실패: 이것도 틀렸다", "오류가 나야 하는데 나지 않았다", "scenarios/fail.luau:7: Sise is not a valid member of Frame", "3개 실패"], hasNot: ["여기까지 오면 안 된다"] },
	{
		name: "broken — 일부러 틀린 프로젝트(코드 1이어야 한다)",
		script: "run.mjs",
		args: ["--project", `${S}/broken/default.project.json`, "--frames", "330"],
		code: 1,
		has: [
			"server/Bad.server.luau:11: attempt to index nil with 'Name'",
			"server/Bad.server.luau:7: DataStore: 값.onDone",
			'client/Util.luau:6: TextColour3 is not a valid member of TextLabel "Players.Player1.PlayerGui.ScreenGui.TextLabel" — 혹시 "TextColor3"?',
			"client/Util.luau:6 function style",
			"client/Broken.client.luau:11 function build",
			"client/Syntax.client.luau:2: Expected identifier",
			"client/Later.client.luau:13: Unable to assign property Size. UDim2 expected, got Vector2",
			"client/Later.client.luau:20: attempt to index nil with 'x'",
			"Requested module was required recursively",
			"Module code did not return exactly one value",
			"경고 [client] 일부러 낸 경고 123",
			"Infinite yield possible on 'Players.Player1.PlayerScripts.client:WaitForChild(\"NeverComes\")'",
			"오류 6 · 경고 2",
		],
		hasNot: ["여기까지 오면 안 된다"],
	},
	{ name: "lune-check — 달의 계승자의 stage · canvas · sprite(베낀 것)", script: "run.mjs", args: ["--project", "tools/mock/work/lune-check/default.project.json", "--script", "tools/mock/work/lune-check/check.luau", "--shot-dir", "tools/mock/work/lune-check"], code: 0, has: ["끝: lune-check"] },
	{ name: "analyze — 견본(틀린 것 없음)", script: "analyze.mjs", args: [...P], code: 0, has: ["끝: 틀린 것 없음"] },
	{
		name: "analyze — 일부러 틀린 프로젝트(코드 1이어야 한다)",
		script: "analyze.mjs",
		args: ["--project", `${S}/broken/default.project.json`],
		code: 1,
		has: ["client/Static.luau(15,9): TypeError: Argument count mismatch", "client/Static.luau(17,22): TypeError: Unknown global 'undefinedName'", "client/Syntax.client.luau(2,11): SyntaxError", 'Instance.new("TextLable") — 없는 클래스 (혹시 TextLabel?)', "Enum.Font.SourceSansBolt", "Enum.TextXAlignmet — 없는 열거형", 'GetService("TweenServise")', 'IsA("GuiObjekt")', ".AbsolutSize", ".TextColour3 = …"],
	},
];

let failed = 0;
const only = process.argv[2];
for (const c of cases) {
	if (only && !c.name.includes(only)) continue;
	const r = run(c.script, c.args);
	const problems = [];
	if (r.code !== c.code) problems.push(`끝난 코드 ${r.code} (기대 ${c.code})`);
	for (const h of c.has || []) if (!r.out.includes(h)) problems.push(`나와야 하는 글이 없다: ${h}`);
	for (const h of c.hasNot || []) if (r.out.includes(h)) problems.push(`나오면 안 되는 글이 있다: ${h}`);
	for (const [file, w, h] of c.png || []) {
		const f = path.join(ROOT, S, "shots", file);
		const size = fs.existsSync(f) ? pngSize(f) : null;
		if (!size) problems.push(`화면 그림이 없다: ${file}`);
		else if (size.w !== w || size.h !== h) problems.push(`화면 그림의 크기가 ${size.w}x${size.h} (기대 ${w}x${h}): ${file}`);
	}
	const sum = /끝: .*$/m.exec(r.out);
	const extra = c.show ? (c.show.exec(r.out) || [""])[0] : "";
	console.log(`${problems.length ? "실패" : "통과"}  ${c.name}  (${(r.ms / 1000).toFixed(1)}초)`);
	if (sum) console.log(`        ${sum[0]}`);
	if (extra) console.log(`        ${extra}`);
	if (problems.length) {
		failed++;
		for (const p of problems) console.log("        ! " + p);
		console.log(r.out.split("\n").slice(-40).map((l) => "        | " + l).join("\n"));
	}
}
console.log(failed ? `\n자체 시험: ${failed}개 실패` : "\n자체 시험: 모두 통과");
process.exit(failed ? 1 : 0);
