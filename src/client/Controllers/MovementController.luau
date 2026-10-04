--!strict
-- Drives the Humanoid with our own acceleration curve. Each frame the planar velocity eases
-- toward the input target (MovementMath.stepVelocity), then the Humanoid is told to move in
-- that direction at exactly that speed. The Humanoid keeps handling collision and stepping,
-- but its near-instant acceleration is replaced by ours.
--
-- Input is camera-relative: W/up always moves up the screen, toward the rim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Movement = require(ReplicatedStorage.Shared.Config.Movement)
local MovementMath = require(ReplicatedStorage.Shared.MovementMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local InputController = require(script.Parent.InputController)

local MovementController = {}

local velocity = Vector3.zero
local override: Vector3? = nil

local function screenAxes(): (Vector3, Vector3)
	local look = workspace.CurrentCamera.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 1e-3 then
		forward = -Vector3.zAxis
	else
		forward = forward.Unit
	end
	return forward, forward:Cross(Vector3.yAxis)
end

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
		local intent = InputController.getMoveIntent()
		local speed = if InputController.isRunning() then Movement.RUN_SPEED else Movement.WALK_SPEED
		local forward, right = screenAxes()
		local target = (right * intent.X + forward * intent.Y) * speed
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

	local speed = velocity.Magnitude
	if speed < Movement.STOP_EPSILON then
		parts.humanoid:Move(Vector3.zero, false)
	else
		parts.humanoid.WalkSpeed = speed
		parts.humanoid:Move(velocity / speed, false)
	end
end

function MovementController.getVelocity(): Vector3
	return velocity
end

-- While set, input is ignored and the player moves at exactly this velocity (used for
-- shot drift such as fadeaways and layup drives). Pass nil to hand control back.
function MovementController.setOverride(forcedVelocity: Vector3?)
	override = forcedVelocity
end

function MovementController.start()
	CharacterRef.onSpawn(function()
		velocity = Vector3.zero
		override = nil
	end)
	RunService:BindToRenderStep("RoHoopsMovement", Enum.RenderPriority.Input.Value + 1, step)
end

return MovementController
