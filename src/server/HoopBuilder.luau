--!strict
-- Builds the test setup: a plain floor to stand on, a backboard, a rim and a support pole.
-- Everything is anchored, shadowless SmoothPlastic so the scene costs as little as possible.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Court = require(ReplicatedStorage.Shared.Config.Court)

local HoopBuilder = {}

local FLOOR_COLOR = Color3.fromRGB(190, 145, 95)
local STEEL_COLOR = Color3.fromRGB(70, 74, 82)
local RIM_COLOR = Color3.fromRGB(230, 90, 30)

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function buildRim(parent: Instance)
	local rim = Instance.new("Model")
	rim.Name = "Rim"

	-- The ring is a loop of short blocks so the ball can physically drop through the middle
	-- and bounce off the edge.
	local center = Court.RIM_POSITION
	local radius = Court.RIM_INNER_RADIUS + Court.RIM_TUBE / 2
	local segmentLength = 2 * math.pi * radius / Court.RIM_SEGMENTS * 1.05
	for i = 1, Court.RIM_SEGMENTS do
		local angle = (i / Court.RIM_SEGMENTS) * 2 * math.pi
		local position = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local segment = makePart(
			rim,
			"Segment",
			Vector3.new(Court.RIM_TUBE, Court.RIM_TUBE, segmentLength),
			CFrame.lookAt(position, position + tangent),
			RIM_COLOR
		)
		segment.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.45, 1, 1)
	end

	-- Bracket joining the rim to the backboard. Cosmetic, so it doesn't collide.
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

local function buildBackboard(parent: Instance)
	local size = Court.BACKBOARD_SIZE
	local faceZ = -Court.RIM_TO_BACKBOARD
	local backboard = makePart(
		parent,
		"Backboard",
		size,
		CFrame.new(0, Court.BACKBOARD_BOTTOM + size.Y / 2, faceZ - size.Z / 2),
		Color3.fromRGB(235, 240, 245)
	)
	backboard.Transparency = 0.35
	backboard.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.6, 1, 1)

	-- Pole behind the backboard plus an arm reaching forward to it.
	local poleZ = faceZ - size.Z - Court.STANCHION_OFFSET
	local armY = Court.BACKBOARD_BOTTOM + size.Y / 2
	local poleHeight = armY + 0.5
	makePart(parent, "Pole", Vector3.new(0.6, poleHeight, 0.6), CFrame.new(0, poleHeight / 2, poleZ), STEEL_COLOR)
	local armLength = Court.STANCHION_OFFSET
	makePart(parent, "Arm", Vector3.new(0.4, 0.4, armLength), CFrame.new(0, armY, poleZ + armLength / 2), STEEL_COLOR)
end

local function buildSpawn(parent: Instance)
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "Spawn"
	spawnLocation.Size = Vector3.new(4, 0.2, 4)
	local position = Vector3.new(0, 0.1, Court.SPAWN_DISTANCE)
	-- Characters spawn facing the spawn's look direction, so face the rim.
	spawnLocation.CFrame = CFrame.lookAt(position, Vector3.new(0, 0.1, 0))
	spawnLocation.Anchored = true
	spawnLocation.CanCollide = false
	spawnLocation.Transparency = 1
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Parent = parent
end

function HoopBuilder.build(): Model
	local existing = workspace:FindFirstChild("Hoop")
	if existing then
		existing:Destroy()
	end

	local hoop = Instance.new("Model")
	hoop.Name = "Hoop"

	local floor = makePart(
		hoop,
		"Floor",
		Court.FLOOR_SIZE,
		CFrame.new(0, -Court.FLOOR_SIZE.Y / 2, Court.FLOOR_CENTER_Z),
		FLOOR_COLOR
	)
	floor.CustomPhysicalProperties = PhysicalProperties.new(1, 0.5, 0.6, 1, 1)

	buildBackboard(hoop)
	buildRim(hoop)
	buildSpawn(hoop)

	hoop.Parent = workspace
	return hoop
end

return HoopBuilder
