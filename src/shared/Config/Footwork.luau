--!strict
-- FOOTWORK SETTINGS
-- The procedural legs (src/client/Controllers/LegController.luau): the feet are planted on
-- the floor and step on their own, instead of playing a canned walk cycle, so they match
-- what the player is really doing. Modelled on real basketball footwork:
--   * dribbling stance – knees bent (hips lowered), feet a bit wider than the hips, the
--     ball-side foot slightly back so the body and the off foot protect the ball;
--   * sideways        – a shuffle: the lead foot steps, the trail foot follows, the feet
--     never cross;
--   * backward        – a backpedal with short, quick steps;
--   * forward running – Roblox's run animation (it already looks like a run);
--   * dribble moves   – each move places the feet itself (MOVE FOOTWORK below), e.g. the
--     spin pivots on one foot and swings the other leg round.
-- Units: studs and seconds. Live-tunable under ReplicatedStorage > Tuning > Footwork.

local Footwork = {
	-- STANCE ------------------------------------------------------------------------------

	STANCE_WIDTH = 1.4, -- studs between the feet (the hips are ~1 stud wide)
	STAGGER = 0.4, -- with the ball: the ball-side foot is this much behind the other one
	-- How much lower the hips are (knees bent), studs. Roblox legs are short (~1.6 studs),
	-- and bent knees are also what lets the feet reach out for a step.
	DRIBBLE_CROUCH = 0.35, -- with the ball (a low, athletic dribbling stance)
	NO_BALL_CROUCH = 0.2, -- without it
	-- Sit back into the stance: the feet are this far in front of the hips (knees over the
	-- toes), and the chest bends forward this many degrees (on top of any move's lean).
	FEET_FORWARD = 0.25,
	DRIBBLE_LEAN = 14, -- with the ball
	NO_BALL_LEAN = 4, -- without it
	CROUCH_SHARPNESS = 10, -- how quickly the hips go up/down and the chest bends. Higher = snappier.

	-- STEPPING ----------------------------------------------------------------------------

	-- A foot steps when it's this far (studs) from where it belongs while moving...
	STEP_TRIGGER = 0.4,
	-- ...or, after standing still for SETTLE_DELAY seconds, this far (squaring up the stance).
	SETTLE_TRIGGER = 0.25,
	SETTLE_DELAY = 0.12,
	-- Seconds per step: STEP_TIME_SLOW when nearly still, down to STEP_TIME_FAST at
	-- FAST_STEP_SPEED studs/s and above (quicker feet when moving faster).
	STEP_TIME_SLOW = 0.2,
	STEP_TIME_FAST = 0.12,
	FAST_STEP_SPEED = 16,
	-- The next foot may leave the floor once the stepping one is this share of the way
	-- through its step (0.65 = as it comes down). Lets the feet keep up at speed.
	STEP_OVERLAP = 0.65,
	-- A moving foot lands ahead of its spot by this share of the distance the body covers
	-- during the step, so the body travels over it instead of leaving it behind.
	LAND_AHEAD = 0.6,
	-- Foot lift, studs: LIFT_PER_STUD per stud of step length, between MIN_LIFT (a shuffle
	-- barely leaves the floor) and MAX_LIFT.
	LIFT_PER_STUD = 0.12,
	MIN_LIFT = 0.05,
	MAX_LIFT = 0.35,
	-- A planted foot further than this (studs, flat) from under its hip has to step straight
	-- away, even if the other foot is still in the air (a quick bound instead of the leg
	-- being stretched out of reach).
	MAX_REACH = 1.35,
	-- Feet never land closer than this (studs, sideways) or crossed over.
	MIN_FOOT_GAP = 0.6,
	-- Knees point forward this far in front of the feet, and this far out to the side.
	KNEE_FORWARD = 2,
	KNEE_OUT = 0.4,

	-- Running forward (within ~50° of straight at the rim, faster than ANIMATION_RUN_SPEED
	-- studs/s) hands the legs back to Roblox's run animation. ANIMATION_RUN_DOT is how
	-- straight ahead the movement must be: 1 = exactly, 0 = anything not backward.
	ANIMATION_RUN_SPEED = 6,
	ANIMATION_RUN_DOT = 0.6,

	-- MOVE FOOTWORK -----------------------------------------------------------------------
	-- Where the feet go in each dribble move (src/client/Controllers/SkillController.luau).
	-- A step's spot is relative to where the hips will be: OUT = studs further out to that
	-- foot's side than the normal stance, FORWARD = studs in front of the hips. Every move
	-- still moves the body only one step (Config/Skills.luau, FOOTWORK).

	-- The body keeps moving a little after each move's foot lands (and comes to a stop
	-- after the step), so move steps land this many seconds of travel further along.
	MOVE_LAND_AHEAD = 0.12,

	-- Wide crossover (Iverson): SELL – plant and jab the ball-side foot out wide, crouching
	-- low like a sprinter; EXPLODE – push off that foot, the new-side foot steps out the new
	-- way and the push foot follows (a quick bound).
	CROSS_JAB_OUT = 0.35,
	CROSS_JAB_FORWARD = 0.35,
	CROSS_JAB_TIME = 0.1, -- seconds for the jab
	CROSS_CROUCH = 0.3, -- extra studs lower during the move
	CROSS_LEAD_TIME = 0.2, -- seconds for the new-side foot's step
	CROSS_TRAIL_DELAY = 0.09, -- seconds after that before the push foot follows
	CROSS_TRAIL_TIME = 0.18,

	-- Stab: the ball-side foot stabs out to that side with the hard dribble, and the other
	-- foot follows it (push, pull, recover: a shuffle, feet never crossing).
	STAB_OUT = 0.25,
	STAB_FORWARD = 0.3,
	STAB_LEAD_TIME = 0.17,
	STAB_TRAIL_DELAY = 0.1,
	STAB_TRAIL_TIME = 0.16,
	STAB_CROUCH = 0.15,

	-- Step-back (Harden style): plant the front (off) foot hard, then push back off it and
	-- land on both feet, back foot first ("1-2").
	STEPBACK_PLANT_FORWARD = 0.4, -- how far forward the front foot plants
	STEPBACK_BACK_FOOT_TIME = 0.26, -- seconds for the back foot's step
	STEPBACK_FRONT_FOOT_DELAY = 0.08, -- front foot leaves this long after the back foot
	STEPBACK_FRONT_FOOT_TIME = 0.24,
	STEPBACK_LIFT = 0.3,
	STEPBACK_CROUCH = 0.15,

	-- Spin (reverse pivot): plant the foot on the side you're spinning toward and pivot on
	-- it while the other leg swings round behind you and lands past it; then the pivot foot
	-- comes off the floor and steps through to finish the stance. Times are shares of the
	-- turn (Skills.SPIN_TIME): 0 = start, 1 = end.
	SPIN_CROUCH = 0.3,
	SPIN_SWING_LANDS_AT = 0.55, -- when the swinging foot lands
	SPIN_PIVOT_LIFTS_AT = 0.5, -- when the pivot foot comes off the floor
	SPIN_PIVOT_LANDS_AT = 0.95,
	SPIN_SWING_BULGE = 1, -- studs the swinging foot sweeps out behind on its way round
	SPIN_SWING_PAST = 0.3, -- it lands this far past the middle of the hips (across the pivot foot)
	SPIN_LIFT = 0.35,
}

return Footwork
