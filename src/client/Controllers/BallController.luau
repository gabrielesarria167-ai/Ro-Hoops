--!strict
-- BALL CONTROLLER
-- Owns the test ball and decides makes and misses. The ball is in one of three modes:
--   Dribble – bouncing beside the player (positioned by code, not physics)
--   Held    – rising along a smooth curve from the dribble to the set point while E is held
--   Flight  – a shot in the air
--
-- How a shot flies: the ball follows its exact arc in code, then switches to real physics
-- just before the hoop so the rim and backboard decide close calls. Flying it in code
-- matters: Roblox moves a lone ball in 1/60 s steps, which makes it fall ~0.3 studs short
-- of the planned arc over a jump shot – enough to turn a perfect release into front rim.
-- A shot counts as made when the ball's centre passes down through the rim circle.
--
-- The ball only exists on this player's computer. That's fine for solo testing; it will
-- move to the server once there are opponents. Tuning values: src/shared/Config/Ball.luau
-- (size, bounce, dribble) and src/shared/Config/Motion.luau (the gather path).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ball = require(ReplicatedStorage.Shared.Config.Ball)
local Court = require(ReplicatedStorage.Shared.Config.Court)
local Motion = require(ReplicatedStorage.Shared.Config.Motion)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local MovementController = require(script.Parent.MovementController)

type Mode = "Dribble" | "Held" | "Flight"

-- Everything about the shot currently in the air.
type Flight = {
	origin: Vector3, -- where the ball was released
	launchVelocity: Vector3, -- its velocity at release, studs/s
	gravity: number, -- downward pull used for the arc, studs/s²
	scripted: boolean, -- true while code flies the ball; false once physics has taken over
	previous: Vector3, -- ball position last frame (to detect passing through the rim)
	startedAt: number, -- clock time of the release, seconds
	resolved: boolean, -- true once the shot has been decided as made or missed
	onResolved: (made: boolean) -> (), -- called once with the result (ShotController updates the HUD)
}

local BallController = {}

local ball: Part -- the ball part itself, created in start()
local mode: Mode = "Dribble" -- what the ball is doing right now
local dribblePhase = 0 -- 0 to 1 through the current bounce: 0 and 1 = on the floor, 0.5 = top
local flight: Flight? = nil -- the shot in the air, or nil
local launchedAt = 0 -- clock time of the last release (ArmController times the follow-through from it)

-- The gather (Held mode): the ball curves from where it was in the dribble to the set point.
local gatherStartedAt = 0 -- clock time when E was pressed
local gatherDuration = 1 -- seconds until the ball reaches the set point (= the perfect release moment)
local gatherFrom = Vector3.zero -- ball position when E was pressed, relative to the hips
-- Increased whenever a pending "give the ball back" timer should be cancelled; a timer
-- only fires if the counter hasn't changed since it was started.
local returnToken = 0

-- Creates the ball. It starts anchored (frozen in place) because code positions it.
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

-- Switches a shot from the scripted arc to real physics at `position` with `velocity`.
local function handToPhysics(current: Flight, position: Vector3, velocity: Vector3)
	current.scripted = false
	ball.CFrame = CFrame.new(position)
	ball.CustomPhysicalProperties = PhysicalProperties.new(Ball.DENSITY, Ball.FRICTION, Ball.ELASTICITY, 1, 1)
	-- Set again here in case the group hadn't reached this client when the ball was created.
	ball.CollisionGroup = Ball.COLLISION_GROUP
	ball.Anchored = false
	ball.CanCollide = true
	ball.AssemblyLinearVelocity = velocity

	-- Backspin: spin around the axis that points sideways relative to the shot.
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	ball.AssemblyAngularVelocity = if flat.Magnitude > 1e-3
		then flat.Unit:Cross(Vector3.yAxis) * Ball.BACKSPIN
		else Vector3.zero
end

-- Moves the ball along its exact arc for this frame, or hands it to physics near the hoop.
local function fly(current: Flight)
	local t = os.clock() - current.startedAt -- seconds since release
	local gravity = Vector3.yAxis * current.gravity
	-- Standard projectile motion: start + velocity × time − ½ × gravity × time².
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

-- Converts a Motion-config offset (right, up, forward) to Roblox's object space, where
-- forward is -Z.
local function toObjectSpace(offset: Vector3): Vector3
	return Vector3.new(offset.X, offset.Y, -offset.Z)
end

