--!strict
-- SKILL MATH
-- Plain math with no Roblox APIs, so it can be unit tested outside Studio with Lune
-- (tests/SkillMath.spec.luau). Covers the decisions behind every dribble move:
--   1. detectSwipe  – did the mouse/trackpad just make a quick flick, and which way?
--   2. detectCircle – did it just draw a circle, and which way round?
--   3. chooseMove   – which dribble move does a flick become?
-- and the ball/hand motion maths behind the dribble and the shooting motion:
--   4. dribbleProfile / dribbleHeight – the height of the ball through one dribble cycle
--   5. wrapSigned   – the shortest signed distance between two cycle phases (footfall lock)
--   6. springStep   – a critically damped spring (the hands' smoothing)
--   7. hermite      – a smooth path between two points with chosen end speeds
--   8. softReach    – squeezes a hand target that is beyond the arm's reach
--   9. monotoneTangent – the speed a smooth path should have as it passes a waypoint
-- SkillController judges each "stroke" (a burst of cursor movement, ended by the cursor
-- stopping) as a whole: a full circle is a spin, otherwise a fast straight stroke is a
-- flick. Waiting for the stroke to end is what stops a circle being read as a flick.

local SkillMath = {}

-- Which hand the ball is in.
export type Hand = "Right" | "Left"

-- Every dribble move:
--   HandSwitch – a quick, simple change of hands (the H key)
--   Crossover  – the wide, Allen Iverson style crossover (flick toward the empty hand)
--   StepBack   – one step back, pulling the ball with you (flick backward)
--   Stab       – a hard dribble out to the ball hand's own side, stepping that way (flick
--                toward the hand that has the ball)
--   Spin       – a 360° reverse-pivot spin, switching hands during the spin
--                (draw a circle)
export type Move = "HandSwitch" | "Crossover" | "StepBack" | "Spin" | "Stab"

-- One cursor reading: the clock time and where the cursor was. Positions are measured in
-- screen heights (so a flick is the same size on any screen) with y pointing UP.
export type Sample = {
	t: number,
	x: number,
	y: number,
}

-- The settings each function needs (they come from Config/Skills.luau).
export type SwipeConfig = {
	SWIPE_DISTANCE: number,
	SWIPE_WINDOW: number,
}

export type CircleConfig = {
	CIRCLE_ANGLE: number,
	CIRCLE_WINDOW: number,
	CIRCLE_MIN_LENGTH: number,
}

export type MoveConfig = {
	SIDE_DOMINANCE: number,
}

-- Segments shorter than this (screen heights) are merged with the next one when measuring
-- how much the path turns, so tiny jitters don't count as turning.
local MIN_SEGMENT = 0.004
-- A single turn sharper than this (degrees) between two segments is the cursor doubling
-- back (a zigzag or a flick and its return), not a circle bending round, so it isn't
-- counted. Real circles bend gradually: recorded spin gestures never turned more than
-- ~60° between readings.
local REVERSAL_ANGLE = math.rad(135)

-- 1. Looks at the cursor's recent path (`samples`, oldest first) and returns the flick it
-- made as a vector in screen heights (x = right, y = up), or nil if there was no flick.
-- A flick = the cursor travelled at least SWIPE_DISTANCE within the last SWIPE_WINDOW
-- seconds. Slow cursor movement never covers that much ground in time, so it's ignored.
function SkillMath.detectSwipe(samples: { Sample }, config: SwipeConfig): (number?, number?)
	local count = #samples
	if count < 2 then
		return nil
	end
	local last = samples[count]
	-- The oldest reading that is still inside the window.
	local first = last
	for i = count - 1, 1, -1 do
		if last.t - samples[i].t > config.SWIPE_WINDOW then
			break
		end
		first = samples[i]
	end
	local dx, dy = last.x - first.x, last.y - first.y
	if math.sqrt(dx * dx + dy * dy) < config.SWIPE_DISTANCE then
		return nil
	end
	return dx, dy
