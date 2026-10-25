--!strict
-- CAMERA SETTINGS
-- The camera is softly locked onto the rim: it sits behind the player facing up-court and
-- turns only RIM_FOLLOW of the way toward the rim, so the keys move along (nearly) straight
-- court lines and the side of the court stays in view. It never takes rotation input (the
-- mouse is used for dribble moves).
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

	-- How much the camera turns to face the rim, 0 to 1. 0 = always looks straight up-court
	-- (left/right keys move in perfectly straight lines; the rim slides sideways on screen
	-- out on the wings). 1 = always faces the rim (the rim never moves on screen, but
	-- left/right circle round it and you can't see the side you're moving toward).
	RIM_FOLLOW = 0.25,

	-- How quickly the camera catches up with the player. Higher = snappier, lower = floatier.
	FOLLOW_SHARPNESS = 8,
}

return Camera
