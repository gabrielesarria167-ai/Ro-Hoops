--!strict
-- GAIT MATH
-- Plain math with no Roblox APIs, so it can be unit tested outside Studio with Lune
-- (tests/GaitMath.spec.luau). The decisions behind the procedural footwork in
-- LegController, modelled on real basketball footwork:
--   1. homeOffset  – where each foot belongs in the dribbling stance: a bit wider than the
--                    hips, staggered with the ball-side foot back (the off foot forward
--                    protects the ball);
--   2. pickStepper – which foot steps next: the one furthest from where it belongs, one
--                    foot at a time, so sideways it's a shuffle (lead foot, then trail
--                    foot) and the feet never cross;
--   3. keepApart   – stops a foot landing across the other one;
--   4. stepDuration and swing – how long a step takes and the path the foot takes through
--                    the air (the lift peaks early, like a real swing leg);
--   5. reachForCrouch – how far a planted foot can really be from under its hip joint, given
--                    how low the hips are (a bent leg reaches less far sideways than a
--                    straight one would);
--   6. effectiveStagger – a hand switch flips the stagger, but the feet only re-step for it
--                    when the change is big (otherwise the weight just shifts);
--   7. dipTravel – how far the body slides while it dips for a shot (so the feet can land
--                    where the hips will be);
--   8. rotate, spinHips and turnProgress – the hips' path in a spin: the body turns
--                    around its planted pivot foot (front-loaded, so the head leads);
--   9. angleDelta – the shortest turn from one direction to another;
--  10. approachSchedule – when each running gather step happens before a layup, timed
--                    backward from the plant so the last two contacts are RIGHT, then LEFT.
-- Body-relative positions are (x = toward the player's right, z = the way they face).

local GaitMath = {}

export type Side = "Right" | "Left"

export type StanceConfig = {
	STANCE_WIDTH: number,
	STAGGER: number,
}

export type StepConfig = {
	STEP_TIME_SLOW: number,
	STEP_TIME_FAST: number,
	FAST_STEP_SPEED: number,
}

-- +1 for the right foot, -1 for the left.
function GaitMath.sign(side: Side): number
	return if side == "Right" then 1 else -1
end

-- 1. Where `side`'s foot belongs relative to the hips, as (x, z). `ballHand` is the hand
-- the ball is in, or nil without the ball (then the feet are level). With the ball, that
-- side's foot is STAGGER/2 back and the other foot STAGGER/2 forward.
function GaitMath.homeOffset(side: Side, ballHand: Side?, config: StanceConfig): (number, number)
	local x = GaitMath.sign(side) * config.STANCE_WIDTH / 2
	if not ballHand then
		return x, 0
	end
	local z = if side == ballHand then -config.STAGGER / 2 else config.STAGGER / 2
	return x, z
end

-- 2. Which foot should step now, or nil. `rightError` / `leftError` = how far (studs)
-- each foot is from where it should be. A foot only steps when it's at least `threshold`
-- away. `leadSide` (the side the body is travelling toward in a shuffle, if any) goes first
-- whenever it wants to step, even if the trail foot is further off: a step-slide is always
-- lead foot, then trail foot. Otherwise the foot further from its spot goes first.
function GaitMath.pickStepper(rightError: number, leftError: number, threshold: number, leadSide: Side?): Side?
	local rightWants, leftWants = rightError >= threshold, leftError >= threshold
	if rightWants and leftWants then
		if leadSide then
			return leadSide
		end
		return if rightError >= leftError then "Right" else "Left"
	end
	if rightWants then
		return "Right"
	end
	if leftWants then
		return "Left"
	end
	return nil
end

-- 3. Keeps a foot on its own side: returns `x` (the foot's body-relative x, measured from
-- the hips) moved out so it is at least `minGap` studs to its own side of the other foot's
-- x, `otherX`. Feet never cross in a shuffle.
function GaitMath.keepApart(side: Side, x: number, otherX: number, minGap: number): number
	if side == "Right" then
		return math.max(x, otherX + minGap)
	end
	return math.min(x, otherX - minGap)
end

-- 4a. How long a step takes at `speed` studs/s: STEP_TIME_SLOW when standing, shortening
-- to STEP_TIME_FAST at FAST_STEP_SPEED and above (quicker feet when moving faster).
function GaitMath.stepDuration(speed: number, config: StepConfig): number
	local fast = math.clamp(speed / math.max(config.FAST_STEP_SPEED, 1e-3), 0, 1)
	return config.STEP_TIME_SLOW + (config.STEP_TIME_FAST - config.STEP_TIME_SLOW) * fast
end

-- Where in a step the foot is highest (share of the step, 0-1). A real swing leg lifts
-- early (toe-off, knee drive) and then reaches forward, so the peak comes before the middle.
GaitMath.LIFT_PEAK = 0.35

-- 4b. The foot's path through a step at `progress` (0 = lifting off, 1 = landed). Returns
-- how far along the ground it has moved (0 to 1, starting and stopping gently) and how
-- high it is as a share of the step's lift (0 on the ground, 1 at the top, which comes
-- `peakAt` of the way through, GaitMath.LIFT_PEAK by default).
function GaitMath.swing(progress: number, peakAt: number?): (number, number)
	local p = math.clamp(progress, 0, 1)
	local along = p * p * (3 - 2 * p)
	-- Bend time so that `peakAt` lands on the middle of the symmetric 4q(1-q) curve:
	-- q = p ^ k with k chosen so that peakAt ^ k = 0.5.
	local peak = math.clamp(peakAt or GaitMath.LIFT_PEAK, 0.05, 0.95)
	local q = p ^ (math.log(0.5) / math.log(peak))
	local height = 4 * q * (1 - q)
	return along, height
