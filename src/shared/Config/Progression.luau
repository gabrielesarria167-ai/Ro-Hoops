--!strict
-- configuring playthrough constants

local MAX_LEVEL = 99
local STARTING_POINTS = 100
local POINTS_PER_LEVEL = 7
local BASE_XP = 50
local XP_GROWTH = 1.1

return table.freeze({
	MAX_LEVEL = MAX_LEVEL,
	STARTING_POINTS = STARTING_POINTS,
	POINTS_PER_LEVEL = POINTS_PER_LEVEL,
	BASE_XP = BASE_XP,
	XP_GROWTH = XP_GROWTH,
})
