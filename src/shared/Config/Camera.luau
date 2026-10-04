--!strict
-- CAMERA SETTINGS
-- The camera is fixed and rim-focused: it sits behind the player (on the side away from
-- the rim), looks at a point between the player and the rim, and never takes rotation
-- input. Used by src/client/Controllers/CameraController.luau.
--
-- Units: studs. Live-tunable in Studio under ReplicatedStorage > Tuning > Camera.

local Camera = {
	-- How wide the camera sees, in degrees. Higher = more zoomed out / more distortion.
	FIELD_OF_VIEW = 60,

	-- Camera height above the floor, studs. Higher = more top-down view.
	HEIGHT = 10,

	-- How far behind the player the camera sits, studs. Higher = player looks smaller.
	DISTANCE = 15,

	-- If the player walks behind the rim, the camera pretends they're at least this far in
	-- front of it, so the camera never slides under the backboard.
	MIN_PLAYER_Z = 3,

	-- How much the camera slides sideways with the player.
	-- 0 = camera stays centred on the rim, 1 = camera stays directly behind the player.
	LATERAL_FOLLOW = 0.55,

	-- Where the camera points, between the player and the rim.
	-- 0 = looks straight at the player, 1 = looks straight at the rim.
	LOOK_BLEND = 0.4,

	-- How quickly the camera catches up with the player. Higher = snappier, lower = floatier.
	FOLLOW_SHARPNESS = 8,
}

return Camera
