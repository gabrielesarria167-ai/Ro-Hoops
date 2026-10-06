--!strict
-- CAMERA SETTINGS
-- The camera is locked onto the rim: it always sits behind the player on the line from the
-- rim through the player, and always faces the rim, so the rim never leaves its spot on
-- screen and "up" on the keys always means "toward the rim". It never takes rotation input.
-- Used by src/client/Controllers/CameraController.luau.
--
-- Units: studs. Live-tunable in Studio under ReplicatedStorage > Tuning > Camera.

local Camera = {
	-- How wide the camera sees, in degrees. Higher = more zoomed out / more distortion.
	FIELD_OF_VIEW = 60,

	-- Camera height above the floor, studs. Higher = more top-down view.
	HEIGHT = 10,

	-- How far behind the player the camera sits, studs. Higher = player looks smaller.
	DISTANCE = 15,

	-- Where the rim sits on screen: degrees ABOVE the middle of the screen (the crosshair).
	-- 0 = the rim is exactly on the crosshair, but then the player's feet drop off the
	-- bottom of the screen; 12 keeps the whole player in view with the rim in the upper part.
	RIM_ABOVE_CENTER = 12,

	-- How far round the rim the camera can swing, degrees either side of straight out in
	-- front of the backboard. Stops it going round behind the backboard (where the board
	-- would block the view) when the player walks along or behind the baseline.
	MAX_ORBIT_ANGLE = 75,

	-- How quickly the camera catches up with the player. Higher = snappier, lower = floatier.
	FOLLOW_SHARPNESS = 8,
}

return Camera
