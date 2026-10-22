--!strict
local Shooting = require("../src/shared/Config/Shooting")
local ShotMath = require("../src/shared/ShotMath")
local t = require("./harness")

local CLASSIFY = { CLOSE_RANGE_FT = 8, LAYUP_RANGE_FT = 10, DRIVE_LAYUP_RANGE_FT = 15, STATIONARY_SPEED = 3 }
local DUNK = { DUNK_RANGE_FT = 15, STANDING_DUNK_RANGE_FT = 5, DUNK_MIN_SPEED = 8 }
local GRADE = { IDEAL_RELEASE = 1, PERFECT_WINDOW = 0.06, GOOD_WINDOW = 0.14, OK_WINDOW = 0.28 }
local AIM = {
	PERFECT_WINDOW = 0.06,
	PERFECT_SPREAD = 0.05,
	DEPTH_ERROR_PER_TIMING = 1.6,
	LATERAL_ERROR_PER_TIMING = 0.8,
}

local function classify(distanceFeet: number, toward: number, lateral: number, running: boolean?): string
	return ShotMath.classify({
		distanceFeet = distanceFeet,
		towardSpeed = toward,
		lateralSpeed = lateral,
		running = running == true,
	}, CLASSIFY)
end

t.describe("ShotMath.classify", function()
	t.test("standing outside close range is a jump shot", function()
		t.equal(classify(18, 0, 0), "JumpShot")
		t.equal(classify(18, 1, 1), "JumpShot")
	end)

	t.test("moving toward the rim from range is a pull-up", function()
		t.equal(classify(18, 13, 0), "PullUp")
	end)

	t.test("moving away is a fadeaway, or a step-back when running", function()
		t.equal(classify(18, -13, 0, false), "Fadeaway")
		t.equal(classify(18, -21, 0, true), "StepBack")
	end)

	t.test("mostly sideways movement is a side shot in either direction", function()
		t.equal(classify(18, 2, 13), "SideShot")
		t.equal(classify(18, 2, -13), "SideShot")
	end)

	t.test("driving at the rim inside close range is a layup", function()
		t.equal(classify(6, 13, 0), "Layup")
	end)

	t.test("standing or backing up inside close range is a close shot", function()
		t.equal(classify(6, 0, 0), "CloseShot")
		t.equal(classify(6, -13, 0), "CloseShot")
	end)

	t.test("driving at the rim from a little further out is still a layup", function()
		t.equal(classify(10, 13, 0, false), "Layup") -- walking: up to LAYUP_RANGE_FT
		t.equal(classify(14, 21, 0, true), "Layup") -- running: up to DRIVE_LAYUP_RANGE_FT
	end)

	t.test("beyond the layup range, or heading mostly sideways, it's a jump shot again", function()
		t.equal(classify(12, 13, 0, false), "PullUp") -- walking reaches only 10 ft
		t.equal(classify(16, 21, 0, true), "PullUp")
		t.equal(classify(12, 8, 13, true), "SideShot")
	end)
end)

-- A dunk context: distance in feet, speed toward the rim and across it.
local function canDunk(distanceFeet: number, toward: number, lateral: number): string?
	return ShotMath.canDunk({
		distanceFeet = distanceFeet,
		towardSpeed = toward,
		lateralSpeed = lateral,
		running = false,
	}, DUNK)
end

t.describe("ShotMath.canDunk", function()
	t.test("attacking the rim from up to DUNK_RANGE_FT is a running dunk", function()
		t.equal(canDunk(15, 21, 0), "Running")
		t.equal(canDunk(9, 13, 0), "Running")
	end)

	t.test("right under the rim you can dunk from a standstill", function()
		t.equal(canDunk(4, 0, 0), "Standing")
	end)

	t.test("too far, too slow or moving across the rim can't dunk", function()
		t.equal(canDunk(16, 21, 0), nil)
		t.equal(canDunk(10, 4, 0), nil)
		t.equal(canDunk(10, 9, 13), nil)
	end)
end)

t.describe("ShotMath.finishTiming", function()
	t.test("close in, the finish takes its minimum time and slows you to fit", function()
		local seconds, speed = ShotMath.finishTiming(2, 13, 0.3)
		t.near(seconds, 0.3, 1e-9)
		t.near(speed, 2 / 0.3, 1e-9)
	end)

	t.test("further out, you keep your drive speed and it takes longer", function()
		local seconds, speed = ShotMath.finishTiming(10, 20, 0.3)
		t.near(seconds, 0.5, 1e-9)
		t.near(speed, 20, 1e-9)
	end)

	t.test("no room left means no forward movement", function()
		local _, speed = ShotMath.finishTiming(-1, 20, 0.3)
		t.near(speed, 0, 1e-9)
	end)
end)

