--!strict
-- MOVEMENT SETTINGS
-- How fast the player moves and how quickly they speed up, slow down and change
-- direction. Used by src/client/Controllers/MovementController.luau.
--
-- Units: speeds in studs per second, rates in studs per second per second (how much speed
-- is gained or lost each second). Live-tunable under ReplicatedStorage > Tuning > Movement.

local Movement = {
	-- TOP SPEEDS ------------------------------------------------------------------------

	WALK_SPEED = 13, -- top speed with no Shift held
	RUN_SPEED = 21, -- top speed while holding Shift

	-- The body always faces the rim, so moving sideways is a shuffle and moving back is a
	-- backpedal. Like a real player, you're slower that way than running at the basket.
	-- Share of the top speed: 1 = as fast as forward. Diagonals blend between.
	SIDE_SPEED_SCALE = 0.8, -- straight sideways (a defensive-style shuffle)
	BACK_SPEED_SCALE = 0.65, -- straight back (a backpedal)

	-- RESPONSIVENESS --------------------------------------------------------------------
	-- Bigger numbers = snappier. E.g. ACCELERATION 70 means walking speed (13) is reached in
	-- 13 / 70 ≈ 0.19 seconds.

	ACCELERATION = 70, -- used when speeding up (starting to move, walk → run)
	DECELERATION = 110, -- used when slowing down (letting go of keys, run → walk)
	TURN_ACCELERATION = 160, -- used when pressing the opposite direction (e.g. D → A)

	-- Below this speed the player is treated as standing still (avoids tiny drifting).
	STOP_EPSILON = 0.05,

	-- FACING ----------------------------------------------------------------------------
	-- The body always faces the rim (moving sideways or backward is a shuffle/backpedal,
	-- not a turn). How quickly it turns to keep facing it: higher = snappier, lower = lazier.
	FACE_RIM_SHARPNESS = 14,
}

return Movement
