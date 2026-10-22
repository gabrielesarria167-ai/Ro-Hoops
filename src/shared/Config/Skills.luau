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
--   flick toward the ball's hand → stab dribble (same hand, out to that side)
--   flick backward              → step-back
--   draw a circle (or a quick U) → 360 spin (clockwise circle = clockwise spin)
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
	-- Mouse readings arrive every ~0.017 s, with gaps of up to ~0.034 s when a frame
	-- misses one, so this must stay comfortably above 0.034.
	STROKE_END_GAP = 0.06,

	-- CIRCLE DETECTION (the spin) -------------------------------------------------------

	-- How far round the circle must go, degrees. 360 = a full circle, 180 = a "U".
	-- Measured in Studio: quick competitive spin gestures (half circles in ~0.2 s) turn
	-- 155-190°, slower ones 200-310°, while flicks turn only 5-15°. 120 sits well between
	-- the two, so a rushed half circle still spins and a flick never does.
	CIRCLE_ANGLE = 120,
	-- ...within this many seconds. Higher = slower circles still count.
	CIRCLE_WINDOW = 0.7,
	-- The circle's path must be at least this long, in screen heights (0.20 ≈ a half
	-- circle 13% of the screen across), so small wobbles don't spin you.
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
	-- Research (docs/MOVEMENT_REFERENCES.md section 6): the sell ball is ~0.3 body heights
	-- out from the centre line and below the knee.
	WIDE_SELL_SPOT = Vector3.new(1.7, 1.0, 0.7), -- held out wide and low on the starting side
	WIDE_BOUNCE_FORWARD = 1.4, -- where it bounces: on the centre line, this far in front
	WIDE_CATCH_SPOT = Vector3.new(1.6, 1.0, 0.8), -- caught low on the rise, outside the new foot

	-- Seconds for each part of the ball's trip. Lower = snappier.
	-- (WIDE_SELL_TIME is also the body's hesitation before the cross: SkillController reads
	-- it, so the feet, head and ball stay in step. Research: hesitation 0.15-0.3 s.)
	WIDE_SELL_TIME = 0.22, -- out to the sell spot
	WIDE_PUSH_TIME = 0.1, -- pounded down to the bounce
	WIDE_RISE_TIME = 0.12, -- up from the bounce into the other hand
	WIDE_RECOVER_TIME = 0.22, -- carried back up to a normal dribble
	-- The old hand keeps the ball through this share of the push down (0-1) before letting
	-- go, so it whips the ball across instead of dropping it.
	WIDE_HOLD_SHARE = 0.7,

	-- Hands: during the move the palm holds the ball's outer side instead of its top (so
	-- it can pull the ball wide and whip it across). This is the direction from the ball's
	-- centre to the palm: (out, up, forward), mirrored for the left hand.
	-- (0.85, 0.55, ...) is ~57 degrees off the top of the ball: the upper-outside quarter.
	WIDE_GRIP = Vector3.new(0.85, 0.55, -0.1),

	-- Body lean, degrees (see PostureController). FORWARD = bent over the ball (a low,
	-- athletic stance); SIDE = toward the ball on the sell, toward the new side on the cross.
	-- The run animation already bends the torso forward ~20° during the burst, so the
	-- cross needs much less forward lean than the sell to look the same.
	WIDE_SELL_FORWARD_LEAN = 12,
	WIDE_SELL_SIDE_LEAN = 18, -- research: trunk side-bend 15-25 degrees toward the jab
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
	-- Where it bounces: between the feet, inside the ball-side foot and a little ahead (away
	-- from the "defender"), clear of the foot. (out, forward) in studs from the hips.
	STEPBACK_BOUNCE_OUT = 0.55,
	STEPBACK_BOUNCE_FORWARD = 0.5,
	-- Degrees the body leans back during the step. Research: the trunk never really leans
	-- back in a step-back (the stance's forward hinge stays), so this is small.
	STEPBACK_LEAN = 6,

	-- STAB DRIBBLE (flick toward the hand that has the ball) -----------------------------
	-- The same hand pounds the ball hard out to its own side while the body leans into it
	-- and takes its one step that way (see FOOTWORK). The ball bounces out wide, then comes
	-- back up into the same hand as the body catches up with it.
	-- Where it bounces: within reach, ~0.6 outside the ball-side foot.
	STAB_BOUNCE_OUT = 1.3, -- this many studs out to the side of the hips...
	STAB_BOUNCE_FORWARD = 0.8, -- ...and this many in front
	-- The hand rolls from inside-top, over the top, to outside-top (never under the ball):
	-- grip values like Config/Ball.luau SWITCH_GRIP_...: 0 = on top, 1 = upper outer side,
	-- negative = upper inner side.
	STAB_GRIP_START = -0.4,
	STAB_GRIP_PUSH_END = 0.6,
	STAB_PUSH_TIME = 0.12, -- seconds to pound it down and out to the bounce
	STAB_RISE_TIME = 0.16, -- seconds for it to come back up into the hand
	-- How much of the step goes forward: 0 = straight sideways, 1 = as much forward as sideways.
	STAB_STEP_FORWARD = 0.15,
	STAB_SIDE_LEAN = 10, -- degrees the body leans toward the ball's side
	STAB_FORWARD_LEAN = 6, -- degrees the body bends forward (low) over the ball

	-- SPIN (draw a circle, or just a quick half circle) -----------------------------------
	-- A reverse pivot that stays legal: only ONE hand is ever on the ball, and the ball
	-- always bounces before the other hand touches it (two hands on it at once ends the
	-- dribble, so dribbling on afterwards would be a double dribble).
	--   1. POUND – plant and get low while the ball hand pounds one hard dribble beside
	--              its own foot;
	--   2. PULL  – the body starts turning (the way you drew it) on the planted foot; the
	--              same hand meets the ball on the way up, palm on its side (not under it),
	--              and pulls it round tight against its hip, shielded by the body. The
	--              free hand stays up as an arm bar;
	--   3. DROP  – coming out of the turn, that hand pushes the ball down across the front
	--              of the feet so it bounces just as the turn ends;
	--   4. CATCH – the other hand takes it off the bounce and carries on dribbling.
	-- A clockwise spin slides you left, counterclockwise slides you right.
	-- Ball spots: Vector3.new(out, height, forward) like the crossover's, `out` toward the
	-- hand the ball started in.
	SPIN_POUND_OUT = 1.2, -- 1. where the pound bounces: this many studs out to the ball's side...
	SPIN_POUND_FORWARD = 0.5, -- ...and this many in front of the hips
	-- 2. where the hand holds it during the turn: close to the hip but clear of the thigh
	-- (the ball's radius is ~0.63, the thigh is ~0.5 out from the hips).
	SPIN_POCKET = Vector3.new(1.25, 1.9, 0.45),
	SPIN_BOUNCE_ACROSS = 0.3, -- 3. where it bounces coming out: this far over to the NEW hand's side...
	SPIN_BOUNCE_FORWARD = 1, -- ...and this far in front of the hips
	SPIN_GATHER_TIME = 0.1, -- seconds for the pound (planted, before the turn starts)
	SPIN_PULL_TIME = 0.1, -- seconds for the ball to come up off the pound into the hand at the hip
	SPIN_TIME = 0.4, -- seconds for the full turn
	SPIN_DROP_TIME = 0.12, -- seconds to push it down to the bounce (ends as the turn ends)
	SPIN_RISE_TIME = 0.14, -- seconds for it to come up off that bounce into the new hand
	SPIN_DEGREES = 360, -- how far the body turns
	SPIN_SLIDE = 4, -- studs slid sideways during the turn
	SPIN_LEAN = 8, -- degrees the body bends forward (low) during the spin
}

return Skills
