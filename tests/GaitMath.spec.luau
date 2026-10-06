--!strict
local GaitMath = require("../src/shared/GaitMath")
local t = require("./harness")

local STANCE = { STANCE_WIDTH = 1.4, STAGGER = 0.5 }
local STEP = { STEP_TIME_SLOW = 0.2, STEP_TIME_FAST = 0.12, FAST_STEP_SPEED = 16 }

t.describe("GaitMath.homeOffset", function()
	t.test("feet sit half the stance width either side of the hips", function()
		local rx = GaitMath.homeOffset("Right", nil, STANCE)
		local lx = GaitMath.homeOffset("Left", nil, STANCE)
		t.near(rx, 0.7, 1e-9)
		t.near(lx, -0.7, 1e-9)
	end)

	t.test("without the ball the feet are level", function()
		local _, z = GaitMath.homeOffset("Right", nil, STANCE)
		t.near(z, 0, 1e-9)
	end)

	t.test("with the ball, the ball-side foot is back and the other forward", function()
		local _, rightZ = GaitMath.homeOffset("Right", "Right", STANCE)
		local _, leftZ = GaitMath.homeOffset("Left", "Right", STANCE)
		t.near(rightZ, -0.25, 1e-9)
		t.near(leftZ, 0.25, 1e-9)
		-- Switching hands swaps the stagger.
		local _, rightZ2 = GaitMath.homeOffset("Right", "Left", STANCE)
		t.near(rightZ2, 0.25, 1e-9)
	end)
end)

t.describe("GaitMath.pickStepper", function()
	t.test("no foot steps while both are close enough", function()
		t.equal(GaitMath.pickStepper(0.1, 0.2, 0.4, nil), nil)
	end)

	t.test("the foot further from its spot steps first", function()
		t.equal(GaitMath.pickStepper(0.9, 0.5, 0.4, nil), "Right")
		t.equal(GaitMath.pickStepper(0.5, 0.9, 0.4, nil), "Left")
	end)

	t.test("only a foot past the threshold steps", function()
		t.equal(GaitMath.pickStepper(0.1, 0.5, 0.4, "Right"), "Left")
	end)

	t.test("on a tie the lead foot goes first (shuffle: lead, then trail)", function()
		t.equal(GaitMath.pickStepper(0.6, 0.6, 0.4, "Left"), "Left")
		t.equal(GaitMath.pickStepper(0.6, 0.6, 0.4, "Right"), "Right")
	end)
end)

t.describe("GaitMath.keepApart", function()
	t.test("a right foot can't land left of the left foot", function()
		t.near(GaitMath.keepApart("Right", -1, -0.7, 0.6), -0.1, 1e-9)
	end)

	t.test("a left foot can't land right of the right foot", function()
		t.near(GaitMath.keepApart("Left", 1, 0.7, 0.6), 0.1, 1e-9)
	end)

	t.test("a foot already on its own side is left alone", function()
		t.near(GaitMath.keepApart("Right", 0.7, -0.7, 0.6), 0.7, 1e-9)
		t.near(GaitMath.keepApart("Left", -0.7, 0.7, 0.6), -0.7, 1e-9)
	end)
end)

t.describe("GaitMath.stepDuration", function()
	t.test("slow steps when standing, fast steps at speed", function()
		t.near(GaitMath.stepDuration(0, STEP), 0.2, 1e-9)
		t.near(GaitMath.stepDuration(16, STEP), 0.12, 1e-9)
		t.near(GaitMath.stepDuration(40, STEP), 0.12, 1e-9)
		t.near(GaitMath.stepDuration(8, STEP), 0.16, 1e-9)
	end)
end)

t.describe("GaitMath.swing", function()
	t.test("starts on the ground and lands on the ground", function()
		local along0, height0 = GaitMath.swing(0)
		local along1, height1 = GaitMath.swing(1)
		t.near(along0, 0, 1e-9)
		t.near(height0, 0, 1e-9)
		t.near(along1, 1, 1e-9)
		t.near(height1, 0, 1e-9)
	end)

	t.test("highest and halfway along at the middle", function()
		local along, height = GaitMath.swing(0.5)
		t.near(along, 0.5, 1e-9)
		t.near(height, 1, 1e-9)
	end)

	t.test("short steps lift less than long ones, within the limits", function()
		t.near(GaitMath.liftFor(0.2, 0.25, 0.08, 0.4), 0.08, 1e-9)
		t.near(GaitMath.liftFor(1, 0.25, 0.08, 0.4), 0.25, 1e-9)
		t.near(GaitMath.liftFor(5, 0.25, 0.08, 0.4), 0.4, 1e-9)
	end)
end)

return nil
