--!strict
-- Fixed, rim-focused camera. It sits behind the player on the court's long axis, follows
-- them only partly sideways, and looks at a point between the player and the rim, so the
-- rim stays in frame. There is no rotation input.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Camera = require(ReplicatedStorage.Shared.Config.Camera)
local Court = require(ReplicatedStorage.Shared.Config.Court)
local MovementMath = require(ReplicatedStorage.Shared.MovementMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)

local CameraController = {}

local smoothedPosition: Vector3? = nil
local smoothedFocus: Vector3? = nil

local function step(dt: number)
	local camera = workspace.CurrentCamera
	-- The default camera scripts may switch the type back on respawn.
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	camera.FieldOfView = Camera.FIELD_OF_VIEW

	local parts = CharacterRef.get()
	if not parts then
		return
	end

	local player = parts.root.Position
	local rim = Court.RIM_POSITION
	local desiredPosition = Vector3.new(
		rim.X + (player.X - rim.X) * Camera.LATERAL_FOLLOW,
		Camera.HEIGHT,
		math.max(player.Z, Camera.MIN_PLAYER_Z) + Camera.DISTANCE
	)
	local desiredFocus = player:Lerp(rim, Camera.LOOK_BLEND)

	local alpha = MovementMath.smoothingAlpha(Camera.FOLLOW_SHARPNESS, dt)
	local position = if smoothedPosition then smoothedPosition:Lerp(desiredPosition, alpha) else desiredPosition
	local focus = if smoothedFocus then smoothedFocus:Lerp(desiredFocus, alpha) else desiredFocus
	smoothedPosition = position
	smoothedFocus = focus

	camera.CFrame = CFrame.lookAt(position, focus)
end

function CameraController.start()
	CharacterRef.onSpawn(function()
		-- Snap instead of gliding across the court on respawn.
		smoothedPosition = nil
		smoothedFocus = nil
	end)
	RunService:BindToRenderStep("RoHoopsCamera", Enum.RenderPriority.Camera.Value, step)
end

return CameraController
