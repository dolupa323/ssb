// 화면 적은 것(JSON) → HTML → 화면 없는 Chrome으로 PNG.
//   node tools/mock/shot.mjs 적은것.json 그림.png [--assets 짝.json]
// run.mjs는 renderShot()을 불러 쓴다. Roblox와 점 하나까지 같지는 않다(README의 「어림」 목록).
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT_DIR = path.join(HERE, "out");
const BROWSERS = ["C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"];

// ---------- PNG 쓰기(RGBA) ----------
const CRC_TABLE = (() => {
	const t = new Uint32Array(256);
	for (let n = 0; n < 256; n++) {
		let c = n;
		for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
		t[n] = c >>> 0;
	}
	return t;
})();
function crc32(buf) {
	let c = 0xffffffff;
	for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
	return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
	const len = Buffer.alloc(4);
	len.writeUInt32BE(data.length);
	const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
	const crc = Buffer.alloc(4);
	crc.writeUInt32BE(crc32(td));
	return Buffer.concat([len, td, crc]);
}
export function encodePng(w, h, rgba) {
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(w, 0);
	ihdr.writeUInt32BE(h, 4);
	ihdr[8] = 8;
	ihdr[9] = 6;
	const raw = Buffer.alloc((w * 4 + 1) * h);
	for (let y = 0; y < h; y++) {
		raw[y * (w * 4 + 1)] = 0;
		rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
	}
	return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 6 })), chunk("IEND", Buffer.alloc(0))]);
}
// PNG의 크기만 읽는다
export function pngSize(file) {
	const b = fs.readFileSync(file);
	if (b.length < 24 || b.readUInt32BE(0) !== 0x89504e47) return null;
	return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
}

// ---------- 그림 짝(에셋 번호 → 로컬 PNG) ----------
export function loadAssets(file) {
	if (!file || !fs.existsSync(file)) return {};
	const raw = JSON.parse(fs.readFileSync(file, "utf8"));
	const base = path.dirname(path.resolve(file));
	const out = {};
	for (const [k, v] of Object.entries(raw)) {
		if (typeof v !== "string") continue;
		const key = /^\d+$/.test(k) ? "rbxassetid://" + k : k;
		out[key] = path.resolve(base, v);
	}
	return out;
}

// ---------- HTML ----------
function esc(s) {
	return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}
