-- (mock 확인용 가짜 자료) sprite.luau가 읽는 캐릭터 판: 장 = { 판 번호, x, y, w, h, dx, dy, 염색판 x?, 염색판 y? }
return {
	pages = { "chars1" },
	masks = { "masks1" },
	chars = {
		hero = {
			ox = 16,
			oy = 32,
			clips = {
				idle = { fps = 4, frames = { { 1, 0, 0, 32, 32, 0, 0, 0, 0 }, { 1, 32, 0, 32, 32, 0, 0, 32, 0 } } },
				walk = { fps = 8, frames = { { 1, 64, 0, 24, 32, 4, 0 }, { 1, 88, 0, 24, 32, 4, 0 } } },
			},
		},
		pet = {
			ox = 8,
			oy = 16,
			size = 0.5,
			clips = { idle = { fps = 2, frames = { { 1, 0, 32, 16, 16, 0, 0 } } } },
		},
	},
}
