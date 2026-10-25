--!strict
-- HOOP AND FLOOR DIMENSIONS
-- The physical setup built by src/server/HoopBuilder.luau. Distances are written in real
-- basketball feet and converted to studs with ft(), so everything scales together.
--
-- Layout: the rim hangs above the world origin (x = 0, z = 0) and the playing area
-- stretches toward +Z. "Toward the rim" therefore means toward -Z.

-- How many studs one real foot is. The avatar stands 5.11 studs from the floor to the top
-- of its head (measured in Studio, rest pose) and counts as 5'0", so 5.11 / 5 = 1.022.
-- Change this to rescale the whole court and hoop relative to players (the ball keeps
-- its own size, Config/Ball.luau RADIUS).
local STUDS_PER_FOOT = 1.022

-- Converts real feet to studs, e.g. ft(10) = rim height in studs.
local function ft(feet: number): number
	return feet * STUDS_PER_FOOT
end

-- Scales the rim, its mount and the net up (heights and distances stay true). 1 = a real
-- 18" rim. ShotController scales the aim error by the same factor. The ball has its own
-- size (Config/Ball.luau, RADIUS). The backboard does not scale, so above ~1.3 the rim
-- outgrows the 24" shooter's square.
local EQUIPMENT_SCALE = 1.3

-- Raises the rim and backboard above their true height (only heights change; distances,
-- ball and rim size do not). 1 = true scale: a 10 ft rim (10.2 studs) over the 5.11 stud
-- (5'0") avatar, the real rim-to-player height ratio. Roblox avatars have long arms and
-- a big jump for their height, so if layups start feeling like dunks, raise this a little
-- (1.1 = about 11.2 studs) rather than shrinking the court.
local RIM_HEIGHT_SCALE = 1

local Court = {
	STUDS_PER_FOOT = STUDS_PER_FOOT, -- exposed so other code can convert studs back to feet
	ft = ft, -- exposed so other config files can use the same conversion
	EQUIPMENT_SCALE = EQUIPMENT_SCALE, -- exposed for the ball size and aim error

	-- RIM -------------------------------------------------------------------------------

	RIM_POSITION = Vector3.new(0, ft(10) * RIM_HEIGHT_SCALE, 0), -- centre of the rim: 10 ft, raised by RIM_HEIGHT_SCALE
	RIM_INNER_RADIUS = ft(0.75) * EQUIPMENT_SCALE, -- inside radius of the rim (18" NBA rim)
	RIM_TUBE = ft(0.625 / 12) * EQUIPMENT_SCALE, -- the ring is a 5/8" solid steel rod
	RIM_SEGMENTS = 36, -- the ring is built from this many short rods; more = rounder
	RIM_PLATE = ft(7 / 12) * EQUIPMENT_SCALE, -- square mounting plate on the board (5" × 5" bolt pattern)
	NET_LOOPS = 12, -- net hooks welded under the ring
	NET_LENGTH = ft(1.5) * EQUIPMENT_SCALE, -- NBA: 18" white cord net
	NET_BOTTOM_RADIUS = ft(0.5) * EQUIPMENT_SCALE, -- the net tapers to about 12" across at the bottom
	NET_ROWS = 4, -- rows of diamonds in the net's mesh
	RIM_TO_BACKBOARD = ft(1.25) * EQUIPMENT_SCALE, -- rim's centre to the backboard's face (a 6" gap to the ring)

	-- BACKBOARD AND SUPPORT -------------------------------------------------------------

	BACKBOARD_SIZE = Vector3.new(ft(6), ft(3.5), ft(0.5 / 12)), -- 72" × 42" × 1/2" tempered glass
	BACKBOARD_BOTTOM = ft(9.5) * RIM_HEIGHT_SCALE, -- bottom edge 6" below the rim (raised with it)
	SHOOTER_SQUARE = Vector2.new(ft(2), ft(1.5)), -- the 24" × 18" box on the board; its bottom is level with the rim
	BACKBOARD_FRAME = ft(1.5 / 12), -- aluminium frame round the glass
	BACKBOARD_PAD = ft(2 / 12), -- padding thickness on the board's bottom edge and lower sides
	BACKBOARD_SIDE_PAD = ft(15 / 12), -- the sides are padded this far up from the bottom edge

	-- The portable stanchion (typical arena-system sizes from spec sheets).
	STANCHION_EXTENSION = ft(8), -- the board's face to the front of the base (an "8 ft boom")
	STANCHION_BASE = Vector3.new(ft(4), ft(39 / 12), ft(8)), -- width, height, length of the padded base
	STANCHION_PAD = ft(3 / 12), -- padding round the column
	COLUMN_PAD_HEIGHT = ft(7), -- the column is padded up to this height

	-- COURT LINES (NBA half court) --------------------------------------------------------
	-- z values are measured from the rim's centre (z = 0), toward the half-court line (+Z).

	COURT_WIDTH = ft(50), -- sideline to sideline
	BASELINE_Z = -ft(5.25), -- the rim's centre is 5'3" in from the baseline
	HALF_COURT_Z = ft(47 - 5.25), -- the half-court line is 47 ft from the baseline
	APRON = ft(6), -- out-of-bounds floor beside the sidelines and past the half-court line
	BASELINE_RUNOFF = ft(16), -- out-of-bounds floor behind the baseline (room for the stanchion)
	LINE_WIDTH = ft(2 / 12), -- every line is 2" wide
	LANE_WIDTH = ft(16), -- the paint (key)
	FREE_THROW_Z = ft(19 - 5.25), -- the free-throw line is 19 ft from the baseline
	FREE_THROW_RADIUS = ft(6), -- circle round the free-throw line (lower half dashed)
	THREE_POINT_RADIUS = ft(23.75), -- arc round the rim's centre
	CORNER_THREE_X = ft(22), -- the straight corner-three lines, this far either side
	RESTRICTED_RADIUS = ft(4), -- the no-charge semicircle under the rim
	CENTER_CIRCLE_RADIUS = ft(6), -- at the half-court line (only this half is drawn)
	CENTER_INNER_RADIUS = ft(2), -- the small circle inside it

	-- Small marks (NBA Rule 1). z values here are measured from the BASELINE.
	MARK_LENGTH = ft(0.5), -- lane space marks and defensive-box hashes are 6" long
	LANE_BLOCK = { ft(7), ft(8) }, -- the block: a solid 1 ft mark on each lane line, 7-8 ft up
	LANE_MARKS = { ft(11), ft(14) }, -- 2" lane space marks further up each lane line
	DEFENSIVE_BOX_OFFSET = ft(3), -- the lower defensive box's hashes: 3 ft outside the lane lines,
	DEFENSIVE_BOX_TOP = ft(13), -- at the baseline and 13 ft up
	SIDELINE_HASH = ft(28), -- throw-in hash on each sideline, 28 ft up,
	SIDELINE_HASH_LENGTH = ft(3), -- reaching 3 ft onto the court

	-- SPAWN ------------------------------------------------------------------------------

	SPAWN_DISTANCE = ft(18), -- players spawn this far in front of the rim, facing it
}

return Court
