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

-- Which body motion a shot uses (the positions for each live in Config/Motion.luau):
--   "JumpShot" – two-foot dip, ball up past the face to above the head, both hands on it
--   "Layup"    – gather step, jump off the left foot driving the right knee up, ball
--                carried up the right side and laid in on an extended right arm
export type MotionStyle = "JumpShot" | "Layup"

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
	-- Which body motion the shot uses (see MotionStyle above). Not live-tunable.
	MOTION: MotionStyle,
	-- How far the whole body tilts back in the air, degrees (negative = forward). It leans
	-- in from takeoff to the perfect release and straightens up after landing.
	LEAN: number,
	-- How far the whole body tilts sideways in the air, degrees. It always tilts the SAME
	-- way you are drifting sideways (a side shot moving left to right bends left to right,
	-- carrying the momentum through the shot). Same timing as LEAN.
	SIDE_LEAN: number,
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
	-- A layup carries you toward the rim but slows you so that you are this many feet from
	-- it (measured to your hips) at the moment of release. The ball is released about a foot
	-- further forward, so 5.5 ft puts it ~3.7 studs from the rim's centre: close enough to
	-- score, far enough that it rises over the front of the rim instead of into it. Lower it
	-- and layups start hitting the front of the rim.
	LAYUP_RELEASE_FT = 5.5,

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
			MOTION = "JumpShot",
			LEAN = 0,
			SIDE_LEAN = 0,
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
			MOTION = "JumpShot",
			LEAN = 0,
			SIDE_LEAN = 0,
		},
		-- Walking away from the rim. You jump backward, leaning ~20° away from the rim, and
		-- shoot with a higher arc over the defender.
		Fadeaway = {
			LABEL = "Fadeaway",
			FILL_TIME = 0.45,
			JUMP_POWER = 15,
			DRIFT = -5,
			LATERAL_DRIFT = 0,
			ARC_HEIGHT = 2.8,
			DIFFICULTY = 1.3,
			MOTION = "JumpShot",
			LEAN = 20, -- the whole body tilts back in one straight line, feet to head
			SIDE_LEAN = 0,
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
			MOTION = "JumpShot",
			LEAN = 0,
			SIDE_LEAN = 0,
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
			MOTION = "JumpShot",
			LEAN = 0,
			SIDE_LEAN = 15, -- tilts 15° toward the sideways drift
		},
		-- Moving toward the rim inside close range. You take off from the left foot, drive the
		-- right knee up, and lay the ball in off an extended right arm.
		Layup = {
			LABEL = "Layup",
			FILL_TIME = 0.34,
			JUMP_POWER = 20,
			DRIFT = 9, -- maximum; reduced automatically so you are LAYUP_RELEASE_FT from the rim at release
			LATERAL_DRIFT = 0,
			-- Studs the arc peaks above the rim. The ball is released well below the rim, so a
			-- low arc (1) sends it up into the ring; 2.5 lets it rise over the front edge.
			ARC_HEIGHT = 2.5,
			DIFFICULTY = 0.5,
			MOTION = "Layup",
			LEAN = -4, -- a touch forward, carrying the drive into the rim
			SIDE_LEAN = 0,
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
			MOTION = "JumpShot",
			LEAN = 0,
			SIDE_LEAN = 0,
		},
	} :: { [string]: ShotTypeConfig },
}

return Shooting
