--!strict
-- `E` shooting and finishing. The shot type is chosen from the player's position and
-- movement when E goes down (ShotMath.classify): standing jump shot, pull-up, fadeaway,
-- step-back, side shot, layup or close shot. The player leaves the floor with that type's
-- drift, and holding E fills the timing meter. Releasing at the top of the meter is a
-- perfect release; the timing offset becomes an aim error, the ball is launched on a solved
-- arc, and physics plays it out against the rim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Court = require(ReplicatedStorage.Shared.Config.Court)
local Shooting = require(ReplicatedStorage.Shared.Config.Shooting)
local ShotMath = require(ReplicatedStorage.Shared.ShotMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local BallController = require(script.Parent.BallController)
local HudController = require(script.Parent.HudController)
local InputController = require(script.Parent.InputController)
local MovementController = require(script.Parent.MovementController)

type Phase = "Ready" | "Gathering" | "Airborne"

type ActiveShot = {
	config: Shooting.ShotTypeConfig,
	startedAt: number,
}

local SHOOT_KEY = Enum.KeyCode.E
local MIN_AIR_TIME = 0.2 -- ignore "landed" readings right after takeoff

local ShotController = {}

local phase: Phase = "Ready"
local shot: ActiveShot? = nil
local random = Random.new()

-- Horizontal distance to the rim, plus unit vectors toward it and to its right.
local function rimAxes(position: Vector3): (number, Vector3, Vector3)
	local offset = Court.RIM_POSITION - position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	local toward = if distance > 1e-3 then flat / distance else -Vector3.zAxis
	return distance, toward, toward:Cross(Vector3.yAxis)
end

local function begin()
	if phase ~= "Ready" or not BallController.hasBall() then
		return
	end
	local parts = CharacterRef.get()
	if not parts or parts.humanoid.FloorMaterial == Enum.Material.Air then
		return
	end
	local humanoid, root = parts.humanoid, parts.root

	local distance, toward, lateral = rimAxes(root.Position)
	local velocity = MovementController.getVelocity()
	local lateralSpeed = velocity:Dot(lateral)
	local typeId = ShotMath.classify({
		distanceFeet = distance / Court.STUDS_PER_FOOT,
		towardSpeed = velocity:Dot(toward),
		lateralSpeed = lateralSpeed,
		running = InputController.isRunning(),
	}, Shooting)
	local config = Shooting.Types[typeId]

	local drift: Vector3
	if typeId == "Layup" then
		-- Carry the drive toward the rim, but stop short of running under it.
		local airTime = 2 * config.JUMP_POWER / workspace.Gravity
		local room = distance - Court.ft(Shooting.LAYUP_STOP_FT)
		drift = toward * math.clamp(room / airTime, 0, config.DRIFT)
	else
		local side = if lateralSpeed >= 0 then 1 else -1
		drift = toward * config.DRIFT + lateral * side * config.LATERAL_DRIFT
	end
	MovementController.setOverride(drift)

	humanoid.AutoRotate = false
	root.CFrame = CFrame.lookAt(root.Position, root.Position + toward)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = config.JUMP_POWER
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	BallController.hold()
	shot = { config = config, startedAt = os.clock() }
	phase = "Gathering"
	HudController.beginShot(config.LABEL)
end

local function release()
	local activeShot = shot
	if phase ~= "Gathering" or not activeShot then
		return
	end
	local config = activeShot.config

	local progress = (os.clock() - activeShot.startedAt) / config.FILL_TIME
	local offset, grade = ShotMath.grade(progress, Shooting)

	local from = BallController.getPosition()
	local distance, toward, lateral = rimAxes(from)
	local distanceFeet = distance / Court.STUDS_PER_FOOT
	local difficulty = ShotMath.difficulty(config.DIFFICULTY, distanceFeet, Shooting)
	local depthError, lateralError =
		ShotMath.aimError(offset, difficulty, Shooting, random:NextNumber(), random:NextNumber())

	local target = Court.RIM_POSITION + toward * depthError + lateral * lateralError
	local arcHeight = config.ARC_HEIGHT + distanceFeet * Shooting.ARC_PER_FT
	local vx, vy, vz =
		ShotMath.launchVelocity(from.X, from.Y, from.Z, target.X, target.Y, target.Z, arcHeight, workspace.Gravity)

	phase = "Airborne"
	HudController.releaseShot(grade, progress)
	BallController.launch(Vector3.new(vx, vy, vz), workspace.Gravity, function(made)
		HudController.shotResolved(made, grade)
	end)
end

local function land()
	phase = "Ready"
	shot = nil
	MovementController.setOverride(nil)
	local parts = CharacterRef.get()
	if parts then
		parts.humanoid.AutoRotate = true
	end
end

local function step()
	local activeShot = shot
	if not activeShot then
		return
	end

	if phase == "Gathering" then
		local progress = (os.clock() - activeShot.startedAt) / activeShot.config.FILL_TIME
		HudController.setProgress(progress)
		if progress >= 1 + Shooting.LATE_LIMIT then
			release()
		end
	elseif phase == "Airborne" then
		local parts = CharacterRef.get()
		local airTime = os.clock() - activeShot.startedAt
		if parts and parts.humanoid.FloorMaterial ~= Enum.Material.Air and airTime > MIN_AIR_TIME then
			land()
		end
	end
end

function ShotController.start()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == SHOOT_KEY then
			begin()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == SHOOT_KEY then
			release()
		end
	end)

	CharacterRef.onSpawn(function()
		phase = "Ready"
		shot = nil
		MovementController.setOverride(nil)
	end)
	RunService:BindToRenderStep("RoHoopsShot", Enum.RenderPriority.Input.Value + 2, step)
end

return ShotController
