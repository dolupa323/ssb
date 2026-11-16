-- 시험용 대역(진짜 src/client/Sound.luau가 아니다): 불린 것을 적어 두기만 한다. 시나리오가 「어디서 어떤 소리를 냈는가」를 확인한다.
local Sound = {}
Sound.isStub = true
Sound.inits = 0
Sound.volume = nil :: any -- { music, sfx }
Sound.log = {} :: { any } -- { name, pan, arg }
Sound.state = nil :: any -- 마지막 music(state)
Sound.musicCalls = 0

function Sound.init()
	Sound.inits += 1
end

function Sound.vol(music: number, sfx: number)
	Sound.volume = { music = music, sfx = sfx }
end

function Sound.sfx(name: string, pan: number?, arg: any)
	table.insert(Sound.log, { name = name, pan = pan, arg = arg })
	if #Sound.log > 4000 then
		table.remove(Sound.log, 1)
	end
end

function Sound.music(state: any)
	Sound.musicCalls += 1
	Sound.state = table.clone(state)
end

-- 시나리오용: 그 이름의 소리가 몇 번 났는가
function Sound.count(name: string): number
	local n = 0
	for _, e in Sound.log do
		if e.name == name then
			n += 1
		end
	end
	return n
end

return Sound
