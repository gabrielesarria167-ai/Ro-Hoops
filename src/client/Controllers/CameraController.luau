--!strict
-- CAMERA CONTROLLER
-- The fixed, rim-focused camera. It sits behind the player (on the side away from the
-- rim), slides only partly sideways with them, and looks at a point between the player
-- and the rim so the rim stays in view. The player can't rotate it.
-- Tuning values: src/shared/Config/Camera.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Camera = require(ReplicatedStorage.Shared.Config.Camera)
local Court = require(ReplicatedStorage.Shared.Config.Court)
local MovementMath = require(ReplicatedStorage.Shared.MovementMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)

local CameraController = {}

-- Where the camera is and what it's looking at, after smoothing. nil = snap next frame.
local smoothedPosition: Vector3? = nil
local smoothedFocus: Vector3? = nil

-- Runs every frame. `dt` = seconds since the last frame.
local function step(dt: number)
	local camera = workspace.CurrentCamera
	-- Scriptable = only our code moves the camera. Roblox's default camera scripts can
	-- switch it back after a respawn, so re-check every frame.
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
	-- Where the camera wants to be: partly following the player sideways, at a fixed
	-- height, a fixed distance behind them.
	local desiredPosition = Vector3.new(
		rim.X + (player.X - rim.X) * Camera.LATERAL_FOLLOW,
		Camera.HEIGHT,
		math.max(player.Z, Camera.MIN_PLAYER_Z) + Camera.DISTANCE
	)
	-- What the camera wants to look at: a point between the player and the rim.
	local desiredFocus = player:Lerp(rim, Camera.LOOK_BLEND)

	-- Glide toward the desired position/focus instead of jumping, so motion looks smooth.
	local alpha = MovementMath.smoothingAlpha(Camera.FOLLOW_SHARPNESS, dt)
	local position = if smoothedPosition then smoothedPosition:Lerp(desiredPosition, alpha) else desiredPosition
	local focus = if smoothedFocus then smoothedFocus:Lerp(desiredFocus, alpha) else desiredFocus
	smoothedPosition = position
	smoothedFocus = focus

	camera.CFrame = CFrame.lookAt(position, focus)
end

function CameraController.start()
	CharacterRef.onSpawn(function()
		-- Snap straight to the new character instead of gliding across the court.
		smoothedPosition = nil
		smoothedFocus = nil
	end)
	RunService:BindToRenderStep("RoHoopsCamera", Enum.RenderPriority.Camera.Value, step)
end

return CameraController
