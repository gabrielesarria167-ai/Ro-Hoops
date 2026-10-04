--!strict
local MovementMath = require("../src/shared/MovementMath")
local t = require("./harness")

local ACCEL, DECEL, TURN = 70, 110, 160

local function simulate(vx: number, vz: number, tx: number, tz: number, dt: number, steps: number): (number, number)
	for _ = 1, steps do
		vx, vz = MovementMath.stepVelocity(vx, vz, tx, tz, ACCEL, DECEL, TURN, dt)
	end
	return vx, vz
end

t.describe("MovementMath.stepVelocity", function()
	t.test("accelerates at the acceleration rate", function()
		local vx = MovementMath.stepVelocity(0, 0, 20, 0, ACCEL, DECEL, TURN, 0.1)
		t.near(vx, 7, 1e-9)
	end)

	t.test("reaches the target without overshooting", function()
		local vx, vz = simulate(0, 0, 13, 0, 1 / 60, 120)
		t.near(vx, 13, 1e-9)
		t.near(vz, 0, 1e-9)
	end)

	t.test("snaps to the target when within one step", function()
		local vx = MovementMath.stepVelocity(12.9, 0, 13, 0, ACCEL, DECEL, TURN, 1 / 60)
		t.equal(vx, 13)
	end)

	t.test("decelerates to a stop at the deceleration rate", function()
		local vx = MovementMath.stepVelocity(20, 0, 0, 0, ACCEL, DECEL, TURN, 0.1)
		t.near(vx, 9, 1e-9)
		local stopped = simulate(20, 0, 0, 0, 1 / 60, 60)
		t.equal(stopped, 0)
	end)

	t.test("slowing from run to walk uses deceleration", function()
		local vx = MovementMath.stepVelocity(21, 0, 13, 0, ACCEL, DECEL, TURN, 0.05)
		t.near(vx, 21 - DECEL * 0.05, 1e-9)
	end)

	t.test("reversing direction uses the turn rate", function()
		local vx = MovementMath.stepVelocity(10, 0, -10, 0, ACCEL, DECEL, TURN, 0.05)
		t.near(vx, 10 - TURN * 0.05, 1e-9)
	end)

	t.test("is frame-rate independent in a straight line", function()
		local coarse = simulate(0, 0, 21, 0, 0.1, 1)
		local fine = simulate(0, 0, 21, 0, 0.01, 10)
		t.near(coarse, fine, 1e-9)
	end)

	t.test("keeps diagonal speed at the target magnitude", function()
		local s = 13 / math.sqrt(2)
		local vx, vz = simulate(0, 0, s, s, 1 / 60, 120)
		t.near(math.sqrt(vx * vx + vz * vz), 13, 1e-9)
	end)
end)

t.describe("MovementMath.smoothingAlpha", function()
	t.test("is zero at dt = 0 and approaches one", function()
		t.equal(MovementMath.smoothingAlpha(8, 0), 0)
		t.truthy(MovementMath.smoothingAlpha(8, 10) > 0.9999)
	end)

	t.test("gives the same result at any frame rate", function()
		local function run(dt: number, steps: number): number
			local value = 0
			for _ = 1, steps do
				value += (1 - value) * MovementMath.smoothingAlpha(8, dt)
			end
			return value
		end
		t.near(run(1 / 30, 30), run(1 / 240, 240), 1e-9)
	end)
end)

return nil
