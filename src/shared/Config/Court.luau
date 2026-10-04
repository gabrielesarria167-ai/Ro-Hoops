--!strict
-- HOOP AND FLOOR DIMENSIONS
-- The physical setup built by src/server/HoopBuilder.luau. Distances are written in real
-- basketball feet and converted to studs with ft(), so everything scales together.
--
-- Layout: the rim hangs above the world origin (x = 0, z = 0) and the playing area
-- stretches toward +Z. "Toward the rim" therefore means toward -Z.

-- How many studs one real foot is. 0.85 makes the default Roblox character (about 5.3
-- studs tall) look roughly 6'3". Change this to rescale the hoop relative to players.
local STUDS_PER_FOOT = 0.85

-- Converts real feet to studs, e.g. ft(10) = rim height in studs.
local function ft(feet: number): number
	return feet * STUDS_PER_FOOT
end

local Court = {
	STUDS_PER_FOOT = STUDS_PER_FOOT, -- exposed so other code can convert studs back to feet
	ft = ft, -- exposed so other config files can use the same conversion

	-- RIM -------------------------------------------------------------------------------

	RIM_POSITION = Vector3.new(0, ft(10), 0), -- centre of the rim, 10 ft off the floor
	RIM_INNER_RADIUS = ft(0.75), -- inside radius of the rim (18" diameter, NBA size)
	RIM_TUBE = 0.15, -- thickness of the metal ring, studs
	RIM_SEGMENTS = 24, -- the ring is built from this many short blocks; more = rounder
	RIM_TO_BACKBOARD = ft(1.25), -- distance from the rim's centre to the backboard's face

	-- BACKBOARD AND SUPPORT -------------------------------------------------------------

	BACKBOARD_SIZE = Vector3.new(ft(6), ft(3.5), 0.15), -- width, height, thickness
	BACKBOARD_BOTTOM = ft(9.5), -- height of the backboard's bottom edge
	STANCHION_OFFSET = ft(4), -- how far the support pole stands behind the backboard

	-- FLOOR AND SPAWN -------------------------------------------------------------------

	FLOOR_SIZE = Vector3.new(ft(60), 1, ft(60)), -- width, thickness, length; top is at y = 0
	FLOOR_CENTER_Z = ft(24), -- shifts the floor forward so most of it is in front of the rim
	SPAWN_DISTANCE = ft(18), -- players spawn this far in front of the rim, facing it
}

return Court