end

-- How high to lift the foot for a step `length` studs long: short shuffles slide low
-- along the floor, long steps lift more, between `minLift` and `maxLift`.
function GaitMath.liftFor(length: number, liftPerStud: number, minLift: number, maxLift: number): number
	return math.clamp(length * liftPerStud, minLift, maxLift)
end

-- 5. How far (studs, flat) a planted foot can be from directly under its hip joint, for a
-- leg `legLength` long (hip joint to ankle) with the hips lowered by `crouch`. The hip joint
-- is then legLength - crouch above the ankle, so by Pythagoras the straightest the leg can
-- be is sqrt(legLength^2 - (legLength - crouch)^2) away sideways. `margin` (studs) shortens
-- the leg a little first, so the knee never locks dead straight (a locked knee looks like a
-- stretched leg). Never negative; a standing leg reaches nowhere sideways.
function GaitMath.reachForCrouch(legLength: number, crouch: number, margin: number): number
	local usable = math.max(legLength - math.max(margin, 0), 0)
	local height = math.clamp(legLength - crouch, 0, usable)
	return math.sqrt(math.max(usable * usable - height * height, 0))
end

-- 6. The stagger (how far the ball-side foot is behind the other) to aim a foot's spot with.
-- `current` = the stagger offset for that foot now, `atPlant` = the one it was planted with.
-- A hand switch changes the stagger, but unless the change is at least `restep` studs the
-- foot keeps its planted stagger (the weight shifts, no step), so pressing H doesn't make
-- both feet shuffle.
function GaitMath.effectiveStagger(current: number, atPlant: number, restep: number): number
	if math.abs(current - atPlant) < restep then
		return atPlant
	end
	return current
end

-- 7. How far (dx, dz studs) a body slides in `seconds` while its velocity (vx, vz) eases
-- toward (tx, tz) at a constant `rate` studs/s^2 (this is how MovementController eases it),
-- starting from (vx, vz). Used to predict where the hips will be during a shot's dip.
function GaitMath.dipTravel(
	vx: number,
	vz: number,
	tx: number,
	tz: number,
	rate: number,
	seconds: number
): (number, number)
	local gx, gz = tx - vx, tz - vz
	local gap = math.sqrt(gx * gx + gz * gz)
	local s = math.max(seconds, 0)
	if gap < 1e-6 or rate <= 0 then
		return tx * s, tz * s
	end
	local arrive = gap / rate -- seconds until the target velocity is reached
	local dirX, dirZ = gx / gap, gz / gap
	local t = math.min(s, arrive)
	-- Constant acceleration phase, then constant target velocity.
	local dx = vx * t + 0.5 * rate * dirX * t * t + tx * (s - t)
	local dz = vz * t + 0.5 * rate * dirZ * t * t + tz * (s - t)
	return dx, dz
end

