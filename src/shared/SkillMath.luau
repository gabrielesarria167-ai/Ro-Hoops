--!strict
-- SKILL MATH
-- Plain math with no Roblox APIs, so it can be unit tested outside Studio with Lune
-- (tests/SkillMath.spec.luau). Covers the two decisions behind every dribble move:
--   1. detectSwipe – did the mouse/trackpad just make a quick flick, and which way?
--   2. chooseMove  – which dribble move does that flick become?

local SkillMath = {}

-- Which hand the ball is in.
export type Hand = "Right" | "Left"

-- Every dribble move:
--   HandSwitch – a quick, simple change of hands (the H key)
--   Crossover  – the wide, Allen Iverson style crossover (flick toward the empty hand)
export type Move = "HandSwitch" | "Crossover"

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

export type MoveConfig = {
	SIDE_DOMINANCE: number,
}

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

-- 2. Picks the move for a flick. `towardRight` and `towardForward` are how much of the
-- flick points to the player's right and the way the player faces (already turned from
-- screen directions into the player's own, so it works whichever way they face). `hand`
-- is where the ball is now.
--   * Flick mostly sideways, toward the empty hand → Crossover (the wide one; the ball
--     goes where you flicked it). The quick HandSwitch is on the H key instead.
--   * Anything else → nil (no move yet; later moves will use forward/back flicks).
function SkillMath.chooseMove(towardRight: number, towardForward: number, hand: Hand, config: MoveConfig): Move?
	if math.abs(towardRight) < math.abs(towardForward) * config.SIDE_DOMINANCE then
		return nil -- mostly forward or back
	end
	local side: Hand = if towardRight > 0 then "Right" else "Left"
	if side ~= hand then
		return "Crossover"
	end
	return nil
end

return SkillMath
