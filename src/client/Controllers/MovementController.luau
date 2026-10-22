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
-- The body always faces the rim (faceRim): the Humanoid's own turning toward the movement
-- direction (AutoRotate) is switched off, so A / D shuffle sideways and S backpedals.
-- SkillController's spin overrides the facing while it turns (it runs later each frame).
-- A shot can ask for a small extra turn (setFacingYaw): a jump shooter stands with the
-- shooting side forward instead of square to the rim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Court = require(ReplicatedStorage.Shared.Config.Court)
local Motion = require(ReplicatedStorage.Shared.Config.Motion)
local Movement = require(ReplicatedStorage.Shared.Config.Movement)
local MovementMath = require(ReplicatedStorage.Shared.MovementMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local InputController = require(script.Parent.InputController)

local MovementController = {}

-- The player's current flat velocity (y is always 0), studs/s. Other systems read it
-- through getVelocity(), e.g. to pick the shot type or speed up the dribble.
local velocity = Vector3.zero
-- The velocity `velocity` is easing toward (the keys' wish, or the override). Zero while
-- slowing to a stop. LegController uses it to place feet where the body is heading.
local targetVelocity = Vector3.zero
-- When set, input is ignored and the player's velocity eases toward this one (at
-- Motion.DRIFT_BLEND_RATE, so momentum carries into the shot). Used by ShotController for
-- shot drift (pull-up stops, fadeaways, layup drives) and by SkillController for the
-- crossover's jab and burst. nil = normal control.
local override: Vector3? = nil
-- How fast the velocity eases toward `override`, studs/s² (nil = Motion.DRIFT_BLEND_RATE).
local overrideRate: number? = nil
-- Extra turn added to "facing the rim", degrees to the player's left (0 = square to the rim).
-- Set by ShotController for a jump shooter's turned stance; 0 the rest of the time.
local facingYaw = 0
-- true = don't turn the body toward the rim at all (set by ShotController while a dunker is
-- in the air: passing under the rim would otherwise swing the body round mid-air).
local facingLocked = false

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

-- Turns the body a little further toward the rim (called every frame), keeping its position.
local function faceRim(parts: CharacterRef.Parts, dt: number)
	local humanoid = parts.humanoid
	-- Off = the Humanoid never turns the body toward where it's walking; we do the turning.
	-- Re-checked every frame because a respawn brings a new Humanoid with it on.
	if humanoid.AutoRotate then
		humanoid.AutoRotate = false
	end
	if facingLocked then
		return -- a dunker in the air keeps facing the way they jumped
	end
	local root = parts.root
	local position = root.Position
	local toRim = Vector3.new(Court.RIM_POSITION.X - position.X, 0, Court.RIM_POSITION.Z - position.Z)
	if toRim.Magnitude < 0.5 then
		return -- standing right under the rim: no clear direction, keep the current facing
	end
	local facingRim = CFrame.lookAt(position, position + toRim) * CFrame.Angles(0, math.rad(facingYaw), 0)
	local alpha = MovementMath.smoothingAlpha(Movement.FACE_RIM_SHARPNESS, dt)
	root.CFrame = root.CFrame:Lerp(facingRim, alpha)
end

-- Runs every frame before the camera updates. `dt` = seconds since the last frame.
local function step(dt: number)
	local parts = CharacterRef.get()
	if not parts or parts.humanoid.Health <= 0 then
		velocity = Vector3.zero
		targetVelocity = Vector3.zero
		return
	end

	local forcedVelocity = override
	if forcedVelocity then
		targetVelocity = Vector3.new(forcedVelocity.X, 0, forcedVelocity.Z)
		local rate = overrideRate or Motion.DRIFT_BLEND_RATE -- same rate whether speeding up, slowing or turning
		local vx, vz =
			MovementMath.stepVelocity(velocity.X, velocity.Z, forcedVelocity.X, forcedVelocity.Z, rate, rate, rate, dt)
		velocity = Vector3.new(vx, 0, vz)
	else
		local intent = InputController.getMoveIntent() -- which keys are held
		local speed = if InputController.isRunning() then Movement.RUN_SPEED else Movement.WALK_SPEED
		local forward, right = screenAxes()
		local direction = right * intent.X + forward * intent.Y
		-- Slower when shuffling sideways or backpedalling (the body faces the rim), see
		-- Movement.SIDE_SPEED_SCALE / BACK_SPEED_SCALE.
		local look, side = parts.root.CFrame.LookVector, parts.root.CFrame.RightVector
		speed *= MovementMath.directionalSpeedScale(
			direction:Dot(side),
			direction:Dot(look),
			Movement.SIDE_SPEED_SCALE,
			Movement.BACK_SPEED_SCALE
		)
		local target = direction * speed -- the velocity we want
		targetVelocity = target
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

	faceRim(parts, dt)
end

-- The screen's "up" and "right" directions flattened onto the floor (world space). Used
-- by SkillController to turn a mouse flick on screen into a direction on the court.
function MovementController.getScreenAxes(): (Vector3, Vector3)
	return screenAxes()
end

-- The player's current flat velocity, studs/s.
-- The flat velocity the player is speeding up / slowing down toward, studs/s (zero when
-- coming to a stop).
function MovementController.getTargetVelocity(): Vector3
	return targetVelocity
end

function MovementController.getVelocity(): Vector3
	return velocity
end

-- Ignores input and eases the player toward `forcedVelocity`, changing speed at `rate`
-- studs/s² (default Motion.DRIFT_BLEND_RATE). Pass nil to give control back to the player.
function MovementController.setOverride(forcedVelocity: Vector3?, rate: number?)
	override = forcedVelocity
	overrideRate = rate
end

-- Makes the body face `degrees` to the left of the rim instead of straight at it (negative =
-- to the right). Pass 0 to face the rim squarely again.
function MovementController.setFacingYaw(degrees: number)
	facingYaw = degrees
end

-- true = stop turning the body toward the rim (it keeps its current facing); false = turn
-- toward the rim again as normal.
function MovementController.setFacingLocked(locked: boolean)
	facingLocked = locked
end

function MovementController.start()
	CharacterRef.onSpawn(function()
		velocity = Vector3.zero
		targetVelocity = Vector3.zero
		override = nil
		overrideRate = nil
		facingYaw = 0
	end)
	-- "Input + 1" priority runs right after Roblox reads input, before the camera moves.
	RunService:BindToRenderStep("RoHoopsMovement", Enum.RenderPriority.Input.Value + 1, step)
end

return MovementController
