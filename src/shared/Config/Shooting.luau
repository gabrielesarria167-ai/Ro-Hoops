--!strict
-- SHOOTING SETTINGS
-- How E works: when you press E the game picks a shot type from how you're moving (see
-- ShotMath.classify), you jump, and the timing meter starts filling. Let go inside the
-- green zone for a perfect release. Used by src/client/Controllers/ShotController.luau.
--
-- Timing is measured as "progress": held time ÷ FILL_TIME. So progress 0 = just pressed,
-- progress 1 = held for the full FILL_TIME. The perfect moment is at IDEAL_RELEASE.
--
-- Where the jump sits in that timing: the perfect release is IDEAL_RELEASE × FILL_TIME
-- seconds after E. The jump is timed backwards from it (ShotMath.dipTime): its top comes
-- JUMP_POWER ÷ gravity after takeoff, and the release comes APEX_OFFSET seconds after the
-- top, so the dip (the time on the ground) is whatever is left. Lower jumps therefore mean
-- a longer dip, and neither the meter nor the grading changes. (Research: close shots are
-- released just after the top of the jump, mid-range at it, long shots just before it.)
--
-- Drift is split in two: DIP_DRIFT / DIP_LATERAL_DRIFT is the body's velocity while it
-- gathers on the ground (a pull-up brakes to a stop, a side shot steps sideways), DRIFT / LATERAL_DRIFT is the (small) velocity it carries through the air.
--
-- Live-tunable under ReplicatedStorage > Tuning > Shooting while playing in Studio.

-- Which body motion a shot uses (the positions for each live in Config/Motion.luau):
--   "JumpShot" – two-foot dip, ball up past the face to above the head, both hands on it
--   "Layup"    – gather step, jump off the left foot driving the right knee up, ball
--                carried up the right side and laid in on an extended right arm
--   "Dunk"     – a two-handed power dunk: deep two-foot load, ball swung down then lifted
--                in both hands up over the head and swung out over the rim, slammed
--                through, hands down on the rim
-- (The ball and hands always follow `MOTION`. The LEGS of a running dunk use the layup's
-- one-foot takeoff instead; ShotController picks that, see its legStyle.)
export type MotionStyle = "JumpShot" | "Layup" | "Dunk"

