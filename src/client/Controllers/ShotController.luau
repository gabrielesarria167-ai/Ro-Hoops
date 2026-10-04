--!strict
-- SHOT CONTROLLER (the E key)
-- Pressing E:
--   1. picks the shot type from your position and movement (ShotMath.classify):
--      jump shot, pull-up, fadeaway, step-back, side shot, layup or close shot,
--   2. jumps you into the air with that shot's drift and starts the timing meter.
-- Releasing E:
--   3. grades the timing (ShotMath.grade) and turns it into an aim error (ShotMath.aimError),
--   4. solves the arc to that target (ShotMath.launchVelocity) and launches the ball.
-- Tuning values: src/shared/Config/Shooting.luau.

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

-- Ready     = can shoot
-- Gathering = E is held, meter filling
-- Airborne  = ball released, waiting for the player to land
type Phase = "Ready" | "Gathering" | "Airborne"

-- The shot in progress.
type ActiveShot = {
	config: Shooting.ShotTypeConfig, -- the settings of the chosen shot type
	startedAt: number, -- clock time when E was pressed, seconds
}

local SHOOT_KEY = Enum.KeyCode.E -- change this to rebind shooting
local MIN_AIR_TIME = 0.2 -- seconds; ignore "on the ground" readings right after takeoff

local ShotController = {}

local phase: Phase = "Ready" -- where we are in the shot
local shot: ActiveShot? = nil -- the shot in progress, or nil
local random = Random.new() -- random numbers for the sideways aim error

-- From `position`, returns the flat distance to the rim (studs) plus two directions:
-- `toward` points at the rim, `lateral` points to its right (across the court).
local function rimAxes(position: Vector3): (number, Vector3, Vector3)
	local offset = Court.RIM_POSITION - position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	local toward = if distance > 1e-3 then flat / distance else -Vector3.zAxis
	return distance, toward, toward:Cross(Vector3.yAxis)
end

-- E pressed: choose the shot, jump, start the meter.
local function begin()
	if phase ~= "Ready" or not BallController.hasBall() then
		return
	end
	local parts = CharacterRef.get()
	-- Must be standing on something (FloorMaterial is Air while jumping or falling).
	if not parts or parts.humanoid.FloorMaterial == Enum.Material.Air then
		return
	end
	local humanoid, root = parts.humanoid, parts.root

	-- Split the player's velocity into "toward the rim" and "across the court" parts.
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

	-- How the player moves through the air during the shot.
	local drift: Vector3
	if typeId == "Layup" then
		-- Carry the drive toward the rim, but slow it so the player stops LAYUP_STOP_FT short.
		local airTime = 2 * config.JUMP_POWER / workspace.Gravity -- seconds in the air
		local room = distance - Court.ft(Shooting.LAYUP_STOP_FT) -- studs left before stopping
		drift = toward * math.clamp(room / airTime, 0, config.DRIFT)
	else
		local side = if lateralSpeed >= 0 then 1 else -1 -- keep drifting the way you were moving
		drift = toward * config.DRIFT + lateral * side * config.LATERAL_DRIFT
	end
	MovementController.setOverride(drift)

	-- Face the rim and jump.
	humanoid.AutoRotate = false -- stop the Humanoid turning toward its movement direction
	root.CFrame = CFrame.lookAt(root.Position, root.Position + toward)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = config.JUMP_POWER
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	BallController.hold()
	shot = { config = config, startedAt = os.clock() }
	phase = "Gathering"
	HudController.beginShot(config.LABEL)
end

-- E released (or the meter ran out): grade the timing, aim, and launch the ball.
local function release()
	local activeShot = shot
	if phase ~= "Gathering" or not activeShot then
		return
	end
	local config = activeShot.config

	-- How far through the meter the release was (IDEAL_RELEASE = perfect).
	local progress = (os.clock() - activeShot.startedAt) / config.FILL_TIME
	local offset, grade = ShotMath.grade(progress, Shooting)

	-- Turn the timing miss into a landing spot relative to the rim's centre.
	local from = BallController.getPosition()
	local distance, toward, lateral = rimAxes(from)
	local distanceFeet = distance / Court.STUDS_PER_FOOT
	local difficulty = ShotMath.difficulty(config.DIFFICULTY, distanceFeet, Shooting)
	local depthError, lateralError =
		ShotMath.aimError(offset, difficulty, Shooting, random:NextNumber(), random:NextNumber())
	local target = Court.RIM_POSITION + toward * depthError + lateral * lateralError

	-- Solve the throw that lands exactly on that target, with a higher arc from further out.
	local arcHeight = config.ARC_HEIGHT + distanceFeet * Shooting.ARC_PER_FT
	local vx, vy, vz =
		ShotMath.launchVelocity(from.X, from.Y, from.Z, target.X, target.Y, target.Z, arcHeight, workspace.Gravity)

	phase = "Airborne"
	HudController.releaseShot(grade, progress)
	BallController.launch(Vector3.new(vx, vy, vz), workspace.Gravity, function(made)
		HudController.shotResolved(made, grade)
	end)
end

-- The player touched down after releasing: give movement control back.
local function land()
	phase = "Ready"
	shot = nil
	MovementController.setOverride(nil)
	local parts = CharacterRef.get()
	if parts then
		parts.humanoid.AutoRotate = true
	end
end

-- Runs every frame: fills the meter while gathering, watches for landing after release.
local function step()
	local activeShot = shot
	if not activeShot then
		return
	end

	if phase == "Gathering" then
		local progress = (os.clock() - activeShot.startedAt) / activeShot.config.FILL_TIME
		HudController.setProgress(progress)
		-- Held too long: the shot goes up on its own (very late).
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
		-- gameProcessed = the key was used by Roblox UI (e.g. typing in chat), so ignore it.
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
	-- "Input + 2" priority runs right after MovementController each frame.
	RunService:BindToRenderStep("RoHoopsShot", Enum.RenderPriority.Input.Value + 2, step)
end

return ShotController
