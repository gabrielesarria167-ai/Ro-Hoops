--!strict
-- SHOT MATH
-- Plain math with no Roblox APIs, so it can be unit tested outside Studio with Lune
-- (tests/ShotMath.spec.luau). Covers the decisions behind every shot:
--   1. classify       – which shot type an E press becomes
--   2. grade          – how well the release was timed
--   3. aimError       – how far off target a mistimed release lands
--   4. launchVelocity – the exact throw that makes the ball land on that target
-- and behind finishing at the rim (layups and dunks):
--   5. canDunk        – whether a double-click can dunk from here, and which kind
--   6. finishTiming   – how long the drive to the rim takes and how fast it goes
--   7. jumpPowerFor   – the jump that rises exactly high enough
--   8. slamVelocity   – the throw that slams the ball down through the rim
-- and behind the jump's timing:
--   9. dipTime        – how long to gather on the ground so the release lands where it should
--                       relative to the top of the jump

local ShotMath = {}

-- Every shot type. Each one must have a matching entry in Config/Shooting.luau `Types`.
export type ShotType = "JumpShot" | "PullUp" | "Fadeaway" | "SideShot" | "Layup" | "CloseShot" | "Dunk"

-- How a dunk is taken: on the run (one-foot takeoff off the left foot, from up to
-- DUNK_RANGE_FT) or from a standstill right under the rim (deep two-foot takeoff).
export type DunkKind = "Running" | "Standing"

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
	LAYUP_RANGE_FT: number,
	DRIVE_LAYUP_RANGE_FT: number,
	STATIONARY_SPEED: number,
}

export type DunkConfig = {
	DUNK_RANGE_FT: number,
	STANDING_DUNK_RANGE_FT: number,
	DUNK_MIN_SPEED: number,
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
	-- A little further out, heading mostly at the rim is still a layup: you drive in for
	-- the gather steps first. Running (Shift) reaches further, like a real drive.
	local layupRange = if context.running then config.DRIVE_LAYUP_RANGE_FT else config.LAYUP_RANGE_FT
	if context.distanceFeet <= layupRange and toward > config.STATIONARY_SPEED and toward >= lateral then
		return "Layup"
	end

	-- Further out: barely moving is a standing jump shot...
	if math.sqrt(toward * toward + lateral * lateral) < config.STATIONARY_SPEED then
		return "JumpShot"
	end
	-- ...otherwise the main direction of movement decides.
	if lateral > math.abs(toward) then
		return "SideShot"
	end
	-- Away from the rim: only sprinting back (Shift) fades away. Walking back is a plain jump
	-- shot, as is a step-back (the dribble move, then E): you rise straight up.
	if toward < 0 then
		return if context.running then "Fadeaway" else "JumpShot"
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

-- 5. Whether a double-click dunks from here (nil = it can't). Right under the rim
-- (STANDING_DUNK_RANGE_FT) you can dunk from a standstill; further out, up to
-- DUNK_RANGE_FT, you need to be attacking the rim: moving at it at DUNK_MIN_SPEED or more,
-- more toward it than across. (Whether the jump can reach the rim is checked separately,
-- with jumpPowerFor.)
function ShotMath.canDunk(context: ShotContext, config: DunkConfig): DunkKind?
	local toward = context.towardSpeed
	local attacking = toward >= config.DUNK_MIN_SPEED and toward >= math.abs(context.lateralSpeed)
	if context.distanceFeet <= config.STANDING_DUNK_RANGE_FT then
		return if attacking then "Running" else "Standing"
	end
	if context.distanceFeet <= config.DUNK_RANGE_FT and attacking then
		return "Running"
	end
	return nil
end

-- 6. A finish (layup or dunk) carries you `room` studs toward the rim. It takes at least
-- `minTime` seconds (the gather and jump themselves), and you never go faster than
-- `driveSpeed` (how fast you were attacking), so from further out it takes longer: those
-- extra seconds are the drive in before the gather. Returns (seconds, speed in studs/s).
function ShotMath.finishTiming(room: number, driveSpeed: number, minTime: number): (number, number)
	room = math.max(room, 0)
	local seconds = math.max(minTime, room / math.max(driveSpeed, 0.01), 0.01)
	return seconds, room / seconds
end

-- 7. The jump power (upward speed at takeoff, studs/s) that rises exactly `rise` studs
-- under `gravity`: rise = power² / (2 × gravity). The top comes power / gravity seconds
-- after takeoff.
function ShotMath.jumpPowerFor(rise: number, gravity: number): number
	return math.sqrt(2 * gravity * math.max(rise, 0))
end

-- 8. The throw that takes the ball from (x0, y0, z0) to (x1, y1, z1) in exactly `seconds`
-- under `gravity`: the straight-line speed plus enough extra upward speed to cancel what
-- gravity adds on the way. Returns (vx, vy, vz).
function ShotMath.slamVelocity(
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	seconds: number,
	gravity: number
): (number, number, number)
	local t = math.max(seconds, 0.01)
	return (x1 - x0) / t, (y1 - y0) / t + 0.5 * gravity * t, (z1 - z0) / t
end

-- 9. How long the dip (the gather on the ground before takeoff) lasts. The perfect release
-- is `idealRelease` seconds after E. The jump's top comes jumpPower / gravity seconds after
-- takeoff, and the release should come `apexOffset` seconds after that top (negative =
-- before it), so the dip is what is left of `idealRelease`. It is kept between `minDip` and
-- `maxDip`: if the clamp bites, the release lands off its intended spot relative to the top
-- (the meter timing never changes, only where in the jump the ball is let go).
function ShotMath.dipTime(
	idealRelease: number,
	jumpPower: number,
	gravity: number,
	apexOffset: number,
	minDip: number,
	maxDip: number
): number
	local releaseAfterTakeoff = jumpPower / gravity + apexOffset
	return math.clamp(idealRelease - releaseAfterTakeoff, minDip, maxDip)
end

return ShotMath
