--!strict
-- Hoop and floor dimensions. Distances are authored in real feet and converted to studs
-- with STUDS_PER_FOOT, so the whole setup scales together. 0.85 makes the default R15
-- character (about 5.3 studs) read as roughly 6'3".
--
-- Layout: the rim sits above the origin and the playing area extends toward +Z.

local STUDS_PER_FOOT = 0.85

local function ft(feet: number): number
	return feet * STUDS_PER_FOOT
end

local Court = {
	STUDS_PER_FOOT = STUDS_PER_FOOT,
	ft = ft,

	RIM_POSITION = Vector3.new(0, ft(10), 0),
	RIM_INNER_RADIUS = ft(0.75), -- 18" diameter rim
	RIM_TUBE = 0.15, -- thickness of the rim ring, studs
	RIM_SEGMENTS = 24,
	RIM_TO_BACKBOARD = ft(1.25), -- rim center to backboard face

	BACKBOARD_SIZE = Vector3.new(ft(6), ft(3.5), 0.15),
	BACKBOARD_BOTTOM = ft(9.5),
	STANCHION_OFFSET = ft(4), -- how far the support pole sits behind the backboard

	FLOOR_SIZE = Vector3.new(ft(60), 1, ft(60)), -- top surface is at y = 0
	FLOOR_CENTER_Z = ft(24),

	SPAWN_DISTANCE = ft(18),
}

return Court
