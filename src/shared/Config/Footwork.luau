--!strict
-- FOOTWORK SETTINGS
-- The procedural legs (src/client/Controllers/LegController.luau): the feet are planted on
-- the floor and step on their own, instead of playing a canned walk cycle, so they match
-- what the player is really doing. Modelled on real basketball footwork (research and
-- sources: docs/MOVEMENT_REFERENCES.md):
--   * dribbling stance – knees bent (hips lowered), feet a bit wider than the hips, nearly
--     square, toes turned out a little; the ball-side foot is slightly back;
--   * sideways        – a step-slide: the lead foot steps, the trail foot follows low, the
--     feet never cross;
--   * backward        – a backpedal with short, quick, toe-first steps;
--   * forward running – Roblox's run animation (it already looks like a run); the footfalls
--     are still detected so the dribble can bounce in time with them;
--   * dribble moves   – each move places the feet itself (MOVE FOOTWORK below), e.g. the
--     spin pivots on the ball of one foot while the other leg swings round;
--   * shots           – a dip where the feet land under the body (GATHERS), a one-foot layup
--     takeoff with running gather steps (APPROACH), legs that reach for the floor
--     (AIR LEGS, LANDING).
-- Units: studs, seconds and degrees unless a comment says otherwise. Live-tunable under
-- ReplicatedStorage > Tuning > Footwork.

