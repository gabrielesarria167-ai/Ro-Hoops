--!strict
-- SHOT MATH
-- Plain math with no Roblox APIs, so it can be unit tested outside Studio with Lune
-- (tests/ShotMath.spec.luau). Covers the four decisions behind every shot:
--   1. classify       – which shot type an E press becomes
--   2. grade          – how well the release was timed
--   3. aimError       – how far off target a mistimed release lands
--   4. launchVelocity – the exact throw that makes the ball land on that target

local ShotMath = {}

-- Every shot type. Each one must have a matching entry in Config/Shooting.luau `Types`.
export type ShotType = "JumpShot" | "PullUp" | "Fadeaway" | "StepBack" | "SideShot" | "Layup" | "CloseShot"

-- Every release grade, from best to worst on each side of the perfect moment.
export type Grade = "Perfect" | "Good" | "Early" | "Late" | "VeryEarly" | "VeryLate"

-- What the player was doing when E was pressed.
export type ShotContext = {
	distanceFeet: number, -- flat distance from the player to the rim, in feet
	towardSpeed: number, -- speed toward the rim, studs/s (negative = moving away from it)
	lateralSpeed: number, -- speed across the court, studs/s (the sign says which side)
	running: boolean, -- whether Shift was held
}

-- The settings each function needs (they come from Config/Shooting.luau).
export type ClassifyConfig = {
	CLOSE_RANGE_FT: number,
	STATIONARY_SPEED: number,
}

export type GradeConfig = {
	IDEAL_RELEASE: number,
	PERFECT_WINDOW: number,
	GOOD_WINDOW: number,
	OK_WINDOW: number,
}

export type DifficultyConfig = {
	EASY_RANGE_FT: number,
	DIFFICULTY_PER_FT: number,
}

export type AimConfig = {
	PERFECT_WINDOW: number,
	PERFECT_SPREAD: number,
	DEPTH_ERROR_PER_TIMING: number,
	LATERAL_ERROR_PER_TIMING: number,
}

-- 1. Picks the shot type. The same E press becomes a different shot depending on where
-- the player is and how they're moving when they press it.
function ShotMath.classify(context: ShotContext, config: ClassifyConfig): ShotType
	local toward = context.towardSpeed
	local lateral = math.abs(context.lateralSpeed)

	-- Near the rim: attacking it is a layup, anything else is a close shot.
	if context.distanceFeet <= config.CLOSE_RANGE_FT then
		if toward > config.STATIONARY_SPEED then
			return "Layup"
		end
		return "CloseShot"
	end

	-- Further out: barely moving is a standing jump shot...
	if math.sqrt(toward * toward + lateral * lateral) < config.STATIONARY_SPEED then
		return "JumpShot"
	end
	-- ...otherwise the main direction of movement decides.
	if lateral > math.abs(toward) then
		return "SideShot"
	end
	if toward < 0 then
		return if context.running then "StepBack" else "Fadeaway"
	end
	return "PullUp"
end

-- 2. Grades the release. `progress` is held time ÷ FILL_TIME; the perfect moment is at
-- IDEAL_RELEASE. Returns the signed timing offset (negative = early, positive = late)
-- and the grade.
function ShotMath.grade(progress: number, config: GradeConfig): (number, Grade)
	local offset = progress - config.IDEAL_RELEASE
	local miss = math.abs(offset) -- how far off, ignoring early/late
	if miss <= config.PERFECT_WINDOW then
		return offset, "Perfect"
	elseif miss <= config.GOOD_WINDOW then
		return offset, "Good"
	elseif miss <= config.OK_WINDOW then
		return offset, if offset < 0 then "Early" else "Late"
	end
	return offset, if offset < 0 then "VeryEarly" else "VeryLate"
end

-- How hard a shot is: the shot type's DIFFICULTY, increased for every foot beyond the
-- easy range. Multiplies the aim error.
function ShotMath.difficulty(typeDifficulty: number, distanceFeet: number, config: DifficultyConfig): number
	local extraFeet = math.max(0, distanceFeet - config.EASY_RANGE_FT)
	return typeDifficulty * (1 + extraFeet * config.DIFFICULTY_PER_FT)
end

-- 3. Turns a timing offset into where the ball lands relative to the rim's centre.
-- Returns (depth, lateral) in studs: depth > 0 is long (past the rim), depth < 0 is short.
--
-- Early releases fall short and late ones go long, so a miss tells the player which way
-- their timing was off. Only the sideways error is random. `roll1` and `roll2` are random
-- numbers between 0 and 1, passed in so tests can control them.
function ShotMath.aimError(
	offset: number,
	difficulty: number,
	config: AimConfig,
	roll1: number,
	roll2: number
): (number, number)
	if math.abs(offset) <= config.PERFECT_WINDOW then
		-- Perfect: a tiny random wobble that still goes in.
		local spread = config.PERFECT_SPREAD * difficulty
		return (roll1 * 2 - 1) * spread, (roll2 * 2 - 1) * spread
	end
	local depth = offset * config.DEPTH_ERROR_PER_TIMING * difficulty
	local lateral = (roll2 * 2 - 1) * math.abs(offset) * config.LATERAL_ERROR_PER_TIMING * difficulty
	return depth, lateral
end

-- 4. Solves the throw. Given a start point (x0, y0, z0), a target (x1, y1, z1), how high
-- the arc should peak (`arcHeight` studs above the higher of the two points) and gravity,
-- returns the launch velocity (vx, vy, vz) and how many seconds the ball will fly.
function ShotMath.launchVelocity(
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	arcHeight: number,
	gravity: number
): (number, number, number, number)
	-- Height of the arc's peak. The tiny minimum avoids dividing by zero on a flat arc.
	local apex = math.max(y0, y1) + math.max(arcHeight, 0.05)
	-- Upward speed needed to rise from y0 to the apex.
	local vy = math.sqrt(2 * gravity * (apex - y0))
	-- Time going up to the apex, plus time falling from the apex down to the target.
	local flightTime = vy / gravity + math.sqrt(2 * (apex - y1) / gravity)
	-- Horizontal speed is constant, so it just covers the distance in that time.
	return (x1 - x0) / flightTime, vy, (z1 - z0) / flightTime, flightTime
end

return ShotMath
