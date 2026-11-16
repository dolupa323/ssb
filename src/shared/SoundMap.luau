--!strict
-- 자동 생성 (tools/audio/bake.mjs) — 손으로 고치지 말 것. 다시 구우면 덮어쓴다.
-- 원본 commute-survival/js/audio.js의 합성 소리를 구운 파일(assets/audio/*.wav) 안의 구간 표.
-- 시각은 초. 구간 = { sheet = 파일 이름(SoundIds의 키), t0 = 시작, t1 = 끝, vol = 음량 배수 }
local SoundMap = {}

-- 구운 파일
SoundMap.sheets = {
	sfx1 = { file = "sfx1.wav", length = 179.885034, channels = 1 },
	music1 = { file = "music1.wav", length = 100.174943, channels = 2 },
	music2 = { file = "music2.wav", length = 90.109093, channels = 2 },
	music3 = { file = "music3.wav", length = 62.773401, channels = 2 },
}

-- 효과음. gap = 원본의 최소 간격(초 — 이보다 빨리 다시 부르면 무시). sets[갈래] = 무작위로 하나 고르는 구간들.
-- kind가 인자(arg)로 갈래를 고르는 법:
--   "one"  인자 없음 → sets.one
--   "flag" 인자가 참(진화한 무기)이면 sets.on, 아니면 sets.off
--   "key"  인자가 글자(hit: 무기 이름 · voice: 보스 종류) → sets[arg], 없으면 sets[default]. hit은 간격도 무기마다 따로 잰다
--   "pick" 원두 줍기: 0.4초 안에 이어 주우면 음이 한 칸씩 오른다(0~12). 값(arg)이 3 이상이면 sets["b"..칸], 아니면 sets["a"..칸]
--   "tick" 남은 초(arg 0~10) → sets["n"..arg]
SoundMap.sfx = {
	hit = { gap = 0.045, kind = "key", default = "card", sets = {
		card = { { sheet = "sfx1", t0 = 46.089048, t1 = 46.166712, vol = 1 }, { sheet = "sfx1", t0 = 46.416712, t1 = 46.496417, vol = 1 }, { sheet = "sfx1", t0 = 46.746417, t1 = 46.825714, vol = 1 } },
		umbrella = { { sheet = "sfx1", t0 = 47.075714, t1 = 47.176825, vol = 1 }, { sheet = "sfx1", t0 = 47.426825, t1 = 47.528639, vol = 1 }, { sheet = "sfx1", t0 = 47.778639, t1 = 47.880136, vol = 1 } },
		backpack = { { sheet = "sfx1", t0 = 48.130136, t1 = 48.247234, vol = 1 }, { sheet = "sfx1", t0 = 48.497234, t1 = 48.613605, vol = 1 }, { sheet = "sfx1", t0 = 48.863605, t1 = 48.979955, vol = 1 } },
		coffee = { { sheet = "sfx1", t0 = 49.229955, t1 = 49.342902, vol = 1 }, { sheet = "sfx1", t0 = 49.592902, t1 = 49.70458, vol = 1 }, { sheet = "sfx1", t0 = 49.95458, t1 = 50.066599, vol = 1 } },
		hotpack = { { sheet = "sfx1", t0 = 50.316599, t1 = 50.402789, vol = 1 }, { sheet = "sfx1", t0 = 50.652789, t1 = 50.736599, vol = 1 }, { sheet = "sfx1", t0 = 50.986599, t1 = 51.074127, vol = 1 } },
		anc = { { sheet = "sfx1", t0 = 51.324127, t1 = 51.417868, vol = 1 }, { sheet = "sfx1", t0 = 51.667868, t1 = 51.760748, vol = 1 }, { sheet = "sfx1", t0 = 52.010748, t1 = 52.10322, vol = 1 } },
		battery = { { sheet = "sfx1", t0 = 52.35322, t1 = 52.426236, vol = 1 }, { sheet = "sfx1", t0 = 52.676236, t1 = 52.748753, vol = 1 }, { sheet = "sfx1", t0 = 52.998753, t1 = 53.071451, vol = 1 } },
		shout = { { sheet = "sfx1", t0 = 53.321451, t1 = 53.41415, vol = 1 }, { sheet = "sfx1", t0 = 53.66415, t1 = 53.75771, vol = 1 }, { sheet = "sfx1", t0 = 54.00771, t1 = 54.10127, vol = 1 } },
		scooter = { { sheet = "sfx1", t0 = 54.35127, t1 = 54.460862, vol = 1 }, { sheet = "sfx1", t0 = 54.710862, t1 = 54.819252, vol = 1 }, { sheet = "sfx1", t0 = 55.069252, t1 = 55.179615, vol = 1 } },
		selfie = { { sheet = "sfx1", t0 = 55.429615, t1 = 55.508073, vol = 1 }, { sheet = "sfx1", t0 = 55.758073, t1 = 55.83746, vol = 1 }, { sheet = "sfx1", t0 = 56.08746, t1 = 56.166032, vol = 1 } },
		handle = { { sheet = "sfx1", t0 = 56.416032, t1 = 56.502608, vol = 1 }, { sheet = "sfx1", t0 = 56.752608, t1 = 56.83941, vol = 1 }, { sheet = "sfx1", t0 = 57.08941, t1 = 57.176327, vol = 1 } },
		alarm = { { sheet = "sfx1", t0 = 57.426327, t1 = 57.526463, vol = 1 }, { sheet = "sfx1", t0 = 57.776463, t1 = 57.876553, vol = 1 }, { sheet = "sfx1", t0 = 58.126553, t1 = 58.228707, vol = 1 } },
		tie = { { sheet = "sfx1", t0 = 58.478707, t1 = 58.557347, vol = 1 }, { sheet = "sfx1", t0 = 58.807347, t1 = 58.885624, vol = 1 }, { sheet = "sfx1", t0 = 59.135624, t1 = 59.213288, vol = 1 } },
		laptop = { { sheet = "sfx1", t0 = 59.463288, t1 = 59.536735, vol = 1 }, { sheet = "sfx1", t0 = 59.786735, t1 = 59.860907, vol = 1 }, { sheet = "sfx1", t0 = 60.110907, t1 = 60.184649, vol = 1 } },
		gum = { { sheet = "sfx1", t0 = 60.434649, t1 = 60.51966, vol = 1 }, { sheet = "sfx1", t0 = 60.76966, t1 = 60.855442, vol = 1 }, { sheet = "sfx1", t0 = 61.105442, t1 = 61.190544, vol = 1 } },
		shoulder = { { sheet = "sfx1", t0 = 61.440544, t1 = 61.55644, vol = 1 }, { sheet = "sfx1", t0 = 61.80644, t1 = 61.924603, vol = 1 }, { sheet = "sfx1", t0 = 62.174603, t1 = 62.291429, vol = 1 } },
	} },
	crit = { gap = 0.06, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 62.541429, t1 = 62.705193, vol = 1 } },
	} },
	kill = { gap = 0.04, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 62.955193, t1 = 63.058277, vol = 1 }, { sheet = "sfx1", t0 = 63.308277, t1 = 63.411497, vol = 1 }, { sheet = "sfx1", t0 = 63.661497, t1 = 63.763628, vol = 1 }, { sheet = "sfx1", t0 = 64.013628, t1 = 64.116485, vol = 1 } },
	} },
	elitedie = { gap = 0.2, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 64.366485, t1 = 65.231995, vol = 1 } },
	} },
	trainkill = { gap = 0.05, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 65.481995, t1 = 65.57746, vol = 1 }, { sheet = "sfx1", t0 = 65.82746, t1 = 65.921814, vol = 1 }, { sheet = "sfx1", t0 = 66.171814, t1 = 66.267029, vol = 1 } },
	} },
	pick = { gap = 0.03, kind = "pick", sets = {
		a0 = { { sheet = "sfx1", t0 = 66.517029, t1 = 66.626531, vol = 1 } },
		a1 = { { sheet = "sfx1", t0 = 66.876531, t1 = 66.986054, vol = 1 } },
		a2 = { { sheet = "sfx1", t0 = 67.236054, t1 = 67.34576, vol = 1 } },
		a3 = { { sheet = "sfx1", t0 = 67.59576, t1 = 67.705306, vol = 1 } },
		a4 = { { sheet = "sfx1", t0 = 67.955306, t1 = 68.064989, vol = 1 } },
		a5 = { { sheet = "sfx1", t0 = 68.314989, t1 = 68.42458, vol = 1 } },
		a6 = { { sheet = "sfx1", t0 = 68.67458, t1 = 68.784218, vol = 1 } },
		a7 = { { sheet = "sfx1", t0 = 69.034218, t1 = 69.143719, vol = 1 } },
		a8 = { { sheet = "sfx1", t0 = 69.393719, t1 = 69.503424, vol = 1 } },
		a9 = { { sheet = "sfx1", t0 = 69.753424, t1 = 69.863175, vol = 1 } },
		a10 = { { sheet = "sfx1", t0 = 70.113175, t1 = 70.222948, vol = 1 } },
		a11 = { { sheet = "sfx1", t0 = 70.472948, t1 = 70.582744, vol = 1 } },
		a12 = { { sheet = "sfx1", t0 = 70.832744, t1 = 70.942336, vol = 1 } },
		b0 = { { sheet = "sfx1", t0 = 71.192336, t1 = 71.363016, vol = 1 } },
		b1 = { { sheet = "sfx1", t0 = 71.613016, t1 = 71.783356, vol = 1 } },
		b2 = { { sheet = "sfx1", t0 = 72.033356, t1 = 72.20381, vol = 1 } },
		b3 = { { sheet = "sfx1", t0 = 72.45381, t1 = 72.623878, vol = 1 } },
		b4 = { { sheet = "sfx1", t0 = 72.873878, t1 = 73.04458, vol = 1 } },
		b5 = { { sheet = "sfx1", t0 = 73.29458, t1 = 73.464422, vol = 1 } },
		b6 = { { sheet = "sfx1", t0 = 73.714422, t1 = 73.885351, vol = 1 } },
		b7 = { { sheet = "sfx1", t0 = 74.135351, t1 = 74.305306, vol = 1 } },
		b8 = { { sheet = "sfx1", t0 = 74.555306, t1 = 74.725669, vol = 1 } },
		b9 = { { sheet = "sfx1", t0 = 74.975669, t1 = 75.145873, vol = 1 } },
		b10 = { { sheet = "sfx1", t0 = 75.395873, t1 = 75.566576, vol = 1 } },
		b11 = { { sheet = "sfx1", t0 = 75.816576, t1 = 75.986463, vol = 1 } },
		b12 = { { sheet = "sfx1", t0 = 76.236463, t1 = 76.406009, vol = 1 } },
	} },
	card = { gap = 0.09, kind = "flag", sets = {
		off = { { sheet = "sfx1", t0 = 76.656009, t1 = 76.745079, vol = 1 } },
		on = { { sheet = "sfx1", t0 = 76.995079, t1 = 77.311927, vol = 1 } },
	} },
	swing = { gap = 0.09, kind = "flag", sets = {
		off = { { sheet = "sfx1", t0 = 77.561927, t1 = 77.736463, vol = 1 } },
		on = { { sheet = "sfx1", t0 = 77.986463, t1 = 78.267143, vol = 1 } },
	} },
	throw = { gap = 0.18, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 78.517143, t1 = 78.758571, vol = 1 } },
	} },
	splash = { gap = 0.12, kind = "flag", sets = {
		off = { { sheet = "sfx1", t0 = 79.008571, t1 = 79.504898, vol = 1 } },
		on = { { sheet = "sfx1", t0 = 79.754898, t1 = 80.436599, vol = 1 } },
	} },
	pulse = { gap = 0.18, kind = "flag", sets = {
		off = { { sheet = "sfx1", t0 = 80.686599, t1 = 80.935215, vol = 1 } },
		on = { { sheet = "sfx1", t0 = 81.185215, t1 = 81.554762, vol = 1 } },
	} },
	zap = { gap = 0.08, kind = "flag", sets = {
		off = { { sheet = "sfx1", t0 = 81.804762, t1 = 81.928322, vol = 1 }, { sheet = "sfx1", t0 = 82.178322, t1 = 82.302222, vol = 1 }, { sheet = "sfx1", t0 = 82.552222, t1 = 82.675805, vol = 1 } },
		on = { { sheet = "sfx1", t0 = 82.925805, t1 = 83.127664, vol = 1 }, { sheet = "sfx1", t0 = 83.377664, t1 = 83.579456, vol = 1 }, { sheet = "sfx1", t0 = 83.829456, t1 = 84.03102, vol = 1 } },
	} },
	shout = { gap = 0.3, kind = "flag", sets = {
		off = { { sheet = "sfx1", t0 = 84.28102, t1 = 85.163333, vol = 1 } },
		on = { { sheet = "sfx1", t0 = 85.413333, t1 = 86.283741, vol = 1 } },
	} },
	dash = { gap = 0.1, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 86.533741, t1 = 86.745374, vol = 1 } },
	} },
	dashready = { gap = 0.5, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 86.995374, t1 = 87.160862, vol = 1 } },
	} },
	hurt = { gap = 0.12, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 87.410862, t1 = 87.633175, vol = 1 } },
	} },
	slip = { gap = 1, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 87.883175, t1 = 88.143401, vol = 1 } },
	} },
	heal = { gap = 0.1, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 88.393401, t1 = 89.313492, vol = 1 } },
	} },
	level = { gap = 0.2, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 89.563492, t1 = 90.584807, vol = 1 } },
	} },
	chest = { gap = 0.3, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 90.834807, t1 = 91.868912, vol = 1 }, { sheet = "sfx1", t0 = 92.118912, t1 = 93.153016, vol = 1 }, { sheet = "sfx1", t0 = 93.403016, t1 = 94.43712, vol = 1 } },
	} },
	evo = { gap = 0.5, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 94.68712, t1 = 96.326984, vol = 1 } },
	} },
	select = { gap = 0.05, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 96.576984, t1 = 96.746417, vol = 1 } },
	} },
	hover = { gap = 0.04, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 96.996417, t1 = 97.062585, vol = 1 } },
	} },
	click = { gap = 0.04, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 97.312585, t1 = 97.386961, vol = 1 } },
	} },
	reroll = { gap = 0.15, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 97.636961, t1 = 97.9561, vol = 1 }, { sheet = "sfx1", t0 = 98.2061, t1 = 98.525261, vol = 1 }, { sheet = "sfx1", t0 = 98.775261, t1 = 99.094399, vol = 1 } },
	} },
	pause = { gap = 0.1, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 99.344399, t1 = 99.543197, vol = 1 } },
	} },
	resume = { gap = 0.1, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 99.793197, t1 = 99.991655, vol = 1 } },
	} },
	start = { gap = 0.5, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 100.241655, t1 = 101.538889, vol = 1 } },
	} },
	station = { gap = 1, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 101.788889, t1 = 103.065624, vol = 1 } },
	} },
	warn = { gap = 0.4, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 103.315624, t1 = 103.997143, vol = 1 } },
	} },
	alert = { gap = 0.25, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 104.247143, t1 = 104.410499, vol = 1 } },
	} },
	flick = { gap = 0.12, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 104.660499, t1 = 104.733129, vol = 1 } },
	} },
	elite = { gap = 0.5, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 104.983129, t1 = 105.738934, vol = 1 } },
	} },
	boss = { gap = 1, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 105.988934, t1 = 107.975986, vol = 1 } },
	} },
	voice = { gap = 0.5, kind = "key", default = "bagman", sets = {
		flyboss = { { sheet = "sfx1", t0 = 108.225986, t1 = 108.632562, vol = 1 }, { sheet = "sfx1", t0 = 108.882562, t1 = 109.377234, vol = 1 }, { sheet = "sfx1", t0 = 109.627234, t1 = 110.106009, vol = 1 } },
		bagman = { { sheet = "sfx1", t0 = 110.356009, t1 = 111.037891, vol = 1 }, { sheet = "sfx1", t0 = 111.287891, t1 = 111.969433, vol = 1 }, { sheet = "sfx1", t0 = 112.219433, t1 = 112.901247, vol = 1 } },
		doorman = { { sheet = "sfx1", t0 = 113.151247, t1 = 113.707937, vol = 1 }, { sheet = "sfx1", t0 = 113.957937, t1 = 114.502109, vol = 1 }, { sheet = "sfx1", t0 = 114.752109, t1 = 115.30619, vol = 1 } },
		speaker = { { sheet = "sfx1", t0 = 115.55619, t1 = 116.314286, vol = 1 }, { sheet = "sfx1", t0 = 116.564286, t1 = 117.331769, vol = 1 }, { sheet = "sfx1", t0 = 117.581769, t1 = 118.358844, vol = 1 } },
		crowd = { { sheet = "sfx1", t0 = 118.608844, t1 = 119.211769, vol = 1 }, { sheet = "sfx1", t0 = 119.461769, t1 = 120.074467, vol = 1 }, { sheet = "sfx1", t0 = 120.324467, t1 = 120.952041, vol = 1 } },
		carrierboss = { { sheet = "sfx1", t0 = 121.202041, t1 = 121.806735, vol = 1 }, { sheet = "sfx1", t0 = 122.056735, t1 = 122.604036, vol = 1 }, { sheet = "sfx1", t0 = 122.854036, t1 = 123.34356, vol = 1 } },
		lead = { { sheet = "sfx1", t0 = 123.59356, t1 = 124.238118, vol = 1 }, { sheet = "sfx1", t0 = 124.488118, t1 = 125.13449, vol = 1 }, { sheet = "sfx1", t0 = 125.38449, t1 = 126.042766, vol = 1 } },
	} },
	roar = { gap = 0.6, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 126.292766, t1 = 127.137234, vol = 1 } },
	} },
	paper = { gap = 0.15, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 127.387234, t1 = 127.617188, vol = 1 }, { sheet = "sfx1", t0 = 127.867188, t1 = 128.097324, vol = 1 }, { sheet = "sfx1", t0 = 128.347324, t1 = 128.578934, vol = 1 } },
	} },
	doorslam = { gap = 0.3, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 128.828934, t1 = 129.407937, vol = 1 } },
	} },
	wheels = { gap = 0.3, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 129.657937, t1 = 130.170975, vol = 1 }, { sheet = "sfx1", t0 = 130.420975, t1 = 130.934127, vol = 1 }, { sheet = "sfx1", t0 = 131.184127, t1 = 131.69771, vol = 1 } },
	} },
	zipper = { gap = 0.2, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 131.94771, t1 = 132.279796, vol = 1 } },
	} },
	rumble = { gap = 0.4, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 132.529796, t1 = 133.183129, vol = 1 }, { sheet = "sfx1", t0 = 133.433129, t1 = 134.081315, vol = 1 }, { sheet = "sfx1", t0 = 134.331315, t1 = 134.979796, vol = 1 } },
	} },
	bass = { gap = 0.4, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 135.229796, t1 = 135.862585, vol = 1 } },
	} },
	nag = { gap = 0.4, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 136.112585, t1 = 137.264603, vol = 1 }, { sheet = "sfx1", t0 = 137.514603, t1 = 138.673061, vol = 1 }, { sheet = "sfx1", t0 = 138.923061, t1 = 140.069161, vol = 1 } },
	} },
	phone = { gap = 0.6, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 140.319161, t1 = 141.0339, vol = 1 } },
	} },
	lash = { gap = 0.09, kind = "flag", sets = {
		off = { { sheet = "sfx1", t0 = 141.2839, t1 = 141.456848, vol = 1 } },
		on = { { sheet = "sfx1", t0 = 141.706848, t1 = 141.936825, vol = 1 } },
	} },
	beam = { gap = 0.12, kind = "flag", sets = {
		off = { { sheet = "sfx1", t0 = 142.186825, t1 = 142.425351, vol = 1 } },
		on = { { sheet = "sfx1", t0 = 142.675351, t1 = 142.965986, vol = 1 } },
	} },
	gum = { gap = 0.3, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 143.215986, t1 = 143.359615, vol = 1 } },
	} },
	bump = { gap = 0.12, kind = "flag", sets = {
		off = { { sheet = "sfx1", t0 = 143.609615, t1 = 143.803492, vol = 1 } },
		on = { { sheet = "sfx1", t0 = 144.053492, t1 = 144.310567, vol = 1 } },
	} },
	boss2 = { gap = 0.2, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 144.560567, t1 = 144.704512, vol = 1 } },
	} },
	bossdie = { gap = 1, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 144.954512, t1 = 146.743696, vol = 1 }, { sheet = "sfx1", t0 = 146.993696, t1 = 148.78288, vol = 1 }, { sheet = "sfx1", t0 = 149.03288, t1 = 150.822063, vol = 1 } },
	} },
	wave = { gap = 0.3, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 151.072063, t1 = 151.912608, vol = 1 } },
	} },
	spin = { gap = 0.5, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 152.162608, t1 = 153.201905, vol = 1 } },
	} },
	page = { gap = 0.3, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 153.451905, t1 = 154.668118, vol = 1 } },
	} },
	note = { gap = 0.2, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 154.918118, t1 = 155.095986, vol = 1 } },
	} },
	scooter = { gap = 0.15, kind = "flag", sets = {
		off = { { sheet = "sfx1", t0 = 155.345986, t1 = 155.738549, vol = 1 } },
		on = { { sheet = "sfx1", t0 = 155.988549, t1 = 156.384218, vol = 1 } },
	} },
	alarmboom = { gap = 0.08, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 156.634218, t1 = 157.423107, vol = 1 } },
	} },
	zone = { gap = 0.5, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 157.673107, t1 = 158.743673, vol = 1 } },
	} },
	doorclose = { gap = 0.5, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 158.993673, t1 = 159.89263, vol = 1 } },
	} },
	buswarn = { gap = 0.5, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 160.14263, t1 = 160.676735, vol = 1 } },
	} },
	buspass = { gap = 0.5, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 160.926735, t1 = 161.69619, vol = 1 } },
	} },
	stamp = { gap = 0.1, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 161.94619, t1 = 162.088594, vol = 1 } },
	} },
	boom = { gap = 0.1, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 162.338594, t1 = 163.228481, vol = 1 } },
	} },
	trainwarn = { gap = 0.5, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 163.478481, t1 = 165.494422, vol = 1 } },
	} },
	trainpass = { gap = 0.5, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 165.744422, t1 = 166.859524, vol = 1 } },
	} },
	trainhit = { gap = 0.3, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 167.109524, t1 = 167.536032, vol = 1 } },
	} },
	tick = { gap = 0.3, kind = "tick", sets = {
		n0 = { { sheet = "sfx1", t0 = 167.786032, t1 = 167.976009, vol = 1 } },
		n1 = { { sheet = "sfx1", t0 = 168.226009, t1 = 168.415714, vol = 1 } },
		n2 = { { sheet = "sfx1", t0 = 168.665714, t1 = 168.855465, vol = 1 } },
		n3 = { { sheet = "sfx1", t0 = 169.105465, t1 = 169.295374, vol = 1 } },
		n4 = { { sheet = "sfx1", t0 = 169.545374, t1 = 169.735261, vol = 1 } },
		n5 = { { sheet = "sfx1", t0 = 169.985261, t1 = 170.175283, vol = 1 } },
		n6 = { { sheet = "sfx1", t0 = 170.425283, t1 = 170.615306, vol = 1 } },
		n7 = { { sheet = "sfx1", t0 = 170.865306, t1 = 171.055193, vol = 1 } },
		n8 = { { sheet = "sfx1", t0 = 171.305193, t1 = 171.495215, vol = 1 } },
		n9 = { { sheet = "sfx1", t0 = 171.745215, t1 = 171.935329, vol = 1 } },
		n10 = { { sheet = "sfx1", t0 = 172.185329, t1 = 172.375465, vol = 1 } },
	} },
	win = { gap = 2, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 172.625465, t1 = 175.257483, vol = 1 } },
	} },
	lose = { gap = 2, kind = "one", sets = {
		one = { { sheet = "sfx1", t0 = 175.507483, t1 = 177.556281, vol = 1 } },
	} },
}

-- 음악. t0 = 처음, loop0 = 되풀이가 시작하는 곳, t1 = 끝 (t0→t1까지 튼 뒤 loop0~t1을 끝없이 되풀이).
-- phrase = 64스텝(4마디)의 길이(초). boss = 보스가 있을 때 겹쳐 트는 층(64스텝 순환, 노래의 스텝에 맞춘다).
SoundMap.music = {
	menu = { sheet = "music3", t0 = 41.653016, loop0 = 52.087483, t1 = 62.52195, vol = 1, bpm = 92, phrase = 10.434467 },
	songs = {
		[0] = { name = "신도림", sheet = "music1", t0 = 0.25, loop0 = 34.534263, t1 = 51.676395, vol = 1, bpm = 112, phrase = 8.571066, boss = { sheet = "sfx1", t0 = 0.251451, t1 = 8.822517, vol = 1 } },
		[1] = { name = "사당", sheet = "music1", t0 = 51.927846, loop0 = 83.924943, t1 = 99.923492, vol = 1, bpm = 120, phrase = 7.999274, boss = { sheet = "sfx1", t0 = 9.07542, t1 = 17.074694, vol = 1 } },
		[2] = { name = "교대", sheet = "music2", t0 = 0.25, loop0 = 30.72619, t1 = 45.964286, vol = 1, bpm = 126, phrase = 7.619048, boss = { sheet = "sfx1", t0 = 17.327596, t1 = 24.946644, vol = 1 } },
		[3] = { name = "강남", sheet = "music2", t0 = 46.215737, loop0 = 75.31034, t1 = 89.857642, vol = 1, bpm = 132, phrase = 7.273651, boss = { sheet = "sfx1", t0 = 25.199546, t1 = 32.473197, vol = 1 } },
		[4] = { name = "역삼", sheet = "music3", t0 = 0.25, loop0 = 27.684376, t1 = 41.401565, vol = 1, bpm = 140, phrase = 6.858594, boss = { sheet = "sfx1", t0 = 32.7261, t1 = 39.584694, vol = 1 } },
	},
	crash = { sheet = "sfx1", t0 = 178.393469, t1 = 179.635034, vol = 1 }, -- 노래가 바뀔 때 한 번 (음악 쪽 음량으로)
	heart = { sheet = "sfx1", t0 = 177.806281, t1 = 178.143469, vol = 1 }, -- 체력 30% 미만일 때 heartEvery초마다 (효과음 쪽 음량으로)
	heartEvery = 0.78,
	amb = { sheet = "sfx1", t0 = 39.837596, t1 = 45.837596, vol = 1 }, -- 웅성거림(끝없이 되풀이). 음량 = min(1, 적 수 / ambFull) (효과음 쪽 음량으로)
	ambFull = 400, ambTau = 0.4,
	lateSpeed = 1.08, -- 지각 상태: 원본은 박자만 8% 빨라진다 → PlaybackSpeed
	muffle = { low = 0, mid = -16, high = -48, tau = 0.12 }, -- 멈춤 화면: 원본은 520Hz 저역 통과 → EqualizerSoundEffect(dB)
}

return SoundMap
