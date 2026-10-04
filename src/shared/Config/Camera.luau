--!strict
-- Fixed, rim-focused camera. The camera sits behind the player on the court's long axis
-- and looks at a point between the player and the rim; it never takes rotation input.

local Camera = {
	FIELD_OF_VIEW = 60,
	HEIGHT = 10, -- studs above the floor
	DISTANCE = 15, -- studs behind the player (away from the rim)
	MIN_PLAYER_Z = 3, -- stops the camera sliding under the backboard when the player is behind the rim
	LATERAL_FOLLOW = 0.55, -- 0 = camera stays centered on the rim, 1 = fully follows the player sideways
	LOOK_BLEND = 0.4, -- 0 = look at the player, 1 = look at the rim
	FOLLOW_SHARPNESS = 8, -- higher = camera catches up faster
}

return Camera
