--!strict
-- SKILL MATH
-- Plain math with no Roblox APIs, so it can be unit tested outside Studio with Lune
-- (tests/SkillMath.spec.luau). Covers the decisions behind every dribble move:
--   1. detectSwipe  – did the mouse/trackpad just make a quick flick, and which way?
--   2. detectCircle – did it just draw a circle, and which way round?
--   3. chooseMove   – which dribble move does a flick become?
-- SkillController judges each "stroke" (a burst of cursor movement, ended by the cursor
-- stopping) as a whole: a full circle is a spin, otherwise a fast straight stroke is a
-- flick. Waiting for the stroke to end is what stops a circle being read as a flick.

local SkillMath = {}

-- Which hand the ball is in.
export type Hand = "Right" | "Left"

-- Every dribble move:
--   HandSwitch – a quick, simple change of hands (the H key)
--   Crossover  – the wide, Allen Iverson style crossover (flick toward the empty hand)
--   StepBack   – one step back, pulling the ball with you (flick backward)
--   Spin       – a 360° reverse-pivot spin, switching hands during the spin
--                (draw a circle)
export type Move = "HandSwitch" | "Crossover" | "StepBack" | "Spin"

-- One cursor reading: the clock time and where the cursor was. Positions are measured in
-- screen heights (so a flick is the same size on any screen) with y pointing UP.
export type Sample = {
	t: number,
	x: number,
	y: number,
}

-- The settings each function needs (they come from Config/Skills.luau).
export type SwipeConfig = {
	SWIPE_DISTANCE: number,
	SWIPE_WINDOW: number,
}

export type CircleConfig = {
	CIRCLE_ANGLE: number,
	CIRCLE_WINDOW: number,
	CIRCLE_MIN_LENGTH: number,
}

export type MoveConfig = {
	SIDE_DOMINANCE: number,
}

-- Segments shorter than this (screen heights) are merged with the next one when measuring
-- how much the path turns, so tiny jitters don't count as turning.
local MIN_SEGMENT = 0.004

-- 1. Looks at the cursor's recent path (`samples`, oldest first) and returns the flick it
-- made as a vector in screen heights (x = right, y = up), or nil if there was no flick.
-- A flick = the cursor travelled at least SWIPE_DISTANCE within the last SWIPE_WINDOW
-- seconds. Slow cursor movement never covers that much ground in time, so it's ignored.
function SkillMath.detectSwipe(samples: { Sample }, config: SwipeConfig): (number?, number?)
	local count = #samples
	if count < 2 then
		return nil
	end
	local last = samples[count]
	-- The oldest reading that is still inside the window.
	local first = last
	for i = count - 1, 1, -1 do
		if last.t - samples[i].t > config.SWIPE_WINDOW then
			break
		end
		first = samples[i]
	end
	local dx, dy = last.x - first.x, last.y - first.y
	if math.sqrt(dx * dx + dy * dy) < config.SWIPE_DISTANCE then
		return nil
	end
	return dx, dy
end

-- 2. Looks at the last CIRCLE_WINDOW seconds of the cursor's path and returns +1 if it
-- drew a circle counterclockwise (on screen), -1 if clockwise, or nil if it didn't.
-- A circle = the path's direction turned through at least CIRCLE_ANGLE degrees in one
-- direction, along a path at least CIRCLE_MIN_LENGTH screen heights long (so small
-- wobbles don't count). Turning one way and then back cancels out.
function SkillMath.detectCircle(samples: { Sample }, config: CircleConfig): number?
	local count = #samples
	if count < 3 then
		return nil
	end
	local lastTime = samples[count].t
	local turned = 0 -- total signed turning, radians (positive = counterclockwise)
	local length = 0 -- path length, screen heights
	local anchor: Sample? = nil -- start of the current segment
	local previousX, previousY = 0, 0 -- direction of the previous segment (zero = none yet)
	for i = 1, count do
		local sample = samples[i]
		if lastTime - sample.t <= config.CIRCLE_WINDOW then
			local from = anchor
			if not from then
				anchor = sample
			else
				local dx, dy = sample.x - from.x, sample.y - from.y
				local segment = math.sqrt(dx * dx + dy * dy)
				if segment >= MIN_SEGMENT then
					if previousX ~= 0 or previousY ~= 0 then
						-- Signed angle from the previous direction to this one.
						local cross = previousX * dy - previousY * dx
						local dot = previousX * dx + previousY * dy
						turned += math.atan2(cross, dot)
					end
					length += segment
					previousX, previousY = dx, dy
					anchor = sample
				end
			end
		end
	end
	if length < config.CIRCLE_MIN_LENGTH or math.abs(turned) < math.rad(config.CIRCLE_ANGLE) then
		return nil
	end
	return if turned > 0 then 1 else -1
end

-- 3. Picks the move for a flick. `towardRight` and `towardForward` are how much of the
-- flick points to the player's right and the way the player faces (already turned from
-- screen directions into the player's own, so it works whichever way they face). `hand`
-- is where the ball is now.
--   * Flick mostly sideways, toward the empty hand → Crossover (the wide one; the ball
--     goes where you flicked it). The quick HandSwitch is on the H key instead.
--   * Flick mostly backward → StepBack.
--   * Anything else → nil (forward is kept free for a later move; toward the ball's own
--     side does nothing).
function SkillMath.chooseMove(towardRight: number, towardForward: number, hand: Hand, config: MoveConfig): Move?
	if math.abs(towardRight) < math.abs(towardForward) * config.SIDE_DOMINANCE then
		-- Mostly forward or back.
		return if towardForward < 0 then "StepBack" else nil
	end
	local side: Hand = if towardRight > 0 then "Right" else "Left"
	if side ~= hand then
		return "Crossover"
	end
	return nil
end

return SkillMath
