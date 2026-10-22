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

	-- The game's real settings: a quick half circle (a "U") is enough.
	local GAME_CIRCLE = { CIRCLE_ANGLE = 120, CIRCLE_WINDOW = 0.7, CIRCLE_MIN_LENGTH = 0.2 }

	t.test("a quick half circle (~170° in 0.2 s, like recorded in Studio) is a spin", function()
		t.equal(SkillMath.detectCircle(circle(0.15, 170 / 360, 0.2, -1), GAME_CIRCLE), -1)
		t.equal(SkillMath.detectCircle(circle(0.15, 170 / 360, 0.2, 1), GAME_CIRCLE), 1)
	end)

	t.test("a straight flick is never a spin with the game's settings", function()
		t.equal(SkillMath.detectCircle(path(3, 0, 8), GAME_CIRCLE), nil)
	end)

	t.test("a flick and a sharp return (doubling back) is not a spin", function()
		local samples = path(2, 0, 8)
		local turnX = samples[#samples].x
		for i = 1, 8 do
			table.insert(samples, { t = (8 + i) / 60, x = turnX - 2 * i / 60, y = 0.5 + 0.002 * i })
		end
		t.equal(SkillMath.detectCircle(samples, GAME_CIRCLE), nil)
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

	t.test("flicking toward the hand that has the ball is a stab dribble", function()
		t.equal(SkillMath.chooseMove(1, 0, "Right", MOVE), "Stab")
		t.equal(SkillMath.chooseMove(-1, 0, "Left", MOVE), "Stab")
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

-- A standing dribble: catch 1.6, release 1.3, ball radius 0.63, 1.6 Hz, contact 55%.
local function standingShape(): SkillMath.DribbleShape
	local cycle = 1 / 1.6
	return {
		floor = 0.63,
		catch = 1.6,
		release = 1.3,
		ride = 0.15,
		rideShare = 0.3,
		contactTime = cycle * 0.55,
		flightTime = cycle * 0.45,
		restitution = 0.85,
	}
end

t.describe("SkillMath.dribbleHeight", function()
	local profile = SkillMath.dribbleProfile(standingShape())

	t.test("the cycle starts at the catch height and comes back to it", function()
		t.near((SkillMath.dribbleHeight(profile, 0)), 1.6, 1e-6)
		t.near((SkillMath.dribbleHeight(profile, profile.total - 1e-6)), 1.6, 1e-3)
	end)

	t.test("the hand rides the ball up, then pushes it down to the release height", function()
		local top = SkillMath.dribbleHeight(profile, profile.rideTime - 1e-6)
		t.near(top, 1.75, 1e-3)
		local released = SkillMath.dribbleHeight(profile, profile.rideTime + profile.pushTime - 1e-6)
		t.near(released, 1.3, 1e-3)
	end)

	t.test("the ball touches the floor exactly when the fall ends", function()
		local floorAt = profile.rideTime + profile.pushTime + profile.downTime
		t.near((SkillMath.dribbleHeight(profile, floorAt - 1e-6)), 0.63, 1e-3)
		local height, stage = SkillMath.dribbleHeight(profile, floorAt + 1e-4)
		t.equal(stage, "Up")
		t.truthy(height >= 0.63 - 1e-6, "above the floor")
	end)

	t.test("the ball is never below the floor and the stages run in order", function()
		local order = {}
		local low = math.huge
		for i = 0, 400 do
			local height, stage = SkillMath.dribbleHeight(profile, profile.total * i / 400)
			low = math.min(low, height)
			if order[#order] ~= stage then
				table.insert(order, stage)
			end
		end
		t.truthy(low >= 0.63 - 1e-6, "never below the floor")
		t.equal(table.concat(order, ","), "Ride,Push,Down,Up,Ride")
	end)

	t.test("the speed after the bounce is the restitution times the speed before it", function()
		local fall = 1.3 - 0.63
		local rise = 1.6 - 0.63
		local impact = 2 * fall / profile.downTime - profile.releaseSpeed
		local away = 2 * rise / profile.upTime - profile.catchSpeed
		t.near(away / impact, 0.85, 1e-3)
	end)

	t.test("the stage times add up to the cycle", function()
		t.near(profile.rideTime + profile.pushTime + profile.downTime + profile.upTime, profile.total, 1e-9)
		t.near(profile.total, 1 / 1.6, 1e-9)
	end)

	t.test("the height is continuous across the whole cycle (no jumps)", function()
		local previous = SkillMath.dribbleHeight(profile, 0)
		for i = 1, 2000 do
			local height = SkillMath.dribbleHeight(profile, profile.total * i / 2000)
			t.truthy(math.abs(height - previous) < 0.08, "step " .. i)
			previous = height
		end
	end)
end)

t.describe("SkillMath.wrapSigned", function()
	t.test("takes the short way round the cycle", function()
		t.near(SkillMath.wrapSigned(0.9, 0.1), 0.2, 1e-9)
		t.near(SkillMath.wrapSigned(0.1, 0.9), -0.2, 1e-9)
		t.near(SkillMath.wrapSigned(0.3, 0.3), 0, 1e-9)
	end)
end)

t.describe("SkillMath.springStep", function()
	t.test("settles on the target without overshooting", function()
		local x, v = 0, 0
		for _ = 1, 120 do
			x, v = SkillMath.springStep(x, v, 1, 18, 1 / 60)
			t.truthy(x <= 1 + 1e-9, "no overshoot")
		end
		t.near(x, 1, 1e-3)
	end)

	t.test("is frame-rate independent", function()
		local a, av = SkillMath.springStep(0, 0, 1, 18, 0.1)
		local b, bv = 0, 0
		for _ = 1, 10 do
			b, bv = SkillMath.springStep(b, bv, 1, 18, 0.01)
		end
		t.near(a, b, 1e-9)
		t.near(av, bv, 1e-9)
	end)

	t.test("keeps its speed when the target changes (no pop)", function()
		local x, v = SkillMath.springStep(0, 5, 0, 18, 1 / 60)
		t.truthy(x > 0.05, "keeps moving the way it was going")
		t.truthy(v > 0, "still moving")
	end)
end)

t.describe("SkillMath.hermite", function()
	t.test("starts and ends at the points, with the given end speeds", function()
		t.near(SkillMath.hermite(1, 0, 3, 2, 0.5, 0), 1, 1e-9)
		t.near(SkillMath.hermite(1, 0, 3, 2, 0.5, 1), 3, 1e-9)
		-- Speed at the end: a tiny step before it.
		local before = SkillMath.hermite(1, 0, 3, 2, 0.5, 1 - 1e-4)
		t.near((3 - before) / (0.5 * 1e-4), 2, 1e-2)
	end)
end)

t.describe("SkillMath.monotoneTangent", function()
	t.test("is the harmonic mean of the slopes either side", function()
		t.near(SkillMath.monotoneTangent(2, 6), 3, 1e-9)
		t.near(SkillMath.monotoneTangent(4, 4), 4, 1e-9)
	end)

	t.test("is 0 at a peak or a stop, so the path never overshoots", function()
		t.equal(SkillMath.monotoneTangent(3, -2), 0)
		t.equal(SkillMath.monotoneTangent(0, 5), 0)
	end)

	t.test("a path through three points with these speeds stays between them", function()
		-- 0 -> 1 over 0.1 s, then 1 -> 1.2 over 0.3 s, using the waypoint speed.
		local speed = SkillMath.monotoneTangent(1 / 0.1, 0.2 / 0.3)
		for i = 0, 100 do
			local height = SkillMath.hermite(0, 0, 1, speed, 0.1, i / 100)
			t.truthy(height >= -1e-9 and height <= 1 + 1e-9, "first part within 0..1")
		end
		for i = 0, 100 do
			local height = SkillMath.hermite(1, speed, 1.2, 0, 0.3, i / 100)
			t.truthy(height >= 1 - 1e-9 and height <= 1.2 + 1e-9, "second part within 1..1.2")
		end
	end)
end)

t.describe("SkillMath.softReach", function()
	t.test("leaves short reaches alone", function()
		t.near(SkillMath.softReach(1.5, 2.5, 2), 1.5, 1e-9)
	end)

	t.test("bends long reaches toward, but never past, the maximum", function()
		local bent = SkillMath.softReach(3.5, 2.5, 2)
		t.truthy(bent > 2 and bent < 2.5, "between the soft start and the maximum")
		t.truthy(SkillMath.softReach(100, 2.5, 2) <= 2.5 + 1e-9, "never past the maximum")
	end)

	t.test("is continuous at the soft start", function()
		t.near(SkillMath.softReach(2 + 1e-6, 2.5, 2), 2, 1e-5)
	end)
end)

return nil
