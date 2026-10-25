--!strict
-- CAMERA CONTROLLER
-- The soft rim-locked camera. It sits behind the player and faces up-court, turning only
-- part of the way toward the rim (Camera.RIM_FOLLOW), so:
--   * the rim stays at the same height on screen (Camera.RIM_ABOVE_CENTER), sliding a bit
--     sideways when you're out on a wing or in a corner;
--   * the keys move along (nearly) straight court lines (MovementController reads its
--     directions from the camera): left/right is a straight shuffle, not a circle round
--     the rim, and you can see the side of the court you're moving toward.
--     (RIM_FOLLOW = 1 gives the old full lock: always facing the rim, left/right circle it.)
-- The player can't rotate it: the mouse is kept for dribble moves (SkillController).
-- Tuning values: src/shared/Config/Camera.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Camera = require(ReplicatedStorage.Shared.Config.Camera)
local Court = require(ReplicatedStorage.Shared.Config.Court)
local MovementMath = require(ReplicatedStorage.Shared.MovementMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)

local CameraController = {}

-- Where the camera is, after smoothing. nil = snap next frame.
local smoothedPosition: Vector3? = nil
-- Flat direction from the rim out to the player (the camera sits further along it). Kept
-- from the last frame when the player stands right under the rim, where it's undefined.
local orbitDirection = Vector3.zAxis

-- The flat direction the camera sits along: from the rim out to `player`, swung back inside
-- MAX_ORBIT_ANGLE (so it never goes round behind the backboard), then only RIM_FOLLOW of
-- the way round from straight up-court.
local function directionFromRim(player: Vector3, rim: Vector3): Vector3
	local flat = Vector3.new(player.X - rim.X, 0, player.Z - rim.Z)
	if flat.Magnitude < 0.5 then
		return orbitDirection -- right under the rim: keep the last direction
	end
	-- Angle round the rim: 0 = straight out in front of the backboard (+Z), +/-90 = along the baseline.
	local maxAngle = math.rad(Camera.MAX_ORBIT_ANGLE)
	local angle = math.clamp(math.atan2(flat.X, flat.Z), -maxAngle, maxAngle) * Camera.RIM_FOLLOW
	return Vector3.new(math.sin(angle), 0, math.cos(angle))
end

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
	orbitDirection = directionFromRim(player, rim)
	-- Where the camera wants to be: DISTANCE further out from the rim than the player, at a
	-- fixed height (it doesn't bob up and down when the player jumps).
	local flatPlayer = Vector3.new(player.X, 0, player.Z)
	local desiredPosition = flatPlayer + orbitDirection * Camera.DISTANCE + Vector3.yAxis * Camera.HEIGHT

	-- Glide toward the desired position instead of jumping, so motion looks smooth.
	local alpha = MovementMath.smoothingAlpha(Camera.FOLLOW_SHARPNESS, dt)
	local position = if smoothedPosition then smoothedPosition:Lerp(desiredPosition, alpha) else desiredPosition
	smoothedPosition = position

	-- Look straight ahead along orbitDirection at a point level with the rim and as far
	-- ahead as the rim is (with RIM_FOLLOW = 1 that point IS the rim), then tilt down by
	-- RIM_ABOVE_CENTER so the rim sits that far above the middle of the screen and the
	-- player fits below it.
	local rimDistance = (Vector3.new(rim.X, 0, rim.Z) - flatPlayer).Magnitude
	local lookAt = flatPlayer - orbitDirection * rimDistance + Vector3.yAxis * rim.Y
	camera.CFrame = CFrame.lookAt(position, lookAt) * CFrame.Angles(-math.rad(Camera.RIM_ABOVE_CENTER), 0, 0)
end

function CameraController.start()
	CharacterRef.onSpawn(function()
		-- Snap straight to the new character instead of gliding across the court.
		smoothedPosition = nil
	end)
	RunService:BindToRenderStep("RoHoopsCamera", Enum.RenderPriority.Camera.Value, step)
end

return CameraController
