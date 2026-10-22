--!strict
-- SHOOTING MOTION SETTINGS
-- How the shots look. Each shot type picks a motion (Shooting.Types[...].MOTION):
--
-- JUMP SHOT (jump shot, pull-up, fadeaway, side shot, close shot):
--   1. DIP     – knees bend, the ball comes into both hands at the belt (the POCKET)
--   2. SET     – arms and legs rise TOGETHER: the ball is already at the forehead (the SET
--                POINT) at takeoff (research: Podmenik 2021 - wrist 103-109% of body height)
--   3. RELEASE – the ball keeps moving up and forward to the release point, above the head
--                on a nearly extended shooting arm (elbow 135-160 degrees), and leaves the
--                hand while still moving
--   4. FOLLOW-THROUGH – the arm stays up with the wrist flexed ~40 degrees (a "gooseneck")
--                for ~0.6 s, then falls forward
--   A FADEAWAY is the same motion with the body tilted back (Shooting.Types
--   .Fadeaway.LEAN): ball and arms tilt with the hips (the chest tilts more, the head
--   less), so the release ends up above and slightly behind the head while the eyes stay
--   on the rim.
--
-- LAYUP (right-handed, see the LAYUP section below):
--   1. GATHER  – a short dip; both hands bring the ball to the right hip
--   2. TAKEOFF – jump off the left foot while the right knee drives up
--   3. RISE    – the ball is carried up the right side (never across the belly) to the
--                shoulder; the left hand peels off at head height into a bent arm bar
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
	-- BALL PATH (dribble → dip → set → release) ----------------------------------------
	-- The ball is at DIP_POCKET when the hips are lowest, at SET_POINT at takeoff (see
	-- BallController.hold's `toSet`), and at RELEASE_POINT at the perfect release moment, so
	-- the top of the motion lines up with the green zone. A smooth curve joins them, and the
	-- ball is still moving at the release (RELEASE_END_...), so launching it looks seamless.

	-- Where the ball sits at the bottom of the dip: both hands, at the belt.
	DIP_POCKET = Vector3.new(0.3, 0.3, 1.1),
	-- Where the ball is at takeoff: in front of the forehead, a little to the shooting side
	-- (the ball is wide, so it has to be ~1 stud in front of the face to clear it).
	SET_POINT = Vector3.new(0.4, 2.15, 1.15),
	-- Used when ShotController doesn't say when takeoff is: the set point is reached this
	-- share of the way from the pocket to the release (0-1).
	SET_TIME_SHARE = 0.55,
	-- Where the ball is at the perfect release: above the head, in front of the shooting
	-- shoulder, with the palm ~2.05 studs from the shoulder (elbow ~150°, not locked).
	RELEASE_POINT = Vector3.new(0.48, 3.46, 0.92),
	-- How fast (studs/s) and which way (right, up, forward) the ball is moving as it reaches
	-- the release point: up and forward, like the launch, so it never stops dead there.
	RELEASE_END_SPEED = 7,
	RELEASE_END_DIRECTION = Vector3.new(0, 1, 0.7),

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

	-- While dribbling, the palm meets the ball on its way up, rides it, pushes it down
	-- (facing down, fingers DRIBBLE_FINGERS) and then hovers where it will meet the ball
	-- again, so it never pumps up and down (BallController says when each happens).
	DRIBBLE_FINGERS = Vector3.new(0, -0.2, 1),
	-- At the push the wrist snaps this many degrees (fingers pitch down); research 10-20.
	DRIBBLE_WRIST_FLEX = 15,
	-- The arm can't stretch past straight: a hand target further than DRIBBLE_SOFT_REACH from
	-- the shoulder is squeezed toward DRIBBLE_MAX_REACH (studs) instead of being hit hard.
	DRIBBLE_SOFT_REACH = 2.1,
	DRIBBLE_MAX_REACH = 2.45,
	-- Upper-body twist while dribbling (PostureController.setDribbleTwist): when running,
	-- the shoulders turn this many degrees in time with the dribbling arm (research 15-25);
	-- when standing the ball-side shoulder drops this many degrees at the push (3-5).
	DRIBBLE_TWIST_YAW = 17,
	DRIBBLE_TWIST_ROLL = 4,

	-- ARM BAR: while dribbling, the free hand comes up to protect the ball, like a real
	-- ball handler: upper arm ~45° forward and out, elbow bent ~90°, forearm across the
	-- front at waist-to-chest height. (out, up, forward) from the hips, where "out" is
	-- toward the free hand's own side (mirrored automatically for either hand).
	ARM_BAR_PALM = Vector3.new(0.8, 0.1, 1.25), -- where the palm is (waist-chest height, ~1.25 in front)
	ARM_BAR_FACING = Vector3.new(0.3, 0, 1), -- palm faces forward and a little out
	ARM_BAR_FINGERS = Vector3.new(0, 1, 0.3), -- fingers up
	ARM_BAR_ELBOW = Vector3.new(2.2, -0.1, 0.5), -- elbow points out and a little forward
	-- The arm bar is alive: it sways gently (a "breathing" movement) and bobs with the
	-- dribble, so it never looks frozen. Studs and Hz.
	ARM_BAR_SWAY = 0.05, -- studs the palm drifts up and down
	ARM_BAR_SWAY_RATE = 0.8, -- sway cycles per second
	ARM_BAR_BOB = 0.1, -- studs the palm drops with each push of the dribble
	-- RUNNING: above RUN_ARM_SPEED_START (studs/s) the free arm starts to swing opposite the
	-- legs like in a normal run, fully at RUN_ARM_SPEED_FULL. Palm spots (out, up, forward)
	-- from the hips for the forward and back ends of the swing, and the elbow aim point.
	RUN_ARM_SPEED_START = 7,
	RUN_ARM_SPEED_FULL = 13,
	RUN_ARM_FORWARD = Vector3.new(0.9, 0.35, 1.15),
	RUN_ARM_BACK = Vector3.new(1.1, -0.1, -0.5),
	RUN_ARM_ELBOW = Vector3.new(2.4, 0.2, -0.8),
	RUN_ARM_FACING = Vector3.new(-0.8, 0, 0.3), -- palm faces in toward the body
	RUN_ARM_FINGERS = Vector3.new(0, 0.2, 1),
	-- Seconds per step used for the swing when no foot-plant information is available.
	RUN_ARM_FALLBACK_STEP = 0.3,

	-- FOLLOW-THROUGH: right after release the shooting arm stays up and reaches toward the
	-- rim with the wrist flexed ~40-45° (a "gooseneck": fingers point forward, not 90° down;
	-- research: Podmenik 2021). The guide hand comes off sideways. After the hold the arms
	-- fall forward to the END positions, then relax back to normal animation.
	FOLLOW_THROUGH = Vector3.new(0.55, 2.9, 1.3), -- shooting palm after release (from the hips)
	FOLLOW_THROUGH_FACING = Vector3.new(0, -0.97, 0.25), -- which way that palm faces (down)
	FOLLOW_THROUGH_FINGERS = Vector3.new(0, 0.15, 1), -- which way its fingers point (forward, ~8° up)
	GUIDE_FOLLOW_THROUGH = Vector3.new(-1.25, 2.0, 0.9), -- guide palm: out to the side, peeled off
	GUIDE_FOLLOW_THROUGH_FACING = Vector3.new(1, 0, 0), -- guide palm faces the shooting hand
	-- Where the arms fall to: in front of the body, around chest height, hands relaxed.
	FOLLOW_THROUGH_END = Vector3.new(0.4, 0.9, 1.8), -- shooting palm
	GUIDE_FOLLOW_THROUGH_END = Vector3.new(-0.5, 0.7, 1.6), -- guide palm
	FOLLOW_THROUGH_END_FINGERS = Vector3.new(0, -0.5, 0.85), -- relaxed fingers, forward and down
	-- Total follow-through time (seconds), and the fraction of it spent holding the arms up
	-- before they start falling forward (0.6 of 1.0 s = the arm stays up ~0.6 s).
	FOLLOW_THROUGH_TIME = 1.0,
	FOLLOW_THROUGH_HOLD = 0.6,

	-- How smoothly the hands move. IK_SMOOTH_TIME is how long a hand takes to catch up
	-- with its target, in seconds (0 = instantly, rigid). IK_BLEND_SHARPNESS is how fast an
	-- arm takes hold of the ball (higher = faster); IK_RELAX_SHARPNESS is how fast it lets
	-- go back to the normal animation, e.g. arms settling down after the follow-through.
	IK_SMOOTH_TIME = 0.02,
	IK_BLEND_SHARPNESS = 12,
	IK_RELAX_SHARPNESS = 4,
	-- HAND SPRINGS (ArmController): whenever a hand is NOT on the ball, its target (position,
	-- facing, fingers) is smoothed by a critically damped spring, so it glides between poses
	-- (arm bar → catch spot, release → follow-through...) instead of popping. Higher = a
	-- stiffer spring (18 reaches half way in ~0.09 s).
	HAND_SPRING_FREQUENCY = 18, -- rad/s, the palm
	HAND_POLE_FREQUENCY = 12, -- rad/s, the elbow aim point (softer)
	-- When a hand takes hold of the ball it fades from the spring to being exactly on the
	-- ball over this many seconds (0 = instantly). Once on the ball it has no lag at all.
	HAND_CONTACT_BLEND = 0.06,
	-- If the hand has to travel far to take hold (e.g. the guide hand coming from the arm bar
	-- to the ball), the fade takes longer: gap / HAND_GRAB_SPEED seconds (studs/s).
	HAND_GRAB_SPEED = 12,

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

	-- Ball path: gathered at the right hip (protected, away from a defender), up the right
	-- side to the shoulder / ear at takeoff (never across the belly), then released
	-- 0.6-1.0 stud above the head in front of the right shoulder. Time share for the set
	-- point and the ball's speed at release: see SET_TIME_SHARE, RELEASE_END_SPEED.
	LAYUP_POCKET = Vector3.new(0.7, -0.3, 0.6),
	LAYUP_SET_POINT = Vector3.new(1.15, 1.7, 0.7),
	LAYUP_RELEASE_POINT = Vector3.new(1.0, 3.4, 1.0), -- ball sits ~1 stud above the palm
	LAYUP_END_DIRECTION = Vector3.new(0, 1, 0.5), -- (right, up, forward) the ball is moving at release

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
	LAYUP_GUIDE_SHIELD = Vector3.new(-0.9, 1.8, 0.9), -- guide palm (from the hips): head height, a bent arm bar
	LAYUP_GUIDE_SHIELD_FACING = Vector3.new(-0.5, 0, 0.85), -- palm faces forward and out
	LAYUP_GUIDE_SHIELD_FINGERS = Vector3.new(0, 1, 0.2), -- fingers up

	-- Follow-through: the right arm stays reaching up toward the board with the wrist
	-- flicked forward (palm facing down and forward, fingers forward), then falls to the
	-- shared FOLLOW_THROUGH_END. The guide hand holds its shield and then falls too.
	LAYUP_FOLLOW_THROUGH = Vector3.new(1.0, 2.8, 1.3), -- shooting palm (out of reach = arm straight)
	LAYUP_FOLLOW_THROUGH_FACING = Vector3.new(0, -0.85, 0.5),
	LAYUP_FOLLOW_THROUGH_FINGERS = Vector3.new(0, 0.5, 0.85),

	-- Legs in the air: the right knee drives up (thigh near level, shin hanging down) while
	-- the left leg, the one you jumped off, stays straight and trails slightly behind.
	LAYUP_KNEE_DRIVE_ANKLE = Vector3.new(0.5, -1.8, 0.8), -- right ankle with the knee up
	LAYUP_KNEE_DRIVE_POLE = Vector3.new(0.5, -0.5, 3), -- right knee points forward and up
	LAYUP_TAKEOFF_ANKLE = Vector3.new(-0.5, -6, -1.2), -- left ankle (out of reach = leg straight)
	-- Seconds for the right knee to come up after takeoff.
	LAYUP_KNEE_DRIVE_TIME = 0.15,

	-- DUNK ------------------------------------------------------------------------------
	-- A basic two-handed power dunk, like a big man's (Rudy Gobert, Nikola Jokic):
	--   1. GATHER  – running: the ball is gathered at the right hip with the plant; standing:
	--                it swings down toward the knees in the dip (an arm swing, with the legs'
	--                deep load);
	--   2. RISE    – both hands swing the ball up overhead at takeoff, cocked back a little;
	--   3. THROW   – at the top of the jump both arms swing it forward and out over the
	--                rim (DUNK_REACH), and the wrists snap it down through;
	--   4. RIM     – both hands come down on the front of the rim for a moment as the body
	--                drops, then let go and fall back down.
	-- Same coordinates as above (from the hips, turning and leaning with the player); hand
	-- spots are for the right hand and mirrored for the left. The jump is worked out so the
	-- ball is at DUNK_REACH, over the rim, at the top of the jump (ShotController).

	-- Ball path: the right hip (or, for a standing dunk, swung down to the knees) → up
	-- overhead at takeoff (DUNK_SET_POINT) → cocked behind the head near the top of the jump
	-- (DUNK_COCK) → out over the rim (DUNK_REACH). A running dunk starts the ball at the
	-- right hip (DUNK_RUN_POCKET) and swings it up with the plant; a standing dunk uses the
	-- arm swing (DUNK_LOW_SWING).
	DUNK_RUN_POCKET = Vector3.new(0.6, -0.3, 0.7), -- running dunk: gathered at the right hip, then swung up with the plant
	-- Standing dunk (BallController.hold's `lowSwing`): the ball swings DOWN toward the knees
	-- in the dip (a countermovement arm swing), then up fast. From the hips.
	DUNK_LOW_SWING = Vector3.new(0, -1.4, 0.9),
	DUNK_SET_POINT = Vector3.new(0, 2.6, 0.8), -- overhead at takeoff
	-- Peak of the cock: about head top + 0.6, a little behind the head.
	DUNK_COCK = Vector3.new(0, 3.1, -0.4),
	-- Share (0-1) of the way from takeoff to the slam at which the ball reaches DUNK_COCK.
	DUNK_COCK_AT = 0.7,
	DUNK_END_DIRECTION = Vector3.new(0, 0.1, 1), -- (right, up, forward) the ball is moving as the slam starts
	-- Where the ball is at the top of the jump, on fully extended arms: out in front over
	-- the rim. Reaching out (not straight up) keeps the body and head in front of the rim
	-- instead of jumping up into it: with the forward lean the hips stay ~2.6 studs from the
	-- rim's centre, outside the ring (its outer edge is ~1.4 studs out).
	DUNK_REACH = Vector3.new(0, 2.7, 2.1),

	-- Hands (right hand; the left mirrors it): palms on the SIDES of the ball in the
	-- chamber, sliding round BEHIND it (and a bit on top) as it goes up, ready to throw it
	-- forward and down. Each is the direction from the ball's centre to the palm.
	DUNK_HAND_LOW = Vector3.new(0.95, 0, -0.3),
	DUNK_FINGERS_LOW = Vector3.new(0, 1, 0.3), -- fingers up
	DUNK_HAND_HIGH = Vector3.new(0.6, 0.3, -0.75),
	DUNK_FINGERS_HIGH = Vector3.new(0, 0.8, 0.6), -- fingers up and forward
	-- Elbow aim point (from the hips, right elbow; mirrored): out to the side and forward,
	-- so the arms frame the ball like a two-handed overhead throw.
	DUNK_ELBOW = Vector3.new(1.6, 1.8, 1.2),

	-- Hands on the rim after the slam: both palms on top of the front of the rim, this
	-- many studs either side of its middle, held for DUNK_RIM_HOLD seconds (the arms
	-- straighten as the body drops below them), then they fall to FOLLOW_THROUGH_END.
	DUNK_RIM_GRIP_SPREAD = 0.55,
	-- Seconds for the hands to move from the ball onto the rim after the slam (0 = jump
	-- there in one frame).
	DUNK_RIM_REACH_TIME = 0.1,
	DUNK_RIM_HOLD = 0.25,
	-- How strongly the head looks at the rim on the way up (HEAD_LOOK_WEIGHT is 1). Right
	-- under the rim full strength cranks the neck straight up; after the slam it's 0.
	DUNK_HEAD_LOOK_WEIGHT = 0.4,
}

return Motion
