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

	t.test("the lead foot goes first even when the trail foot is further off", function()
		t.equal(GaitMath.pickStepper(0.5, 1.2, 0.4, "Right"), "Right")
		t.equal(GaitMath.pickStepper(1.2, 0.5, 0.4, "Left"), "Left")
	end)

	t.test("the trail foot goes once the lead foot has landed (it no longer wants to step)", function()
		t.equal(GaitMath.pickStepper(0.1, 0.9, 0.4, "Right"), "Left")
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

	t.test("halfway along at the middle", function()
		local along = GaitMath.swing(0.5)
		t.near(along, 0.5, 1e-9)
	end)

	t.test("the lift peaks early (at LIFT_PEAK), not in the middle", function()
		local _, atPeak = GaitMath.swing(GaitMath.LIFT_PEAK)
		t.near(atPeak, 1, 1e-9)
		local _, early = GaitMath.swing(0.25)
		local _, late = GaitMath.swing(0.75)
		t.truthy(early > late, "the foot is higher a quarter in than three quarters in")
		for i = 0, 20 do
			local _, h = GaitMath.swing(i / 20)
			t.truthy(h <= 1 + 1e-9 and h >= 0, "lift stays between 0 and 1")
		end
	end)

	t.test("a different peak time moves the top of the lift", function()
		local _, atHalf = GaitMath.swing(0.5, 0.5)
		t.near(atHalf, 1, 1e-9)
	end)

	t.test("short steps lift less than long ones, within the limits", function()
		t.near(GaitMath.liftFor(0.2, 0.25, 0.08, 0.4), 0.08, 1e-9)
		t.near(GaitMath.liftFor(1, 0.25, 0.08, 0.4), 0.25, 1e-9)
		t.near(GaitMath.liftFor(5, 0.25, 0.08, 0.4), 0.4, 1e-9)
	end)
end)

t.describe("GaitMath.reachForCrouch", function()
	t.test("a standing leg (no crouch, no margin) reaches nowhere sideways", function()
		t.near(GaitMath.reachForCrouch(1.6, 0, 0), 0, 1e-9)
	end)

	t.test("the rig's dribble crouch reaches under a stud", function()
		-- 1.6 long leg, crouch 0.27 (hip 1.33 above the ankle), margin 0.08 (1.52 usable)
		t.near(GaitMath.reachForCrouch(1.6, 0.27, 0.08), math.sqrt(1.52 * 1.52 - 1.33 * 1.33), 1e-9)
		t.near(GaitMath.reachForCrouch(1.6, 0.27, 0), 0.889, 0.001)
	end)

	t.test("a lower crouch reaches further, up to the leg's full length", function()
		local low = GaitMath.reachForCrouch(1.6, 0.27, 0.08)
		local lower = GaitMath.reachForCrouch(1.6, 0.6, 0.08)
		t.truthy(lower > low, "deeper crouch = longer reach")
		t.near(GaitMath.reachForCrouch(1.6, 5, 0), 1.6, 1e-9)
		t.near(GaitMath.reachForCrouch(1.6, 5, 0.1), 1.5, 1e-9)
	end)

	t.test("the margin shortens the reach", function()
		t.truthy(
			GaitMath.reachForCrouch(1.6, 0.3, 0.1) < GaitMath.reachForCrouch(1.6, 0.3, 0),
			"margin 0.1 reaches less"
		)
	end)
end)

t.describe("GaitMath.effectiveStagger", function()
	t.test("a small change (a hand switch) keeps the planted stagger", function()
		t.near(GaitMath.effectiveStagger(0.1, -0.1, 0.35), -0.1, 1e-9)
	end)

	t.test("a big change takes the new stagger (the foot re-steps)", function()
		t.near(GaitMath.effectiveStagger(0.2, -0.2, 0.35), 0.2, 1e-9)
	end)
end)

t.describe("GaitMath.dipTravel", function()
	t.test("standing still and staying still goes nowhere", function()
		local dx, dz = GaitMath.dipTravel(0, 0, 0, 0, 60, 0.2)
		t.near(dx, 0, 1e-9)
		t.near(dz, 0, 1e-9)
	end)

	t.test("holding a steady velocity covers velocity x time", function()
		local dx, dz = GaitMath.dipTravel(3, -2, 3, -2, 60, 0.5)
		t.near(dx, 1.5, 1e-9)
		t.near(dz, -1, 1e-9)
	end)

	t.test("braking from 12 studs/s at 60 studs/s^2 stops after 0.2 s and 1.2 studs", function()
		local dx = GaitMath.dipTravel(12, 0, 0, 0, 60, 1)
		t.near(dx, 1.2, 1e-9)
	end)

	t.test("braking for less than the stop time covers less ground", function()
		local dx = GaitMath.dipTravel(12, 0, 0, 0, 60, 0.1)
		-- 12 * 0.1 - 0.5 * 60 * 0.01 = 0.9
		t.near(dx, 0.9, 1e-9)
	end)

	t.test("speeding up to a target velocity ends at that velocity", function()
		-- 0 -> -8 at 80 studs/s^2 takes 0.1 s (0.4 stud), then 0.1 s more at -8.
		local dx = GaitMath.dipTravel(0, 0, -8, 0, 80, 0.2)
		t.near(dx, -0.4 - 0.8, 1e-9)
	end)
end)

