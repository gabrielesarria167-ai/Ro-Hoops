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
--                    the air.
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
-- away; the one further away goes first. On a tie, `leadSide` (the side the body is
-- moving toward, if any) goes first, so a sideways shuffle always starts with the lead foot.
function GaitMath.pickStepper(rightError: number, leftError: number, threshold: number, leadSide: Side?): Side?
	local rightWants, leftWants = rightError >= threshold, leftError >= threshold
	if rightWants and leftWants then
		if math.abs(rightError - leftError) < 1e-3 and leadSide then
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

-- 4b. The foot's path through a step at `progress` (0 = lifting off, 1 = landed). Returns
-- how far along the ground it has moved (0 to 1, starting and stopping gently) and how
-- high it is as a share of the step's lift (0 on the ground, 1 at the top, mid-step).
function GaitMath.swing(progress: number): (number, number)
	local p = math.clamp(progress, 0, 1)
	local along = p * p * (3 - 2 * p)
	local height = 4 * p * (1 - p)
	return along, height
end

-- How high to lift the foot for a step `length` studs long: short shuffles slide low
-- along the floor, long steps lift more, between `minLift` and `maxLift`.
function GaitMath.liftFor(length: number, liftPerStud: number, minLift: number, maxLift: number): number
	return math.clamp(length * liftPerStud, minLift, maxLift)
end

return GaitMath
