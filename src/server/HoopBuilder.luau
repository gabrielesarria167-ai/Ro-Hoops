--!strict
-- HOOP BUILDER (runs on the server)
-- Builds the test setup when the game starts: an NBA half court (floor, paint and lines),
-- a glass backboard, a breakaway rim and net, a portable stanchion and the spawn point. All sizes and positions come
-- from src/shared/Config/Court.luau.
--
-- Everything is anchored (doesn't move) and shadowless, so the scene costs as little
-- performance as possible.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ball = require(ReplicatedStorage.Shared.Config.Ball)
local Court = require(ReplicatedStorage.Shared.Config.Court)

local HoopBuilder = {}

-- Colours (red, green, blue from 0 to 255).
local WOOD_COLOR = Color3.fromRGB(214, 168, 112) -- maple, inside the lines
local PAINT_COLOR = Color3.fromRGB(32, 58, 112) -- the key, and the apron outside the court
local LINE_COLOR = Color3.fromRGB(245, 245, 240)
local STEEL_COLOR = Color3.fromRGB(46, 48, 54) -- the stanchion's column, boom and frames
local PAD_COLOR = Color3.fromRGB(22, 30, 52) -- padding on the base, column and board
local RIM_COLOR = Color3.fromRGB(230, 90, 30)
local NET_COLOR = Color3.fromRGB(245, 245, 240)
local GLASS_COLOR = Color3.fromRGB(205, 225, 235)
local GLASS_TRANSPARENCY = 0.6 -- 0 = solid, 1 = invisible
local FRAME_COLOR = Color3.fromRGB(150, 155, 162) -- brushed aluminium round the glass
local CLOCK_COLOR = Color3.fromRGB(18, 18, 20)

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

-- Turns `part` into looks only: no collisions, no raycast hits, no touch events.
local function lookOnly(part: Part): Part
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- A round rod (a cylinder) from `a` to `b`, `thickness` studs across. Stretched by
-- `overlap` studs at each end so rods meeting at an angle leave no gap.
local function makeRod(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	thickness: number,
	color: Color3,
	overlap: number?
): Part
	local length = (b - a).Magnitude + 2 * (overlap or 0)
	-- A cylinder's length runs along its X axis; turn X to point from a to b.
	local cframe = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	local rod = makePart(parent, name, Vector3.new(length, thickness, thickness), cframe, color)
	rod.Shape = Enum.PartType.Cylinder
	return rod
end

-- A point on a flat circle round `center`, at `angle` radians from +X toward +Z.
local function around(center: Vector3, radius: number, angle: number): Vector3
	return center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
end

-- An NBA-style breakaway rim, from real references: an 18" ring of 5/8" steel rod, its
-- back 6" off the board on a bolted plate with the spring housing underneath, 12 welded
-- net hooks, and an 18" white cord net. Only the ring collides (with the ball, not
-- players, see CollisionGroups); the mount, hooks and net are looks only.
local function buildRim(parent: Instance)
	local rim = Instance.new("Model")
	rim.Name = "Rim"

	local center = Court.RIM_POSITION
	local tube = Court.RIM_TUBE
	local radius = Court.RIM_INNER_RADIUS + tube / 2 -- circle through the middle of the rod
	local inch = Court.ft(1 / 12) * Court.EQUIPMENT_SCALE -- the mount's sizes are real inches, scaled with the rim

	-- The ring: short rods round the circle.
	local segments = Court.RIM_SEGMENTS
	for i = 1, segments do
		local a = around(center, radius, (i - 1) / segments * 2 * math.pi)
		local b = around(center, radius, i / segments * 2 * math.pi)
		local segment = makeRod(rim, "Segment", a, b, tube, RIM_COLOR, tube / 2)
		segment.CustomPhysicalProperties = RIM_PHYSICS
		segment.CollisionGroup = Ball.RIM_COLLISION_GROUP
	end

	-- The mount, between the board's face (z = faceZ) and the back of the ring.
	local faceZ = -Court.RIM_TO_BACKBOARD
	local top = center.Y - tube / 2 -- the ring sits on top of the mount
	-- Mounting plate bolted to the board, its top a little above the ring.
	local plate = Court.RIM_PLATE
	local plateDepth = 0.75 * inch
	local plateTop = top + inch
	lookOnly(
		makePart(
			rim,
			"MountPlate",
			Vector3.new(plate, plate, plateDepth),
			CFrame.new(0, plateTop - plate / 2, faceZ + plateDepth / 2),
			RIM_COLOR
		)
	)
	-- Spring housing (the breakaway hinge): a box from the plate to just under the ring's back.
	local housing = Vector3.new(4 * inch, 2.5 * inch, -radius + 1.5 * inch - faceZ)
	lookOnly(
		makePart(rim, "SpringHousing", housing, CFrame.new(0, top - housing.Y / 2, faceZ + housing.Z / 2), RIM_COLOR)
	)
	-- Flat flange on top of the housing that the ring is welded to.
	local flange = Vector3.new(6 * inch, 0.3 * inch, housing.Z)
	lookOnly(makePart(rim, "Flange", flange, CFrame.new(0, top - flange.Y / 2, faceZ + flange.Z / 2), RIM_COLOR))
	-- Two braces from the sides of the ring (35° round from the back) down to the bottom
	-- corners of the plate.
	for _, side in { -1, 1 } do
		local onRing = around(center, radius, -math.pi / 2 + side * math.rad(35)) - Vector3.yAxis * tube / 2
		local onPlate = Vector3.new(side * (plate / 2 - inch), plateTop - plate + inch, faceZ + plateDepth)
		lookOnly(makeRod(rim, "Brace", onRing, onPlate, 0.6 * inch, RIM_COLOR, 0.3 * inch))
	end

	-- Net hooks: short tabs under the ring, evenly spaced, straddling the back.
	local loops = Court.NET_LOOPS
	local hookLength = 1.25 * inch
	for i = 0, loops - 1 do
		local at = around(center, radius, (i + 0.5) / loops * 2 * math.pi)
		lookOnly(makeRod(rim, "NetHook", at, at - Vector3.yAxis * (tube / 2 + hookLength), 0.35 * inch, RIM_COLOR))
	end

	-- The net: a diamond mesh. Knots sit on rings tapering from the hooks to the bottom;
	-- each row is turned half a hook further round, so every knot ties to the two knots
	-- below it.
	local rows = Court.NET_ROWS
	local netTop = top - hookLength
	local cord = 0.3 * inch
	local function knot(row: number, i: number): Vector3
		local t = row / rows -- 0 at the hooks, 1 at the bottom
		local ringRadius = radius + (Court.NET_BOTTOM_RADIUS - radius) * t
		local angle = (i + 0.5 + row / 2) / loops * 2 * math.pi
		return around(Vector3.new(center.X, netTop - Court.NET_LENGTH * t, center.Z), ringRadius, angle)
	end
	for row = 0, rows - 1 do
		for i = 0, loops - 1 do
			local from = knot(row, i)
			lookOnly(makeRod(rim, "NetCord", from, knot(row + 1, i), cord, NET_COLOR, cord / 2))
			lookOnly(makeRod(rim, "NetCord", from, knot(row + 1, i - 1), cord, NET_COLOR, cord / 2))
		end
	end

	rim.Parent = parent
