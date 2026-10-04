--!strict
-- SHOOTING SETTINGS
-- How E works: when you press E the game picks a shot type from how you're moving (see
-- ShotMath.classify), you jump, and the timing meter starts filling. Let go inside the
-- green zone for a perfect release. Used by src/client/Controllers/ShotController.luau.
--
-- Timing is measured as "progress": held time ÷ FILL_TIME. So progress 0 = just pressed,
-- progress 1 = held for the full FILL_TIME. The perfect moment is at IDEAL_RELEASE.
--
-- Live-tunable under ReplicatedStorage > Tuning > Shooting while playing in Studio.

-- The settings every shot type has (see `Types` at the bottom of this file).
export type ShotTypeConfig = {
	-- Name shown above the meter.
	LABEL: string,
	-- Seconds for the meter to reach progress 1. Bigger = slower meter, easier timing.
	FILL_TIME: number,
	-- Upward speed when jumping into the shot, studs/s. Bigger = higher jump.
	JUMP_POWER: number,
	-- Speed toward the rim while in the air, studs/s. Negative = drifting away (fadeaway).
	DRIFT: number,
	-- Sideways speed while in the air, in the direction you were moving, studs/s.
	LATERAL_DRIFT: number,
	-- How high the ball's arc peaks above the release point or the rim (whichever is
	-- higher), studs. Distance adds more on top via ARC_PER_FT.
	ARC_HEIGHT: number,
	-- Multiplies the aim error of a mistimed release. 1 = normal, 2 = misses twice as far.
	DIFFICULTY: number,
}

local Shooting = {
	-- TIMING ----------------------------------------------------------------------------

	-- Where the perfect moment (centre of the green zone) sits, as progress.
	-- Lower = you have to release earlier. 0.92 = 92% of FILL_TIME (~0.39 s on a jump shot).
	IDEAL_RELEASE = 0.92,

	-- How far from IDEAL_RELEASE (in progress) a release can be and still get each grade.
	-- E.g. 0.06 on a jump shot = ±0.06 × 0.42 s ≈ ±25 ms for a perfect.
	PERFECT_WINDOW = 0.06, -- green zone: "PERFECT"
	GOOD_WINDOW = 0.14, -- "GOOD"
	OK_WINDOW = 0.28, -- "EARLY" / "LATE"; anything further is "WAY EARLY" / "WAY LATE"

	-- If you never let go, the shot releases by itself at progress 1 + LATE_LIMIT.
	LATE_LIMIT = 0.4,

	-- AIM ERROR -------------------------------------------------------------------------
	-- A mistimed release misses in a readable way: early = short, late = long.

	-- Studs short/long the ball lands per unit of timing error (before difficulty, and
	-- before the Court.EQUIPMENT_SCALE scaling). At 3, GOOD releases still go in (often
	-- off the rim) and EARLY / LATE releases land past the rim's edge and mostly miss.
	DEPTH_ERROR_PER_TIMING = 3,
	-- Max studs left/right per unit of timing error; the actual amount is random.
	LATERAL_ERROR_PER_TIMING = 0.8,
	-- Tiny random error on a perfect release, studs. Small enough to still go in.
	PERFECT_SPREAD = 0.05,

	-- DISTANCE --------------------------------------------------------------------------

	-- Shots from within this many feet get no distance penalty.
	EASY_RANGE_FT = 12,
	-- Each foot beyond EASY_RANGE_FT makes aim error this much bigger (0.04 = +4% per ft).
	DIFFICULTY_PER_FT = 0.04,
	-- Each foot of distance raises the ball's arc by this many studs.
	ARC_PER_FT = 0.12,

	-- SHOT TYPE SELECTION ---------------------------------------------------------------

	-- Inside this many feet from the rim, E becomes a Layup (if moving toward the rim) or
	-- a Close Shot (otherwise).
	CLOSE_RANGE_FT = 8,
	-- Moving slower than this (studs/s) counts as standing still → Jump Shot.
	STATIONARY_SPEED = 3,
	-- A layup carries you toward the rim but stops you this many feet short of it.
	LAYUP_STOP_FT = 4,

	-- SHOT TYPES ------------------------------------------------------------------------
	-- One entry per shot. The key (e.g. JumpShot) must match a ShotType in ShotMath.luau.

	Types = {
		-- Standing still outside close range.
		JumpShot = {
			LABEL = "Jump Shot",
			FILL_TIME = 0.42,
			JUMP_POWER = 16,
			DRIFT = 0,
			LATERAL_DRIFT = 0,
			ARC_HEIGHT = 2.5,
			DIFFICULTY = 1,
		},
		-- Moving toward the rim outside close range. You stop and rise.
		PullUp = {
			LABEL = "Pull-up",
			FILL_TIME = 0.4,
			JUMP_POWER = 16,
			DRIFT = 0,
			LATERAL_DRIFT = 0,
			ARC_HEIGHT = 2.5,
			DIFFICULTY = 1.15,
		},
		-- Walking away from the rim. You drift backward in the air.
		Fadeaway = {
			LABEL = "Fadeaway",
			FILL_TIME = 0.45,
			JUMP_POWER = 15,
			DRIFT = -5,
			LATERAL_DRIFT = 0,
			ARC_HEIGHT = 2.8,
			DIFFICULTY = 1.3,
		},
		-- Running (Shift) away from the rim. A bigger backward hop than a fadeaway.
		StepBack = {
			LABEL = "Step-back",
			FILL_TIME = 0.48,
			JUMP_POWER = 15,
			DRIFT = -9,
			LATERAL_DRIFT = 0,
			ARC_HEIGHT = 2.8,
			DIFFICULTY = 1.35,
		},
		-- Moving mostly sideways. You drift sideways in the air.
		SideShot = {
			LABEL = "Side Shot",
			FILL_TIME = 0.44,
			JUMP_POWER = 15,
			DRIFT = 0,
			LATERAL_DRIFT = 5,
			ARC_HEIGHT = 2.6,
			DIFFICULTY = 1.25,
		},
		-- Moving toward the rim inside close range. You carry forward and lay it in.
		Layup = {
			LABEL = "Layup",
			FILL_TIME = 0.34,
			JUMP_POWER = 20,
			DRIFT = 9, -- maximum; reduced automatically so you stop LAYUP_STOP_FT short of the rim
			LATERAL_DRIFT = 0,
			ARC_HEIGHT = 1,
			DIFFICULTY = 0.5,
		},
		-- Standing or backing up inside close range.
		CloseShot = {
			LABEL = "Close Shot",
			FILL_TIME = 0.38,
			JUMP_POWER = 15,
			DRIFT = 0,
			LATERAL_DRIFT = 0,
			ARC_HEIGHT = 1.5,
			DIFFICULTY = 0.7,
		},
	} :: { [string]: ShotTypeConfig },
}

return Shooting
