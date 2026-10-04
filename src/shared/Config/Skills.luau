--!strict
-- DRIBBLE SKILL SETTINGS
-- How mouse/trackpad flicks turn into dribble moves, and how the wide crossover looks.
-- Used by src/client/Controllers/SkillController.luau (body: lean, jab, burst),
-- src/client/Controllers/BallController.luau (ball path), ArmController (hands) and the
-- pure math in src/shared/SkillMath.luau. The quick hand switch (H key) is in
-- src/shared/Config/Ball.luau (SWITCH_...).
--
-- There's no button to hold: just flick the mouse (or swipe on the trackpad) quickly.
-- Slow cursor movement does nothing. Live-tunable under ReplicatedStorage > Tuning > Skills.

local Skills = {
	-- FLICK DETECTION -------------------------------------------------------------------

	-- How far the cursor must travel to count as a flick, in screen heights (0.06 = 6% of
	-- the screen's height, ~65 px on a 1080p screen). Lower = more sensitive (easier to
	-- trigger by accident), higher = needs a bigger flick.
	SWIPE_DISTANCE = 0.06,
	-- ...and it must cover that distance within this many seconds. Lower = needs a faster
	-- flick. 0.06 within 0.12 s means the cursor moves at least half a screen per second.
	SWIPE_WINDOW = 0.12,

	-- WHICH MOVE --------------------------------------------------------------------------

	-- A flick counts as sideways (a crossover) when its sideways part is at least this many
	-- times its forward/back part. 1 = anything closer to sideways than diagonal.
	SIDE_DOMINANCE = 1,

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

	-- Footwork: the feet plant on the sell (any momentum stops), then ONE quick step toward
	-- the new side as the ball crosses. With these values the step covers about 2 studs
	-- (one stride). After it your keys take over again, so hold a direction to keep going.
	WIDE_STEP_SPEED = 13, -- studs/s during the step
	WIDE_STEP_TIME = 0.25, -- seconds the step lasts
	-- How much of the step goes forward: 0 = straight sideways, 1 = as much forward as
	-- sideways. Keep it small, or a run of crossovers carries you across the court.
	WIDE_STEP_FORWARD = 0.15,
	-- How quickly your speed changes into the plant and the step (studs/s²). Higher = more
	-- explosive (the normal walk acceleration is 70).
	WIDE_STEP_RATE = 220,
}

return Skills
