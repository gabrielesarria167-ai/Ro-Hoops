--!strict
-- DRIBBLE SKILL SETTINGS
-- How mouse/trackpad gestures turn into dribble moves, and how each move looks.
-- Used by src/client/Controllers/SkillController.luau (body: lean, jab, burst),
-- src/client/Controllers/BallController.luau (ball path), ArmController (hands) and the
-- pure math in src/shared/SkillMath.luau. The quick hand switch (H key) is in
-- src/shared/Config/Ball.luau (SWITCH_...).
--
-- There's no button to hold: flick the mouse (or swipe on the trackpad) quickly, or draw a
-- quick circle. Slow cursor movement does nothing.
--   flick toward the empty hand → wide crossover
--   flick backward              → step-back
--   draw a circle               → 360 spin (clockwise circle = clockwise spin)
--   H key                       → quick hand switch (Config/Ball.luau, SWITCH_...)
-- Every move takes at most ONE short step (see FOOTWORK), so moves can be chained without
-- carrying the player across the court. Live-tunable under ReplicatedStorage > Tuning > Skills.

local Skills = {
	-- FLICK DETECTION -------------------------------------------------------------------

	-- How far the cursor must travel to count as a flick, in screen heights (0.06 = 6% of
	-- the screen's height, ~65 px on a 1080p screen). Lower = more sensitive (easier to
	-- trigger by accident), higher = needs a bigger flick.
	SWIPE_DISTANCE = 0.06,
	-- ...and it must cover that distance within this many seconds. Lower = needs a faster
	-- flick. 0.06 within 0.12 s means the cursor moves at least half a screen per second.
	SWIPE_WINDOW = 0.12,
	-- A gesture is judged once the cursor stops: this many seconds with no movement ends
	-- it. Waiting for the end is what tells a circle apart from a flick (a circle is full
	-- of flick-like pieces). Lower = flicks fire sooner, but a pause mid-circle splits it.
	STROKE_END_GAP = 0.04,

	-- CIRCLE DETECTION (the spin) -------------------------------------------------------

	-- How far round the circle must go, degrees. 360 = a full circle; 300 forgives a
	-- slightly short one.
	CIRCLE_ANGLE = 190,
	-- ...within this many seconds. Higher = slower circles still count.
	CIRCLE_WINDOW = 0.7,
	-- The circle's path must be at least this long, in screen heights (0.25 ≈ a circle
	-- 8% of the screen across), so small wobbles don't spin you.
	CIRCLE_MIN_LENGTH = 0.20,

	-- WHICH MOVE --------------------------------------------------------------------------

	-- A flick counts as sideways (a crossover) when its sideways part is at least this many
	-- times its forward/back part. 1 = anything closer to sideways than diagonal.
	SIDE_DOMINANCE = 1, -- (otherwise the flick is forward or back; backward = step-back)

	-- FOOTWORK (shared by every move) ---------------------------------------------------
	-- Each move plants the feet (any momentum stops) and takes at most ONE quick step.
	-- With these values a step covers about 3.5 studs, counting the slow-down after it.
	-- After the step your keys take over again, so hold a direction to keep going.
	STEP_SPEED = 13, -- studs/s during the step
	STEP_TIME = 0.25, -- seconds the step lasts
	-- How quickly your speed changes into the plant and the step (studs/s²). Higher = more
	-- explosive (the normal walk acceleration is 70).
	STEP_RATE = 220,

	-- WIDE CROSSOVER (Allen Iverson style: flick toward the empty hand) -----------------
	-- Three beats, ~0.6 s in all:
	--   1. SELL    – the ball is pulled out wide and low on its side while the feet plant
	--                and the body leans that way, so the defender bites;
	--   2. CROSS   – the ball is pounded down, bounces low on the centre line in front of
	--                the feet, and is caught out wide and low on the other side;
	--   3. EXPLODE – the body whips over to the new side and takes ONE quick step that way
	--                while the ball comes back up into a normal dribble in the new hand.
	--
	-- Ball spots are Vector3.new(out, height, forward): `out` = studs out to the side the
	-- ball is on at that moment (mirrored automatically for either hand), `height` = studs
	-- from the floor to the ball's centre, `forward` = studs in front of the hips.
	WIDE_SELL_SPOT = Vector3.new(1.9, 1.8, 0.9), -- held out wide on the starting side
	WIDE_BOUNCE_FORWARD = 1.4, -- where it bounces: on the centre line, this far in front
	WIDE_CATCH_SPOT = Vector3.new(1.8, 1.5, 1.0), -- caught wide and low on the other side

	-- Seconds for each part of the ball's trip. Lower = snappier.
	WIDE_SELL_TIME = 0.16, -- out to the sell spot
	WIDE_PUSH_TIME = 0.1, -- pounded down to the bounce
	WIDE_RISE_TIME = 0.12, -- up from the bounce into the other hand
	WIDE_RECOVER_TIME = 0.22, -- carried back up to a normal dribble

	-- Hands: during the move the palm holds the ball's outer side instead of its top (so
	-- it can pull the ball wide and whip it across). This is the direction from the ball's
	-- centre to the palm: (out, up, forward), mirrored for the left hand.
	WIDE_GRIP = Vector3.new(0.55, 0.8, -0.1),

	-- Body lean, degrees (see PostureController). FORWARD = bent over the ball (a low,
	-- athletic stance); SIDE = toward the ball on the sell, toward the new side on the cross.
	-- The run animation already bends the torso forward ~20° during the burst, so the
	-- cross needs much less forward lean than the sell to look the same.
	WIDE_SELL_FORWARD_LEAN = 12,
	WIDE_SELL_SIDE_LEAN = 10,
	WIDE_CROSS_FORWARD_LEAN = 4,
	WIDE_CROSS_SIDE_LEAN = 18,
	-- Seconds to straighten back up after the move.
	WIDE_LEAN_RECOVER_TIME = 0.3,

	-- The step (see FOOTWORK) goes toward the new side as the ball crosses. This is how
	-- much of it goes forward: 0 = straight sideways, 1 = as much forward as sideways. Keep
	-- it small, or a run of crossovers carries you across the court.
	WIDE_STEP_FORWARD = 0.15,

	-- STEP-BACK (flick backward) ------------------------------------------------------------
	-- Plant, lean back a little, and take one step straight back (see FOOTWORK) while the
	-- ball is pulled back with you: it bounces just in front of the hips, then comes up
	-- into the same hand. Good for creating space before a shot.
	STEPBACK_PLANT_TIME = 0.06, -- seconds planted before the step back
	STEPBACK_PULL_TIME = 0.14, -- seconds for the ball to be pulled back and down to its bounce
	STEPBACK_RISE_TIME = 0.16, -- seconds for it to come back up into the hand
	STEPBACK_BOUNCE_FORWARD = 0.3, -- where it bounces: this many studs in front of the hips
	-- Degrees the body leans back during the step. The run animation bends the torso
	-- ~20° forward while moving, so this has to be fairly big to read as leaning back.
	STEPBACK_LEAN = 12,

	-- SPIN (draw a circle) ----------------------------------------------------------------
	-- A reverse pivot, like a real spin move:
	--   1. plant and get low; the dribbling hand pulls the ball in tight to its hip;
	--   2. turn a full circle (the way you drew it) on the planted foot, sliding sideways.
	--      As you turn, the dribbling hand pulls the ball ACROSS the front of the body (your
	--      back is to the defender, so the body shields it); partway round the hands meet
	--      on the ball and the other hand takes it on to its own hip;
	--   3. coming out of the spin, the new hand pushes it into the dribble.
	-- A clockwise spin slides you left, counterclockwise slides you right.
	SPIN_POCKET = Vector3.new(1, 2.3, 0.4), -- ball against a hip (out, height, forward); mirrored for the other hand
	SPIN_HANDOFF_SPOT = Vector3.new(0, 2.2, 0.8), -- in front of the belly, where the hands swap
	-- How far through the turn the hands swap (0 = start, 1 = end; 0.5 = halfway round,
	-- back to the defender).
	SPIN_HANDOFF_AT = 0.5,
	SPIN_BOUNCE_FORWARD = 1, -- coming out: the new hand bounces it beside itself, this far in front
	SPIN_GATHER_TIME = 0.1, -- seconds to pull the ball in to the hip
	SPIN_TIME = 0.4, -- seconds for the full turn
	SPIN_DROP_TIME = 0.12, -- seconds for the new hand to push the ball down to its bounce
	SPIN_RISE_TIME = 0.14, -- seconds for it to come back up into that hand
	SPIN_DEGREES = 360, -- how far the body turns
	SPIN_SLIDE = 4, -- studs slid sideways during the turn
	SPIN_LEAN = 8, -- degrees the body bends forward (low) during the spin
}

return Skills