end

-- 2. Looks at the last CIRCLE_WINDOW seconds of the cursor's path and returns +1 if it
-- drew a circle counterclockwise (on screen), -1 if clockwise, or nil if it didn't.
-- A circle = the path's direction turned through at least CIRCLE_ANGLE degrees in one
-- direction, along a path at least CIRCLE_MIN_LENGTH screen heights long (so small
-- wobbles don't count). It doesn't have to be a full circle: a quick half circle (a "U")
-- counts too, since there's no time for full circles in a real game. Turning one way and
-- then back cancels out, and sharp reversals (REVERSAL_ANGLE) don't count at all.
function SkillMath.detectCircle(samples: { Sample }, config: CircleConfig): number?
	local count = #samples
	if count < 3 then
		return nil
	end
	local lastTime = samples[count].t
	local turned = 0 -- total signed turning, radians (positive = counterclockwise)
	local length = 0 -- path length, screen heights
	local anchor: Sample? = nil -- start of the current segment
	local previousX, previousY = 0, 0 -- direction of the previous segment (zero = none yet)
	for i = 1, count do
		local sample = samples[i]
		if lastTime - sample.t <= config.CIRCLE_WINDOW then
			local from = anchor
			if not from then
				anchor = sample
			else
				local dx, dy = sample.x - from.x, sample.y - from.y
				local segment = math.sqrt(dx * dx + dy * dy)
				if segment >= MIN_SEGMENT then
					if previousX ~= 0 or previousY ~= 0 then
						-- Signed angle from the previous direction to this one.
						local cross = previousX * dy - previousY * dx
						local dot = previousX * dx + previousY * dy
						local angle = math.atan2(cross, dot)
						if math.abs(angle) < REVERSAL_ANGLE then
							turned += angle
						end
					end
					length += segment
					previousX, previousY = dx, dy
					anchor = sample
				end
			end
		end
	end
	if length < config.CIRCLE_MIN_LENGTH or math.abs(turned) < math.rad(config.CIRCLE_ANGLE) then
		return nil
	end
	return if turned > 0 then 1 else -1
end

-- 3. Picks the move for a flick. `towardRight` and `towardForward` are how much of the
-- flick points to the player's right and the way the player faces (already turned from
-- screen directions into the player's own, so it works whichever way they face). `hand`
-- is where the ball is now.
--   * Flick mostly sideways, toward the empty hand → Crossover (the wide one; the ball
--     goes where you flicked it). The quick HandSwitch is on the H key instead.
--   * Flick mostly sideways, toward the hand that has the ball → Stab (same hand, out to
--     that side).
--   * Flick mostly backward → StepBack.
--   * Flick mostly forward → nil (kept free for a later move).
function SkillMath.chooseMove(towardRight: number, towardForward: number, hand: Hand, config: MoveConfig): Move?
	if math.abs(towardRight) < math.abs(towardForward) * config.SIDE_DOMINANCE then
		-- Mostly forward or back.
		return if towardForward < 0 then "StepBack" else nil
	end
	local side: Hand = if towardRight > 0 then "Right" else "Left"
	return if side ~= hand then "Crossover" else "Stab"
end

-- 4. THE DRIBBLE CYCLE ------------------------------------------------------------------
-- One bounce, from the moment the hand meets the ball (t = 0) to the next time it does:
--   RIDE  – the hand meets the ball on its way UP and rides it up a few centimetres;
--   PUSH  – the hand pushes it down (accelerating) and lets go at `release`;
--   DOWN  – the ball falls to the floor (flight);
--   UP    – it bounces (losing a little speed: `restitution`) and rises into the hand again.
-- Heights are the ball's CENTRE above the floor. Research: Hirata et al. 2011 (the hand
-- meets the ball while it is still rising; contact ~55-60% of the cycle).

