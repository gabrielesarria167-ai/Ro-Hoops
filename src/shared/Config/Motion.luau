--!strict
-- SHOOTING MOTION SETTINGS
-- How the shot looks: the path the ball takes from the dribble up to the release, where
-- the hands sit on the ball, how the body turns and jumps, and the follow-through.
-- Used by BallController (ball path), ArmController (hands) and ShotController (body).
--
-- Positions are written as Vector3.new(right, up, forward), measured from the player's
-- hips (the HumanoidRootPart) and turning with the player. So (0.3, 2.45, 0.75) means
-- 0.3 studs to the right, 2.45 up and 0.75 in front of the hips.
-- Live-tunable under ReplicatedStorage > Tuning > Motion while playing in Studio.

local Motion = {
	-- BALL PATH (dribble → release) -----------------------------------------------------
	-- When E is pressed the ball curves from wherever it is in the dribble, past the chest,
	-- up to the set point above the forehead. It arrives at the set point exactly at the
	-- perfect release moment, so the top of the motion lines up with the green zone.

	-- The curve bends toward this point on the way up (around the chest).
	GATHER_POCKET = Vector3.new(0.35, 0.9, 1.15),
	-- Where the ball is at the perfect release: in front of the forehead. (Roblox arms are
	-- short next to the big head, so the ball can't go much higher and stay in both hands.)
	SET_POINT = Vector3.new(0.3, 1.85, 1.35),

	-- HANDS ON THE BALL (arm IK) --------------------------------------------------------
	-- The arms are bent automatically so the wrists reach target points (Roblox IKControl
	-- moves the wrist; the hand itself keeps its animated angle). Each hand's target is in
	-- a direction from the ball's centre, (right, up, forward), at the ball's radius plus a
	-- gap that leaves room for the hand between the wrist and the ball.

	SHOOTING_HAND = Vector3.new(0.25, -0.8, -0.55), -- right hand: under and slightly behind the ball
	SHOOTING_WRIST_GAP = 0.2, -- studs between the ball's surface and the right wrist
	GUIDE_HAND = Vector3.new(-0.85, 0, -0.5), -- left hand: on the side, toward the back
	GUIDE_WRIST_GAP = 0.25, -- studs between the ball's surface and the left wrist

	-- Elbow aim points (from the hips). Each elbow bends toward its point, which keeps the
	-- arms in a natural shape instead of folding the wrong way.
	SHOOTING_ELBOW = Vector3.new(0.9, 0.6, 2), -- shooting elbow points forward, under the ball
	GUIDE_ELBOW = Vector3.new(-2, 0.8, 0.8), -- guide elbow points out to the left
	DRIBBLE_ELBOW = Vector3.new(2, 0.6, -1), -- dribbling elbow points out and back

	-- While dribbling, the right hand rides on top of the ball but its wrist never drops
	-- below this height above the floor (studs), so it "waits" while the ball goes down.
	DRIBBLE_WRIST_MIN_HEIGHT = 2.4,
	-- Height of the dribbling wrist above the top of the ball (the hand is in between), studs.
	DRIBBLE_WRIST_GAP = 0.35,

	-- After release the shooting wrist reaches up and toward the rim (the follow-through;
	-- the arm straightens as far as it can) and holds for FOLLOW_THROUGH_TIME seconds.
	FOLLOW_THROUGH = Vector3.new(0.45, 2.3, 1.2),
	FOLLOW_THROUGH_TIME = 0.6,

	-- How smoothly the hands move. IK_SMOOTH_TIME is how long a hand takes to catch up
	-- with its target, in seconds (0 = instantly, rigid). IK_BLEND_SHARPNESS is how fast
	-- an arm switches between "following the ball" and "normal animation" (higher = faster).
	IK_SMOOTH_TIME = 0.02,
	IK_BLEND_SHARPNESS = 12,

	-- BODY ------------------------------------------------------------------------------

	-- How fast the body turns to face the rim when a shot starts (higher = snappier).
	-- 18 turns most of the way in about 0.15 s.
	TURN_SHARPNESS = 18,
	-- How quickly your momentum changes into the shot's drift (studs/s²). Lower = you slide
	-- further into a pull-up; higher = you stop more abruptly.
	DRIFT_BLEND_RATE = 60,
	-- The jump is delayed so you reach the top of it at the perfect release moment, but
	-- never by more than this many seconds (keeps long shots from feeling sluggish).
	MAX_JUMP_DELAY = 0.15,
}

return Motion
