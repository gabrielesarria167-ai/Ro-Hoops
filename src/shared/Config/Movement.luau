--!strict
-- Player movement tuning. Speeds are studs/s, rates are studs/s².

local Movement = {
	WALK_SPEED = 13,
	RUN_SPEED = 21,

	ACCELERATION = 70, -- speeding up toward the input direction
	DECELERATION = 110, -- slowing down or stopping
	TURN_ACCELERATION = 160, -- when the new input opposes the current velocity

	STOP_EPSILON = 0.05, -- below this speed the player is treated as standing still
}

return Movement