-- Where the ball is during the gather. It follows a curve from `gatherFrom`, bending
-- toward the pocket (chest), ending at the set point, all relative to the hips so it moves
-- and turns with the player. Smoothstep timing makes it start gently, speed up, then
-- settle into the set point right at the perfect release moment.
local function gatherPosition(rootCFrame: CFrame): Vector3
	local p = math.clamp((os.clock() - gatherStartedAt) / gatherDuration, 0, 1)
	local t = p * p * (3 - 2 * p) -- smoothstep: eases in and out
	local u = 1 - t
	-- Quadratic Bezier curve: start → (pulled toward pocket) → set point.
	local pocket = toObjectSpace(Motion.GATHER_POCKET)
	local setPoint = toObjectSpace(Motion.SET_POINT)
	local localPosition = gatherFrom * (u * u) + pocket * (2 * u * t) + setPoint * (t * t)
	return rootCFrame:PointToWorldSpace(localPosition)
end

-- Runs every frame: positions the ball for the current mode. `dt` = seconds since last frame.
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

	local rootCFrame = parts.root.CFrame -- the character's hip position and facing
	if mode == "Held" then
		ball.CFrame = CFrame.new(gatherPosition(rootCFrame))
		return
	end

	-- Dribble: one bounce per trip of dribblePhase from 0 to 1. Moving faster bounces faster.
	local speed = MovementController.getVelocity().Magnitude
	dribblePhase = (dribblePhase + dt * (Ball.DRIBBLE_RATE + speed * Ball.DRIBBLE_RATE_PER_SPEED)) % 1
	local bounce = math.sin(dribblePhase * math.pi) -- 0 on the floor, 1 at the top
	local floorY = rootCFrame.Position.Y - parts.humanoid.HipHeight - parts.root.Size.Y / 2
	local beside = rootCFrame.Position
		+ rootCFrame.RightVector * Ball.DRIBBLE_SIDE
		+ rootCFrame.LookVector * Ball.DRIBBLE_FORWARD
	ball.CFrame = CFrame.new(beside.X, floorY + Ball.RADIUS + bounce * Ball.DRIBBLE_HEIGHT, beside.Z)
end

-- Decides the shot (once) and schedules the ball's return to the player.
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

-- Runs every frame after physics: watches the shot in the air for a make or a miss.
local function track()
	local current = flight
	if not current or current.resolved then
		return
	end

	local position = ball.Position
	local previous = current.previous
	current.previous = position

	-- MAKE: between last frame and this one, the ball dropped through the rim's height.
	-- Work out exactly where it crossed and check that point is inside the rim circle.
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

	-- MISS: the ball is falling well below the rim, or the shot took too long.
	local fallingBelowRim = position.Y < previous.Y and position.Y < rim.Y - Ball.MISS_DEPTH
	if fallingBelowRim or os.clock() - current.startedAt > Ball.SHOT_TIMEOUT then
		resolve(current, false)
	end
end

-- True if the player has the ball (it isn't in the air).
function BallController.hasBall(): boolean
	return mode ~= "Flight"
end

-- Where the ball is right now.
function BallController.getPosition(): Vector3
	return ball.Position
end

-- What the ball is doing: "Dribble", "Held" or "Flight".
function BallController.getMode(): Mode
	return mode
end

-- Clock time of the most recent release.
function BallController.getLaunchTime(): number
	return launchedAt
end

-- Starts the gather: the ball rises from the dribble and reaches the set point after
-- `duration` seconds (ShotController passes the time of the perfect release).
function BallController.hold(duration: number)
	if mode ~= "Dribble" then
		return
	end
	local parts = CharacterRef.get()
	if parts then
		gatherFrom = parts.root.CFrame:PointToObjectSpace(ball.Position)
	end
	gatherStartedAt = os.clock()
	gatherDuration = math.max(duration, 0.05)
	mode = "Held"
end

-- Shoots the ball from where it is.
--   velocity    launch velocity, studs/s (solved by ShotMath.launchVelocity)
--   gravity     downward pull, studs/s² (Workspace.Gravity)
--   onResolved  called once with true (made) or false (missed)
function BallController.launch(velocity: Vector3, gravity: number, onResolved: (made: boolean) -> ())
	mode = "Flight"
	launchedAt = os.clock()
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

-- Puts the ball back in the player's hands immediately.
function BallController.giveBack()
	returnToken += 1 -- cancels any pending return timer
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
	-- Positioning runs before each frame is drawn; make/miss tracking runs after physics.
	RunService:BindToRenderStep("RoHoopsBall", Enum.RenderPriority.Character.Value + 1, update)
	RunService.Heartbeat:Connect(track)
end

return BallController
