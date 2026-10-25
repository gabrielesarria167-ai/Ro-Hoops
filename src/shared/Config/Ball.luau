--!strict
-- BALL SETTINGS
-- Everything about the test ball: how it looks, how it bounces, where it sits while you
-- dribble or gather a shot, and the rules that decide when a shot is over.
--
-- Units: distances are in studs (Roblox's unit, 1 stud ≈ 1.06 ft at our scale), times in
-- seconds. Live-tunable in Studio under ReplicatedStorage > Tuning > Ball while playing.

local Ball = {
	-- LOOK ------------------------------------------------------------------------------

	-- Ball radius in studs. Bigger than real on purpose so it reads clearly bigger than the
	-- avatar's (oversized) hand: about 1.26 studs across, the size used before the court was
	-- rescaled. That makes the rim (Court.RIM_INNER_RADIUS) about 1.5× the ball's width
	-- instead of the real ~1.9×, so there's less room for a clean make.
	-- (Changing this live does not resize the ball; edit it here and restart Play.)
	RADIUS = 0.63,
	-- Ball colour (red, green, blue from 0 to 255).
	COLOR = Color3.fromRGB(214, 110, 40),

	-- COLLISION GROUPS ------------------------------------------------------------------
	-- Names used by src/server/CollisionGroups.luau so the ball passes through players
	-- and only the floor, rim and backboard can touch it.

	COLLISION_GROUP = "Ball", -- group the ball belongs to
	PLAYER_COLLISION_GROUP = "Players", -- group every character part belongs to
	-- Group the rim's ring is in: the ball bounces off it, players pass by it (so a dunk's
	-- body brushing the front of the rim doesn't snag on it). The backboard stays solid.
	RIM_COLLISION_GROUP = "Rim",

	-- BOUNCE PHYSICS (only used once a shot is handed to Roblox physics near the rim) ---

	DENSITY = 0.6, -- how heavy the ball is per stud³; affects how it pushes other parts
	FRICTION = 0.5, -- 0 = ice, 1 = rubbery; how much the ball grips the rim when it rolls
	ELASTICITY = 0.72, -- 0 = dead ball, 1 = super bouncy; how much speed survives a bounce
	BACKSPIN = 12, -- spin added on release, in radians per second (visual and bounce feel)

	-- DRIBBLE (the fake dribble animation while you have the ball) ----------------------
	-- One bounce (cycle): the hand meets the ball while it is still RISING, rides it up a few
	-- centimetres, then pushes it down and lets go (the "contact" part of the cycle); the
	-- ball then falls, bounces and rises into the hand again (the "flight" part).
	-- Research: docs/MOVEMENT_REFERENCES.md sections 1-4 (Hirata 2011, Liu & Hodgins 2018).
	-- Heights are the ball's CENTRE above the floor, studs.

	DRIBBLE_HEIGHT = 2.1, -- reference bounce height (studs) used to scale how much a crouch lowers the ball in a dribble MOVE
	DRIBBLE_CATCH_HEIGHT = 1.6, -- where the hand meets the ball, standing still (≈ 0.42 of body height)
	DRIBBLE_RELEASE_HEIGHT = 1.3, -- where the hand lets go of it (≈ 0.34 of body height)
	DRIBBLE_RUN_CATCH_HEIGHT = 2.1, -- the catch height at full speed (the ball is kept higher when running)
	DRIBBLE_HEIGHT_SPEED = 18, -- speed (studs/s) at which the catch height reaches DRIBBLE_RUN_CATCH_HEIGHT
	-- Shuffling sideways the dribble stays low: "no higher than your knees" (research,
	-- docs/MOVEMENT_REFERENCES.md section 2). The catch height eases to this as the sideways
	-- speed beats the forward/back speed by DRIBBLE_SHUFFLE_SPEED studs/s.
	DRIBBLE_SHUFFLE_CATCH_HEIGHT = 1.25,
	DRIBBLE_SHUFFLE_SPEED = 4,
	DRIBBLE_RIDE_UP = 0.15, -- how far the hand rides the ball up after meeting it, studs
	DRIBBLE_RIDE_SHARE = 0.3, -- share of the contact time spent riding up (the rest is the push down), 0-1
	DRIBBLE_CONTACT_SHARE = 0.55, -- share of the cycle the hand is on the ball (0.39 s of 0.6 s in the research), 0-1
	DRIBBLE_RESTITUTION = 0.85, -- speed the ball keeps in the floor bounce (FIBA spec), 0-1
	DRIBBLE_JITTER = 0.08, -- each bounce is randomly this share faster/slower and higher/lower (a perfect loop looks robotic), 0-1

	DRIBBLE_RATE = 1.6, -- bounces per second while standing still
	-- With no footfall information, moving speeds the dribble up: extra bounces per second
	-- for each stud/s you're moving, up to DRIBBLE_MAX_RATE.
	DRIBBLE_RATE_PER_SPEED = 0.05,
	DRIBBLE_MAX_RATE = 1.8, -- bounces per second, the most the speed-based fallback rate gives
	-- While moving, the dribble locks to the footsteps (LegController tells BallController
	-- about every foot plant): one bounce per two steps (one stride / one shuffle cycle),
	-- with the ball reaching the floor on a plant. These limit that rate:
	DRIBBLE_LOCKED_MIN_RATE = 1.0, -- bounces per second, slowest locked dribble
	DRIBBLE_LOCKED_MAX_RATE = 2.4, -- bounces per second, fastest locked dribble
	DRIBBLE_LOCK_STRENGTH = 0.5, -- share of the timing error corrected at each foot plant (1 = snap), 0-1
	DRIBBLE_FOOTFALL_STALE = 0.45, -- seconds without a foot plant after which the dribble falls back to the speed-based rate
	DRIBBLE_RUN_SPEED = 9, -- studs/s above which the dribble is a running dribble (push ahead, twist, one bounce per stride)

	-- Where the ball bounces, relative to the player (mirrored to the left in the left hand):
	DRIBBLE_SIDE = 1.2, -- studs to the player's right: about 0.45 outside the ball-side foot (the stance is 1.5 wide)
	DRIBBLE_FORWARD = 0.6, -- studs in front of the hips: beside the toes, not in front of them
	DRIBBLE_BACK_FORWARD = -0.1, -- studs in front of the hips when backpedalling (the ball stays beside / behind the rear foot)
	-- The ball is pushed ahead in the direction of travel: this many studs per stud/s of
	-- speed (≈ 0.55 at shuffle speed, ≈ 1.2 at run speed), at most DRIBBLE_MAX_LEAD.
	DRIBBLE_LEAD_PER_SPEED = 0.055,
	DRIBBLE_MAX_LEAD = 1.3,
	-- Seconds for the ball to settle into its dribble position after a move, a shot or a
	-- hand change (so it never pops): the offset fades with this speed (higher = quicker).
	DRIBBLE_SETTLE_RATE = 14,

	-- DRIBBLE MOVES --------------------------------------------------------------------
	-- A move asked for while the ball is in flight (falling or rising, hand not on it) waits
	-- for the hand to meet it, at most this many seconds, instead of dragging the ball
	-- along the floor.
	MOVE_MAX_WAIT = 0.15,
	-- The fastest the ball may be moving (studs/s) when a move takes over: the first leg of
	-- the move keeps the ball's current speed so it doesn't restart from rest.
	MOVE_MAX_CARRY_SPEED = 12,

	-- HAND SWITCH (the H key) ----------------------------------------------------------
	-- A quick, simple change of hands: the ball is pushed down and across in front of the
	-- body, hits the floor on the centre line, and rises into the other hand, which waits
	-- low and meets it on the way up. (The wide Iverson crossover is in Config/Skills.luau.)

	-- Seconds from the key press until the other hand has the ball (when the ball starts
	-- from the top of a bounce). Research: ~0.3-0.35 s. Lower = snappier.
	SWITCH_TIME = 0.32,
	-- Fraction of SWITCH_TIME spent driving the ball down to the floor; the rest is the
	-- rise into the other hand. If the ball is already low when you press H, the push down
	-- is shorter, so the switch always starts instantly.
	SWITCH_DOWN_SHARE = 0.45,
	-- Where the ball hits the floor as it crosses: this many studs in front of the hips, on
	-- the centre line (0.05-0.15 body heights in front of the toes), below the knee.
	SWITCH_FORWARD = 0.6,
	-- Where the sending hand holds the ball while it whips it across: 0 = on top, 1 = on its
	-- upper outer side (Skills.WIDE_GRIP), from the start to the end of the push down.
	SWITCH_GRIP_FROM = 0.3,
	SWITCH_GRIP_TO = 0.8,

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
