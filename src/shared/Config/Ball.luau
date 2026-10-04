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

	-- Ball radius in studs: a real 9.4" ball (0.39 ft radius) scaled up with the rim by
	-- Court.EQUIPMENT_SCALE, so it's bigger than the avatar's hand (~1.25 studs across).
	-- (Changing this live does not resize the ball; edit it here and restart Play.)
	RADIUS = Court.ft(0.39) * Court.EQUIPMENT_SCALE,
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

	DRIBBLE_HEIGHT = 2.1, -- how high the ball bounces above the floor, studs
	DRIBBLE_RATE = 1.7, -- bounces per second while standing still
	DRIBBLE_RATE_PER_SPEED = 0.05, -- extra bounces per second for each stud/s you're moving
	DRIBBLE_SIDE = 1.3, -- how far to the player's right the ball bounces, studs
	DRIBBLE_FORWARD = 0.9, -- how far in front of the player the ball bounces, studs
	-- (DRIBBLE_SIDE is mirrored to the left when the ball is in the left hand.)

	-- HAND SWITCH (the H key) ----------------------------------------------------------
	-- A quick, simple change of hands: the ball is pushed down and across in front of the
	-- body, hits the floor on the centre line, and rises into the other hand at the top of
	-- its bounce. (The wide Iverson crossover is in Config/Skills.luau.)

	-- Seconds from the key press until the ball is at the top of the bounce in the other
	-- hand (when the ball starts from the top of a bounce). Lower = snappier.
	SWITCH_TIME = 0.26,
	-- Fraction of SWITCH_TIME spent driving the ball down to the floor; the rest is the
	-- rise into the other hand. If the ball is already low when you press H, the push down
	-- is shorter, so the switch always starts instantly.
	SWITCH_DOWN_SHARE = 0.45,
	-- Where the ball hits the floor as it crosses: this many studs in front of the hips, on
	-- the centre line. Far enough forward that it doesn't pass through the feet.
	SWITCH_FORWARD = 1.2,

	-- SHOT RESOLUTION -------------------------------------------------------------------

	-- Shots fly along a perfect scripted arc, then switch to real physics when the ball
	-- gets this close to the rim (studs), so the rim and backboard decide close calls.
	HANDOFF_DISTANCE = 3,
	-- Once a falling ball is this many studs below the rim it can't go in: it's a miss.
	MISS_DEPTH = 2,
	-- A shot that hasn't gone in after this many seconds (e.g. stuck on the rim) is a miss.
	SHOT_TIMEOUT = 4,
	-- Seconds between a shot being decided and the ball reappearing in your hands.
	RETURN_DELAY = 1.2,
}

return Ball