-- Everything that shapes one dribble cycle.
export type DribbleShape = {
	floor: number, -- ball centre height when it touches the floor (= the ball's radius), studs
	catch: number, -- ball centre height when the hand meets it, studs
	release: number, -- ball centre height when the hand lets go, studs
	ride: number, -- how far the hand rides the ball up after meeting it, studs
	rideShare: number, -- share of the contact time spent riding (the rest is the push), 0-1
	contactTime: number, -- seconds the hand is on the ball
	flightTime: number, -- seconds the ball is free (down + up)
	restitution: number, -- speed kept in the floor bounce (0-1)
}

-- A dribble cycle worked out once (see dribbleProfile): the stage lengths and the speeds
-- that make the heights join up smoothly.
export type DribbleProfile = {
	shape: DribbleShape,
	rideTime: number, -- seconds
	pushTime: number, -- seconds
	downTime: number, -- seconds from release to the floor
	upTime: number, -- seconds from the floor to the hand
	catchSpeed: number, -- upward speed of the ball as the hand meets it, studs/s
	releaseSpeed: number, -- downward speed of the ball as the hand lets go, studs/s
	total: number, -- seconds for the whole cycle
}

-- Works out a cycle's stage lengths. The hand's ride and push use the contact time; the free
-- flight is split between falling (`downTime`) and rising (`upTime`) so that the speed after
-- the bounce is `restitution` times the speed before it (found by bisection: the faster the
-- fall is, the bigger the ratio gets, so there is exactly one answer).
function SkillMath.dribbleProfile(shape: DribbleShape): DribbleProfile
	local rideTime = math.max(shape.contactTime * shape.rideShare, 1e-3)
	local pushTime = math.max(shape.contactTime - rideTime, 1e-3)
	local catchSpeed = 2 * shape.ride / rideTime -- ride eases out, starting at this upward speed
	local top = shape.catch + shape.ride
	local releaseSpeed = 2 * math.max(top - shape.release, 0) / pushTime -- push eases in
	local flight = math.max(shape.flightTime, 0.04)
	local fall = math.max(shape.release - shape.floor, 0.01) -- distance to drop
	local rise = math.max(shape.catch - shape.floor, 0.01) -- distance to climb back

	-- Speed just before / after the bounce for a given split of the flight.
	local function ratio(downTime: number): number
		local upTime = flight - downTime
		local impact = 2 * fall / downTime - releaseSpeed
		local away = 2 * rise / upTime - catchSpeed
		return away / math.max(impact, 1e-3)
	end
	-- The fall can't take longer than the push speed alone would take to cover the distance
	-- (that would need the ball to slow down while falling).
	local lo = flight * 0.1
	local hi = math.min(flight * 0.9, fall / math.max(releaseSpeed, 1e-3))
	hi = math.max(hi, lo + 1e-3)
	local downTime
	if ratio(lo) >= shape.restitution then
		downTime = lo
	elseif ratio(hi) <= shape.restitution then
		downTime = hi
	else
		for _ = 1, 24 do
			local mid = (lo + hi) / 2
			if ratio(mid) < shape.restitution then
				lo = mid
			else
				hi = mid
			end
		end
		downTime = (lo + hi) / 2
	end
	return {
		shape = shape,
		rideTime = rideTime,
		pushTime = pushTime,
		downTime = downTime,
		upTime = flight - downTime,
		catchSpeed = catchSpeed,
		releaseSpeed = releaseSpeed,
		total = shape.contactTime + flight,
	}
end

export type DribbleStage = "Ride" | "Push" | "Down" | "Up"

-- The ball's centre height `t` seconds after the hand met it (wraps round the cycle), the
-- stage it is in, and how far through that stage (0-1).
function SkillMath.dribbleHeight(profile: DribbleProfile, t: number): (number, DribbleStage, number)
	local shape = profile.shape
	t = t % profile.total
	if t < profile.rideTime then
		local u = t / profile.rideTime
		return shape.catch + shape.ride * (1 - (1 - u) * (1 - u)), "Ride", u
	end
	t -= profile.rideTime
	if t < profile.pushTime then
		local u = t / profile.pushTime
		return shape.catch + shape.ride - (shape.catch + shape.ride - shape.release) * u * u, "Push", u
	end
	t -= profile.pushTime
	if t < profile.downTime then
		-- Falling: starts at the release speed and speeds up so it lands exactly on time.
		local fall = shape.release - shape.floor
		local accel = 2 * (fall - profile.releaseSpeed * profile.downTime) / (profile.downTime * profile.downTime)
		return shape.release - profile.releaseSpeed * t - 0.5 * accel * t * t, "Down", t / profile.downTime
	end
	t -= profile.downTime
	-- Rising: leaves the floor fast, slows, and arrives at the hand moving at catchSpeed.
	local rise = shape.catch - shape.floor
	local decel = 2 * (rise - profile.catchSpeed * profile.upTime) / (profile.upTime * profile.upTime)
	local launch = profile.catchSpeed + decel * profile.upTime
	return shape.floor + launch * t - 0.5 * decel * t * t, "Up", math.min(t / profile.upTime, 1)
end

-- 5. The shortest signed distance from phase `from` to phase `to` round a cycle (phases
-- are 0-1 and wrap), so the result is in [-0.5, 0.5). Used to nudge the dribble toward
-- the foot plants.
function SkillMath.wrapSigned(from: number, to: number): number
	return (to - from + 0.5) % 1 - 0.5
end

-- 6. One frame of a critically damped spring (no overshoot): moves `position` toward
-- `target`, keeping its `velocity`. `omega` = stiffness in rad/s (18 reaches half way in
-- ~0.09 s). Exact for any `dt`, so frame rate doesn't change the feel. Returns the new
-- position and velocity.
function SkillMath.springStep(
	position: number,
	velocity: number,
	target: number,
	omega: number,
	dt: number
): (number, number)
	local decay = math.exp(-omega * dt)
	local offset = position - target
	local carry = (velocity + omega * offset) * dt
	return target + (offset + carry) * decay, (velocity - omega * carry) * decay
end

-- 7. A smooth (cubic Hermite) path from `p0` to `p1` taking `duration` seconds, leaving at
-- speed `m0` and arriving at speed `m1` (units per second). `u` = 0 to 1 through the path.
-- Used for the shot's ball path so the ball never stops dead at a waypoint.
function SkillMath.hermite(p0: number, m0: number, p1: number, m1: number, duration: number, u: number): number
	local u2 = u * u
	local u3 = u2 * u
	return (2 * u3 - 3 * u2 + 1) * p0
		+ (u3 - 2 * u2 + u) * m0 * duration
		+ (-2 * u3 + 3 * u2) * p1
		+ (u3 - u2) * m1 * duration
end

-- 8. Squeezes a reach: distances up to `softStart` pass through unchanged, beyond that
-- they bend smoothly toward (but never reach) `maxReach`. The dribbling hand uses it so a
-- low ball never asks the arm to stretch past straight.
function SkillMath.softReach(distance: number, maxReach: number, softStart: number): number
	if distance <= softStart then
		return distance
	end
	local room = math.max(maxReach - softStart, 1e-3)
	local x = (distance - softStart) / room
	-- tanh(x) written with exp so there is no dependency on a math.tanh.
	local e = math.exp(-2 * x)
	return softStart + room * (1 - e) / (1 + e)
end

-- 9. The speed (units per second) a smooth path should have at a waypoint, given the
-- average speed on the way in (`before`) and on the way out (`after`). The harmonic mean
-- keeps the path from overshooting either neighbour (a "monotone" cubic, Fritsch-Carlson):
-- if the path goes up then down, the waypoint is a peak and the speed there is 0.
function SkillMath.monotoneTangent(before: number, after: number): number
	if before * after <= 0 then
		return 0
	end
	return 2 * before * after / (before + after)
end

return SkillMath
