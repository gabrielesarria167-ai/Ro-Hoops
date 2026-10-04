--!strict
-- The test ball: physical properties, the code-driven dribble and hold positions, and
-- how a shot in flight is resolved.

local Court = require(script.Parent.Court)

local Ball = {
	RADIUS = Court.ft(0.39), -- 9.4" diameter ball
	COLOR = Color3.fromRGB(214, 110, 40),

	COLLISION_GROUP = "Ball",
	PLAYER_COLLISION_GROUP = "Players",

	DENSITY = 0.6,
	FRICTION = 0.5,
	ELASTICITY = 0.72,
	BACKSPIN = 12, -- rad/s applied on release

	DRIBBLE_HEIGHT = 2.3, -- peak height of the bounce above the floor, studs
	DRIBBLE_RATE = 1.7, -- bounces per second while standing
	DRIBBLE_RATE_PER_SPEED = 0.05, -- extra bounces per second per stud/s of movement
	DRIBBLE_SIDE = 1.1, -- offset to the player's right
	DRIBBLE_FORWARD = 0.7,

	HOLD_HEIGHT = 2.6, -- above the root part while gathering a shot
	HOLD_FORWARD = 0.6,

	MISS_DEPTH = 2, -- a falling ball this far below the rim can no longer go in
	SHOT_TIMEOUT = 4, -- seconds before a shot stuck on the rim counts as a miss
	RETURN_DELAY = 1.2, -- seconds after a shot resolves before the ball comes back
}

return Ball