const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${Math.max(0, Math.min(1, a)).toFixed(3)})`;

function fontStack(fam) {
	const f = String(fam || "");
	if (/Inconsolata|RobotoMono|Code|PressStart/i.test(f)) return '"D2Coding","Consolas","Malgun Gothic",monospace';
	if (/Merriweather|Guru|Accanthis|Roman|Balthazar|Fondamento|Grenze/i.test(f)) return '"Batang","Georgia","Malgun Gothic",serif';
	return '"Malgun Gothic","맑은 고딕","Apple SD Gothic Neo","Noto Sans KR","Segoe UI",sans-serif';
}

// Roblox의 꾸밈 글(RichText) → HTML (기본 꼬리표만)
function richToHtml(s, sizePx) {
	let out = "";
	const re = /<(\/?)([a-zA-Z]+)((?:\s+[a-zA-Z]+\s*=\s*"[^"]*")*)\s*(\/?)>|([^<]+)|(<)/g;
	let m;
	while ((m = re.exec(s))) {
		if (m[5] !== undefined) {
			out += m[5].replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>");
			continue;
		}
		if (m[6] !== undefined) {
			out += "&lt;";
			continue;
		}
		const close = m[1] === "/";
		const tag = m[2].toLowerCase();
		const attrs = {};
		for (const a of (m[3] || "").matchAll(/([a-zA-Z]+)\s*=\s*"([^"]*)"/g)) attrs[a[1].toLowerCase()] = a[2];
		if (tag === "br") out += "<br>";
		else if (tag === "b" || tag === "i" || tag === "u" || tag === "s") out += close ? `</${tag}>` : `<${tag}>`;
		else if (tag === "font" || tag === "stroke" || tag === "mark" || tag === "uc" || tag === "uppercase" || tag === "sc" || tag === "smallcaps") {
			if (close) out += "</span>";
			else {
				let st = "";
				if (tag === "font") {
					if (attrs.color) st += `color:${attrs.color};`;
					if (attrs.size) st += `font-size:${(Number(attrs.size) * 0.85 * (sizePx.scale || 1)).toFixed(2)}px;`;
					if (attrs.weight) st += `font-weight:${/^\d+$/.test(attrs.weight) ? attrs.weight : attrs.weight.toLowerCase() === "bold" ? 700 : 400};`;
					if (attrs.transparency) st += `opacity:${1 - Number(attrs.transparency)};`;
				} else if (tag === "stroke") st += `-webkit-text-stroke:${(Number(attrs.thickness || 1) * 2).toFixed(1)}px ${attrs.color || "#000"};paint-order:stroke fill;`;
				else if (tag === "mark") st += `background:${attrs.color || "#ff0"};`;
				else if (tag === "uc" || tag === "uppercase") st += "text-transform:uppercase;";
				else st += "font-variant:small-caps;";
				out += `<span style="${st}">`;
			}
		}
	}
	return out;
}

function gradientCss(gr, base, baseAlpha) {
	// Roblox: Rotation 0 = 왼쪽 → 오른쪽. CSS: 90deg = 왼쪽 → 오른쪽
	const pts = new Set();
	for (const c of gr.cs) pts.add(c[0]);
	for (const t of gr.ts) pts.add(t[0]);
	const at = (keys, t, n) => {
		for (let i = 0; i < keys.length - 1; i++) {
			const a = keys[i], b = keys[i + 1];
			if (t >= a[0] && t <= b[0]) {
				const f = b[0] === a[0] ? 0 : (t - a[0]) / (b[0] - a[0]);
				return Array.from({ length: n }, (_, j) => a[1 + j] + (b[1 + j] - a[1 + j]) * f);
			}
		}
		return keys[keys.length - 1].slice(1, 1 + n);
	};
	const stops = [...pts].sort((a, b) => a - b).map((t) => {
		const c = at(gr.cs, t, 3);
		const tr = at(gr.ts, t, 1)[0];
		const col = [Math.round((base[0] * c[0]) / 255), Math.round((base[1] * c[1]) / 255), Math.round((base[2] * c[2]) / 255)];
		return `${rgba(col, baseAlpha * (1 - tr))} ${((t + gr.off[0]) * 100).toFixed(2)}%`;
	});
	return `linear-gradient(${(gr.rot + 90).toFixed(2)}deg, ${stops.join(", ")})`;
}

export function buildHtml(data, images, assets, opts = {}) {
	const W = data.w, H = data.h;
	const imgSrc = {}; // 열쇠 → URL
	const imgList = []; // 페이지에 싣는 그림 { key, url }
	const useImage = (key, url) => {
		if (!(key in imgSrc)) {
			imgSrc[key] = imgList.length;
			imgList.push({ key, url });
		}
		return imgSrc[key];
	};
	const draws = []; // 캔버스에 그릴 것
	const parts = [];
	let cid = 0;
	for (const it of data.items) {
		const cx = it.clip ? it.clip[0] : 0, cy = it.clip ? it.clip[1] : 0;
		if (it.clip) {
			const cw = Math.max(0, it.clip[2] - it.clip[0]), ch = Math.max(0, it.clip[3] - it.clip[1]);
			parts.push(`<div class="c" style="left:${cx}px;top:${cy}px;width:${cw}px;height:${ch}px">`);
		}
		let style = `left:${(it.x - cx).toFixed(2)}px;top:${(it.y - cy).toFixed(2)}px;width:${it.w}px;height:${it.h}px;`;
		if (it.rot) {
			const tf = it.rot.map((r) => {
				const px = (r[0] - it.x).toFixed(2), py = (r[1] - it.y).toFixed(2);
				return `translate(${px}px,${py}px) rotate(${r[2]}deg) translate(${-px}px,${-py}px)`;
			});
			style += `transform-origin:0 0;transform:${tf.join(" ")};`;
		}
		if (it.a !== undefined) style += `opacity:${it.a};`;
		if (it.cr) style += `border-radius:${it.cr}px;`;
		const shadows = [];
		if (it.bg) {
			const alpha = 1 - it.bt;
			style += it.gr ? `background:${gradientCss(it.gr, it.bg, alpha)};` : `background:${rgba(it.bg, alpha)};`;
			if (it.bs && !it.cr) {
				const col = rgba(it.bc, alpha);
				if (it.bm === "Inset") shadows.push(`inset 0 0 0 ${it.bs}px ${col}`);
				else if (it.bm === "Middle") shadows.push(`0 0 0 ${it.bs / 2}px ${col}`, `inset 0 0 0 ${it.bs / 2}px ${col}`);
				else shadows.push(`0 0 0 ${it.bs}px ${col}`);
			}
		}
		if (it.st && !it.st.text && it.st.t > 0) shadows.push(`0 0 0 ${it.st.t}px ${rgba(it.st.c, 1 - it.st.tr)}`);
		if (shadows.length) style += `box-shadow:${shadows.join(",")};`;
		let inner = "";
		if (it.img) {
			const im = it.img;
			let source;
			if (im.ei !== undefined) {
				const key = "ei:" + im.ei + ":" + im.ver;
				const rec = images[key];
				source = rec ? { i: useImage(key, rec.url) } : { missing: "EditableImage(점 자료 없음)" };
			} else if (assets[im.src]) {
				source = { i: useImage(im.src, pathToFileURL(assets[im.src]).href) };
			} else source = { missing: im.src };
			const cw = Math.max(1, Math.round(it.w)), ch = Math.max(1, Math.round(it.h));
			const id = "k" + cid++;
			inner += `<canvas id="${id}" width="${cw}" height="${ch}" style="width:${it.w}px;height:${it.h}px;opacity:${(1 - im.tr).toFixed(3)};${it.cr ? `border-radius:${it.cr}px;` : ""}"></canvas>`;
			draws.push({ id, ...source, rx: im.rx, ry: im.ry, rw: im.rw, rh: im.rh, col: im.col, scale: im.scale, px: im.resample === "Pixelated", slice: im.slice, ss: im.sliceScale, tile: im.tile, w: cw, h: ch });
		}
		if (it.txt) {
			const t = it.txt;
			const jc = t.ax === "Left" ? "flex-start" : t.ax === "Right" ? "flex-end" : "center";
			const ai = t.ay === "Top" ? "flex-start" : t.ay === "Bottom" ? "flex-end" : "center";
			let ts = `font-size:${(t.size * 0.85).toFixed(2)}px;line-height:${(t.size * t.lh).toFixed(2)}px;color:${rgba(t.col, 1 - t.tr)};font-family:${fontStack(t.font.fam)};font-weight:${t.font.weight};`;
			if (t.font.italic) ts += "font-style:italic;";
			ts += `text-align:${t.ax === "Left" ? "left" : t.ax === "Right" ? "right" : "center"};`;
			ts += t.wrap ? "white-space:pre-wrap;overflow-wrap:anywhere;max-width:100%;" : "white-space:pre;";
			if (t.trunc !== "None") ts += "overflow:hidden;text-overflow:ellipsis;max-width:100%;";
			if (it.st && it.st.text && it.st.t > 0) ts += `-webkit-text-stroke:${(it.st.t * 2).toFixed(2)}px ${rgba(it.st.c, 1 - it.st.tr)};paint-order:stroke fill;`;
			else if (t.sc) {
				const col = rgba(t.sc, 1 - t.str);
				ts += `text-shadow:1px 0 ${col},-1px 0 ${col},0 1px ${col},0 -1px ${col},1px 1px ${col},-1px -1px ${col},1px -1px ${col},-1px 1px ${col};`;
			}
			const html = t.rich ? richToHtml(t.s, { scale: 1 }) : esc(t.s).replace(/\n/g, "<br>");
			inner += `<div class="t" style="justify-content:${jc};align-items:${ai}"><div style='${ts}'>${html}</div></div>`;
		}
		parts.push(`<div class="i" data-n="${esc(it.n)}" style="${style}">${inner}</div>`);
		if (it.clip) parts.push("</div>");
	}
	let overlay = "";
	if (opts.coreOverlay !== false && data.inset > 0) {
		// Roblox 기본 단추(메뉴 · 채팅)가 놓이는 자리 — 어림으로 그려 둔다(가려지는 것을 알아보게)
		const s = 44, top = Math.max(0, (data.inset - s) / 2);
		for (let i = 0; i < 2; i++) overlay += `<div class="core" style="left:${12 + i * (s + 8)}px;top:${top}px;width:${s}px;height:${s}px"></div>`;
	}
	const safe = (v) => JSON.stringify(v).replace(/</g, "\\u003c"); // (글 안의 "</script>"가 스크립트를 끊지 않게)
	const script = `