t.describe("ShotMath.jumpPowerFor / slamVelocity", function()
	t.test("the jump power rises exactly the asked height", function()
		local power = ShotMath.jumpPowerFor(5, 55)
		t.near(power * power / (2 * 55), 5, 1e-9)
	end)

	t.test("the slam reaches its target in exactly the given time", function()
		local vx, vy, vz = ShotMath.slamVelocity(0, 12, 1, 0, 9, 0, 0.1, 55)
		local tt = 0.1
		t.near(0 + vx * tt, 0, 1e-9)
		t.near(12 + vy * tt - 0.5 * 55 * tt * tt, 9, 1e-9)
		t.near(1 + vz * tt, 0, 1e-9)
	end)
end)

t.describe("ShotMath.grade", function()
	t.test("grades by distance from the ideal release", function()
		local _, perfect = ShotMath.grade(1.03, GRADE)
		local _, good = ShotMath.grade(0.9, GRADE)
		local _, early = ShotMath.grade(0.8, GRADE)
		local _, late = ShotMath.grade(1.2, GRADE)
		local _, veryEarly = ShotMath.grade(0.5, GRADE)
		local _, veryLate = ShotMath.grade(1.4, GRADE)
		t.equal(perfect, "Perfect")
		t.equal(good, "Good")
		t.equal(early, "Early")
		t.equal(late, "Late")
		t.equal(veryEarly, "VeryEarly")
		t.equal(veryLate, "VeryLate")
	end)

	t.test("centers the windows on an earlier ideal release", function()
		local early = { IDEAL_RELEASE = 0.92, PERFECT_WINDOW = 0.06, GOOD_WINDOW = 0.14, OK_WINDOW = 0.28 }
		local offset, perfect = ShotMath.grade(0.9, early)
		local _, good = ShotMath.grade(1, early)
		t.near(offset, -0.02, 1e-9)
		t.equal(perfect, "Perfect")
		t.equal(good, "Good", "the old ideal point is now slightly late")
	end)

	t.test("returns the signed offset", function()
		local offset = ShotMath.grade(0.75, GRADE)
		t.near(offset, -0.25, 1e-9)
	end)
end)

t.describe("ShotMath.difficulty", function()
	local config = { EASY_RANGE_FT = 12, DIFFICULTY_PER_FT = 0.04 }

	t.test("is the type difficulty inside the easy range", function()
		t.near(ShotMath.difficulty(1.3, 8, config), 1.3, 1e-9)
	end)

	t.test("grows with distance past the easy range", function()
		t.near(ShotMath.difficulty(1, 22, config), 1.4, 1e-9)
	end)
end)

t.describe("ShotMath.aimError", function()
	t.test("early releases fall short and late ones go long", function()
		local short = ShotMath.aimError(-0.2, 1, AIM, 0.5, 0.5)
		local long = ShotMath.aimError(0.2, 1, AIM, 0.5, 0.5)
		t.truthy(short < 0, "early should be short")
		t.truthy(long > 0, "late should be long")
	end)

	t.test("a perfect release stays within the perfect spread", function()
		for _, rolls in { { 0, 0 }, { 0.999, 0.999 }, { 0.3, 0.8 } } do
			local depth, lateral = ShotMath.aimError(0.02, 1.5, AIM, rolls[1], rolls[2])
			t.truthy(math.abs(depth) <= AIM.PERFECT_SPREAD * 1.5 + 1e-9, "depth within spread")
			t.truthy(math.abs(lateral) <= AIM.PERFECT_SPREAD * 1.5 + 1e-9, "lateral within spread")
		end
	end)

	t.test("error scales with difficulty", function()
		local easy = ShotMath.aimError(0.2, 1, AIM, 0.5, 0.5)
		local hard = ShotMath.aimError(0.2, 2, AIM, 0.5, 0.5)
		t.near(hard, easy * 2, 1e-9)
	end)
end)

t.describe("ShotMath.launchVelocity", function()
	local GRAVITY = 55

	local function landing(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, arc: number)
		local vx, vy, vz, flightTime = ShotMath.launchVelocity(x0, y0, z0, x1, y1, z1, arc, GRAVITY)
		local x = x0 + vx * flightTime
		local y = y0 + vy * flightTime - 0.5 * GRAVITY * flightTime * flightTime
		local z = z0 + vz * flightTime
		local apex = y0 + vy * vy / (2 * GRAVITY)
		return x, y, z, apex
	end

	t.test("a jump shot passes through the target", function()
		local x, y, z = landing(0, 7.9, 15, 0, 8.5, 0, 4)
		t.near(x, 0, 1e-6)
		t.near(y, 8.5, 1e-6)
		t.near(z, 0, 1e-6)
	end)

	t.test("a layup released above the rim still lands on target", function()
		local x, y, z, apex = landing(0.5, 9.2, 2.6, 0, 8.5, 0, 1)
		t.near(x, 0, 1e-6)
		t.near(y, 8.5, 1e-6)
		t.near(z, 0, 1e-6)
		t.near(apex, 10.2, 1e-6, "apex is arc height above the higher endpoint")
	end)

	t.test("a zero arc height does not divide by zero", function()
		local vx, vy, vz, flightTime = ShotMath.launchVelocity(0, 8.5, 1, 0, 8.5, 0, 0, GRAVITY)
		t.truthy(flightTime > 0)
		t.truthy(vx == vx and vy == vy and vz == vz, "no NaN")
	end)
end)

