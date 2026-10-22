--!strict
-- POSTURE SETTINGS
-- The upper body (src/client/Controllers/PostureController.luau): how a lean is shared out
-- along the spine, how the neck keeps the eyes level, how the head looks at the rim, and
-- the small extra motions layered on top (dip hinge, landing, head turn, dribble twist).
-- Units: degrees, seconds, 0-1 shares, or "sharpness" (higher = snappier; 10 reaches ~63%
-- of the way in 0.1 s). Live-tunable under ReplicatedStorage > Tuning > Posture.
--
-- The model: every forward/back/side lean is split between the PELVIS (the Root joint, the
-- hips) and the CHEST (the Waist joint). The NECK then rotates the other way to cancel part
-- of the trunk's tilt, so the eyes stay near level instead of staring at the floor.
-- Research (docs/MOVEMENT_REFERENCES.md): a dribbler hinges 20-35 deg at the hips with a
-- straight back while the neck extends 15-30 deg to keep the gaze level.

local Posture = {
	-- SPINE -------------------------------------------------------------------------------

	-- Share (0-1) of every forward/back lean that happens at the hips (pelvis) and at the
	-- chest (waist). They should add up to 1 so the trunk ends up at the full lean angle.
	PELVIS_LEAN_SHARE = 0.45,
	CHEST_LEAN_SHARE = 0.55,
	-- The same split for the sideways lean (a bit more of it lives in the chest).
	PELVIS_SIDE_SHARE = 0.35,
	CHEST_SIDE_SHARE = 0.65,
	-- While shooting, this share (0-1) of the chest's sideways lean is taken away again, so
	-- the shoulders stay roughly level at the release (research: side shot trunk 0-5 deg).
	SHOT_SHOULDER_LEVEL = 0.4,
	SHOT_LEVEL_SHARPNESS = 10, -- how fast that levelling blends in/out when a shot starts/ends

	-- NECK (level gaze) -------------------------------------------------------------------

	-- Share (0-1) of the trunk's forward/back tilt that the neck undoes.
	NECK_PITCH_COUNTER = 0.65,
	-- Share (0-1) of the trunk's sideways tilt that the neck undoes.
	NECK_ROLL_COUNTER = 0.6,
	-- Share (0-1) of the dribble twist (the chest's yaw) that the neck undoes, so the head
	-- keeps facing forward while the shoulders swing.
	NECK_YAW_COUNTER = 0.6,
	-- The neck never tilts more than this many degrees (pitch or roll).
	NECK_MAX_DEGREES = 35,

	-- HEAD LOOK (the rim-facing head IK during a shot) ---------------------------------------

	HEAD_LOOK_SHARPNESS = 8, -- how fast the head turns toward the rim when a shot starts
	HEAD_DROP_SHARPNESS = 6, -- how fast it lets go mid-shot (the dunk slam): a gentle ease down
	-- When the rim is steeper than this many degrees above the head (close shots, dunks),
	-- the look weight is turned down so the neck isn't cranked back...
	HEAD_MAX_LOOK_PITCH = 40, -- degrees of elevation to the rim
	-- ...reaching zero this many degrees further up.
	HEAD_PITCH_FALLOFF = 30, -- degrees

	-- HEAD TURN (setHeadTurn: spin lead, crossover head fake) --------------------------------

	HEAD_TURN_MAX = 60, -- the most the head may turn away from the chest, degrees

	-- LEAN DYNAMICS -----------------------------------------------------------------------

	-- The dribbling-stance lean follows its goal like a critically damped spring (it never
	-- jumps and keeps its speed when the goal changes). This is the spring's frequency in
	-- cycles per second: 6 settles in about 0.1 s.
	STANCE_SPRING_FREQUENCY = 6,
	-- The extra forward hinge in the shot's dip (setDipHinge) eases toward its goal this fast.
	DIP_HINGE_SHARPNESS = 25,

	-- LANDING (absorbLanding) -------------------------------------------------------------

	LANDING_HINGE = 12, -- degrees the trunk dips forward at full strength (1)
	LANDING_RECOVER_TIME = 0.3, -- seconds from touchdown until the trunk is back up
	LANDING_DIP_SHARE = 0.25, -- share (0-1) of that time spent dipping (quick) before recovering (smooth)

	-- DRIBBLE TWIST (setDribbleTwist) ---------------------------------------------------------

	TWIST_SHARPNESS = 14, -- how fast the chest follows the requested twist
	TWIST_MAX_YAW = 25, -- the chest never turns more than this many degrees (research: +-15-25 running)
	TWIST_MAX_ROLL = 8, -- ...or rolls more than this many degrees (ball-side shoulder drop)
}

return Posture
