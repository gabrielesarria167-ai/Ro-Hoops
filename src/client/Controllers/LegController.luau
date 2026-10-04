--!strict
-- LEG CONTROLLER
-- The lower body of the jump shot, using leg IK (see src/client/LimbIK.luau):
--   Dip  – the hips drop (by lowering the Humanoid's HipHeight) while the feet stay
--          planted, so the knees bend; then the legs drive back up into the takeoff.
--   Air  – jump shot: both legs reach straight down (extended, like a real jumper).
--          Layup: the right knee drives up while the left leg (the one you jumped off)
--          stays straight and trails slightly behind.
--          Either way the legs follow the body's lean (PostureController), so on a
--          fadeaway the feet swing forward as the body tilts back, in one straight line.
--   Off  – normal walking/standing animation.
-- ShotController tells it when each phase starts (startDip / takeoff / land).
--
-- Only works for R15 characters (the default); R6 characters just skip it.
-- Tuning values: src/shared/Config/Motion.luau (DIP_DEPTH, DIP_LOWEST_POINT, KNEE_POLE,
-- LAYUP_DIP_DEPTH, LAYUP_KNEE_DRIVE_...).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Motion = require(ReplicatedStorage.Shared.Config.Motion)
local Shooting = require(ReplicatedStorage.Shared.Config.Shooting)
local MovementMath = require(ReplicatedStorage.Shared.MovementMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local LimbIK = require(script.Parent.Parent.LimbIK)
local PostureController = require(script.Parent.PostureController)

type Phase = "Off" | "Dip" | "Air"

local LegController = {}

local SIDES = { "Right", "Left" }
-- How often (seconds) to retry setting up legs that couldn't be found (avatar loading / R6).
local RETRY_INTERVAL = 0.5

local legs: { [string]: LimbIK.Limb } = {} -- "Right" / "Left" → that leg's IK
local nextRetryAt = 0 -- clock time of the next setup retry

local phase: Phase = "Off"
local dipStartedAt = 0 -- clock time when the dip began
local dipDuration = 0.2 -- seconds from the start of the dip to takeoff
local takeoffAt = 0 -- clock time of the takeoff
local style: Shooting.MotionStyle = "JumpShot" -- which motion the current shot uses
local baseHipHeight = 0 -- the Humanoid's normal HipHeight, restored after the dip
local floorY = 0 -- height of the floor under the player when the dip began
-- Where each ankle was (relative to the hips) when the dip began; the feet stay there.
local plantedAnkles: { [string]: Vector3 } = {}

-- Converts a Motion-config offset (right, up, forward) to Roblox's object space, where
-- forward is -Z.
local function toObjectSpace(offset: Vector3): Vector3
	return Vector3.new(offset.X, offset.Y, -offset.Z)
end

-- Makes sure both legs have working IK on the current body parts, rebuilding them if the
-- parts were missing or replaced. Returns true when both legs are ready.
local function ensureLegs(humanoid: Humanoid, character: Model): boolean
	if LimbIK.isAttached(legs.Right, character) and LimbIK.isAttached(legs.Left, character) then
		return true
	end
	local now = os.clock()
	if now < nextRetryAt then
		return false
	end
	nextRetryAt = now + RETRY_INTERVAL

	for _, side in SIDES do
		LimbIK.destroy(legs[side])
		local leg = LimbIK.make(
			humanoid,
			character,
			side .. "Leg",
			side .. "UpperLeg",
			side .. "Foot",
			side .. "AnkleRigAttachment"
		)
		legs[side] = leg :: any
	end
	-- Let the hips bend far enough for the layup's knee drive (newer avatars limit the hip
	-- to a 40° cone for ragdolls, see LimbIK.freeJoints).
	LimbIK.freeJoints(character, { "RightHip", "RightKnee", "LeftHip", "LeftKnee" })
	return legs.Right ~= nil and legs.Left ~= nil
end

-- How far down the hips are during the dip (0 = standing, 1 = full DIP_DEPTH) at
-- `progress` (0 = start of dip, 1 = takeoff). It's a smooth down-and-up wave whose lowest
-- point is at DIP_LOWEST_POINT, so the legs are already driving up at takeoff.
local function dipAmount(progress: number): number
	if progress <= 0 or progress >= 1 then
		return 0
	end
	local lowest = math.clamp(Motion.DIP_LOWEST_POINT, 0.05, 0.95)
	-- Squash time so the wave's midpoint (its lowest point) lands on `lowest`.
	local wave = if progress < lowest then 0.5 * progress / lowest else 0.5 + 0.5 * (progress - lowest) / (1 - lowest)
	return math.sin(wave * math.pi)
end

-- Eases 0→1 gently at both ends (smoothstep), for motion that starts and stops softly.
local function ease(p: number): number
	p = math.clamp(p, 0, 1)
	return p * p * (3 - 2 * p)
end

-- Starts the dip. `duration` = seconds until takeoff; `motionStyle` = which motion the
-- shot uses (a layup has a shallower dip and a knee drive in the air).
function LegController.startDip(duration: number, motionStyle: Shooting.MotionStyle)
	local parts = CharacterRef.get()
	if not parts then
		return
	end
	if phase == "Off" then
		baseHipHeight = parts.humanoid.HipHeight
	end

	-- Find the floor under the player (ignoring the player's own body).
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { parts.character }
	local hit = workspace:Raycast(parts.root.Position, Vector3.new(0, -20, 0), params)
	floorY = if hit then hit.Position.Y else parts.root.Position.Y - baseHipHeight - parts.root.Size.Y / 2

	-- Remember where each ankle is now, so the feet stay put while the hips drop.
	for _, side in SIDES do
		local foot = parts.character:FindFirstChild(side .. "Foot")
		local ankle = foot and foot:FindFirstChild(side .. "AnkleRigAttachment") :: Attachment?
		if ankle then
			plantedAnkles[side] = parts.root.CFrame:PointToObjectSpace(ankle.WorldPosition)
		end
	end

	dipStartedAt = os.clock()
	dipDuration = math.max(duration, 0.05)
	style = motionStyle
	phase = "Dip"
end

-- The player left the ground: straighten the legs (or, on a layup, drive the knee up).
function LegController.takeoff()
	takeoffAt = os.clock()
	phase = "Air"
end

-- The player landed (or the shot was cancelled): back to normal animation.
function LegController.land()
	phase = "Off"
end

-- Runs every frame.
local function update(dt: number)
	local parts = CharacterRef.get()
	if not parts or not ensureLegs(parts.humanoid, parts.character) then
		return
	end

	local rootCFrame = parts.root.CFrame
	local goal = 0 -- how much the legs follow their IK targets this frame

	if phase == "Dip" then
		local progress = (os.clock() - dipStartedAt) / dipDuration
		local depth = if style == "Layup" then Motion.LAYUP_DIP_DEPTH else Motion.DIP_DEPTH
		parts.humanoid.HipHeight = baseHipHeight - depth * dipAmount(progress)
		for _, side in SIDES do
			local planted = plantedAnkles[side]
			local leg = legs[side]
			if planted and leg then
				LimbIK.pinToWorld(leg, true) -- planted: the target must not move down with the hips
				-- Feet stay where they were, at their original height above the floor, while the
				-- hips (and everything relative to them) move down and up.
				local ankleHeight = planted.Y + baseHipHeight + parts.root.Size.Y / 2
				local flat = rootCFrame:PointToWorldSpace(Vector3.new(planted.X, 0, planted.Z))
				leg.target.WorldPosition = Vector3.new(flat.X, floorY + ankleHeight, flat.Z)
				leg.pole.WorldPosition =
					rootCFrame:PointToWorldSpace(toObjectSpace(Motion.KNEE_POLE) + Vector3.new(planted.X, 0, 0))
			end
		end
		goal = 1
	elseif phase == "Air" then
		parts.humanoid.HipHeight = baseHipHeight
		-- Measure from the leaned body, so the legs tilt with it.
		local bodyCFrame = PostureController.getBodyCFrame(rootCFrame)
		for _, side in SIDES do
			local planted = plantedAnkles[side]
			local leg = legs[side]
			if planted and leg then
				LimbIK.pinToWorld(leg, false) -- in the air: the target moves with the body
				-- Jump shot: aim the ankles far below the hips (out of reach), so the legs straighten.
				local ankle = Vector3.new(planted.X, -6, planted.Z)
				local pole = toObjectSpace(Motion.KNEE_POLE) + Vector3.new(planted.X, 0, 0)
				if style == "Layup" and side == "Right" then
					-- Knee drive: the right ankle rises from where it was planted to the
					-- knee-up spot over LAYUP_KNEE_DRIVE_TIME.
					local drive = ease((os.clock() - takeoffAt) / math.max(Motion.LAYUP_KNEE_DRIVE_TIME, 0.01))
					ankle = planted:Lerp(toObjectSpace(Motion.LAYUP_KNEE_DRIVE_ANKLE), drive)
					pole = toObjectSpace(Motion.LAYUP_KNEE_DRIVE_POLE)
				elseif style == "Layup" then
					-- Takeoff leg: straight, trailing a little behind.
					ankle = toObjectSpace(Motion.LAYUP_TAKEOFF_ANKLE)
				end
				leg.target.WorldPosition = bodyCFrame:PointToWorldSpace(ankle)
				leg.pole.WorldPosition = bodyCFrame:PointToWorldSpace(pole)
			end
		end
		goal = 1
	elseif baseHipHeight > 0 and parts.humanoid.HipHeight ~= baseHipHeight then
		parts.humanoid.HipHeight = baseHipHeight -- make sure the dip never sticks
	end

	local alpha = MovementMath.smoothingAlpha(Motion.LEG_BLEND_SHARPNESS, dt)
	for _, leg in legs do
		LimbIK.blend(leg, goal, alpha, 0) -- no smoothing: planted feet must not slide
	end
end

function LegController.start()
	CharacterRef.onSpawn(function()
		for _, leg in legs do
			LimbIK.destroy(leg)
		end
		legs = {}
		nextRetryAt = 0
		phase = "Off"
		baseHipHeight = 0 -- re-read from the new character on its first dip
	end)
	-- Runs before the arms and ball so the hips are in their dipped position this frame.
	RunService:BindToRenderStep("RoHoopsLegs", Enum.RenderPriority.Character.Value, update)
end

return LegController