end

-- The court's markings lie on the floor in thin layers, each a little higher than the one
-- below so they never flicker through each other: wood over the apron, paint over the
-- wood, lines over the paint. They're only paint: no collisions and no raycast hits, so
-- the ball and feet still meet the floor itself (y = 0).
local LAYER = 0.02 -- studs between layers

local function makeMarking(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	return lookOnly(makePart(parent, name, size, cframe, color))
end

-- A rectangle outline of 2" white lines on the backboard's face (looks only), `width` ×
-- `height` from x = -width/2..width/2 and y = bottom..bottom+height, at depth `z`.
local function makeBoardOutline(
	parent: Instance,
	name: string,
	width: number,
	height: number,
	bottom: number,
	z: number
)
	local w = Court.LINE_WIDTH
	local middleY, top = bottom + height / 2, bottom + height
	for _, edge in
		{
			{ Vector3.new(width + w, w, w), Vector3.new(0, bottom, z) },
			{ Vector3.new(width + w, w, w), Vector3.new(0, top, z) },
			{ Vector3.new(w, height + w, w), Vector3.new(-width / 2, middleY, z) },
			{ Vector3.new(w, height + w, w), Vector3.new(width / 2, middleY, z) },
		}
	do
		makeMarking(parent, name, edge[1], CFrame.new(edge[2]), LINE_COLOR)
	end
end

-- An NBA-style glass backboard: a 72" × 42" × 1/2" tempered glass board in a slim
-- aluminium frame, with a 2" white border and the 24" × 18" shooter's square, padding
-- along the bottom edge and the lower 15" of the sides, and a shot clock on top.
local function buildBackboard(parent: Instance)
	local size = Court.BACKBOARD_SIZE
	local faceZ = -Court.RIM_TO_BACKBOARD -- z of the glass's front face (the rim is at z = 0)
	local bottom, top = Court.BACKBOARD_BOTTOM, Court.BACKBOARD_BOTTOM + size.Y
	local middleY = (bottom + top) / 2
	local glassZ = faceZ - size.Z / 2 -- the glass's centre plane

	-- The glass: the only part of the board the ball bounces off.
	local glass = makePart(parent, "Backboard", size, CFrame.new(0, middleY, glassZ), GLASS_COLOR)
	glass.Material = Enum.Material.Glass
	glass.Transparency = GLASS_TRANSPARENCY
	glass.CustomPhysicalProperties = BACKBOARD_PHYSICS

	-- Aluminium frame round the edge.
	local frame = Court.BACKBOARD_FRAME
	local frameDepth = size.Z + 2 * frame -- wraps a little round the front and back of the glass
	for _, bar in
		{
			{ Vector3.new(size.X + 2 * frame, frame, frameDepth), Vector3.new(0, bottom - frame / 2, glassZ) },
			{ Vector3.new(size.X + 2 * frame, frame, frameDepth), Vector3.new(0, top + frame / 2, glassZ) },
			{ Vector3.new(frame, size.Y, frameDepth), Vector3.new(-(size.X + frame) / 2, middleY, glassZ) },
			{ Vector3.new(frame, size.Y, frameDepth), Vector3.new((size.X + frame) / 2, middleY, glassZ) },
		}
	do
		lookOnly(makePart(parent, "Frame", bar[1], CFrame.new(bar[2]), FRAME_COLOR))
	end

	-- Painted lines, just in front of the glass so they don't flicker.
	local paintZ = faceZ + 0.01
	local inset = Court.LINE_WIDTH -- the border sits just inside the frame
	makeBoardOutline(parent, "Border", size.X - 2 * inset, size.Y - 2 * inset, bottom + inset, paintZ)
	local square = Court.SHOOTER_SQUARE
	makeBoardOutline(parent, "ShooterSquare", square.X, square.Y, Court.RIM_POSITION.Y, paintZ)

	-- Padding: wraps the bottom edge (and the bottom of the frame) and the lower 15" of
	-- each side. Solid, so a ball hitting it bounces off.
	local pad = Court.BACKBOARD_PAD
	local padDepth = frameDepth + 2 * pad
	local outerWidth = size.X + 2 * frame
	local padBottom = bottom - frame - pad
	local bottomPad = Vector3.new(outerWidth + 2 * pad, pad + frame + Court.ft(3 / 12), padDepth)
	makePart(parent, "Padding", bottomPad, CFrame.new(0, padBottom + bottomPad.Y / 2, glassZ), PAD_COLOR)
	local sideHeight = Court.BACKBOARD_SIDE_PAD
	for _, side in { -1, 1 } do
		makePart(
			parent,
			"Padding",
			Vector3.new(pad, sideHeight, padDepth),
			CFrame.new(side * (outerWidth + pad) / 2, padBottom + sideHeight / 2, glassZ),
			PAD_COLOR
		)
	end

	-- Shot clock: a black box on top of the board, showing 24 toward the court.
	local clockSize = Vector3.new(Court.ft(30 / 12), Court.ft(10 / 12), Court.ft(5 / 12))
	local clock = lookOnly(
		makePart(
			parent,
			"ShotClock",
			clockSize,
			CFrame.new(0, top + frame + clockSize.Y / 2, glassZ - clockSize.Z / 2 + frameDepth / 2),
			CLOCK_COLOR
		)
	)
	local face = Instance.new("SurfaceGui")
	face.Face = Enum.NormalId.Back -- +Z, toward the court
	face.CanvasSize = Vector2.new(300, 100)
	local digits = Instance.new("TextLabel")
	digits.Size = UDim2.fromScale(1, 1)
	digits.BackgroundTransparency = 1
	digits.Text = "24"
	digits.Font = Enum.Font.Code
	digits.TextScaled = true
	digits.TextColor3 = Color3.fromRGB(255, 40, 30)
	digits.Parent = face
	face.Parent = clock
end

-- The support: an NBA-style portable stanchion behind the baseline. A heavy padded base,
-- a padded steel column leaning slightly toward the court, a boom reaching forward to the
-- back of the board with a diagonal brace under it (a truss), and an H-frame behind the
-- glass that the boom bolts to. Sizes are typical arena-system values (spec sheets: an 8'
-- boom, 39" base frame height, 4" front / 2" side padding). The base and column are solid.
local function buildStanchion(parent: Instance)
	local board = Court.BACKBOARD_SIZE
	local faceZ = -Court.RIM_TO_BACKBOARD
	local backZ = faceZ - board.Z - Court.BACKBOARD_FRAME -- just behind the glass and its frame
	local middleY = Court.BACKBOARD_BOTTOM + board.Y / 2
	local steel = Court.ft(6 / 12) -- the column and boom are 6" square steel tube
	local tube = Court.ft(2 / 12) -- the board's H-frame and the brace are 2" tube

	-- Base: a padded box on the floor, its front STANCHION_EXTENSION behind the board.
	local base = Court.STANCHION_BASE
	local baseFront = faceZ - Court.STANCHION_EXTENSION
	makePart(parent, "Base", base, CFrame.new(0, base.Y / 2, baseFront - base.Z / 2), PAD_COLOR)

	-- Column: from the top of the base near its front, up to the boom's height, leaning a
	-- little toward the court.
	local columnFoot = Vector3.new(0, base.Y, baseFront - Court.ft(1.5))
	local elbow = Vector3.new(0, middleY, baseFront - Court.ft(0.5))
	local column = makeRod(parent, "Column", columnFoot, elbow, steel, STEEL_COLOR, steel / 2)
	column.Shape = Enum.PartType.Block
	-- Its padding: a thicker wrap over the lower part, up to COLUMN_PAD_HEIGHT.
	local padTop = columnFoot:Lerp(elbow, (Court.COLUMN_PAD_HEIGHT - base.Y) / (elbow.Y - base.Y))
	local columnPad = makeRod(parent, "ColumnPad", columnFoot, padTop, steel + 2 * Court.STANCHION_PAD, PAD_COLOR)
	columnPad.Shape = Enum.PartType.Block

	-- Boom: straight forward from the column to the back of the board.
	local boomEnd = Vector3.new(0, middleY, backZ - tube)
	local boom = makeRod(parent, "Boom", elbow, boomEnd, steel, STEEL_COLOR, steel / 2)
	boom.Shape = Enum.PartType.Block
	-- Brace: from the column, below the padding's top, up to the boom near the board.
	local braceFoot = columnFoot:Lerp(elbow, 0.45)
	local braceTop = elbow:Lerp(boomEnd, 0.7) - Vector3.yAxis * steel / 2
	makeRod(parent, "Brace", braceFoot, braceTop, tube * 1.5, STEEL_COLOR)

	-- H-frame on the back of the glass: two uprights and a cross bar the boom meets.
	local frameZ = backZ - tube / 2
	for _, side in { -1, 1 } do
		lookOnly(
			makePart(
				parent,
				"BoardFrame",
				Vector3.new(tube, board.Y * 0.85, tube),
				CFrame.new(side * board.X * 0.3, middleY, frameZ),
				STEEL_COLOR
			)
		)
	end
	lookOnly(
		makePart(
			parent,
			"BoardFrame",
			Vector3.new(board.X * 0.6 + tube, tube, tube),
			CFrame.new(0, middleY, frameZ),
			STEEL_COLOR
		)
	)
end

-- A flat rectangle on layer `layer`, from x1..x2 and z1..z2.
local function makePatch(
	parent: Instance,
	name: string,
	x1: number,
	x2: number,
	z1: number,
	z2: number,
	layer: number,
	color: Color3
): Part
	local height = layer * LAYER
	return makeMarking(
		parent,
		name,
		Vector3.new(math.abs(x2 - x1), height, math.abs(z2 - z1)),
		CFrame.new((x1 + x2) / 2, height / 2, (z1 + z2) / 2),
		color
	)
end

-- A straight line on the floor between two flat points (x, z). Stretched by half a line
-- width at each end so corners close up.
local function makeLine(parent: Instance, from: Vector2, to: Vector2)
	local height = 3 * LAYER
	local a, b = Vector3.new(from.X, height / 2, from.Y), Vector3.new(to.X, height / 2, to.Y)
	makeMarking(
		parent,
		"Line",
		Vector3.new(Court.LINE_WIDTH, height, (b - a).Magnitude + Court.LINE_WIDTH),
		CFrame.lookAt((a + b) / 2, b),
		LINE_COLOR
	)
end

-- A point `radius` from `center` (x, z), at `angle` radians round from +Z toward +X.
local function onCircle(center: Vector2, radius: number, angle: number): Vector2
	return center + Vector2.new(math.sin(angle), math.cos(angle)) * radius
end

-- An arc of a circle, drawn as short straight pieces (about one per foot). `dashed` =
-- leave every other piece out.
local function makeArc(
	parent: Instance,
	center: Vector2,
	radius: number,
	fromDeg: number,
	toDeg: number,
	dashed: boolean?
)
	local from, to = math.rad(fromDeg), math.rad(toDeg)
	local pieces = math.max(math.ceil(radius * math.abs(to - from) / Court.ft(1)), 2)
	for i = 1, pieces do
		if not dashed or i % 2 == 1 then
			local a = from + (to - from) * (i - 1) / pieces
			local b = from + (to - from) * i / pieces
			makeLine(parent, onCircle(center, radius, a), onCircle(center, radius, b))
		end
	end
end

-- The floor and every line of an NBA half court, in front of the rim (+Z).
local function buildCourt(parent: Instance)
	local court = Instance.new("Model")
	court.Name = "Court"

	local half = Court.COURT_WIDTH / 2
	local baseline, halfCourt = Court.BASELINE_Z, Court.HALF_COURT_Z
	local apron = Court.APRON
	local floorBack = baseline - Court.BASELINE_RUNOFF -- the floor reaches past the stanchion's base
	local lane = Court.LANE_WIDTH / 2
	local freeThrow = Court.FREE_THROW_Z

	-- The floor everything stands on: the whole area including the apron. Its top is y = 0.
	local floor = makePart(
		court,
		"Floor",
		Vector3.new(Court.COURT_WIDTH + 2 * apron, 1, halfCourt + apron - floorBack),
		CFrame.new(0, -0.5, (floorBack + halfCourt + apron) / 2),
		PAINT_COLOR
	)
	floor.CustomPhysicalProperties = FLOOR_PHYSICS
	local wood = makePatch(court, "Wood", -half, half, baseline, halfCourt, 1, WOOD_COLOR)
	wood.Material = Enum.Material.WoodPlanks
	makePatch(court, "Paint", -lane, lane, baseline, freeThrow, 2, PAINT_COLOR)

	-- Boundary: baseline, sidelines, half-court line.
	makeLine(court, Vector2.new(-half, baseline), Vector2.new(half, baseline))
	makeLine(court, Vector2.new(-half, baseline), Vector2.new(-half, halfCourt))
	makeLine(court, Vector2.new(half, baseline), Vector2.new(half, halfCourt))
	makeLine(court, Vector2.new(-half, halfCourt), Vector2.new(half, halfCourt))

	-- The key: lane lines and the free-throw line, then its circle (solid outside the key,
	-- dashed inside it).
	makeLine(court, Vector2.new(-lane, baseline), Vector2.new(-lane, freeThrow))
	makeLine(court, Vector2.new(lane, baseline), Vector2.new(lane, freeThrow))
	makeLine(court, Vector2.new(-lane, freeThrow), Vector2.new(lane, freeThrow))
	local freeThrowCenter = Vector2.new(0, freeThrow)
	makeArc(court, freeThrowCenter, Court.FREE_THROW_RADIUS, -90, 90)
	makeArc(court, freeThrowCenter, Court.FREE_THROW_RADIUS, 90, 270, true)

	-- Three-point line: straight in the corners until it meets the arc round the rim.
	local radius, cornerX = Court.THREE_POINT_RADIUS, Court.CORNER_THREE_X
	local cornerZ = math.sqrt(radius * radius - cornerX * cornerX) -- where the corner line meets the arc
	makeLine(court, Vector2.new(-cornerX, baseline), Vector2.new(-cornerX, cornerZ))
	makeLine(court, Vector2.new(cornerX, baseline), Vector2.new(cornerX, cornerZ))
	local cornerDeg = math.deg(math.asin(cornerX / radius))
	makeArc(court, Vector2.zero, radius, -cornerDeg, cornerDeg)

	-- Restricted area: a semicircle round the rim, its ends running straight back to the
	-- backboard.
	local restricted = Court.RESTRICTED_RADIUS
	makeArc(court, Vector2.zero, restricted, -90, 90)
	makeLine(court, Vector2.new(-restricted, 0), Vector2.new(-restricted, -Court.RIM_TO_BACKBOARD))
	makeLine(court, Vector2.new(restricted, 0), Vector2.new(restricted, -Court.RIM_TO_BACKBOARD))

	-- This half of the centre circles.
	makeArc(court, Vector2.new(0, halfCourt), Court.CENTER_CIRCLE_RADIUS, 90, 270)
	makeArc(court, Vector2.new(0, halfCourt), Court.CENTER_INNER_RADIUS, 90, 270)

	-- Small marks, mirrored on both sides (`side` = -1 left, +1 right). Mark positions in
	-- Court are measured from the baseline.
	local markLength = Court.MARK_LENGTH
	for _, side in { -1, 1 } do
		local laneX = side * lane
		local outside = side * (lane + markLength) -- lane space marks stick out of the lane
		local block = Court.LANE_BLOCK
		makePatch(court, "Block", laneX, outside, baseline + block[1], baseline + block[2], 3, LINE_COLOR)
		for _, z in Court.LANE_MARKS do
			makeLine(court, Vector2.new(laneX, baseline + z), Vector2.new(outside, baseline + z))
		end
		-- The lower defensive box: a hash 3 ft outside the lane at the baseline and 13 ft up.
		local boxX = side * (lane + Court.DEFENSIVE_BOX_OFFSET)
		makeLine(court, Vector2.new(boxX, baseline), Vector2.new(boxX, baseline + markLength))
		local boxTop = baseline + Court.DEFENSIVE_BOX_TOP
		makeLine(court, Vector2.new(boxX, boxTop), Vector2.new(boxX, boxTop + markLength))
		-- Throw-in hash on the sideline.
		local hashZ = baseline + Court.SIDELINE_HASH
		makeLine(court, Vector2.new(side * half, hashZ), Vector2.new(side * (half - Court.SIDELINE_HASH_LENGTH), hashZ))
	end

	court.Parent = parent
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

	buildCourt(hoop)
	buildBackboard(hoop)
	buildStanchion(hoop)
	buildRim(hoop)
	buildSpawn(hoop)

	hoop.Parent = workspace
	return hoop
end

return HoopBuilder
