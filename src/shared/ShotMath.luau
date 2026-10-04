--!strict
-- Pure shot logic with no Roblox APIs, so it can be unit tested with Lune: picking the shot
-- type from movement, grading release timing, turning a timing miss into an aim error, and
-- solving the launch velocity of the arc.

local ShotMath = {}

export type ShotType = "JumpShot" | "PullUp" | "Fadeaway" | "StepBack" | "SideShot" | "Layup" | "CloseShot"
export type Grade = "Perfect" | "Good" | "Early" | "Late" | "VeryEarly" | "VeryLate"

export type ShotContext = {
	distanceFeet: number, -- horizontal distance to the rim
	towardSpeed: number, -- velocity toward the rim, studs/s (negative = moving away)
	lateralSpeed: number, -- velocity across the court, studs/s (sign = side)
	running: boolean,
}

export type ClassifyConfig = {
	CLOSE_RANGE_FT: number,
	STATIONARY_SPEED: number,
}

export type GradeConfig = {
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

-- The same E press becomes a different shot depending on where the player is and how
-- they're moving when they press it.
function ShotMath.classify(context: ShotContext, config: ClassifyConfig): ShotType
	local toward = context.towardSpeed
	local lateral = math.abs(context.lateralSpeed)

	if context.distanceFeet <= config.CLOSE_RANGE_FT then
		if toward > config.STATIONARY_SPEED then
			return "Layup"
		end
		return "CloseShot"
	end

	if math.sqrt(toward * toward + lateral * lateral) < config.STATIONARY_SPEED then
		return "JumpShot"
	end
	if lateral > math.abs(toward) then
		return "SideShot"
	end
	if toward < 0 then
		return if context.running then "StepBack" else "Fadeaway"
	end
	return "PullUp"
end

-- `progress` is held time / fill time, so 1 is the ideal release. Returns the signed timing
-- offset (negative = early) and its grade.
function ShotMath.grade(progress: number, config: GradeConfig): (number, Grade)
	local offset = progress - 1
	local miss = math.abs(offset)
	if miss <= config.PERFECT_WINDOW then
		return offset, "Perfect"
	elseif miss <= config.GOOD_WINDOW then
		return offset, "Good"
	elseif miss <= config.OK_WINDOW then
		return offset, if offset < 0 then "Early" else "Late"
	end
	return offset, if offset < 0 then "VeryEarly" else "VeryLate"
end

function ShotMath.difficulty(typeDifficulty: number, distanceFeet: number, config: DifficultyConfig): number
	local extraFeet = math.max(0, distanceFeet - config.EASY_RANGE_FT)
	return typeDifficulty * (1 + extraFeet * config.DIFFICULTY_PER_FT)
end

-- Returns (depth, lateral) error in studs. Positive depth is long, negative is short.
-- Early releases fall short and late ones go long, so a miss tells the player which way
-- their timing was off; only the sideways error is random. `roll1` and `roll2` are in [0, 1).
function ShotMath.aimError(
	offset: number,
	difficulty: number,
	config: AimConfig,
	roll1: number,
	roll2: number
): (number, number)
	if math.abs(offset) <= config.PERFECT_WINDOW then
		local spread = config.PERFECT_SPREAD * difficulty
		return (roll1 * 2 - 1) * spread, (roll2 * 2 - 1) * spread
	end
	local depth = offset * config.DEPTH_ERROR_PER_TIMING * difficulty
	local lateral = (roll2 * 2 - 1) * math.abs(offset) * config.LATERAL_ERROR_PER_TIMING * difficulty
	return depth, lateral
end

-- Solves the launch velocity of a projectile from (x0, y0, z0) to (x1, y1, z1) whose apex is
-- `arcHeight` above the higher endpoint. Returns vx, vy, vz and the flight time.
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
	local apex = math.max(y0, y1) + math.max(arcHeight, 0.05)
	local vy = math.sqrt(2 * gravity * (apex - y0))
	local flightTime = vy / gravity + math.sqrt(2 * (apex - y1) / gravity)
	return (x1 - x0) / flightTime, vy, (z1 - z0) / flightTime, flightTime
end

return ShotMath