-- 8a. Rotates the flat point (x, z) around the origin by `radians`, the same way
-- CFrame.Angles(0, radians, 0) turns things (positive = counterclockwise seen from above).
function GaitMath.rotate(x: number, z: number, radians: number): (number, number)
	local c, s = math.cos(radians), math.sin(radians)
	return x * c + z * s, -x * s + z * c
end

-- 8b. The shape of a spin's turn: how far round the body is (0 to 1) at `progress` (0 to 1).
-- Front-loaded (it starts fast and eases into the end), so the head and shoulders lead the
-- turn, but it still starts with a little ramp-up so there's no instant jerk.
function GaitMath.turnProgress(progress: number): number
	local p = math.clamp(progress, 0, 1)
	local smooth = p * p * (3 - 2 * p)
	local easeOut = 1 - (1 - p) * (1 - p)
	return 0.35 * smooth + 0.65 * easeOut
end

-- 8c. How much of a spin's weight shift (the hips moving over the pivot foot and past it) has
-- happened at `progress` (0 to 1) of the turn. `sharpness` 1 = evenly through the turn; higher
-- = most of it early, so the hips are over the pivot foot (and the body turns tightly about
-- it) before the turn is well under way.
function GaitMath.spinShift(progress: number, sharpness: number): number
	local p = math.clamp(progress, 0, 1)
	return 1 - (1 - p) ^ math.max(sharpness, 1)
end

-- 8d. Where the hips are during a spin. The body turns rigidly around its planted pivot foot
-- (the point (pivotX, pivotZ), the ball of that foot), so the pivot leg's hip stays right
-- above it; while it turns the hips also drift `travel` studs toward the pivot side
-- (`shift`, 0 to 1, is how much of that has happened: see spinShift), because the weight moves over the
-- pivot foot and carries on past it. (startX, startZ) = where the hips were before the spin,
-- `angle` = how far the body has turned (radians, as in GaitMath.rotate). Returns (x, z).
function GaitMath.spinHips(
	pivotX: number,
	pivotZ: number,
	startX: number,
	startZ: number,
	travel: number,
	shift: number,
	angle: number
): (number, number)
	local ox, oz = startX - pivotX, startZ - pivotZ
	local radius = math.sqrt(ox * ox + oz * oz)
	if radius < 1e-6 then
		return pivotX, pivotZ
	end
	-- The hips start `radius` from the pivot and end `radius - travel` from it (negative =
	-- on the far side), always along the direction from the pivot to the starting hips.
	local scale = (radius - travel * shift) / radius
	local rx, rz = GaitMath.rotate(ox * scale, oz * scale, angle)
	return pivotX + rx, pivotZ + rz
end

-- 9. The shortest signed turn (radians, -pi to pi) from direction `from` to direction `to`.
function GaitMath.angleDelta(from: number, to: number): number
	local delta = (to - from) % (2 * math.pi)
	if delta > math.pi then
		delta -= 2 * math.pi
	end
	return delta
end

-- One running step of a layup's approach.
export type ApproachStep = {
	side: Side,
	startAt: number, -- seconds after the approach starts that the foot leaves the floor
	landAt: number, -- seconds after the approach starts that it touches down
}

-- 10. The foot contacts of a layup's approach, `duration` seconds long, timed BACKWARD from
-- the end: the LEFT foot plants exactly at `duration` (that is when the dip starts), the
-- RIGHT gather step lands `plantTime` before it, and before that the feet alternate with
-- `gatherTime` between contacts. Each foot leaves the floor as the other one lands (a
-- run), so a step's flight is the gap before its landing. A step that would start before
-- the approach does is cut to start at 0, and one that would land before `minFlight` is
-- dropped. Returned in time order; the last step is always the left plant.
function GaitMath.approachSchedule(
	duration: number,
	gatherTime: number,
	plantTime: number,
	minFlight: number
): { ApproachStep }
	local steps: { ApproachStep } = {}
	local landAt = duration
	local side: Side = "Left"
	local gap = plantTime -- time from the previous contact to this landing
	while landAt >= minFlight and #steps < 12 do
		local startAt = landAt - gap
		table.insert(steps, 1, { side = side, startAt = math.max(startAt, 0), landAt = landAt })
		landAt = startAt
		gap = gatherTime
		side = if side == "Left" then "Right" else "Left"
	end
	return steps
end

return GaitMath