local Footwork = {
	-- STANCE ------------------------------------------------------------------------------

	STANCE_WIDTH = 1.5, -- studs between the feet (the hips are ~1 stud wide)
	-- With the ball: the ball-side foot is this many studs behind the other one. Research:
	-- a neutral stance is nearly square (0-0.15), a protecting one has 0.5-0.85.
	STAGGER = 0.2,
	TOE_OUT = 10, -- degrees each foot is turned outward (research 5-15)
	-- How much lower the hips are (knees bent), studs. Roblox legs are short (~1.6 studs),
	-- and bent knees are also what lets the feet reach out for a step.
	DRIBBLE_CROUCH = 0.27, -- with the ball (knees ~55-60 degrees; research idle 30-40, low 50-65)
	NO_BALL_CROUCH = 0.15, -- without it
	-- Sit back into the stance: the feet are this far in front of the hips (knees over the
	-- toes), and the trunk hinges forward this many degrees in total (PostureController
	-- splits it over hips and chest and keeps the eyes level).
	FEET_FORWARD = 0.25,
	DRIBBLE_LEAN = 24, -- with the ball
	NO_BALL_LEAN = 8, -- without it
	CROUCH_SHARPNESS = 10, -- how quickly the hips go up/down and the chest bends. Higher = snappier.
	-- The leg's length from hip joint to ankle joint, studs. Only a fallback: the real length
	-- is measured from the character's own body parts when its legs are set up.
	LEG_LENGTH = 1.6,
	-- Shortens the leg by this many studs when working out how far a planted foot can reach,
	-- so a foot is never asked to be placed with the knee locked dead straight.
	REACH_MARGIN = 0.08,
	-- A reaching foot is allowed this many studs more than the stance's crouch gives (a
	-- walking hip dips as the leg reaches), when working out where a step may land.
	REACH_STEP_DIP = 0.1,

	-- STEPPING ----------------------------------------------------------------------------

	-- A foot steps when it's this far (studs) from where it belongs while moving...
	STEP_TRIGGER = 0.4,
	-- ...or, after standing still for SETTLE_DELAY seconds, this far (squaring up the stance).
	SETTLE_TRIGGER = 0.25,
	SETTLE_DELAY = 0.12,
	-- Switching ball hand flips the stagger. A foot only re-steps for that when the flip is at
	-- least this many studs (the stagger itself is smaller, so H just shifts the weight).
	STAGGER_RESTEP = 0.35,
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
	-- Feet never land closer than this (studs, sideways) or crossed over.
	MIN_FOOT_GAP = 0.6,
	-- Knees point forward this far in front of the feet, and this far out to the side.
	KNEE_FORWARD = 2,
	KNEE_OUT = 0.4,

	-- Step-slide (sideways): the lead foot (the side you travel toward) always steps first and
	-- the trail foot leaves once the lead step is this share through, low over the floor.
	SHUFFLE_TRAIL_DELAY = 0.45,
	SHUFFLE_LIFT = 0.07, -- studs a shuffling foot rises (research clearance 0.05-0.1)

	-- Backpedal: short steps (studs, at most) landing toe first, then the heel comes down.
	BACKPEDAL_MAX_STEP = 0.9,
	BACKPEDAL_TOE_DOWN = 15, -- degrees the toe points down at touchdown
	TOE_LAND_TIME = 0.08, -- seconds for the heel to come down after a toe-first (or heel-first) landing

	-- FEET ---------------------------------------------------------------------------------

	SWING_TOE_UP = 10, -- degrees the toe is raised in the middle of a step (the foot clears the floor)
	-- A planted foot keeps its direction while the body turns, until the body has turned this
	-- many degrees away from it; then it steps (or, in a dribble move, twists on the spot).
	FOOT_TWIST_LIMIT = 35,
	-- Studs from the ankle forward to the ball of the foot, the spot a foot pivots on.
	FOOT_BALL_FORWARD = 0.25,
	-- Studs from the ankle to the tip of the toe and to the back of the heel. A foot that is
	-- pitched is raised this much so the toe (or heel) rests on the floor, not inside it.
	FOOT_TOE_LENGTH = 0.5,
	FOOT_HEEL_LENGTH = 0.35,
	-- A foot that was in the air (taking over from the run animation, landing from a jump)
	-- eases down to the floor over this many seconds instead of snapping to it.
	FOOT_SETTLE_TIME = 0.08,

	-- RUNNING (Roblox's run animation) --------------------------------------------------------

	-- Running forward (within ~50 degrees of straight at the rim, faster than ANIMATION_RUN_SPEED
	-- studs/s) hands the legs to Roblox's run animation. ANIMATION_RUN_DOT is how straight
	-- ahead the movement must be: 1 = exactly, 0 = anything not backward. The footwork takes
	-- the legs back only below the EXIT values (lower, so there's no flicker near the edge).
	ANIMATION_RUN_SPEED = 6,
	ANIMATION_RUN_DOT = 0.6,
	ANIMATION_RUN_EXIT_SPEED = 4.5,
	ANIMATION_RUN_EXIT_DOT = 0.45,
	-- Under the run animation a foot "plants" when its ankle comes within this many studs of
	-- the floor (resting height) after having been higher. The plant is reported to
	-- BallController so the dribble bounces in time with the feet.
	PLANT_DETECT_HEIGHT = 0.15,
	-- Seconds without a footfall after which the step period estimate is forgotten.
	GAIT_FORGET_TIME = 0.8,

	-- SHOT DIP ----------------------------------------------------------------------------
	-- The hips drop from the crouch you are already in by this many EXTRA studs at the bottom
	-- of the dip (relative, so it shows even from a deep stance), then drive up into the jump.
	-- When the ball is lowest (Motion.DIP_LOWEST_POINT) is shared with the ball's timing.
	SHOT_DIP_EXTRA = 0.18, -- jump shots (scaled by the shot type's DIP_DEPTH_SCALE)
	LAYUP_PLANT_EXTRA = 0.12, -- the layup's left-foot plant compresses a little
	DUNK_DIP_EXTRA = 0.4, -- a standing dunk loads up deep
	DIP_MAX_CROUCH = 0.85, -- the most the hips are ever lowered in total, studs
	-- Degrees the trunk hinges forward at the bottom of the dip (the chest goes forward as the
	-- knees bend, instead of straightening): jump shot, standing dunk, layup plant.
	DIP_HINGE = 12,
	DUNK_DIP_HINGE = 30,
	LAYUP_DIP_HINGE = 6,

	-- GATHERS (the 1-2 landing inside the dip) -----------------------------------------------
	-- Where the feet go while the body slides during the dip. Total step length is capped so
	-- a shot never carries more than about one step.
	DIP_MAX_STEP = 2, -- studs a foot may travel in the dip
	DIP_MIN_SLIDE = 0.25, -- a plain gather only steps the feet if the body slides at least this far in the dip
	DIP_STEP_LIFT = 0.15, -- studs a foot rises when it steps in the dip
	DIP_FEET_LAND_AT = 0.45, -- plain gather: both feet are down by this share of the dip
	-- Pull-up (brake 1-2 off the run): the inside foot (opposite the ball hand) plants ahead of
	-- the hips, heel first, at once; the other foot steps in level at PULLUP_SECOND_FOOT_AT.
	PULLUP_BRAKE_AHEAD = 0.9, -- studs ahead of the hips the braking foot plants
	PULLUP_BRAKE_LAND_AT = 0.25, -- share of the dip when the braking foot touches down
	PULLUP_SECOND_FOOT_AT = 0.45, -- share of the dip when the second foot lands
	PULLUP_BRAKE_TOE_UP = 20, -- degrees the braking foot's toe is up when it lands (heel first)
	-- Step-back and side-step shots: the body hops back (or sideways) in the dip; the first
	-- foot lands at ..._FIRST_AT of the dip (back foot / lead foot), the second at ..._SECOND_AT.
	STEPBACK_SHOT_FIRST_AT = 0.35,
	STEPBACK_SHOT_SECOND_AT = 0.7,
	BALL_OF_FOOT_PITCH = 15, -- degrees the heel is raised in these landings (on the balls of the feet)
	SIDESTEP_LEAD_AHEAD = 0.3, -- the lead foot of a side-step lands this far beyond where the hips end up

	-- APPROACH (running gather steps before a layup or running dunk) ---------------------------
	-- The last two contacts before the dip: a long RIGHT gather step (the hips drop a little),
	-- then the shorter LEFT plant, which lands exactly as the dip starts. Before that the legs
	-- keep the run animation.
	GATHER_STEP_LENGTH = 1.9, -- studs between the foot before the gather and the right gather foot
	PLANT_STEP_SHARE = 0.85, -- the left plant step is this share of the gather step
	GATHER_HIP_DROP = 0.12, -- studs the hips drop at the right gather step
	GATHER_AHEAD = 0.55, -- the right gather foot lands this far ahead of the hips
	PLANT_AHEAD = 0.4, -- the left plant foot lands this far ahead of the hips (heel first)
	APPROACH_STEP_MIN_TIME = 0.1, -- the gather and plant steps take at least this many seconds...
	APPROACH_STEP_MAX_TIME = 0.2, -- ...and at most this many
	APPROACH_STEP_LIFT = 0.3, -- studs a gather step rises
	APPROACH_PLANT_TOE_UP = 15, -- degrees the left plant lands heel first

	-- AIR LEGS -----------------------------------------------------------------------------
	-- Shots: the legs hang down with the knees slightly bent and the toes pointed, under or a
	-- little ahead of the hips (and well ahead on a fadeaway, as a counterweight).
	AIR_KNEE_BEND = 0.12, -- the ankle is this many studs short of a straight leg
	AIR_TOE_POINT = 25, -- degrees the toes point down in the air
	AIR_FEET_FORWARD = 0.15, -- studs ahead of the hips
	FADE_FEET_FORWARD = 0.35, -- extra studs ahead when the body is drifting backward (fadeaway)
	FADE_BACK_SPEED = 2, -- studs/s backward at takeoff that counts as a fadeaway
	AIR_FEET_SPREAD = 0.1, -- studs each foot hangs further out than its hip joint
	-- Layup / running dunk: the right knee drives up (offsets from the middle of the hips in
	-- the body's frame: right, up, forward) while the left leg that you jumped off trails
	-- behind, slightly bent.
	LAYUP_KNEE_DRIVE_ANKLE = Vector3.new(0.5, -1.8, 0.8), -- right ankle with the knee up
	LAYUP_KNEE_DRIVE_POLE = Vector3.new(0.5, -0.5, 3), -- right knee points forward and up
	LAYUP_KNEE_DRIVE_TIME = 0.15, -- seconds for the knee to come up after takeoff
	LAYUP_DRIVE_START = 0.35, -- share of the dip at which the right leg starts swinging forward
	AIR_KNEE_POLE = Vector3.new(0, -1.5, 3), -- knees point forward (right, up, forward from the hips)
	LAYUP_TRAIL_ANKLE = Vector3.new(-0.5, -2.35, -0.5), -- left ankle, trailing behind
	-- Running dunk, after the top of the jump: the knees tuck up (ankles behind and under the
	-- hips, knees about 90 degrees) for the slam. A one-foot jump counts as a dunk when it
	-- takes off faster than DUNK_TUCK_MIN_POWER (studs/s upward; layups are well below).
	DUNK_KNEE_TUCK_ANKLE = Vector3.new(0.35, -1.95, -0.6),
	DUNK_KNEE_TUCK_POLE = Vector3.new(0.35, -0.7, 3),
	DUNK_KNEE_TUCK_TIME = 0.2, -- seconds from the top of the jump to the full tuck
	DUNK_TUCK_MIN_POWER = 19,

	-- LANDING --------------------------------------------------------------------------------

	LAND_PREPARE_TIME = 0.1, -- seconds before touchdown the legs start reaching for the floor
	LAND_FOOT_BLEND = 0.06, -- seconds the feet take to settle onto the floor after touchdown
	LAND_ABSORB = 0.3, -- studs of extra crouch right after a full-strength landing
	LAND_RECOVER_TIME = 0.25, -- seconds to stand back up from that
	-- Fall speed (studs/s) of a hardest landing (strength 1); landing strength is the fall
	-- speed over this, kept between LAND_MIN_STRENGTH and 1. About 0.4 for a jump shot,
	-- 0.7 for a dunk.
	LAND_FALL_SPEED_REF = 35,
	LAND_MIN_STRENGTH = 0.25,

	-- MOVE FOOTWORK -----------------------------------------------------------------------
	-- Where the feet go in each dribble move (src/client/Controllers/SkillController.luau).
	-- A step's spot is relative to where the hips will be: OUT = studs further out to that
	-- foot's side than the normal stance, FORWARD = studs in front of the hips. Every move
	-- still moves the body only one step (Config/Skills.luau, FOOTWORK). Times that must line
	-- up with the ball or the body are read from Config/Skills.luau, not set here.

	-- The body keeps moving a little after each move's foot lands (and comes to a stop
	-- after the step), so move steps land this many seconds of travel further along.
	MOVE_LAND_AHEAD = 0.12,

	-- Wide crossover (Iverson): SELL – plant and jab the ball-side foot diagonally out (about
	-- 35 degrees off straight ahead), crouching low like a sprinter, with a head fake;
	-- EXPLODE – push off that foot, the new-side foot steps out the new way and the push foot
	-- follows (a quick bound).
	CROSS_JAB_OUT = 0.3,
	CROSS_JAB_FORWARD = 0.45,
	CROSS_JAB_TIME = 0.12, -- seconds for the jab
	CROSS_CROUCH = 0.3, -- extra studs lower during the move
	CROSS_LEAD_TIME = 0.2, -- seconds for the new-side foot's step
	CROSS_TRAIL_DELAY = 0.09, -- seconds after that before the push foot follows
	CROSS_TRAIL_TIME = 0.18,
	-- Head fake: the head turns this many degrees toward the jab as the move starts, snaps
	-- CROSS_HEAD_SNAP degrees the other way shortly before the ball is pounded across, and
	-- comes back to the front once the cross is done.
	CROSS_HEAD_FAKE = 20,
	CROSS_HEAD_FAKE_TIME = 0.1, -- seconds to turn to the fake
	CROSS_HEAD_SNAP = 10,
	CROSS_HEAD_SNAP_TIME = 0.06, -- seconds for the snap (it also starts this long before the cross)

	-- Stab: the ball-side foot stabs out-forward (30-45 degrees off straight) to that side
	-- with the hard dribble, landing as the ball bounces (the step takes Skills.STAB_PUSH_TIME);
	-- the other foot only recovers to the stance (push, pull, recover, feet never crossing).
	STAB_OUT = 0.2,
	STAB_FORWARD = 0.25,
	STAB_TRAIL_DELAY = 0.1,
	STAB_TRAIL_TIME = 0.16,
	STAB_CROUCH = 0.15,

	-- Step-back (Harden style): plant the front (off) foot hard, then push back off it and
	-- land on both feet, back foot first ("1-2"), with a low flat hop between.
	STEPBACK_PLANT_FORWARD = 0.4, -- how far forward the front foot plants
	STEPBACK_PLANT_FOOT_TIME = 0.1, -- seconds the front foot takes to plant (longer than a snap)
	STEPBACK_BACK_FOOT_TIME = 0.26, -- seconds for the back foot's step
	STEPBACK_FRONT_FOOT_DELAY = 0.1, -- front foot leaves this long after the back foot
	STEPBACK_FRONT_FOOT_TIME = 0.24,
	STEPBACK_LIFT = 0.3,
	STEPBACK_CROUCH = 0.15,
	STEPBACK_HOP_RISE = 0.08, -- studs the hips come up while both feet are off the floor (a flat hop)
	STEPBACK_LAND_STRENGTH = 0.3, -- landing absorption (0-1) when the back foot comes down

	-- Spin (reverse pivot): the body turns around the ball of the front (pivot) foot, which
	-- stays planted and twists on the spot; the other leg swings round low and lands before
	-- the pivot foot comes off the floor; then the pivot foot steps through to finish the
	-- stance. Times are shares of the turn (Skills.SPIN_TIME): 0 = start, 1 = end.
	SPIN_CROUCH = 0.3,
	SPIN_SWING_LANDS_AT = 0.55, -- when the swinging foot lands
	SPIN_PIVOT_LIFTS_AT = 0.65, -- when the pivot foot comes off the floor
	SPIN_PIVOT_LANDS_AT = 0.95,
	-- How far (studs) the hips travel in all, toward the pivot side: the weight moves over the
	-- pivot foot and carries on past it. A real spin travels, but never more than one step.
	SPIN_TRAVEL = 1.2,
	-- How early the weight shifts over the pivot foot: 1 = evenly through the turn, higher =
	-- mostly at the start, so the body turns tightly about the pivot foot.
	SPIN_SHIFT_SHARPNESS = 2.2,
	SPIN_SWING_BULGE = 0.8, -- studs the swinging foot sweeps out behind the body, turning with it
	SPIN_SWING_FORWARD = 0.5, -- the swinging foot lands this far in front of its final stance spot
	SPIN_LIFT = 0.2, -- studs the swinging foot rises (low, knee bent)
	SPIN_HEAD_LEAD = 35, -- degrees the head turns toward the spin before the body follows
}

return Footwork
