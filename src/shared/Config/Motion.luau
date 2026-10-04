--!strict
-- SHOOTING MOTION SETTINGS
-- How the shots look. Each shot type picks a motion (Shooting.Types[...].MOTION):
--
-- JUMP SHOT (jump shot, pull-up, fadeaway, step-back, side shot, close shot):
--   1. DIP     – knees bend, the ball comes into both hands at the chest
--   2. RISE    – legs drive up into the jump, the ball rises past the face
--   3. RELEASE – at the top, the ball is above the head on a fully extended shooting arm
--   4. FOLLOW-THROUGH – both arms reach toward the rim, hold, then fall forward
--   A FADEAWAY is the same motion with the whole body tilted back (Shooting.Types
--   .Fadeaway.LEAN, ~20°): ball, arms and legs all tilt with it, so the release ends up
--   above and slightly behind the head while the eyes stay on the rim.
--
-- LAYUP (right-handed, see the LAYUP section below):
--   1. GATHER  – a short dip; both hands bring the ball to the right side of the chest
--   2. TAKEOFF – jump off the left foot while the right knee drives up
--   3. RISE    – the ball is carried up the right side; the left hand comes off the ball
--                and stays up in front as a shield
--   4. RELEASE – high and in front, on a fully extended right arm, palm behind the ball
--   5. FOLLOW-THROUGH – the right arm stays up with the wrist flicked, then falls
--
-- Used by BallController (ball path), ArmController (hands), LegController (knees and legs),
-- PostureController (body lean) and ShotController (turning and jump timing).
--
-- Positions are written as Vector3.new(right, up, forward), measured from the player's
-- hips (the HumanoidRootPart) and turning (and leaning) with the player. So
-- (0.35, 2.75, 0.7) means 0.35 studs to the right, 2.75 up and 0.7 in front of the hips.
-- Live-tunable under ReplicatedStorage > Tuning > Motion while playing in Studio.