t.describe("GaitMath.rotate", function()
	t.test("matches CFrame.Angles(0, a, 0): forward (-Z) turns to the left (-X) for +90 degrees", function()
		local x, z = GaitMath.rotate(0, -1, math.rad(90))
		t.near(x, -1, 1e-9)
		t.near(z, 0, 1e-9)
	end)

	t.test("a full turn comes back", function()
		local x, z = GaitMath.rotate(0.7, -0.3, math.rad(360))
		t.near(x, 0.7, 1e-9)
		t.near(z, -0.3, 1e-9)
	end)
end)

t.describe("GaitMath.turnProgress", function()
	t.test("runs from 0 to 1", function()
		t.near(GaitMath.turnProgress(0), 0, 1e-9)
		t.near(GaitMath.turnProgress(1), 1, 1e-9)
	end)

	t.test("is front-loaded: more than half the turn is done by the half-way point", function()
		t.truthy(GaitMath.turnProgress(0.5) > 0.6)
	end)

	t.test("only ever moves forward", function()
		local last = -1
		for i = 0, 40 do
			local v = GaitMath.turnProgress(i / 40)
			t.truthy(v >= last, "never goes backward")
			last = v
		end
	end)
end)

t.describe("GaitMath.spinShift", function()
	t.test("runs from nothing to everything", function()
		t.near(GaitMath.spinShift(0, 2.2), 0, 1e-9)
		t.near(GaitMath.spinShift(1, 2.2), 1, 1e-9)
	end)

	t.test("a sharper shift happens earlier", function()
		t.truthy(GaitMath.spinShift(0.2, 3) > GaitMath.spinShift(0.2, 1.5))
		t.near(GaitMath.spinShift(0.5, 1), 0.5, 1e-9)
	end)
end)

t.describe("GaitMath.spinHips", function()
	-- Pivot foot 0.75 to the right of the hips (+X); the hips start at the origin.
	local function hips(shift: number, degrees: number)
		return GaitMath.spinHips(0.75, 0, 0, 0, 1.2, shift, math.rad(degrees))
	end

	t.test("at the start the hips are where they were", function()
		local x, z = hips(0, 0)
		t.near(x, 0, 1e-9)
		t.near(z, 0, 1e-9)
	end)

	t.test("before any weight shift the hips swing round the pivot at the stance radius", function()
		local x, z = hips(0, 180)
		t.near(x, 1.5, 1e-9) -- the far side of the pivot foot
		t.near(z, 0, 1e-9)
	end)

	t.test("after a full turn the hips have travelled `travel` studs toward the pivot side", function()
		local x, z = hips(1, 360)
		t.near(x, 1.2, 1e-9)
		t.near(z, 0, 1e-9)
	end)

	t.test(
		"the pivot hip joint (0.5 toward the pivot side, turning with the body) stays near the pivot foot",
		function()
			-- With no shift the hip joint is always 0.25 from the pivot foot, whatever the angle.
			for degrees = 0, 360, 45 do
				local x, z = hips(0, degrees)
				local jx, jz = GaitMath.rotate(0.5, 0, math.rad(degrees))
				local distance = math.sqrt((x + jx - 0.75) ^ 2 + (z + jz) ^ 2)
				t.near(distance, 0.25, 1e-9)
			end
		end
	)
end)

t.describe("GaitMath.angleDelta", function()
	t.test("takes the short way round", function()
		t.near(GaitMath.angleDelta(math.rad(170), math.rad(-170)), math.rad(20), 1e-9)
		t.near(GaitMath.angleDelta(math.rad(-170), math.rad(170)), math.rad(-20), 1e-9)
		t.near(GaitMath.angleDelta(0.3, 0.1), -0.2, 1e-9)
	end)
end)

t.describe("GaitMath.approachSchedule", function()
	t.test("ends with the long right gather step, then the left plant exactly at the end", function()
		local steps = GaitMath.approachSchedule(0.5, 0.12, 0.1, 0.05)
		local last, before = steps[#steps], steps[#steps - 1]
		t.equal(last.side, "Left")
		t.near(last.landAt, 0.5, 1e-9)
		t.equal(before.side, "Right")
		t.near(before.landAt, 0.4, 1e-9)
	end)

	t.test("feet alternate and each leaves as the other lands", function()
		local steps = GaitMath.approachSchedule(0.6, 0.12, 0.1, 0.05)
		for i = 2, #steps do
			t.truthy(steps[i].side ~= steps[i - 1].side, "alternating feet")
			t.near(steps[i].startAt, steps[i - 1].landAt, 1e-9)
		end
	end)

	t.test("nothing starts before the approach does", function()
		for _, step in GaitMath.approachSchedule(0.45, 0.13, 0.11, 0.05) do
			t.truthy(step.startAt >= 0, "startAt >= 0")
			t.truthy(step.landAt > step.startAt, "lands after it leaves")
		end
	end)

	t.test("a very short approach is just the left plant", function()
		local steps = GaitMath.approachSchedule(0.08, 0.12, 0.1, 0.05)
		t.equal(#steps, 1)
		t.equal(steps[1].side, "Left")
		t.near(steps[1].startAt, 0, 1e-9)
	end)
end)

return nil
