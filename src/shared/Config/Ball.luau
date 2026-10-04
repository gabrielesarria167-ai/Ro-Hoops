--!strict
-- BALL SETTINGS
-- Everything about the test ball: how it looks, how it bounces, where it sits while you
-- dribble or gather a shot, and the rules that decide when a shot is over.
--
-- Units: distances are in studs (Roblox's unit, 1 stud ≈ 1.18 ft at our scale), times in
-- seconds. Live-tunable in Studio under ReplicatedStorage > Tuning > Ball while playing.

local Court = require(script.Parent.Court)

local Ball = {
	-- LOOK ------------------------------------------------------------------------------

	-- Ball radius in studs. Court.ft converts real feet: 0.39 ft = a 9.4" diameter ball.
	-- (Changing this live does not resize the ball; edit it here and restart Play.)
	RADIUS = Court.ft(0.39),
	-- Ball colour (red, green, blue from 0 to 255).
	COLOR = Color3.fromRGB(214, 110, 40),

	-- COLLISION GROUPS ------------------------------------------------------------------
	-- Names used by src/server/CollisionGroups.luau so the ball passes through players
	-- and only the floor, rim and backboard can touch it.

	COLLISION_GROUP = "Ball", -- group the ball belongs to
	PLAYER_COLLISION_GROUP = "Players", -- group every character part belongs to

	-- BOUNCE PHYSICS (only used once a shot is handed to Roblox physics near the rim) ---

	DENSITY = 0.6, -- how heavy the ball is per stud³; affects how it pushes other parts
	FRICTION = 0.5, -- 0 = ice, 1 = rubbery; how much the ball grips the rim when it rolls
	ELASTICITY = 0.72, -- 0 = dead ball, 1 = super bouncy; how much speed survives a bounce
	BACKSPIN = 12, -- spin added on release, in radians per second (visual and bounce feel)

	-- DRIBBLE (the fake dribble animation while you have the ball) ----------------------

	DRIBBLE_HEIGHT = 2.3, -- how high the ball bounces above the floor, studs
	DRIBBLE_RATE = 1.7, -- bounces per second while standing still
	DRIBBLE_RATE_PER_SPEED = 0.05, -- extra bounces per second for each stud/s you're moving
	DRIBBLE_SIDE = 1.1, -- how far to the player's right the ball bounces, studs
	DRIBBLE_FORWARD = 0.7, -- how far in front of the player the ball bounces, studs

	-- SHOT GATHER (where the ball sits while you hold E) --------------------------------

	HOLD_HEIGHT = 2.6, -- studs above the character's hip (HumanoidRootPart) – roughly overhead
	HOLD_FORWARD = 0.6, -- studs in front of the character

	-- SHOT RESOLUTION -------------------------------------------------------------------

	-- Shots fly along a perfect scripted arc, then switch to real physics when the ball
	-- gets this close to the rim (studs), so the rim and backboard decide close calls.
	HANDOFF_DISTANCE = 2.5,
	-- Once a falling ball is this many studs below the rim it can't go in: it's a miss.
	MISS_DEPTH = 2,
	-- A shot that hasn't gone in after this many seconds (e.g. stuck on the rim) is a miss.
	SHOT_TIMEOUT = 4,
	-- Seconds between a shot being decided and the ball reappearing in your hands.
	RETURN_DELAY = 1.2,
}

return Ball
