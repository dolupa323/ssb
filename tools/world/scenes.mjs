// 장면 목록. 두 쪽(driver.luau · orig/driver.js)이 같은 뜻으로 읽는다.
const run = (ticks, extra) => Object.assign({ op: "run", ticks, input: "bot" }, extra || {});
const shot = (name, extra) => Object.assign({ op: "shot", name }, extra || {});
const set = (obj, key, value) => ({ op: "set", obj, key, value });
const BASE = { w: [["card", 3], ["backpack", 2], ["battery", 2], ["coffee", 1]], p: [] };
const crowd = (k = 1, ry) => [
	{ op: "spawn", type: "pass", n: 36 * k, r: 300, ry },
	{ op: "spawn", type: "stud", n: 8 * k, r: 260, ry },
	{ op: "spawn", type: "intern", n: 8 * k, r: 280, ry },
	{ op: "spawn", type: "zomb", n: 8 * k, r: 300, ry },
	{ op: "spawn", type: "runner", n: 4 * k, r: 320, ry },
	{ op: "spawn", type: "uncle", n: 3 * k, r: 200, ry },
	{ op: "spawn", type: "carrier", n: 2 * k, r: 240, ry },
	{ op: "spawn", type: "flyer", n: 6 * k, r: 340, ry },
];
const K = { keepHp: true, hold: 6 };
const W = ["card", "umbrella", "backpack", "coffee", "anc", "shout", "battery", "hotpack", "scooter", "selfie", "handle", "alarm", "tie", "laptop", "gum", "shoulder"];
const lv = (names, l) => names.map((n) => [n, l]);
const zoneScene = (name, i, boss, extra) => ({
	name, seed: 20 + i, diff: 2, build: BASE,
	steps: [
		run(4, { input: "none" }), { op: "enterZone", i }, run(50, K), shot("enter"), ...crowd(1, i === 3 ? 60 : undefined), run(120, K), shot("fight"),
		...(extra || []),
		{ op: "boss", type: boss }, run(40, K), shot("bossin"), run(260, K), shot("boss1"), set("S", "rage", 2), run(300, K), shot("boss2"), { op: "bossHp", frac: 0.4 }, run(300, K), shot("boss3"),
		{ op: "bossHp", frac: 0.0001 }, run(60, K), shot("bossdie"), run(160, K), shot("after"),
	],
});