t.describe("ShotMath.launchVelocity from a lower jump", function()
	local GRAVITY = 55

	-- Where the ball is after `seconds` of flight.
	local function flyTo(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, arc: number)
		local vx, vy, vz, flightTime = ShotMath.launchVelocity(x0, y0, z0, x1, y1, z1, arc, GRAVITY)
		return x0 + vx * flightTime, y0 + vy * flightTime - 0.5 * GRAVITY * flightTime ^ 2, z0 + vz * flightTime
	end

	t.test("a lower release point still lands exactly on the same target", function()
		-- The old jump released the ball ~1.3 studs higher than the new, lower one.
		for _, releaseY in { 8.4, 7.9, 7.1, 6.6 } do
			local x, y, z = flyTo(0.4, releaseY, 15, 0, 8.5, 0, 2.5)
			t.near(x, 0, 1e-6)
			t.near(y, 8.5, 1e-6)
			t.near(z, 0, 1e-6)
		end
	end)

	t.test("so a perfect release is not affected by how high the jump was", function()
		-- Same target + same aim offset => same landing, whatever the release height.
		local x1, _, z1 = flyTo(0, 8.4, 12, 0.03, 8.5, -0.02, 2.5)
		local x2, _, z2 = flyTo(0, 6.9, 12, 0.03, 8.5, -0.02, 2.5)
		t.near(x1, x2, 1e-6)
		t.near(z1, z2, 1e-6)
	end)
end)

t.describe("ShotMath.dipTime", function()
	local GRAVITY = 55

	t.test("the dip is what is left of the ideal release after the rise to the top", function()
		-- Ideal release 0.4 s, jump 11 takes 0.2 s to peak, released at the top.
		t.near(ShotMath.dipTime(0.4, 11, GRAVITY, 0, 0.14, 0.24), 0.2, 1e-9)
	end)

	t.test("a release after the top (positive offset) shortens the dip, before it lengthens it", function()
		local atTop = ShotMath.dipTime(0.4, 11, GRAVITY, 0, 0.1, 0.3)
		t.near(ShotMath.dipTime(0.4, 11, GRAVITY, 0.04, 0.1, 0.3), atTop - 0.04, 1e-9)
		t.near(ShotMath.dipTime(0.4, 11, GRAVITY, -0.06, 0.1, 0.3), atTop + 0.06, 1e-9)
	end)

	t.test("a higher jump needs a shorter dip", function()
		local low = ShotMath.dipTime(0.4, 11, GRAVITY, 0, 0.05, 0.3)
		local high = ShotMath.dipTime(0.4, 16, GRAVITY, 0, 0.05, 0.3)
		t.truthy(high < low)
	end)

	t.test("the dip is clamped to the minimum and maximum", function()
		t.near(ShotMath.dipTime(0.3, 20, GRAVITY, 0, 0.16, 0.22), 0.16, 1e-9) -- would be negative
		t.near(ShotMath.dipTime(0.9, 10, GRAVITY, 0, 0.14, 0.24), 0.24, 1e-9)
	end)

	t.test("every shot type's jump fits its dip limits, so the release lands at its APEX_OFFSET", function()
		-- If the clamp bit, the ball would be released somewhere other than the configured
		-- spot relative to the top of the jump. Dunks have no meter (their dip is fixed).
		for id, config in Shooting.Types do
			if id == "Dunk" then
				continue
			end
			local ideal = config.FILL_TIME * Shooting.IDEAL_RELEASE
			local minDip = config.MIN_DIP_TIME or Shooting.MIN_DIP_TIME
			local dip =
				ShotMath.dipTime(ideal, config.JUMP_POWER, GRAVITY, config.APEX_OFFSET, minDip, Shooting.MAX_DIP_TIME)
			local releaseVsTop = ideal - dip - config.JUMP_POWER / GRAVITY
			t.near(releaseVsTop, config.APEX_OFFSET, 1e-9, id .. " release vs top of the jump")
		end
	end)
end)

return nil
