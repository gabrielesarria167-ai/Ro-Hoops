--!strict
local SkillMath = require("../src/shared/SkillMath")
local t = require("./harness")

local SWIPE = { SWIPE_DISTANCE = 0.06, SWIPE_WINDOW = 0.12 }
local MOVE = { SIDE_DOMINANCE = 1 }
local CIRCLE = { CIRCLE_ANGLE = 300, CIRCLE_WINDOW = 0.7, CIRCLE_MIN_LENGTH = 0.25 }

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

-- Cursor readings every 1/60 s going round a circle of `radius` screen heights, `turns`
-- times round in `seconds`. `direction` 1 = counterclockwise, -1 = clockwise.
local function circle(radius: number, turns: number, seconds: number, direction: number): { SkillMath.Sample }
	local samples = {}
	local frames = math.floor(seconds * 60)
	for i = 0, frames do
		local angle = direction * turns * 2 * math.pi * i / frames
		table.insert(samples, { t = i / 60, x = 0.5 + radius * math.cos(angle), y = 0.5 + radius * math.sin(angle) })
	end
	return samples
end

t.describe("SkillMath.detectCircle", function()
	t.test("a full counterclockwise circle is detected as +1", function()
		t.equal(SkillMath.detectCircle(circle(0.08, 1, 0.4, 1), CIRCLE), 1)
	end)

	t.test("a full clockwise circle is detected as -1", function()
		t.equal(SkillMath.detectCircle(circle(0.08, 1, 0.4, -1), CIRCLE), -1)
	end)

	t.test("half a circle is not enough", function()
		t.equal(SkillMath.detectCircle(circle(0.08, 0.5, 0.3, 1), CIRCLE), nil)
	end)

	t.test("a tiny circle (a wobble) does not count", function()
		t.equal(SkillMath.detectCircle(circle(0.02, 1, 0.4, 1), CIRCLE), nil)
	end)

	t.test("a straight flick is not a circle", function()
		t.equal(SkillMath.detectCircle(path(1.5, 0, 8), CIRCLE), nil)
	end)

	t.test("a zigzag (turning back and forth) cancels out", function()
		local samples = {}
		for i = 0, 40 do
			-- Left-right zigzag drifting upward.
			local x = if i % 10 < 5 then (i % 5) * 0.02 else (5 - i % 5) * 0.02
			table.insert(samples, { t = i / 60, x = 0.5 + x, y = 0.5 + i * 0.005 })
		end
		t.equal(SkillMath.detectCircle(samples, CIRCLE), nil)
	end)

	t.test("a circle drawn too slowly (outside the window) does not count", function()
		t.equal(SkillMath.detectCircle(circle(0.08, 1, 2, 1), CIRCLE), nil)
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

	t.test("a mostly backward flick is a step-back, whichever hand has the ball", function()
		t.equal(SkillMath.chooseMove(-0.3, -1, "Right", MOVE), "StepBack")
		t.equal(SkillMath.chooseMove(0.3, -1, "Left", MOVE), "StepBack")
	end)

	t.test("a mostly forward flick does nothing (kept free for a later move)", function()
		t.equal(SkillMath.chooseMove(-0.3, 1, "Right", MOVE), nil)
	end)

	t.test("a diagonal leaning sideways still counts", function()
		t.equal(SkillMath.chooseMove(-1, 0.8, "Right", MOVE), "Crossover")
	end)
end)

return nil
