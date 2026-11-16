-- 로블록스에 올린 그림 판의 에셋 번호. 열쇠 = 판의 이름(Atlas.pages[i].name · 글자 판은 font_*) = assets/<이름>.png.
--  여기 적힌 판은 올린 그림을 쓰고(기기 메모리에 판을 직접 만들지 않는다), 빠진 판은 코드에 실린 점 자료로 만든다.
--  2026-11-16에 dolupa95 계정으로 올림(크리에이터 허브 · 이름 ssb_<판 이름>).
--  주의: 크리에이터 허브가 보여 주는 번호는 「데칼」 번호라 그림으로 쓸 수 없다("Asset type does not match requested type").
--   여기에는 그 데칼 안의 **그림(Image) 번호**를 적는다 — Studio 편집 상태에서 InsertService:LoadAsset(데칼 번호)로 읽은 Decal.Texture
--   (tools/studio/args/decal2image.json). 오른쪽 주석이 데칼 번호다.
--  그림을 다시 구우면(node tools/bake/bake.mjs · node tools/font/bake.mjs) 바뀐 판은 다시 올리고 번호를 고쳐야 한다 —
--   안 고치면 옛 그림에 새 자리표를 대어 그림이 어긋난다.
return {
	chars1 = "rbxassetid://132708788325990", -- 데칼 89436922368074
	mask1 = "rbxassetid://112858634798285", -- 데칼 93786954705365
	world1 = "rbxassetid://76327994263563", -- 데칼 81136765497516
	world2 = "rbxassetid://110342747783068", -- 데칼 105967792701673
	fx1 = "rbxassetid://134603973614398", -- 데칼 101159298788995
	fx2 = "rbxassetid://104264006981744", -- 데칼 135733377352930
	icons1 = "rbxassetid://125649776224430", -- 데칼 117847085335484
	floor_street = "rbxassetid://99396933611489", -- 데칼 92279794100402
	floor_gates = "rbxassetid://129523704236027", -- 데칼 126238882021730
	floor_platA = "rbxassetid://90978368371042", -- 데칼 95328094329717
	floor_train = "rbxassetid://93570173394963", -- 데칼 137848202367725
	floor_platB = "rbxassetid://101018358828557", -- 데칼 114416728929340
	floor_office = "rbxassetid://110500641887082", -- 데칼 110187298144914
	font_dh_s = "rbxassetid://94978207203489", -- 데칼 83390867349380
	font_dh_l = "rbxassetid://139977661791262", -- 데칼 84569420729211
	font_vt = "rbxassetid://87748938658465", -- 데칼 87153964147691
}
