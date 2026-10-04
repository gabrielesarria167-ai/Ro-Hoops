--!strict
local SkillMath = require("../src/shared/SkillMath")
local t = require("./harness")

local SWIPE = { SWIPE_DISTANCE = 0.06, SWIPE_WINDOW = 0.12 }
local MOVE = { SIDE_DOMINANCE = 1 }

-- Cursor readings every 1/60 s moving `vx`, `vy` screen heights per second.
local function path(vx: number, vy: number, frames: number): { SkillMath.Sample }
	local samples = {}
	for i = 0, frames do
		local time = i / 60
		table.insert(samples, { t = time, x = 0.5 + vx * time, y = 0.5 + vy * time })
	end
	return samples
end

t.describe("SkillMath.detectSwipe", function()
	t.test("a fast flick right is detected, pointing right", function()
		local dx, dy = SkillMath.detectSwipe(path(1.5, 0, 6), SWIPE)
		t.truthy(dx and dx > 0, "dx > 0")
		t.near(dy :: number, 0, 1e-9)
	end)

	t.test("a fast flick left points left", function()
		local dx = SkillMath.detectSwipe(path(-1.5, 0, 6), SWIPE)
		t.truthy(dx and dx < 0, "dx < 0")
	end)

	t.test("slow cursor movement is not a flick, however long it lasts", function()
		t.equal(SkillMath.detectSwipe(path(0.3, 0, 120), SWIPE), nil)
	end)

	t.test("only the last SWIPE_WINDOW seconds count", function()
		-- Moved a lot long ago, then stopped: not a flick now.
		local samples = path(2, 0, 6)
		table.insert(samples, { t = 1, x = samples[#samples].x, y = 0.5 })
		t.equal(SkillMath.detectSwipe(samples, SWIPE), nil)
	end)

	t.test("needs at least two readings", function()
		t.equal(SkillMath.detectSwipe({ { t = 0, x = 0, y = 0 } }, SWIPE), nil)
		t.equal(SkillMath.detectSwipe({}, SWIPE), nil)
	end)
end)

t.describe("SkillMath.chooseMove", function()
	t.test("flicking toward the empty hand is a crossover", function()
		t.equal(SkillMath.chooseMove(-1, 0, "Right", MOVE), "Crossover")
		t.equal(SkillMath.chooseMove(1, 0, "Left", MOVE), "Crossover")
	end)

	t.test("flicking toward the hand that has the ball does nothing", function()
		t.equal(SkillMath.chooseMove(1, 0, "Right", MOVE), nil)
		t.equal(SkillMath.chooseMove(-1, 0, "Left", MOVE), nil)
	end)

	t.test("mostly forward or back flicks are not crossovers", function()
		t.equal(SkillMath.chooseMove(-0.3, 1, "Right", MOVE), nil)
		t.equal(SkillMath.chooseMove(-0.3, -1, "Right", MOVE), nil)
	end)

	t.test("a diagonal leaning sideways still counts", function()
		t.equal(SkillMath.chooseMove(-1, 0.8, "Right", MOVE), "Crossover")
	end)
end)

return nil