local Motion = {
	-- BALL PATH (dribble → dip → release) ------------------------------------------------
	-- The ball reaches RELEASE_POINT exactly at the perfect release moment, so the top of
	-- the motion lines up with the green zone.

	-- Where the ball sits at the bottom of the dip: both hands, at the chest. It arrives
	-- when the hips are lowest (see DIP_LOWEST_POINT), then rises with the jump.
	DIP_POCKET = Vector3.new(0.3, 0.45, 1.2),
	-- On the way up, the ball's path bends toward this point, keeping it in front of the
	-- face instead of passing through the head.
	RISE_BEND = Vector3.new(0.35, 2.4, 1.6),
	-- Where the ball is at the perfect release: above the head on an extended arm.
	RELEASE_POINT = Vector3.new(0.35, 2.75, 0.7),

	-- HANDS ON THE BALL (arm IK) --------------------------------------------------------
	-- The arms bend so each PALM sits on the ball, facing the ball's centre, with the
	-- fingers pointing a chosen way (Roblox IKControl, see src/client/LimbIK.luau).
	-- A hand's spot on the ball is a direction from the ball's centre, (right, up, forward).

	-- The shooting hand slides from behind the ball (in the dip, fingers up) to under it
	-- (at the release, fingers toward the rim) as the ball rises.
	SHOOTING_HAND_LOW = Vector3.new(0.15, -0.3, -0.95), -- dip: behind the ball
	SHOOTING_FINGERS_LOW = Vector3.new(0, 1, 0), -- dip: fingers up
	SHOOTING_HAND_HIGH = Vector3.new(0.1, -0.95, -0.25), -- release: under the ball
	SHOOTING_FINGERS_HIGH = Vector3.new(0, 0.3, 1), -- release: fingers forward, toward the rim
	-- The guide (left) hand stays on the side of the ball, fingers up.
	GUIDE_HAND = Vector3.new(-1, 0.05, -0.1),
	GUIDE_FINGERS = Vector3.new(0, 1, 0.2),
	-- Gap between the palm and the ball's surface, studs (stops the hand sinking in).
	PALM_GAP = 0.06,

	-- Elbow aim points (from the hips). Each elbow bends toward its point, which keeps the
	-- arms in a natural shape instead of folding the wrong way.
	SHOOTING_ELBOW = Vector3.new(0.9, 0.6, 2), -- shooting elbow points forward, under the ball
	GUIDE_ELBOW = Vector3.new(-2, 0.8, 0.8), -- guide elbow points out to the left
	DRIBBLE_ELBOW = Vector3.new(2, 0.6, -1), -- dribbling elbow points out and back

	-- While dribbling, the right palm rides on top of the ball (facing down, fingers
	-- DRIBBLE_FINGERS) but never drops below DRIBBLE_PALM_MIN_HEIGHT above the floor, so it
	-- "waits" there while the ball goes down and comes back up.
	DRIBBLE_FINGERS = Vector3.new(0, -0.2, 1),
	DRIBBLE_PALM_MIN_HEIGHT = 2.1,

	-- FOLLOW-THROUGH: right after release both arms reach up and forward toward the rim
	-- (they straighten as far as they can). The shooting hand is in a "gooseneck": wrist
	-- flicked, palm facing down, fingers pointing at the rim. After a short hold the arms
	-- fall forward to the END positions, then relax back to normal animation.
	FOLLOW_THROUGH = Vector3.new(0.45, 2.3, 1.9), -- shooting palm at release (from the hips)
	FOLLOW_THROUGH_FACING = Vector3.new(0, -0.6, -0.8), -- which way that palm faces
	FOLLOW_THROUGH_FINGERS = Vector3.new(0, -0.8, 0.6), -- which way its fingers point
	GUIDE_FOLLOW_THROUGH = Vector3.new(-0.55, 2.1, 1.7), -- guide palm: up beside it, a bit lower
	GUIDE_FOLLOW_THROUGH_FACING = Vector3.new(1, 0, 0), -- guide palm faces the shooting hand
	-- Where the arms fall to: in front of the body, around chest height, hands relaxed.
	FOLLOW_THROUGH_END = Vector3.new(0.4, 0.9, 1.8), -- shooting palm
	GUIDE_FOLLOW_THROUGH_END = Vector3.new(-0.5, 0.7, 1.6), -- guide palm
	FOLLOW_THROUGH_END_FINGERS = Vector3.new(0, -0.5, 0.85), -- relaxed fingers, forward and down
	-- Total follow-through time (seconds), and the fraction of it spent holding the arms up
	-- before they start falling forward.
	FOLLOW_THROUGH_TIME = 0.9,
	FOLLOW_THROUGH_HOLD = 0.35,

	-- How smoothly the hands move. IK_SMOOTH_TIME is how long a hand takes to catch up
	-- with its target, in seconds (0 = instantly, rigid). IK_BLEND_SHARPNESS is how fast an
	-- arm takes hold of the ball (higher = faster); IK_RELAX_SHARPNESS is how fast it lets
	-- go back to the normal animation, e.g. arms settling down after the follow-through.
	IK_SMOOTH_TIME = 0.02,
	IK_BLEND_SHARPNESS = 12,
	IK_RELAX_SHARPNESS = 4,

	-- LEGS (leg IK) ---------------------------------------------------------------------

	-- How far the hips drop at the bottom of the dip, studs. The feet stay planted, so the
	-- knees bend. 0.4 is a solid athletic dip; 0.6+ is a deep squat.
	DIP_DEPTH = 0.4,
	-- When the hips are lowest, as a fraction of the dip (0 = at E press, 1 = at takeoff).
	-- After that the legs drive up into the jump. The ball reaches DIP_POCKET at this moment.
	DIP_LOWEST_POINT = 0.6,
	-- Knee aim point (from the hips): knees bend forward, over the toes.
	KNEE_POLE = Vector3.new(0, -1.5, 3),
	-- How fast the legs switch between IK and normal animation (higher = faster).
	LEG_BLEND_SHARPNESS = 20,

	-- BODY ------------------------------------------------------------------------------

	-- How strongly the head turns to look at the rim during a shot (0 = not at all,
	-- 1 = eyes locked on the rim). See PostureController.
	HEAD_LOOK_WEIGHT = 1,
	-- Body lean (how far is set per shot type: Shooting.Types[...].LEAN). The lean grows
	-- from takeoff to the perfect release, is held in the air, and after landing takes
	-- LEAN_RECOVER_TIME seconds to straighten back up.
	LEAN_RECOVER_TIME = 0.3,
	-- The shortest time the lean may take to build up, seconds (so it never snaps in).
	MIN_LEAN_TIME = 0.12,

	-- How fast the body turns to face the rim when a shot starts (higher = snappier).
	-- 18 turns most of the way in about 0.15 s.
	TURN_SHARPNESS = 18,
	-- How quickly your momentum changes into the shot's drift (studs/s²). Lower = you slide
	-- further into a pull-up; higher = you stop more abruptly.
	DRIFT_BLEND_RATE = 60,
	-- Time on the ground before the jump (the dip), seconds. The jump is timed so you peak
	-- at the perfect release, but the dip always lasts at least MIN_DIP_TIME (so it's
	-- visible) and at most MAX_DIP_TIME (so long shots don't feel sluggish).
	MIN_DIP_TIME = 0.16,
	MAX_DIP_TIME = 0.22,

	-- LAYUP -----------------------------------------------------------------------------
	-- A right-handed layup: jump off the left foot, right knee up, ball laid in with the
	-- right hand. Same coordinates as above (from the hips, turning and leaning with the
	-- player). Positions not listed here (follow-through END, elbows) are shared with the
	-- jump shot.

	-- How far the hips drop in the gather step, studs. Shallower than the jump shot's
	-- DIP_DEPTH: a layup is a stride into the jump, not a squat.
	LAYUP_DIP_DEPTH = 0.25,

	-- Ball path: into the pocket on the right side of the chest (protected, away from a
	-- defender), up the right side past the shoulder, to the release point high and in
	-- front on a fully extended right arm.
	LAYUP_POCKET = Vector3.new(0.55, 0.6, 1.0),
	LAYUP_RISE_BEND = Vector3.new(0.85, 1.8, 1.4),
	LAYUP_RELEASE_POINT = Vector3.new(0.8, 3.0, 1.1), -- ball sits ~1 stud above the palm

	-- Shooting (right) hand: a scoop. It starts behind and under the ball, and as the ball
	-- rises the hand slides directly UNDER it, palm up and fingers pointing forward toward
	-- the board, so the ball sits on the palm and rolls off the fingertips on release. Each
	-- "hand" value is the direction from the ball's centre to the palm (right, up, forward).
	LAYUP_HAND_LOW = Vector3.new(0.2, -0.7, -0.6), -- gather: under and a little behind the ball
	LAYUP_FINGERS_LOW = Vector3.new(0, 0.3, 1), -- gather: fingers forward, slightly up
	LAYUP_HAND_HIGH = Vector3.new(0, -1, 0.1), -- release: palm straight under the ball, palm up
	LAYUP_FINGERS_HIGH = Vector3.new(0, 0.35, 1), -- release: fingers forward and a little up

	-- Guide (left) hand: on the left side of the ball through the gather. Once the ball
	-- has risen LAYUP_GUIDE_LET_GO of the way (0 = pocket, 1 = release point) it comes
	-- off and moves up to LAYUP_GUIDE_SHIELD: forearm up in front, protecting the ball.
	LAYUP_GUIDE_HAND = Vector3.new(-0.9, 0.3, 0), -- spot on the ball (from its centre)
	LAYUP_GUIDE_LET_GO = 0.55,
	LAYUP_GUIDE_SHIELD = Vector3.new(-0.8, 0.9, 1.0), -- guide palm (from the hips)
	LAYUP_GUIDE_SHIELD_FACING = Vector3.new(-0.5, 0, 0.85), -- palm faces forward and out
	LAYUP_GUIDE_SHIELD_FINGERS = Vector3.new(0, 1, 0.2), -- fingers up

	-- Follow-through: the right arm stays reaching up toward the board with the wrist
	-- flicked forward (palm facing down and forward, fingers forward), then falls to the
	-- shared FOLLOW_THROUGH_END. The guide hand holds its shield and then falls too.
	LAYUP_FOLLOW_THROUGH = Vector3.new(0.8, 2.6, 1.4), -- shooting palm (out of reach = arm straight)
	LAYUP_FOLLOW_THROUGH_FACING = Vector3.new(0, -0.85, 0.5),
	LAYUP_FOLLOW_THROUGH_FINGERS = Vector3.new(0, 0.5, 0.85),

	-- Legs in the air: the right knee drives up (thigh near level, shin hanging down) while
	-- the left leg, the one you jumped off, stays straight and trails slightly behind.
	LAYUP_KNEE_DRIVE_ANKLE = Vector3.new(0.5, -1.8, 0.8), -- right ankle with the knee up
	LAYUP_KNEE_DRIVE_POLE = Vector3.new(0.5, -0.5, 3), -- right knee points forward and up
	LAYUP_TAKEOFF_ANKLE = Vector3.new(-0.5, -6, -1.2), -- left ankle (out of reach = leg straight)
	-- Seconds for the right knee to come up after takeoff.
	LAYUP_KNEE_DRIVE_TIME = 0.15,
}

return Motion
