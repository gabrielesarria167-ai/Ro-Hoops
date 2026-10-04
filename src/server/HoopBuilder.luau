--!strict
-- HOOP BUILDER (runs on the server)
-- Builds the test setup when the game starts: a plain floor to stand on, a backboard, a
-- rim, a support pole and the spawn point. All sizes and positions come from
-- src/shared/Config/Court.luau.
--
-- Everything is anchored (doesn't move), shadowless SmoothPlastic, so the scene costs as
-- little performance as possible.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Court = require(ReplicatedStorage.Shared.Config.Court)

local HoopBuilder = {}

-- Colours (red, green, blue from 0 to 255).
local FLOOR_COLOR = Color3.fromRGB(190, 145, 95)
local STEEL_COLOR = Color3.fromRGB(70, 74, 82) -- pole and arm
local RIM_COLOR = Color3.fromRGB(230, 90, 30)
local BACKBOARD_COLOR = Color3.fromRGB(235, 240, 245)
local BACKBOARD_TRANSPARENCY = 0.35 -- 0 = solid, 1 = invisible

-- How each surface reacts when the ball hits it:
-- PhysicalProperties.new(density, friction, elasticity, frictionWeight, elasticityWeight).
-- Elasticity is the bounciness (0 = dead, 1 = perfect bounce). The weights (1, 1) mean the
-- surface and the ball count equally when Roblox mixes their values on contact.
local RIM_PHYSICS = PhysicalProperties.new(2, 0.3, 0.45, 1, 1) -- softer rim = more shooter's rolls
local BACKBOARD_PHYSICS = PhysicalProperties.new(2, 0.3, 0.6, 1, 1)
local FLOOR_PHYSICS = PhysicalProperties.new(1, 0.5, 0.6, 1, 1)

-- Creates one anchored block with the shared look and returns it.
local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe -- position and rotation
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- The rim is a ring of short blocks laid end to end, so the ball can physically drop
-- through the middle and bounce off the metal.
local function buildRim(parent: Instance)
	local rim = Instance.new("Model")
	rim.Name = "Rim"

	local center = Court.RIM_POSITION
	-- Blocks sit on a circle through the middle of the tube.
	local radius = Court.RIM_INNER_RADIUS + Court.RIM_TUBE / 2
	-- Each block covers its share of the circle, plus 5% overlap so there are no gaps.
	local segmentLength = 2 * math.pi * radius / Court.RIM_SEGMENTS * 1.05
	for i = 1, Court.RIM_SEGMENTS do
		local angle = (i / Court.RIM_SEGMENTS) * 2 * math.pi
		local position = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
		-- Direction along the circle at this point; the block is rotated to lie along it.
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local segment = makePart(
			rim,
			"Segment",
			Vector3.new(Court.RIM_TUBE, Court.RIM_TUBE, segmentLength),
			CFrame.lookAt(position, position + tangent),
			RIM_COLOR
		)
		segment.CustomPhysicalProperties = RIM_PHYSICS
	end

	-- Bracket joining the rim to the backboard. Purely visual, so it doesn't collide.
	local bracketLength = Court.RIM_TO_BACKBOARD - Court.RIM_INNER_RADIUS - Court.RIM_TUBE
	local bracket = makePart(
		rim,
		"Bracket",
		Vector3.new(0.3, 0.1, bracketLength),
		CFrame.new(0, center.Y - 0.1, -(Court.RIM_TO_BACKBOARD - bracketLength / 2)),
		RIM_COLOR
	)
	bracket.CanCollide = false

	rim.Parent = parent
end

-- The backboard, plus a pole behind it with an arm reaching forward to hold it up.
local function buildBackboard(parent: Instance)
	local size = Court.BACKBOARD_SIZE
	local faceZ = -Court.RIM_TO_BACKBOARD -- z of the backboard's front face (the rim is at z = 0)
	local backboard = makePart(
		parent,
		"Backboard",
		size,
		CFrame.new(0, Court.BACKBOARD_BOTTOM + size.Y / 2, faceZ - size.Z / 2),
		BACKBOARD_COLOR
	)
	backboard.Transparency = BACKBOARD_TRANSPARENCY
	backboard.CustomPhysicalProperties = BACKBOARD_PHYSICS

	local poleZ = faceZ - size.Z - Court.STANCHION_OFFSET -- pole stands behind the backboard
	local armY = Court.BACKBOARD_BOTTOM + size.Y / 2 -- arm meets the backboard's middle
	local poleHeight = armY + 0.5
	makePart(parent, "Pole", Vector3.new(0.6, poleHeight, 0.6), CFrame.new(0, poleHeight / 2, poleZ), STEEL_COLOR)
	local armLength = Court.STANCHION_OFFSET
	makePart(parent, "Arm", Vector3.new(0.4, 0.4, armLength), CFrame.new(0, armY, poleZ + armLength / 2), STEEL_COLOR)
end

-- An invisible spawn pad in front of the rim. Players spawn on it facing the rim.
local function buildSpawn(parent: Instance)
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "Spawn"
	spawnLocation.Size = Vector3.new(4, 0.2, 4)
	local position = Vector3.new(0, 0.1, Court.SPAWN_DISTANCE)
	-- Characters spawn facing the way the pad faces, so point it at the rim.
	spawnLocation.CFrame = CFrame.lookAt(position, Vector3.new(0, 0.1, 0))
	spawnLocation.Anchored = true
	spawnLocation.CanCollide = false
	spawnLocation.Transparency = 1
	spawnLocation.Neutral = true -- anyone can spawn here, regardless of team
	spawnLocation.Duration = 0 -- no spawn force field
	spawnLocation.Parent = parent
end

-- Builds everything into a Workspace.Hoop model, replacing an old one if it exists.
function HoopBuilder.build(): Model
	local existing = workspace:FindFirstChild("Hoop")
	if existing then
		existing:Destroy()
	end

	local hoop = Instance.new("Model")
	hoop.Name = "Hoop"

	-- The floor's top surface sits at y = 0, so it's centred half its thickness below.
	local floor = makePart(
		hoop,
		"Floor",
		Court.FLOOR_SIZE,
		CFrame.new(0, -Court.FLOOR_SIZE.Y / 2, Court.FLOOR_CENTER_Z),
		FLOOR_COLOR
	)
	floor.CustomPhysicalProperties = FLOOR_PHYSICS

	buildBackboard(hoop)
	buildRim(hoop)
	buildSpawn(hoop)

	hoop.Parent = workspace
	return hoop
end

return HoopBuilder
