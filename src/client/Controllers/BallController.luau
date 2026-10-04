--!strict
-- Owns the local test ball. While the player has it, the ball is anchored and positioned in
-- code (a simple dribble, or held overhead while gathering a shot).
--
-- A shot is flown along its exact parabola in code, then handed to the physics engine just
-- before it reaches the hoop so the rim and backboard decide the outcome. Flying it in code
-- matters: Roblox integrates a lone ball at 60 Hz, which makes it fall short of the analytic
-- arc by ~0.3 studs over a jump shot - enough to turn a perfect release into front rim.
-- A make is detected when the ball's center crosses down through the rim circle.
--
-- The ball only exists on this client. That's fine for single-player testing; ball state
-- will move to the server once possession and opponents exist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ball = require(ReplicatedStorage.Shared.Config.Ball)
local Court = require(ReplicatedStorage.Shared.Config.Court)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local MovementController = require(script.Parent.MovementController)

type Mode = "Dribble" | "Held" | "Flight"

type Flight = {
	origin: Vector3,
	launchVelocity: Vector3,
	gravity: number,
	scripted: boolean, -- true until the ball is handed to physics near the hoop
	previous: Vector3,
	startedAt: number,
	resolved: boolean,
	onResolved: (made: boolean) -> (),
}

local BallController = {}

local ball: Part
local mode: Mode = "Dribble"
local dribblePhase = 0
local flight: Flight? = nil
local returnToken = 0

local function createBall(): Part
	local part = Instance.new("Part")
	part.Name = "LocalBall"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * Ball.RADIUS * 2
	part.Color = Ball.COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.CollisionGroup = Ball.COLLISION_GROUP
	part.Parent = workspace
	return part
end

local function handToPhysics(current: Flight, position: Vector3, velocity: Vector3)
	current.scripted = false
	ball.CFrame = CFrame.new(position)
	ball.CustomPhysicalProperties = PhysicalProperties.new(Ball.DENSITY, Ball.FRICTION, Ball.ELASTICITY, 1, 1)
	-- Re-applied here because the group may not have replicated yet when the ball was created.
	ball.CollisionGroup = Ball.COLLISION_GROUP
	ball.Anchored = false
	ball.CanCollide = true
	ball.AssemblyLinearVelocity = velocity

	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	ball.AssemblyAngularVelocity = if flat.Magnitude > 1e-3
		then flat.Unit:Cross(Vector3.yAxis) * Ball.BACKSPIN
		else Vector3.zero
end

local function fly(current: Flight)
	local t = os.clock() - current.startedAt
	local gravity = Vector3.yAxis * current.gravity
	local position = current.origin + current.launchVelocity * t - gravity * (0.5 * t * t)
	local velocity = current.launchVelocity - gravity * t

	local rim = Court.RIM_POSITION
	local nearHoop = (position - rim).Magnitude <= Ball.HANDOFF_DISTANCE
	-- Way-off shots never get near the hoop; let physics take them as they come down.
	local comingDown = velocity.Y < 0 and position.Y <= rim.Y + 1
	if nearHoop or comingDown then
		handToPhysics(current, position, velocity)
	else
		ball.CFrame = CFrame.new(position)
	end
end

local function update(dt: number)
	if mode == "Flight" then
		local current = flight
		if current and current.scripted then
			fly(current)
		end
		return
	end
	local parts = CharacterRef.get()
	if not parts then
		return
	end

	local rootCFrame = parts.root.CFrame
	if mode == "Held" then
		ball.CFrame = CFrame.new(
			rootCFrame.Position + Vector3.yAxis * Ball.HOLD_HEIGHT + rootCFrame.LookVector * Ball.HOLD_FORWARD
		)
		return
	end

	-- One bounce per phase cycle: on the floor at 0 and 1, at the top at 0.5. Faster
	-- movement means a faster dribble.
	local speed = MovementController.getVelocity().Magnitude
	dribblePhase = (dribblePhase + dt * (Ball.DRIBBLE_RATE + speed * Ball.DRIBBLE_RATE_PER_SPEED)) % 1
	local bounce = math.sin(dribblePhase * math.pi)
	local floorY = rootCFrame.Position.Y - parts.humanoid.HipHeight - parts.root.Size.Y / 2
	local beside = rootCFrame.Position
		+ rootCFrame.RightVector * Ball.DRIBBLE_SIDE
		+ rootCFrame.LookVector * Ball.DRIBBLE_FORWARD
	ball.CFrame = CFrame.new(beside.X, floorY + Ball.RADIUS + bounce * Ball.DRIBBLE_HEIGHT, beside.Z)
end

local function resolve(current: Flight, made: boolean)
	if current.resolved then
		return
	end
	current.resolved = true
	current.onResolved(made)

	returnToken += 1
	local token = returnToken
	task.delay(Ball.RETURN_DELAY, function()
		if token == returnToken then
			BallController.giveBack()
		end
	end)
end

local function track()
	local current = flight
	if not current or current.resolved then
		return
	end

	local position = ball.Position
	local previous = current.previous
	current.previous = position

	local rim = Court.RIM_POSITION
	if previous.Y >= rim.Y and position.Y < rim.Y then
		local t = (previous.Y - rim.Y) / (previous.Y - position.Y)
		local crossing = previous:Lerp(position, t)
		local dx, dz = crossing.X - rim.X, crossing.Z - rim.Z
		if math.sqrt(dx * dx + dz * dz) < Court.RIM_INNER_RADIUS then
			resolve(current, true)
			return
		end
	end

	local fallingBelowRim = position.Y < previous.Y and position.Y < rim.Y - Ball.MISS_DEPTH
	if fallingBelowRim or os.clock() - current.startedAt > Ball.SHOT_TIMEOUT then
		resolve(current, false)
	end
end

function BallController.hasBall(): boolean
	return mode ~= "Flight"
end

function BallController.getPosition(): Vector3
	return ball.Position
end

-- Raise the ball overhead while a shot is gathered.
function BallController.hold()
	if mode == "Dribble" then
		mode = "Held"
	end
end

-- Shoot the ball from where it is with `velocity`, under `gravity` (studs/s², downward).
function BallController.launch(velocity: Vector3, gravity: number, onResolved: (made: boolean) -> ())
	mode = "Flight"
	local from = ball.Position
	flight = {
		origin = from,
		launchVelocity = velocity,
		gravity = gravity,
		scripted = true,
		previous = from,
		startedAt = os.clock(),
		resolved = false,
		onResolved = onResolved,
	}
end

-- Put the ball back in the player's hands immediately.
function BallController.giveBack()
	returnToken += 1
	flight = nil
	mode = "Dribble"
	ball.Anchored = true
	ball.CanCollide = false
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
end

function BallController.start()
	ball = createBall()
	CharacterRef.onSpawn(function()
		BallController.giveBack()
	end)
	RunService:BindToRenderStep("RoHoopsBall", Enum.RenderPriority.Character.Value + 1, update)
	RunService.Heartbeat:Connect(track)
end

return BallController