const IM = ${safe(imgList.map((x) => x.url))};
const DR = ${safe(draws)};
function placeholder(ctx, d) {
	ctx.fillStyle = "#d9c7e8"; ctx.fillRect(0, 0, d.w, d.h);
	ctx.strokeStyle = "#8a5fb0"; ctx.lineWidth = 1;
	ctx.beginPath();
	for (let x = -d.h; x < d.w; x += 8) { ctx.moveTo(x, 0); ctx.lineTo(x + d.h, d.h); }
	ctx.stroke();
	ctx.strokeRect(0.5, 0.5, d.w - 1, d.h - 1);
	const label = String(d.missing).replace("rbxassetid://", "#") + (d.rw || d.rh ? " [" + d.rx + "," + d.ry + " " + d.rw + "x" + d.rh + "]" : "");
	ctx.font = "10px Consolas, monospace"; ctx.textBaseline = "top";
	const tw = ctx.measureText(label).width;
	ctx.fillStyle = "rgba(255,255,255,0.85)"; ctx.fillRect(1, 1, Math.min(d.w - 2, tw + 4), 12);
	ctx.fillStyle = "#402060"; ctx.fillText(label, 3, 2, Math.max(1, d.w - 6));
}
function paint(ctx, img, d) {
	let sx = d.rx, sy = d.ry, sw = d.rw, sh = d.rh;
	if (sw === 0 && sh === 0) { sx = 0; sy = 0; sw = img.naturalWidth; sh = img.naturalHeight; }
	let fx = false, fy = false;
	if (sw < 0) { sx += sw; sw = -sw; fx = true; }
	if (sh < 0) { sy += sh; sh = -sh; fy = true; }
	ctx.save();
	if (fx || fy) { ctx.translate(fx ? d.w : 0, fy ? d.h : 0); ctx.scale(fx ? -1 : 1, fy ? -1 : 1); }
	if (d.scale === "Fit" || d.scale === "Crop") {
		const k = d.scale === "Fit" ? Math.min(d.w / sw, d.h / sh) : Math.max(d.w / sw, d.h / sh);
		const w = sw * k, h = sh * k;
		ctx.drawImage(img, sx, sy, sw, sh, (d.w - w) / 2, (d.h - h) / 2, w, h);
	} else if (d.scale === "Tile" && d.tile) {
		for (let y = 0; y < d.h; y += Math.max(1, d.tile[1])) for (let x = 0; x < d.w; x += Math.max(1, d.tile[0])) ctx.drawImage(img, sx, sy, sw, sh, x, y, d.tile[0], d.tile[1]);
	} else if (d.scale === "Slice" && d.slice) {
		const [l, t, r, b] = d.slice, k = d.ss || 1;
		const xs = [0, l, r, sw], ys = [0, t, b, sh];
		const dx = [0, l * k, d.w - (sw - r) * k, d.w], dy = [0, t * k, d.h - (sh - b) * k, d.h];
		for (let j = 0; j < 3; j++) for (let i = 0; i < 3; i++) {
			const w = xs[i + 1] - xs[i], h = ys[j + 1] - ys[j];
			if (w > 0 && h > 0 && dx[i + 1] > dx[i] && dy[j + 1] > dy[j]) ctx.drawImage(img, sx + xs[i], sy + ys[j], w, h, dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j]);
		}
	} else ctx.drawImage(img, sx, sy, sw, sh, 0, 0, d.w, d.h);
	ctx.restore();
}
function drawAll(imgs) {
	for (const d of DR) {
		const cv = document.getElementById(d.id), ctx = cv.getContext("2d");
		if (d.missing !== undefined) { placeholder(ctx, d); continue; }
		const img = imgs[d.i];
		if (!img || !img.naturalWidth) { d.missing = "그림을 읽지 못함"; placeholder(ctx, d); continue; }
		ctx.imageSmoothingEnabled = !d.px;
		paint(ctx, img, d);
		if (d.col[0] !== 255 || d.col[1] !== 255 || d.col[2] !== 255) {
			ctx.globalCompositeOperation = "multiply";
			ctx.fillStyle = "rgb(" + d.col.join(",") + ")"; ctx.fillRect(0, 0, d.w, d.h);
			ctx.globalCompositeOperation = "destination-in";
			paint(ctx, img, d);
			ctx.globalCompositeOperation = "source-over";
		}
	}
	document.title = "done";
}
const imgs = IM.map((u) => { const im = new Image(); im.src = u; return im; });
Promise.all(imgs.map((im) => im.decode().catch(() => null))).then(() => drawAll(imgs));
`;
	return `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;width:${W}px;height:${H}px;overflow:hidden;background:#3b4a5a}