-- How the feet land in the gather (LegController.startDip's `gather` option):
--   "None"     – both feet plant together under the body
--   "PullUp"   – braking 1-2 steps after a run: one foot lands ahead, the other steps in
--   "SideStep" – the body hops sideways: the leading foot lands first, the other shoulder-width away
export type GatherKind = "None" | "PullUp" | "SideStep"

-- The settings every shot type has (see `Types` at the bottom of this file).
export type ShotTypeConfig = {
	-- Name shown above the meter.
	LABEL: string,
	-- Seconds for the meter to reach progress 1. Bigger = slower meter, easier timing.
	FILL_TIME: number,
	-- Upward speed when jumping into the shot, studs/s. Bigger = higher jump (the rise is
	-- JUMP_POWER² ÷ (2 × gravity) studs). The dip is timed to fit: see ShotMath.dipTime.
	JUMP_POWER: number,
	-- Seconds the perfect release comes AFTER the top of the jump (negative = before it).
	APEX_OFFSET: number,
	-- Overrides Shooting.MIN_DIP_TIME for this shot (seconds), when its timing needs a
	-- shorter dip than the default. Leave out to use the default.
	MIN_DIP_TIME: number?,
	-- Speed toward the rim while gathering on the ground (the dip), studs/s. Negative =
	-- moving away from the rim.
	DIP_DRIFT: number,
	-- Sideways speed while gathering, in the direction you were moving, studs/s (a side
	-- shot's step to the side).
	DIP_LATERAL_DRIFT: number,
	-- Speed toward the rim while in the air, studs/s. Negative = drifting away (fadeaway).
	DRIFT: number,
	-- Sideways speed while in the air, in the direction you were moving, studs/s.
	LATERAL_DRIFT: number,
	-- How the feet land in the gather (see GatherKind). A pull-up only gathers like one
	-- when you were moving at PULLUP_GATHER_MIN_SPEED or more, else it plants both feet.
	GATHER: GatherKind,
	-- How deep the knees dip compared with a normal jump shot (1 = normal, 0.5 = half as
	-- deep). A close shot barely crouches.
	DIP_DEPTH_SCALE: number,
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

	-- The dip (time on the ground before takeoff) is worked out per shot by ShotMath.dipTime
	-- and kept between these two, seconds. Not shorter than MIN_DIP_TIME so the knee bend is
	-- visible, not longer than MAX_DIP_TIME so long shots don't feel sluggish. (A shot type
	-- may set its own MIN_DIP_TIME.)
	MIN_DIP_TIME = 0.14,
	MAX_DIP_TIME = 0.24,

	-- BODY FACING -----------------------------------------------------------------------

	-- How quickly the body turns to face the rim when a shot starts (higher = snappier).
	-- Lower than a normal turn so the head and eyes (PostureController) lead the body.
	SHOT_TURN_SHARPNESS = 12,
	-- A jump shooter stands turned a little: shooting side forward, shoulders 15-30° round
	-- (research: Miller & Bartlett 1993). Degrees the body faces to the LEFT of the line to
	-- the rim for a right-handed shot (0 = square to the rim). Jump shots only: layups and
	-- dunks face the rim.
	SHOT_BODY_YAW = 12,
	-- A pull-up only brakes with the 1-2 gather when you were moving at least this fast
	-- (studs/s); slower than that you just plant both feet.
	PULLUP_GATHER_MIN_SPEED = 6,

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
	-- Further out, heading mostly toward the rim is still a Layup up to this many feet
	-- walking, or DRIVE_LAYUP_RANGE_FT running (Shift). From out there you first drive in
	-- at your own speed (the gather steps), then take off as usual. Beyond these, moving
	-- toward the rim is a Pull-up.
	LAYUP_RANGE_FT = 10,
	DRIVE_LAYUP_RANGE_FT = 15,
	-- Moving slower than this (studs/s) counts as standing still → Jump Shot.
	STATIONARY_SPEED = 3,
	-- A layup carries you toward the rim but slows you so that you are this many feet from
	-- it (measured to your hips) at the moment of release. The ball is released about a foot
	-- further forward, so 5.5 ft puts it ~3.7 studs from the rim's centre: close enough to
	-- score, far enough that it rises over the front of the rim instead of into it. Lower it
	-- and layups start hitting the front of the rim.
	LAYUP_RELEASE_FT = 5.5,
	-- How much of the drive's forward speed you keep after letting go of a layup (0 = drop
	-- straight down, 1 = keep flying). A fast drive would otherwise carry you right under
	-- the rim and out past the backboard.
	LAYUP_CARRY_AFTER_RELEASE = 0.35,

	-- DUNK (double-click) -----------------------------------------------------------------
	-- Double-click (two clicks within DOUBLE_CLICK_TIME) to dunk. On the run you can dunk
	-- from up to DUNK_RANGE_FT when attacking the rim (moving toward it at DUNK_MIN_SPEED
	-- or more); right under it (STANDING_DUNK_RANGE_FT) also from a standstill. Like a long
	-- layup you first drive in at your own speed, then gather and take off. The jump is
	-- worked out so the ball is DUNK_CLEARANCE above the rim at the top, where it's slammed
	-- through automatically: no meter, a dunk you can get to always goes in (for now:
	-- later it can depend on defenders and the build's dunk/vertical attributes).
	DOUBLE_CLICK_TIME = 0.3, -- seconds allowed between the two clicks
	DUNK_RANGE_FT = 15,
	STANDING_DUNK_RANGE_FT = 5,
	DUNK_MIN_SPEED = 8, -- studs/s toward the rim (walking is 13, running 21)
	DUNK_CLEARANCE = 0.4, -- studs between the bottom of the ball and the rim at the top of the jump
	-- The highest jump power a dunk may use (upward speed, studs/s; layups use 14). If
	-- reaching the rim needs more, the dunk isn't possible ("CAN'T REACH").
	DUNK_MAX_JUMP_POWER = 28,
	DUNK_DIP_TIME = 0.2, -- seconds of gather (the left-foot plant) before a running takeoff
	STANDING_DUNK_DIP_TIME = 0.3, -- a standing dunk loads up longer (deep two-foot squat; no meter)
	-- Share (0-1) of the running speed kept while planting for a running dunk. The plant
	-- converts forward speed into height, so the planted foot isn't dragged; the rest of
	-- the distance to the rim is covered in the air.
	DUNK_PLANT_CARRY = 0.35,
	-- The slam: the ball is pushed from the top of the jump to DUNK_SLAM_DEPTH studs below
	-- the rim's centre in DUNK_SLAM_TIME seconds (shorter = harder slam). A basic dunk is
	-- a wrist snap over the rim, not a hammer, so it isn't too fast.
	DUNK_SLAM_DEPTH = 1.5,
	DUNK_SLAM_TIME = 0.14,
	-- How much of the forward speed you keep after the slam (0 = drop straight down, 1 =
	-- keep flying, under the rim and past the backboard). The rim "catches" you. Keep it
	-- near 0: drifting past the rim's centre makes the body turn round to face it again.
	DUNK_CARRY_AFTER_SLAM = 0,
	-- How quickly the speed drops to that at the slam (studs/s²; the normal drift blend is
	-- 60). Fast, so a running dunk stops in front of the rim instead of sliding under it.
	DUNK_STOP_RATE = 150,

	-- SHOT TYPES ------------------------------------------------------------------------
	-- One entry per shot. The key (e.g. JumpShot) must match a ShotType in ShotMath.luau.

	Types = {
		-- Standing still outside close range. Jump power 12 rises 1.3 studs (~26% of body
		-- height: still bigger than life), and the ball leaves the hand at the top.
		JumpShot = {
			LABEL = "Jump Shot",
			FILL_TIME = 0.42,
			JUMP_POWER = 12, -- top 0.22 s after takeoff, so a dip of ~0.17 s
			APEX_OFFSET = 0, -- released at the top of the jump
			DIP_DRIFT = 0,
			DIP_LATERAL_DRIFT = 0,
			DRIFT = 1, -- a small hop forward: lands ~0.4 stud ahead
			LATERAL_DRIFT = 0,
			GATHER = "None",
			DIP_DEPTH_SCALE = 1,
			ARC_HEIGHT = 2.5,
			DIFFICULTY = 1,
			MOTION = "JumpShot",
			LEAN = 0,
			SIDE_LEAN = 0,
		},
		-- Moving toward the rim outside close range. You brake over the dip and rise.
		PullUp = {
			LABEL = "Pull-up",
			FILL_TIME = 0.4,
			JUMP_POWER = 12, -- dip ~0.15 s
			APEX_OFFSET = 0,
			DIP_DRIFT = 0, -- brakes from your speed to a stop by takeoff (the feet stop under the body)
			DIP_LATERAL_DRIFT = 0,
			DRIFT = 1.5,
			LATERAL_DRIFT = 0,
			GATHER = "PullUp",
			DIP_DEPTH_SCALE = 1,
			ARC_HEIGHT = 2.5,
			DIFFICULTY = 1.15,
			MOTION = "JumpShot",
			LEAN = 0,
			SIDE_LEAN = 0,
		},
		-- Sprinting (Shift) away from the rim. You rise straight up, then fall back ~1 stud, leaning
		-- ~14° away from the rim (research: 12-15°), and shoot with a higher arc over the defender.
		Fadeaway = {
			LABEL = "Fadeaway",
			FILL_TIME = 0.45,
			JUMP_POWER = 11, -- a lower jump than a jump shot (research); dip ~0.21 s
			APEX_OFFSET = 0,
			DIP_DRIFT = 0,
			DIP_LATERAL_DRIFT = 0,
			DRIFT = -2.5, -- drifts back ~1 stud over the flight
			LATERAL_DRIFT = 0,
			GATHER = "None",
			DIP_DEPTH_SCALE = 1,
			ARC_HEIGHT = 2.8,
			DIFFICULTY = 1.3,
			MOTION = "JumpShot",
			LEAN = 14, -- total trunk tilt back; PostureController shares it out between hips and chest
			SIDE_LEAN = 0,
		},
		-- Moving mostly sideways. You step sideways DURING the dip (~1.2 studs), then rise
		-- with only a little sideways drift.
		SideShot = {
			LABEL = "Side Shot",
			FILL_TIME = 0.44,
			JUMP_POWER = 12, -- dip ~0.19 s
			APEX_OFFSET = 0,
			DIP_DRIFT = 0,
			DIP_LATERAL_DRIFT = 7,
			DRIFT = 0,
			LATERAL_DRIFT = 0.8,
			GATHER = "SideStep",
			DIP_DEPTH_SCALE = 1,
			ARC_HEIGHT = 2.6,
			DIFFICULTY = 1.25,
			MOTION = "JumpShot",
			LEAN = 0,
			-- Degrees the trunk tilts toward the sideways drift. Research says only 0-5° at the
			-- release, but that barely shows; Posture.SHOT_SHOULDER_LEVEL takes some back, so
			-- 16 looks like ~12° of bend.
			SIDE_LEAN = 23,
		},
		-- Moving toward the rim inside the layup range. You take off from the left foot, drive
		-- the right knee up, and lay the ball in off an extended right arm.
		Layup = {
			LABEL = "Layup",
			FILL_TIME = 0.34,
			-- 14 rises 1.8 studs (it used to be 20 = 3.6). The perfect release comes 0.06 s
			-- BEFORE the top of the jump, as in a real layup; the ball is still thrown to the rim.
			JUMP_POWER = 14,
			APEX_OFFSET = -0.06,
			MIN_DIP_TIME = 0.1, -- the left-foot plant is short: this timing needs a dip of ~0.12 s
			-- Not used: a layup keeps its drive speed (DRIFT below) through the plant and the air.
			DIP_DRIFT = 0,
			DIP_LATERAL_DRIFT = 0,
			-- Slowest drive into the layup, studs/s. You keep your own speed if faster; either way
			-- it's reduced automatically so you are LAYUP_RELEASE_FT from the rim at release.
			DRIFT = 9,
			LATERAL_DRIFT = 0,
			GATHER = "None", -- the approach's gather steps (LegController.startApproach) do the footwork
			DIP_DEPTH_SCALE = 1,
			-- Studs the arc peaks above the rim. The ball is released well below the rim, so a
			-- low arc (1) sends it up into the ring; 2.5 lets it rise over the front edge.
			ARC_HEIGHT = 2.5,
			DIFFICULTY = 0.5,
			MOTION = "Layup",
			LEAN = -8, -- forward, tall and carrying the drive into the rim (research: 5-15°)
			SIDE_LEAN = 0,
		},
		-- Standing or backing up inside close range. Close shots are released just AFTER the
		-- top of the jump (research), from a shallow, quick dip.
		CloseShot = {
			LABEL = "Close Shot",
			FILL_TIME = 0.38,
			JUMP_POWER = 11,
			APEX_OFFSET = 0.04,
			MIN_DIP_TIME = 0.1, -- this timing needs a dip of ~0.11 s
			DIP_DRIFT = 0,
			DIP_LATERAL_DRIFT = 0,
			DRIFT = 0.5,
			LATERAL_DRIFT = 0,
			GATHER = "None",
			DIP_DEPTH_SCALE = 0.5, -- half the knee bend of a jump shot
			ARC_HEIGHT = 1.5,
			DIFFICULTY = 0.7,
			MOTION = "JumpShot",
			LEAN = 0,
			SIDE_LEAN = 0,
		},
		-- Double-click (see DUNK above). Only LABEL, MOTION and LEAN are used: the jump, the
		-- drive and the release are all worked out from the rim, and there's no meter.
		Dunk = {
			LABEL = "Dunk",
			FILL_TIME = 1,
			JUMP_POWER = 0,
			APEX_OFFSET = 0,
			DIP_DRIFT = 0,
			DIP_LATERAL_DRIFT = 0,
			DRIFT = 0,
			LATERAL_DRIFT = 0,
			GATHER = "None",
			DIP_DEPTH_SCALE = 1,
			ARC_HEIGHT = 0,
			DIFFICULTY = 0,
			MOTION = "Dunk",
			LEAN = -10, -- leaning in toward the rim, reaching over it
			SIDE_LEAN = 0,
		},
	} :: { [string]: ShotTypeConfig },
}

return Shooting
