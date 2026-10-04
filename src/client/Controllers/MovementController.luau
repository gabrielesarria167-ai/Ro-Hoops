--!strict
-- MOVEMENT CONTROLLER
-- Moves the character with our own acceleration curve. Every frame:
--   1. work out the velocity the player wants (keys × walk/run speed),
--   2. ease the current velocity toward it (MovementMath.stepVelocity),
--   3. tell the Humanoid to move in that direction at exactly that speed.
-- The Humanoid still handles collisions and stairs; we only replace its near-instant
-- acceleration with ours. Tuning values: src/shared/Config/Movement.luau.
--
-- Input is relative to the screen: W / up always moves up the screen, toward the rim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Movement = require(ReplicatedStorage.Shared.Config.Movement)
local MovementMath = require(ReplicatedStorage.Shared.MovementMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local InputController = require(script.Parent.InputController)

local MovementController = {}

-- The player's current flat velocity (y is always 0), studs/s. Other systems read it
-- through getVelocity(), e.g. to pick the shot type or speed up the dribble.
local velocity = Vector3.zero
-- When set, input is ignored and the player moves at exactly this velocity. Used by
-- ShotController for in-air drift (fadeaways, layup drives). nil = normal control.
local override: Vector3? = nil

-- Returns the screen's "up" and "right" directions flattened onto the floor, so key
-- presses map to on-screen directions no matter where the camera is.
local function screenAxes(): (Vector3, Vector3)
	local look = workspace.CurrentCamera.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 1e-3 then
		forward = -Vector3.zAxis -- camera looking straight down: assume "up" is toward the rim
	else
		forward = forward.Unit
	end
	return forward, forward:Cross(Vector3.yAxis)
end

-- Runs every frame before the camera updates. `dt` = seconds since the last frame.
local function step(dt: number)
	local parts = CharacterRef.get()
	if not parts or parts.humanoid.Health <= 0 then
		velocity = Vector3.zero
		return
	end

	local forcedVelocity = override
	if forcedVelocity then
		velocity = forcedVelocity
	else
		local intent = InputController.getMoveIntent() -- which keys are held
		local speed = if InputController.isRunning() then Movement.RUN_SPEED else Movement.WALK_SPEED
		local forward, right = screenAxes()
		local target = (right * intent.X + forward * intent.Y) * speed -- the velocity we want
		local vx, vz = MovementMath.stepVelocity(
			velocity.X,
			velocity.Z,
			target.X,
			target.Z,
			Movement.ACCELERATION,
			Movement.DECELERATION,
			Movement.TURN_ACCELERATION,
			dt
		)
		velocity = Vector3.new(vx, 0, vz)
	end

	-- Hand the result to the Humanoid: direction via Move(), speed via WalkSpeed.
	local speed = velocity.Magnitude
	if speed < Movement.STOP_EPSILON then
		parts.humanoid:Move(Vector3.zero, false)
	else
		parts.humanoid.WalkSpeed = speed
		parts.humanoid:Move(velocity / speed, false)
	end
end

-- The player's current flat velocity, studs/s.
function MovementController.getVelocity(): Vector3
	return velocity
end

-- Forces the player to move at `forcedVelocity`, ignoring input. Pass nil to give control
-- back to the player.
function MovementController.setOverride(forcedVelocity: Vector3?)
	override = forcedVelocity
end

function MovementController.start()
	CharacterRef.onSpawn(function()
		velocity = Vector3.zero
		override = nil
	end)
	-- "Input + 1" priority runs right after Roblox reads input, before the camera moves.
	RunService:BindToRenderStep("RoHoopsMovement", Enum.RenderPriority.Input.Value + 1, step)
end

return MovementController
