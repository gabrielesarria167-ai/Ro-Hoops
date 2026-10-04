--!strict
local ShotMath = require("../src/shared/ShotMath")
local t = require("./harness")

local CLASSIFY = { CLOSE_RANGE_FT = 8, STATIONARY_SPEED = 3 }
local GRADE = { PERFECT_WINDOW = 0.06, GOOD_WINDOW = 0.14, OK_WINDOW = 0.28 }
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

return nil