.c{position:absolute;overflow:hidden}
.i{position:absolute;box-sizing:border-box}
.i canvas{position:absolute;left:0;top:0;display:block}
.t{position:absolute;inset:0;display:flex}
.core{position:absolute;border:1px dashed rgba(255,255,255,.8);border-radius:10px;background:rgba(0,0,0,.35);box-sizing:border-box}
</style></head><body>${parts.join("\n")}${overlay}<script>${script}</script></body></html>`;
}

export function findBrowser() {
	for (const b of BROWSERS) if (fs.existsSync(b)) return b;
	return null;
}

// data = 화면 적은 것 · images = { "ei:번호:판": { w, h, b64 } } · outPng = 그림 파일
export function renderShot(data, images, outPng, opts = {}) {
	const browser = opts.browser || findBrowser();
	if (!browser) throw new Error("Chrome/Edge를 찾지 못했다");
	const shots = path.join(OUT_DIR, "shots");
	fs.mkdirSync(shots, { recursive: true });
	const urls = {};
	for (const [key, rec] of Object.entries(images)) {
		if (!rec.url) {
			const png = encodePng(rec.w, rec.h, Buffer.from(rec.b64, "base64"));
			rec.url = "data:image/png;base64," + png.toString("base64");
		}
		urls[key] = rec;
	}
	const html = buildHtml(data, urls, opts.assets || {}, opts);
	const base = path.basename(outPng).replace(/\.png$/i, "");
	const htmlPath = path.join(shots, base + ".html");
	fs.writeFileSync(htmlPath, html);
	fs.mkdirSync(path.dirname(path.resolve(outPng)), { recursive: true });
	const profile = path.join(OUT_DIR, "chrome-profile");
	const args = [
		"--headless=new",
		"--disable-gpu",
		"--hide-scrollbars",
		"--no-first-run",
		"--no-default-browser-check",
		"--disable-extensions",
		// 바깥으로 나가는 것을 끈다(업데이트 확인 · 동기화 · 통계) — 로컬 HTML만 연다
		"--disable-background-networking",
		"--disable-component-update",
		"--disable-sync",
		"--disable-default-apps",
		"--disable-domain-reliability",
		"--no-pings",
		"--metrics-recording-only",
		"--allow-file-access-from-files",
		"--force-device-scale-factor=1",
		`--user-data-dir=${profile}`,
		`--window-size=${data.w},${data.h}`,
		"--virtual-time-budget=3000",
		`--screenshot=${path.resolve(outPng)}`,
		pathToFileURL(htmlPath).href,
	];
	if (fs.existsSync(outPng)) fs.rmSync(outPng);
	const r = spawnSync(browser, args, { encoding: "utf8", timeout: 180000 }); // (다른 일이 같이 돌면 Chrome이 뜨는 데 수십 초가 걸리기도 한다)
	if (!fs.existsSync(outPng)) throw new Error("화면을 찍지 못했다: " + (r.stderr || r.error || "").toString().slice(0, 400));
	const size = pngSize(outPng);
	return { png: path.resolve(outPng), html: htmlPath, size };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	const args = process.argv.slice(2);
	let assets = null;
	const rest = [];
	for (let i = 0; i < args.length; i++) {
		if (args[i] === "--assets") assets = args[++i];
		else rest.push(args[i]);
	}
	if (rest.length < 2) {
		console.error("쓰는 법: node tools/mock/shot.mjs 적은것.json 그림.png [--assets 짝.json]");
		process.exit(2);
	}
	const dump = JSON.parse(fs.readFileSync(rest[0], "utf8"));
	const r = renderShot(dump.shot || dump, dump.images || {}, rest[1], { assets: loadAssets(assets) });
	console.log(`찍음: ${r.png} (${r.size ? r.size.w + "x" + r.size.h : "?"})`);
}
