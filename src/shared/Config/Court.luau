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

-- Roblox avatars have huge hands and heads compared to a real person, so a true-to-scale
-- ball looks smaller than the hand holding it. The ball and the rim are therefore scaled
-- up together by this factor (heights and distances are not). Because the ball and rim
-- grow together, shooting is exactly as hard as at real size: ShotController scales the
-- aim error by the same factor.
local EQUIPMENT_SCALE = 1.9

-- Roblox avatars have long arms and a big jump relative to their height, so a rim at a
-- true 10 ft (8.5 studs here) sits barely above an avatar's overhead reach and a layup
-- feels like a dunk. The rim and backboard are therefore raised by this factor (1 = true
-- scale, 1.25 = about 10.6 studs). Raise it if layups still feel too easy, lower it if
-- jump shots feel too hard. Only heights change; distances, ball and rim size do not.
local RIM_HEIGHT_SCALE = 1.25

local Court = {
	STUDS_PER_FOOT = STUDS_PER_FOOT, -- exposed so other code can convert studs back to feet
	ft = ft, -- exposed so other config files can use the same conversion
	EQUIPMENT_SCALE = EQUIPMENT_SCALE, -- exposed for the ball size and aim error

	-- RIM -------------------------------------------------------------------------------

	RIM_POSITION = Vector3.new(0, ft(10) * RIM_HEIGHT_SCALE, 0), -- centre of the rim: 10 ft, raised by RIM_HEIGHT_SCALE
	RIM_INNER_RADIUS = ft(0.75) * EQUIPMENT_SCALE, -- inside radius of the rim (18" NBA rim, scaled up)
	RIM_TUBE = 0.22, -- thickness of the metal ring, studs
	RIM_SEGMENTS = 24, -- the ring is built from this many short blocks; more = rounder
	RIM_TO_BACKBOARD = ft(1.25) * EQUIPMENT_SCALE, -- distance from the rim's centre to the backboard's face

	-- BACKBOARD AND SUPPORT -------------------------------------------------------------

	-- Width, height, thickness. 1.4× regulation (6 × 3.5 ft) so the bigger rim still fits
	-- nicely without the board towering over the players.
	BACKBOARD_SIZE = Vector3.new(ft(6) * 1.4, ft(3.5) * 1.4, 0.2),
	BACKBOARD_BOTTOM = ft(9.5) * RIM_HEIGHT_SCALE, -- height of the backboard's bottom edge (raised with the rim)
	STANCHION_OFFSET = ft(4), -- how far the support pole stands behind the backboard

	-- FLOOR AND SPAWN -------------------------------------------------------------------

	FLOOR_SIZE = Vector3.new(ft(60), 1, ft(60)), -- width, thickness, length; top is at y = 0
	FLOOR_CENTER_Z = ft(24), -- shifts the floor forward so most of it is in front of the rim
	SPAWN_DISTANCE = ft(18), -- players spawn this far in front of the rim, facing it
}

return Court
