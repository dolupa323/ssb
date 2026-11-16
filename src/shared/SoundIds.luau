--!strict
-- 구운 소리 파일을 로블록스에 올린 뒤 받은 에셋 번호를 적는 곳.
-- 예: sfx1 = "rbxassetid://1234567890"  (assets/audio/sfx1.wav를 올리고 받은 번호)
-- 비어 있는("") 파일의 소리는 나지 않는다(오류 없이 조용히 넘어간다).
-- tools/audio/bake.mjs가 다시 만들어도 여기 적은 번호는 그대로 둔다.
return {
	-- 2026-11-16에 dolupa95 계정으로 올림(크리에이터 허브 · 이름 ssb_sfx1 · ssb_music1~3)
	sfx1 = "rbxassetid://80923132757326", -- assets/audio/sfx1.wav · 179.9초 · 모노
	music1 = "rbxassetid://138528906442642", -- assets/audio/music1.wav · 100.2초 · 스테레오
	music2 = "rbxassetid://113220874777450", -- assets/audio/music2.wav · 90.1초 · 스테레오
	music3 = "rbxassetid://86343753679377", -- assets/audio/music3.wav · 62.8초 · 스테레오
}
