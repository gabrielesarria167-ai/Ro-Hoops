--!strict
-- Shooting tuning. `E` picks a shot type from the player's movement (see ShotMath.classify),
-- holding it fills the timing meter, and releasing at the top of the meter is a perfect
-- release. Timing is measured as progress = held time / FILL_TIME, so 1.0 is ideal.

export type ShotTypeConfig = {
	LABEL: string,
	FILL_TIME: number, -- seconds from pressing E to the ideal release
	JUMP_POWER: number, -- vertical takeoff speed, studs/s
	DRIFT: number, -- velocity toward the rim during the jump (negative = away), studs/s
	LATERAL_DRIFT: number, -- sideways velocity in the direction the player was moving, studs/s
	ARC_HEIGHT: number, -- base apex height above the release or rim (whichever is higher), studs
	DIFFICULTY: number, -- multiplies aim error
}

local Shooting = {
	-- Timing windows, as a fraction of FILL_TIME either side of the ideal release.
	PERFECT_WINDOW = 0.06,
	GOOD_WINDOW = 0.14,
	OK_WINDOW = 0.28,
	LATE_LIMIT = 0.4, -- the shot releases on its own at progress 1 + LATE_LIMIT

	-- Aim error. Early releases fall short and late ones go long; sideways error is random.
	DEPTH_ERROR_PER_TIMING = 1.6, -- studs of short/long per unit of timing offset
	LATERAL_ERROR_PER_TIMING = 0.8,
	PERFECT_SPREAD = 0.05, -- small random error on a perfect release, studs

	-- Distance makes every shot harder past the easy range.
	EASY_RANGE_FT = 12,
	DIFFICULTY_PER_FT = 0.04,
	ARC_PER_FT = 0.12, -- longer shots get a higher arc, studs per foot of distance

	-- Shot type selection.
	CLOSE_RANGE_FT = 8, -- inside this, E becomes a layup or close shot
	STATIONARY_SPEED = 3, -- below this the player counts as standing still, studs/s
	LAYUP_STOP_FT = 3, -- a layup drive stops carrying the player this close to the rim

	Types = {
		JumpShot = {
			LABEL = "Jump Shot",
			FILL_TIME = 0.42,
			JUMP_POWER = 16,
			DRIFT = 0,
			LATERAL_DRIFT = 0,
			ARC_HEIGHT = 2.5,
			DIFFICULTY = 1,
		},
		PullUp = {
			LABEL = "Pull-up",
			FILL_TIME = 0.4,
			JUMP_POWER = 16,
			DRIFT = 0,
			LATERAL_DRIFT = 0,
			ARC_HEIGHT = 2.5,
			DIFFICULTY = 1.15,
		},
		Fadeaway = {
			LABEL = "Fadeaway",
			FILL_TIME = 0.45,
			JUMP_POWER = 15,
			DRIFT = -5,
			LATERAL_DRIFT = 0,
			ARC_HEIGHT = 2.8,
			DIFFICULTY = 1.3,
		},
		StepBack = {
			LABEL = "Step-back",
			FILL_TIME = 0.48,
			JUMP_POWER = 15,
			DRIFT = -9,
			LATERAL_DRIFT = 0,
			ARC_HEIGHT = 2.8,
			DIFFICULTY = 1.35,
		},
		SideShot = {
			LABEL = "Side Shot",
			FILL_TIME = 0.44,
			JUMP_POWER = 15,
			DRIFT = 0,
			LATERAL_DRIFT = 5,
			ARC_HEIGHT = 2.6,
			DIFFICULTY = 1.25,
		},
		Layup = {
			LABEL = "Layup",
			FILL_TIME = 0.34,
			JUMP_POWER = 20,
			DRIFT = 9, -- maximum; the actual drift is reduced so the player stops short of the rim
			LATERAL_DRIFT = 0,
			ARC_HEIGHT = 1,
			DIFFICULTY = 0.5,
		},
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
