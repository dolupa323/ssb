-- 자체 시험: 일부러 실패한다 — 확인 실패와 시나리오의 오류가 「끝날 때의 코드 1」로 이어지는지 본다(test.mjs가 부른다).
local h = harness
h.eq(1 + 1, 3, "일부러 틀린 확인")
h.expect(false, "이것도 틀렸다")
h.expectError(function() end, "오류", "오류가 나야 하는데 나지 않는다")
local frame = Instance.new("Frame");
(frame :: any).Sise = UDim2.new() -- 시나리오 안의 오타 → 시나리오가 오류로 멈춘다
print("여기까지 오면 안 된다")
