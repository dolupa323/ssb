// 견본 그림 파일을 만든다(화면 찍기 시험에서 「에셋 번호 → 로컬 PNG」 짝을 볼 때 쓴다).
//   node tools/mock/sample/make-assets.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { encodePng } from "../shot.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(HERE, "assets");
fs.mkdirSync(OUT, { recursive: true });

function image(w, h, fn) {
	const buf = Buffer.alloc(w * h * 4);
	for (let y = 0; y < h; y++)
		for (let x = 0; x < w; x++) {
			const [r, g, b, a] = fn(x, y);
			const i = (y * w + x) * 4;
			buf[i] = r;
			buf[i + 1] = g;
			buf[i + 2] = b;
			buf[i + 3] = a;
		}
	return encodePng(w, h, buf);
}

// 아홉 조각 틀(24x24): 테두리 4 · 모서리가 둥글다
fs.writeFileSync(
	path.join(OUT, "panel.png"),
	image(24, 24, (x, y) => {
		const dx = Math.min(x, 23 - x), dy = Math.min(y, 23 - y);
		if (dx + dy < 3) return [0, 0, 0, 0];
		if (dx < 4 || dy < 4) return [250, 200, 60, 255];
		return [40, 50, 80, 255];
	}),
);
// 무늬(16x16): 대각선 줄
fs.writeFileSync(path.join(OUT, "tile.png"), image(16, 16, (x, y) => ((x + y) % 8 < 4 ? [70, 130, 200, 255] : [230, 240, 255, 255])));
// 가로로 긴 그림(48x16): 왼쪽 빨강 · 가운데 초록 · 오른쪽 파랑, 왼쪽 위에 흰 점(방향을 알아보게)
fs.writeFileSync(
	path.join(OUT, "wide.png"),
	image(48, 16, (x, y) => {
		if (x < 4 && y < 4) return [255, 255, 255, 255];
		return x < 16 ? [220, 60, 60, 255] : x < 32 ? [60, 190, 90, 255] : [60, 90, 220, 255];
	}),
);
fs.writeFileSync(
	path.join(HERE, "assets.json"),
	JSON.stringify({ "rbxassetid://9001": "assets/panel.png", "rbxassetid://9002": "assets/tile.png", "9003": "assets/wide.png" }, null, 2) + "\n",
);
console.log("만듦: " + OUT + " (panel.png · tile.png · wide.png) · assets.json");