export const SCENES = [
	{
		name: "street", seed: 11, diff: 1, build: BASE,
		steps: [
			run(360), shot("walk"), ...crowd(), run(90, K), shot("fight"), set("S", "trainT", 0.05), run(40, K), shot("buswarn"), run(110, K), shot("bus"),
			{ op: "boss", type: "flyboss" }, run(50, K), shot("bossin"), run(200, K), shot("boss"),
		],
	},
	zoneScene("gates", 1, "bagman"),
	zoneScene("platA", 2, "doorman", [set("S", "trainT", 0.05), run(40, K), shot("trainwarn"), run(100, K), shot("train")]),
	zoneScene("train", 3, "speaker", [set("S", "zt", 80), run(200, { keepHp: true }), shot("doors")]),
	zoneScene("platB", 4, "crowd"),
	zoneScene("esc", 5, "carrierboss"),
	zoneScene("office", 6, "lead"),
	// 무기 16종: 1레벨 → 6레벨 → 진화
	...[0, 1, 2, 3].map((g) => ({
		name: "weapons" + g, seed: 40 + g, diff: 1, build: { w: lv(W.slice(g * 4, g * 4 + 4), 1), p: [["tumbler", 2]] },
		steps: [
			run(4, { input: "none" }), ...crowd(), run(150, K), shot("lv1"),
			{ op: "build", w: lv(W.slice(g * 4, g * 4 + 4), 6), p: [["tumbler", 2]], fus: [] }, ...crowd(), run(170, K), shot("lv6"),
			{ op: "build", w: lv(W.slice(g * 4, g * 4 + 4), 7), p: [["tumbler", 2]], fus: [] }, ...crowd(), run(170, K), shot("evo"), run(47, K), shot("evo2"),
		],
	})),
	// 히든 조합 5종
	...["bulldozer", "routine", "gentleman", "freepass", "remote"].map((f, i) => ({
		name: "fuse." + f, seed: 50 + i, diff: 1, build: { w: [["gum", 2]], p: [["tumbler", 1]] },
		steps: [
			run(4, { input: "none" }), { op: "build", w: [["gum", 2]], p: [["tumbler", 1]], fus: [f] }, ...crowd(), run(140, K), shot("a"), ...crowd(), run(97, { keepHp: true, hold: 6, dashEvery: 30 }), shot("b"),
			{ op: "boss", type: "bagman" }, run(260, { keepHp: true, hold: 6, dashEvery: 45 }), shot("c"),
		],
	})),
	// 줍는 것 · 회복 · 레벨 업 · 폭주 · 피격
	{
		name: "items", seed: 61, diff: 2, build: BASE,
		steps: [
			run(4, { input: "none" }), { op: "item", kind: "chest", dx: 90, dy: -40 }, { op: "item", kind: "kimbap", dx: -80, dy: 50 }, { op: "item", kind: "pass", dx: 60, dy: 80 }, { op: "item", kind: "chest", dx: 900, dy: -500 },
			...crowd(), { op: "spawn", type: "pass", n: 6, r: 200, elite: true }, run(30, { input: "none", keepHp: true }), shot("items"), set("S", "rage", 3), set("p", "hp", 20), run(120, { hold: 6 }), shot("lowhp"),
			run(200, K), shot("later"),
		],
	},
	// 무거운 장면: 적 450
	{
		name: "heavy", seed: 71, diff: 3, build: { w: [["card", 5], ["backpack", 4], ["anc", 4], ["hotpack", 3], ["battery", 3]], p: [["tumbler", 3]] },
		steps: [
			run(4, { input: "none" }), { op: "enterZone", i: 6 }, ...crowd(6).map((c) => Object.assign({}, c, { hp: 1e7 })), set("S", "admRate", 0), run(240, K), shot("crowd"),
			{ op: "steady", name: "데우기", ticks: 600, keepHp: true, hold: 6 }, { op: "steady", name: "그 뒤 1", ticks: 600, keepHp: true, hold: 6 }, { op: "steady", name: "그 뒤 2", ticks: 600, keepHp: true, hold: 6 }, shot("end"),
		],
	},
	// 메뉴 뒤의 시연 (mode = menu · 카메라를 왼쪽으로 밀어 둠)
	{ name: "menu", seed: 81, diff: 1, mode: "menu", offX: -0.2, build: BASE, steps: [set("S", "t", 18), run(420, { keepHp: true }), shot("demo")] },
	// 처음부터 끝까지 봇이 하는 판 (화면은 찍지 않는다 — 오류 없이 일곱 장소를 다 도는지). 멘탈을 채워 주어 끝까지 간다
	...[
		["full.a", 101, 2, ["card", "backpack", "anc", "hotpack", "battery"]],
		["full.b", 102, 1, ["umbrella", "coffee", "shout", "scooter", "selfie"]],
		["full.c", 103, 3, ["handle", "alarm", "tie", "laptop", "gum"]],
		["full.d", 104, 0, ["shoulder", "card", "tie", "umbrella", "backpack"]],
	].map(([name, seed, diff, ws]) => ({ name, seed, diff, noOrig: true, build: { w: lv(ws, 7), p: [["tumbler", 3], ["shoes", 2]] }, steps: [run(45000, { keepHp: true, stepEvery: 30 })] })),
	// 도착 축하 · 옵션
	{ name: "celebrate", seed: 91, diff: 1, build: BASE, steps: [run(120), { op: "celebrate" }, run(90, K), shot("confetti"), { op: "opts", fx: 0, bloom: 0, shake: 0 }, ...crowd(), run(120, K), shot("fx0")] },
];
