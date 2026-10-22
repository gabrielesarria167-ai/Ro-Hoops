--!strict
-- LEG CONTROLLER
-- Everything the legs do, using leg IK (see src/client/LimbIK.luau):
--   Ground   – procedural footwork (Config/Footwork.luau). Each foot is planted on the floor
--              and stays put until it steps; GaitMath decides when and where:
--                * the dribbling stance: knees bent, feet a bit wider than the hips, nearly
--                  square, toes out, the ball-side foot slightly back;
--                * sideways = a step-slide (the lead foot always goes first, the trail foot
--                  follows low and quick, never crossing), backward = a short toe-first
--                  backpedal, standing still = the stance squares itself up;
--                * running forward hands the legs to Roblox's run animation instead (with a
--                  gap between entering and leaving it, so there's no flicker); footfalls
--                  are still detected so the dribble can bounce in time with the feet;
--                * dribble moves place the feet themselves (SkillController calls stepFoot,
--                  stepFootTo, pivotFoot, setHipsPath, setScripted and setMoveCrouch).
--   Approach – a layup or running dunk from further out: the legs take running gather steps
--              (long RIGHT step, then the LEFT plant that starts the dip), timed backward
--              from the moment the dip starts (startApproach).
--   Dip      – the hips drop (by lowering the Humanoid's HipHeight) while the feet stay
--              planted, so the knees bend, and the trunk hinges forward (PostureController
--              .setDipHinge); then the legs drive back up into the takeoff. The feet are
--              placed to suit where the body is going (the "gather"): under the hips for a
--              plain shot, a braking 1-2 for a pull-up, a side step for a side
--              shot. A layup plants the LEFT foot and swings the right knee up.
--   Air      – knees slightly bent, toes pointed, feet under or a bit ahead of the hips
--              (further ahead on a fadeaway). Layup: the right knee drives up while the left
--              leg trails; a running dunk tucks the knees after the top of the jump. Just
--              before landing the legs reach for the floor.
--   Landing  – the feet land where they are and settle onto the floor, the knees absorb the
--              landing (a crouch that recovers) and the trunk dips (absorbLanding).
-- ShotController tells it when each shot phase starts (startApproach / startDip / takeoff /
-- land).
--
-- Feet are placed with full transform IK, so they have a direction (toes out, planted
-- feet keep theirs while the body turns a little, a pivot foot twists on the ball of the
-- foot) and a pitch (toe up in a swing, toe down on a backpedal landing, pointed in the air).
-- Reach is the real thing: the hip joints are read from the character and GaitMath
-- .reachForCrouch says how far a foot can really be from under its hip.
--
-- Interfaces with other systems:
--   * BallController.notifyFootPlant(side, period) on every touchdown (steps and run-cycle
--     plants), and getGaitInfo() for anyone who wants the rhythm;
--   * PostureController.setDipHinge / absorbLanding for the trunk.
--
-- Only works for R15 characters (the default); R6 characters just skip it.
-- Tuning values: src/shared/Config/Footwork.luau (everything), src/shared/Config/Motion.luau
-- (DIP_LOWEST_POINT, which the ball's timing also uses, LEG_BLEND_SHARPNESS).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Footwork = require(ReplicatedStorage.Shared.Config.Footwork)
local Motion = require(ReplicatedStorage.Shared.Config.Motion)
local Shooting = require(ReplicatedStorage.Shared.Config.Shooting)
local GaitMath = require(ReplicatedStorage.Shared.GaitMath)
local MovementMath = require(ReplicatedStorage.Shared.MovementMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local LimbIK = require(script.Parent.Parent.LimbIK)
local BallController = require(script.Parent.BallController)
local MovementController = require(script.Parent.MovementController)
local PostureController = require(script.Parent.PostureController)

type Phase = "Off" | "Dip" | "Air"
type Side = GaitMath.Side

-- What the feet do inside the dip (see startDip).
export type GatherKind = "None" | "PullUp" | "SideStep"
export type DipOptions = {
	gather: GatherKind?, -- which 1-2 landing happens inside the dip (nil = "None")
	drift: Vector3?, -- the flat world velocity the body has during the dip (nil = its current velocity)
	depthScale: number?, -- multiplies the extra dip depth (a close shot dips less)
	rate: number?, -- how fast the body's velocity eases to `drift`, studs/s² (nil = Motion.DRIFT_BLEND_RATE); must match ShotController's
}

-- Where a step is aimed: a spot beside the hips at the moment the foot lands. It's worked
-- out again every frame of the step from where the hips are and where they're heading, so
-- the foot lands in the right place even though the body is still moving.
type Aim = {
	offset: Vector3, -- from the hips: x = studs to the right, z = studs forward (y unused)
	frame: CFrame?, -- which way "right" and "forward" are (nil = the way the body faces now)
	ahead: number, -- land this many extra seconds of travel ahead (so the body moves over the foot)
	keepApart: boolean, -- never land across the other foot (automatic steps)
	world: Vector3?, -- a fixed spot in the world (flat) instead of an offset from the hips
	maxStep: number?, -- never step further than this from where the foot left (flat)
}

-- One foot on the ground (the Ground phase). Positions are flat (y = 0); the floor height
-- is added when the foot is placed.
type Foot = {
	position: Vector3, -- where the ankle is now (planted, or partway through a step)
	yaw: number, -- the direction the foot points (radians, as CFrame.Angles(0, yaw, 0))
	stepping: boolean, -- in the air, on its way from `from` to `to`
	from: Vector3,
	to: Vector3, -- where it will land (updated every frame from `aim`)
	yawFrom: number, -- the foot's direction when the step started
	fromHeight: number, -- how high the ankle was above its resting height when the step started
	aim: Aim?,
	startedAt: number, -- clock time the step started
	duration: number, -- seconds the step takes
	lift: number, -- studs the foot rises at the top of the step
	bulge: Vector3, -- sideways sweep at the middle of the step (the spin's swing leg)
	bulgeBody: boolean, -- `bulge` is in the body's frame (turns with it) instead of the world's
	pendingLandPitch: number, -- radians: the pitch the foot touches down with (+ toe up)
	landPitch: number, -- the touchdown pitch of the last landing, easing back to flat
	landedAt: number, -- clock time of the last touchdown
	settleHeight: number, -- extra ankle height that eases away (a foot that was in the air)
	settleStart: number,
	settleDuration: number,
	staggerZ: number, -- the stagger offset this foot was last placed with (a hand switch changes the wish)
	pivot: boolean, -- twisting on the ball of the foot (the spin's pivot foot)
	pivotYawOffset: number, -- how far the foot pointed from the body's wish when the pivot began (kept)
	ballPoint: Vector3, -- the ball of the foot (flat world), the point a pivot foot turns about
	airborne: boolean, -- (run animation) the ankle has been lifted since the last plant
}

-- One planned step inside a shot's dip. Times are shares of the dip (0 = start, 1 = takeoff).
type DipStep = {
	from: Vector3,
	to: Vector3,
	startAt: number,
	landAt: number,
	lift: number,
	landPitch: number, -- radians, + toe up, eases flat after landing
	holdPitch: number, -- radians kept after landing (on the balls of the feet)
}

-- A foot during the dip.
type DipFoot = {
	current: Vector3, -- flat, where the ankle is now
	yaw: number,
	step: DipStep?,
}

-- The running gather steps of an approach (startApproach).
type Approach = {
	startedAt: number,
	steps: { GaitMath.ApproachStep },
	started: { boolean }, -- parallel to steps: has this step been started
	dropFrom: number, -- seconds into the approach the hips start dropping for the gather...
	dropTo: number, -- ...and finish dropping
	startCrouch: number, -- the crouch (studs) when the approach began; eased from, so the hips don't pop up
}

local LegController = {}

local SIDES: { Side } = { "Right", "Left" }
-- How often (seconds) to retry setting up legs that couldn't be found (avatar loading / R6).
local RETRY_INTERVAL = 0.5

local legs: { [Side]: LimbIK.Limb } = {} -- each leg's IK
local nextRetryAt = 0 -- clock time of the next setup retry
-- Height of each ankle joint above the bottom of its foot, so a foot on the floor sits flat.
local ankleHeights: { [Side]: number } = { Right = 0.5, Left = 0.5 }
-- The Humanoid's normal (standing) HipHeight; crouching and the dip lower it from here.
local standingHipHeight = 0
local legLength = Footwork.LEG_LENGTH -- hip joint to ankle joint, studs (measured per character)
-- The hip joints: LowerTorso attachments (nil = use the guess root +/- 0.5), and where they are
-- relative to the root (flat, world axes), refreshed every frame.
local hipAttachments: { [Side]: Attachment? } = {}
local hipOffsets: { [Side]: Vector3 } = { Right = Vector3.new(0.5, 0, 0), Left = Vector3.new(-0.5, 0, 0) }
-- The hip joints in the root's own space (for the air legs), taken when the dip starts.
local hipRel: { [Side]: Vector3 } = { Right = Vector3.new(0.5, -1, 0), Left = Vector3.new(-0.5, -1, 0) }

local phase: Phase = "Off"
local dipStartedAt = 0 -- clock time when the dip began
local dipDuration = 0.2 -- seconds from the start of the dip to takeoff
local dipStartDrop = 0 -- how far the hips were already lowered (the crouch) when the dip began
local dipDeepest = 0 -- how far the hips are lowered at the bottom of the dip
local dipFeet: { [Side]: DipFoot } = {}
local freeLegRel: Vector3 = Vector3.zero -- (layup) the right ankle in the root's space, last frame of the dip
local takeoffAt = 0 -- clock time of the takeoff
local style: Shooting.MotionStyle = "JumpShot" -- which motion the current shot uses
local apexAt: number? = nil -- clock time the jump started falling
local peakFall = 0 -- fastest downward speed in the air (landing strength comes from it)
local takeoffPower = 0 -- upward speed just after takeoff (tells a dunk from a layup)
local fadeBlend = 0 -- 0-1: how much the legs swing forward as a fadeaway counterweight
local approach: Approach? = nil -- the running gather steps before a layup, or nil

-- GROUND STATE
local feet: { [Side]: Foot }? = nil -- nil = take the feet from wherever they are now
local crouch = 0 -- how far the hips are lowered right now, studs
local scripted = false -- a dribble move is placing the feet (no automatic steps)
local moveCrouch = 0 -- extra crouch asked for by the current dribble move, studs
local stillSince = 0 -- clock time the player stopped moving (for squaring up the stance)
local animationRunning = false -- the run animation has the legs (with hysteresis)
local hipsPath: ((seconds: number) -> Vector3)? = nil -- (dribble moves) where the hips will be
local legGoals: { [Side]: number } = { Right = 0, Left = 0 } -- how much each leg follows its IK this frame

-- LANDING STATE
local landedAt = -math.huge -- clock time of the last landing
local landStrength = 0 -- 0-1, how hard it was

-- GAIT STATE (footfall signal)
local plantTimes: { number } = {} -- clock times of the last few footfalls (either foot)
local lastPlantAt = -math.huge
local lastSpeed = 0 -- flat speed last frame, studs/s
local animationLifted: { [Side]: boolean } = { Right = false, Left = false } -- (run animation) ankle lifted since the last plant

-- Converts a config offset (right, up, forward) to Roblox's object space, where
-- forward is -Z.
local function toObjectSpace(offset: Vector3): Vector3
	return Vector3.new(offset.X, offset.Y, -offset.Z)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function ease(p: number): number
	p = math.clamp(p, 0, 1)
	return p * p * (3 - 2 * p)
end

-- The direction a CFrame looks in, as a turn about the vertical axis (radians): the number
-- to give CFrame.Angles(0, yaw, 0) to look that way.
local function yawOf(cframe: CFrame): number
	local look = cframe.LookVector
	return math.atan2(-look.X, -look.Z)
end

-- The flat direction a foot with this yaw points in.
local function forwardOf(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

-- Where `side`'s ankle is (its attachment), if the body has one.
local function ankleOf(character: Model, side: Side): Attachment?
	local foot = character:FindFirstChild(side .. "Foot")
	return foot and foot:FindFirstChild(side .. "AnkleRigAttachment") :: Attachment?
end

-- Hip joint to ankle joint, studs, measured from the leg's own attachments (so scaled
-- avatars work). Falls back to Footwork.LEG_LENGTH.
local function measureLeg(character: Model, side: Side): number
	local upper = character:FindFirstChild(side .. "UpperLeg")
	local lower = character:FindFirstChild(side .. "LowerLeg")
	local hip = upper and upper:FindFirstChild(side .. "HipRigAttachment") :: Attachment?
	local kneeUpper = upper and upper:FindFirstChild(side .. "KneeRigAttachment") :: Attachment?
	local kneeLower = lower and lower:FindFirstChild(side .. "KneeRigAttachment") :: Attachment?
	local ankle = lower and lower:FindFirstChild(side .. "AnkleRigAttachment") :: Attachment?
	if hip and kneeUpper and kneeLower and ankle then
		return (hip.Position - kneeUpper.Position).Magnitude + (kneeLower.Position - ankle.Position).Magnitude
	end
	return Footwork.LEG_LENGTH
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

	local measured = 0
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
		if leg then
			-- Place the whole foot (position AND angle) so it stays flat on the floor.
			leg.ik.Type = Enum.IKControlType.Transform
			legs[side] = leg
		end
		local foot = character:FindFirstChild(side .. "Foot") :: BasePart?
		local ankle = foot and foot:FindFirstChild(side .. "AnkleRigAttachment") :: Attachment?
		if foot and ankle then
			ankleHeights[side] = foot.Size.Y / 2 + ankle.Position.Y
		end
		local lowerTorso = character:FindFirstChild("LowerTorso")
		hipAttachments[side] = lowerTorso and lowerTorso:FindFirstChild(side .. "HipRigAttachment") :: Attachment?
		measured = math.max(measured, measureLeg(character, side))
	end
	legLength = if measured > 0.5 then measured else Footwork.LEG_LENGTH
	-- New body parts = Roblox has just worked out the standing HipHeight for them.
	standingHipHeight = humanoid.HipHeight
	crouch = 0
	feet = nil
	-- Let the hips bend far enough for the layup's knee drive and the ankles turn for a
	-- pivot (newer avatars limit joints for ragdolls, see LimbIK.freeJoints).
	LimbIK.freeJoints(character, { "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" })
	return legs.Right ~= nil and legs.Left ~= nil
end

-- Reads where the hip joints are this frame (flat offsets from the root, world axes).
local function refreshHips(parts: CharacterRef.Parts)
	for _, side in SIDES do
		local attachment = hipAttachments[side]
		if attachment and attachment.Parent then
			hipOffsets[side] = flat(attachment.WorldPosition - parts.root.Position)
		else
			hipOffsets[side] = flat(parts.root.CFrame.RightVector) * (GaitMath.sign(side) * 0.5)
		end
	end
end

-- How far down the hips are during the dip (0 = standing, 1 = full depth) at `progress`
-- (0 = start of dip, 1 = takeoff). It's a smooth down-and-up wave whose lowest point is at
-- DIP_LOWEST_POINT, so the legs are already driving up at takeoff.
local function dipAmount(progress: number): number
	if progress <= 0 or progress >= 1 then
		return 0
	end
	local lowest = math.clamp(Motion.DIP_LOWEST_POINT, 0.05, 0.95)
	-- Squash time so the wave's midpoint (its lowest point) lands on `lowest`.
	local wave = if progress < lowest then 0.5 * progress / lowest else 0.5 + 0.5 * (progress - lowest) / (1 - lowest)
	return math.sin(wave * math.pi)
end

-- The floor height under the player (a ray straight down, ignoring the player's body).
local function floorHeight(parts: CharacterRef.Parts): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { parts.character }
	params.RespectCanCollide = true -- only solid ground (not the ball or other effects)
	local hit = workspace:Raycast(parts.root.Position, Vector3.new(0, -20, 0), params)
	return if hit then hit.Position.Y else parts.root.Position.Y - parts.humanoid.HipHeight - parts.root.Size.Y / 2
end

-- The way the body faces, flat (rotation only, no tilt).
local function facing(rootCFrame: CFrame): CFrame
	local look = flat(rootCFrame.LookVector)
	if look.Magnitude < 1e-3 then
		return CFrame.identity
	end
	return CFrame.lookAt(Vector3.zero, look.Unit)
end

-- The yaw a planted foot of `side` wants for a body facing `bodyYaw`: toes turned out.
local function wantedYaw(side: Side, bodyYaw: number): number
	return bodyYaw - GaitMath.sign(side) * math.rad(Footwork.TOE_OUT)
end

-- How far a foot can be from directly under its hip joint right now (flat studs).
local function currentReach(extraCrouch: number): number
	return GaitMath.reachForCrouch(legLength, crouch + extraCrouch + Footwork.REACH_STEP_DIP, Footwork.REACH_MARGIN)
end

-- `spot` moved toward `center` if it is further than `reach` from it (flat).
local function withinReach(spot: Vector3, center: Vector3, reach: number): Vector3
	local offset = flat(spot - center)
	if offset.Magnitude > reach then
		return center + offset.Unit * reach
	end
	return spot
end

-- The crouch impulse of a landing right now, studs: dips quickly, then recovers.
local function landExtra(now: number): number
	local t = (now - landedAt) / math.max(Footwork.LAND_RECOVER_TIME, 0.05)
	if t < 0 or t >= 1 then
		return 0
	end
	local dip = 0.3 -- share of the recovery time spent going down
	local shape = if t < dip then ease(t / dip) else 1 - ease((t - dip) / (1 - dip))
	return Footwork.LAND_ABSORB * landStrength * shape
end

-- The CFrame to aim an ankle at: flat position + resting ankle height + `height`, pointing
-- `yaw`, with the foot pitched by `pitch` (radians, + toe up). A pitched foot is raised so
-- its toe (or heel) rests on the floor rather than inside it.
local function footCFrame(
	side: Side,
	position: Vector3,
	height: number,
	yaw: number,
	pitch: number,
	floorY: number
): CFrame
	local clearance = if pitch < 0
		then Footwork.FOOT_TOE_LENGTH * math.sin(-pitch)
		else Footwork.FOOT_HEEL_LENGTH * math.sin(pitch)
	local ankle = Vector3.new(position.X, floorY + ankleHeights[side] + height + clearance, position.Z)
	return CFrame.new(ankle) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

-- Where the knee should point for a foot at `position`: forward and a bit out, above the floor.
local function kneePole(side: Side, position: Vector3, look: Vector3, right: Vector3, floorY: number): Vector3
	return position
		+ look * Footwork.KNEE_FORWARD
		+ right * (GaitMath.sign(side) * Footwork.KNEE_OUT)
		+ Vector3.new(0, floorY + 1, 0)
end

-- FOOTFALL SIGNAL ---------------------------------------------------------------------------

-- The average time between the last few footfalls, or nil if there aren't enough yet.
local function gaitPeriod(): number?
	if #plantTimes < 2 then
		return nil
	end
	return (plantTimes[#plantTimes] - plantTimes[1]) / (#plantTimes - 1)
end

-- A foot touched down: remember when, and tell the ball (it bounces in time with the feet).
local function recordPlant(side: Side, now: number)
	if now - lastPlantAt > Footwork.GAIT_FORGET_TIME then
		table.clear(plantTimes) -- a long gap: the rhythm starts over
	end
	lastPlantAt = now
	table.insert(plantTimes, now)
	if #plantTimes > 4 then
		table.remove(plantTimes, 1) -- keep the last 4 = the last 3 intervals
	end
	-- Standing still has no rhythm to follow.
	BallController.notifyFootPlant(side, if lastSpeed > 1 then gaitPeriod() else nil)
end

-- Seconds since the last foot touched down, and the estimated seconds between footfalls
-- (nil if unknown or standing).
function LegController.getGaitInfo(): (number, number?)
	return os.clock() - lastPlantAt, if lastSpeed > 1 then gaitPeriod() else nil
end

-- While Roblox's run animation has the legs: a foot "plants" when its ankle comes back down
-- to the floor (within PLANT_DETECT_HEIGHT of its resting height) after having been lifted.
-- The two heights (lift at twice the plant height, plant below it) are a hysteresis, so a
-- foot wobbling near the floor reports one plant, not many.
local function detectAnimationPlants(parts: CharacterRef.Parts, floorY: number, now: number)
	for _, side in SIDES do
		local ankle = ankleOf(parts.character, side)
		if ankle then
			local height = ankle.WorldPosition.Y - floorY - ankleHeights[side]
			if height > Footwork.PLANT_DETECT_HEIGHT * 2 then
				animationLifted[side] = true
			elseif animationLifted[side] and height < Footwork.PLANT_DETECT_HEIGHT then
				animationLifted[side] = false
				recordPlant(side, now)
			end
		end
	end
end

-- GROUND FOOTWORK ---------------------------------------------------------------------------

-- A fresh foot at flat world position `position`, pointing `yaw`, whose ankle is `height`
-- studs above its resting height (it eases down over `settle` seconds).
local function newFoot(
	position: Vector3,
	yaw: number,
	height: number,
	settle: number,
	staggerZ: number,
	now: number
): Foot
	return {
		position = position,
		yaw = yaw,
		stepping = false,
		from = position,
		to = position,
		yawFrom = yaw,
		fromHeight = 0,
		aim = nil,
		startedAt = 0,
		duration = 0.1,
		lift = 0,
		bulge = Vector3.zero,
		bulgeBody = false,
		pendingLandPitch = 0,
		landPitch = 0,
		landedAt = -math.huge,
		settleHeight = math.max(height, 0),
		settleStart = now,
		settleDuration = math.max(settle, 0.01),
		staggerZ = staggerZ,
		pivot = false,
		pivotYawOffset = 0,
		ballPoint = position,
		airborne = false,
	}
end

-- How high a foot's settle offset still is (a foot that was in the air eases to the floor).
local function settleOf(foot: Foot, now: number): number
	if foot.settleHeight <= 0 then
		return 0
	end
	local remaining = 1 - (now - foot.settleStart) / foot.settleDuration
	if remaining <= 0 then
		return 0
	end
	return foot.settleHeight * ease(remaining)
end

-- The stagger offset (z) `side`'s foot would get in the stance with the ball in `ballHand`.
local function staggerOf(side: Side, ballHand: Side?): number
	local _, z = GaitMath.homeOffset(side, ballHand, Footwork)
	return z
end

-- Where each foot is right now, read from the body (used to start the footwork from
-- whatever pose the body is in, e.g. after landing or after running). A foot that is off the
-- floor keeps that height and eases down over `settle` seconds, so nothing snaps.
local function readFeet(parts: CharacterRef.Parts, floorY: number, settle: number, now: number): { [Side]: Foot }
	local result = {}
	local ballHand: Side? = if BallController.getMode() == "Dribble" then BallController.getHand() else nil
	local bodyYaw = yawOf(parts.root.CFrame)
	for _, side in SIDES do
		local ankle = ankleOf(parts.character, side)
		local position = if ankle
			then flat(ankle.WorldPosition)
			else flat(parts.root.CFrame:PointToWorldSpace(Vector3.new(GaitMath.sign(side) * 0.5, 0, 0)))
		local height = if ankle then ankle.WorldPosition.Y - floorY - ankleHeights[side] else 0
		-- The foot's own direction (flat) from the ankle, if it points anywhere sensible.
		local yaw = wantedYaw(side, bodyYaw)
		if ankle then
			local look = flat(ankle.WorldCFrame.LookVector)
			if look.Magnitude > 0.3 then
				yaw = math.atan2(-look.X, -look.Z)
				-- Stay within the twist limit of the body so a stray animation pose can't leave a sideways foot.
				local off = GaitMath.angleDelta(wantedYaw(side, bodyYaw), yaw)
				local limit = math.rad(Footwork.FOOT_TWIST_LIMIT)
				yaw = wantedYaw(side, bodyYaw) + math.clamp(off, -limit, limit)
			end
		end
		result[side] = newFoot(position, yaw, height, settle, staggerOf(side, ballHand), now)
	end
	return result
end

-- Starts `foot` stepping toward `target` (flat, roughly where it will land) over `duration`
-- seconds, rising `lift` studs. `aim` says how the landing spot is worked out each frame.
local function beginStep(
	foot: Foot,
	aim: Aim,
	target: Vector3,
	duration: number,
	lift: number,
	landPitch: number,
	now: number
)
	foot.fromHeight = settleOf(foot, now)
	foot.settleHeight = 0
	foot.stepping = true
	foot.pivot = false
	foot.from = foot.position
	foot.yawFrom = foot.yaw
	foot.to = target
	foot.aim = aim
	foot.startedAt = now
	foot.duration = math.max(duration, 0.03)
	foot.lift = lift
	foot.bulge = Vector3.zero
	foot.bulgeBody = false
	foot.pendingLandPitch = landPitch
end

-- Gets `feet` ready (reading them from the body if need be) for the public step functions.
local function ensureFeet(parts: CharacterRef.Parts, now: number): { [Side]: Foot }
	local existing = feet
	if existing then
		return existing
	end
	local read = readFeet(parts, floorHeight(parts), Footwork.FOOT_SETTLE_TIME, now)
	feet = read
	return read
end

-- Starts the dip. `duration` = seconds until takeoff; `motionStyle` = which motion the shot
-- uses (JumpShot: a two-foot dip; Layup: a one-foot takeoff off the LEFT foot with the right
-- knee driving; Dunk: a deep two-foot load). `options` says what the feet do inside the dip
-- (see DipOptions): which gather, how the body slides, how deep. Everything fits inside the
-- dip, so the shot's timing is unchanged.
function LegController.startDip(duration: number, motionStyle: Shooting.MotionStyle, options: DipOptions?)
	local parts = CharacterRef.get()
	if not parts then
		return
	end
	local now = os.clock()
	local floorY = floorHeight(parts)
	local rootCFrame = parts.root.CFrame
	local turn = facing(rootCFrame)
	local right, look = turn.RightVector, turn.LookVector
	local bodyYaw = yawOf(turn)
	local hips = flat(rootCFrame.Position)
	refreshHips(parts)

	local gather: GatherKind = (options and options.gather) or "None"
	local depthScale = (options and options.depthScale) or 1
	local v0 = flat(MovementController.getVelocity())
	local driftV = if options and options.drift then flat(options.drift) else v0
	-- How fast ShotController eases the body to that drift (studs/s²); the feet are placed
	-- for the same slide, so they land under the hips instead of being dragged.
	local dipRate = if options and options.rate then options.rate else Motion.DRIFT_BLEND_RATE

	-- The dip starts from the crouch the player is already in and goes a bit lower, relative
	-- to it, so the dip shows whether the player was standing tall or low.
	dipStartDrop = math.max(standingHipHeight - parts.humanoid.HipHeight, 0)
	local extra = if motionStyle == "Layup"
		then Footwork.LAYUP_PLANT_EXTRA
		elseif motionStyle == "Dunk" then Footwork.DUNK_DIP_EXTRA
		else Footwork.SHOT_DIP_EXTRA
	dipDeepest = math.max(math.min(dipStartDrop + extra * depthScale, Footwork.DIP_MAX_CROUCH), dipStartDrop)
	dipStartedAt = now
	dipDuration = math.max(duration, 0.05)
	style = motionStyle
	phase = "Dip"
	scripted = false
	moveCrouch = 0
	hipsPath = nil

	-- Hip joints in the root's own space (the air legs hang from them).
	for _, side in SIDES do
		local attachment = hipAttachments[side]
		hipRel[side] = if attachment and attachment.Parent
			then rootCFrame:PointToObjectSpace(attachment.WorldPosition)
			else Vector3.new(GaitMath.sign(side) * 0.5, -1, 0)
	end

	-- Where the feet are now. After an approach they are exactly where the steps put them.
	local startFeet: { [Side]: Foot }
	if feet then
		startFeet = feet
		for _, side in SIDES do
			local foot = startFeet[side]
			if foot.stepping then
				foot.position = foot.to -- a step that is a frame from landing lands now
				foot.stepping = false
			end
		end
	else
		startFeet = readFeet(parts, floorY, Footwork.FOOT_SETTLE_TIME, now)
	end
	local hadApproach = approach ~= nil
	approach = nil

	dipFeet = {}
	for _, side in SIDES do
		local foot = startFeet[side]
		dipFeet[side] = { current = foot.position, yaw = foot.yaw, step = nil }
	end

	-- Plans a step for `side` inside the dip, landing at `to` (flat) at `landAt` (share of the dip).
	local function planStep(
		side: Side,
		to: Vector3,
		startAt: number,
		landAt: number,
		landPitch: number,
		holdPitch: number
	)
		local from = dipFeet[side].current
		local delta = flat(to - from)
		if delta.Magnitude > Footwork.DIP_MAX_STEP then
			delta = delta.Unit * Footwork.DIP_MAX_STEP -- never more than about one step
		end
		local lift = if delta.Magnitude < 0.1 then 0 else Footwork.DIP_STEP_LIFT
		dipFeet[side].step = {
			from = from,
			to = from + delta,
			startAt = startAt,
			landAt = math.max(landAt, startAt + 0.05),
			lift = lift,
			landPitch = landPitch,
			holdPitch = holdPitch,
		}
		dipFeet[side].yaw = wantedYaw(side, bodyYaw)
	end

	-- How far the hips will have slid `seconds` into the dip (flat). A pull-up is given the
	-- average velocity over its braking, so that is simply velocity x time; the others ease
	-- from the current velocity to the drift the way MovementController does.
	local function slide(seconds: number): Vector3
		if gather == "PullUp" then
			return driftV * seconds
		end
		local dx, dz = GaitMath.dipTravel(v0.X, v0.Z, driftV.X, driftV.Z, dipRate, seconds)
		return Vector3.new(dx, 0, dz)
	end
	local lowest = math.clamp(Motion.DIP_LOWEST_POINT, 0.05, 0.95)
	local halfWidth = Footwork.STANCE_WIDTH / 2
	local travel = slide(dipDuration)
	local travelDir = if travel.Magnitude > 0.05 then travel.Unit else look
	local ballHand: Side = BallController.getHand()
	local toePitch = math.rad(Footwork.BALL_OF_FOOT_PITCH)

	if gather == "PullUp" and v0.Magnitude > 0.5 then
		-- Brake 1-2: the inside foot (opposite the ball hand) plants AHEAD of the hips, heel
		-- first; the other foot steps in level beside it a little later.
		local inside: Side = if ballHand == "Right" then "Left" else "Right"
		local outside: Side = if inside == "Right" then "Left" else "Right"
		local brake = hips + travelDir * Footwork.PULLUP_BRAKE_AHEAD + right * (GaitMath.sign(inside) * halfWidth)
		planStep(inside, brake, 0, Footwork.PULLUP_BRAKE_LAND_AT, math.rad(Footwork.PULLUP_BRAKE_TOE_UP), 0)
		planStep(
			outside,
			brake - right * (GaitMath.sign(inside) * Footwork.STANCE_WIDTH),
			Footwork.PULLUP_BRAKE_LAND_AT * 0.5,
			Footwork.PULLUP_SECOND_FOOT_AT,
			0,
			0
		)
	elseif gather == "SideStep" then
		-- The body hops sideways in the dip. The LEAD foot in the direction of travel lands
		-- first and brakes; the other follows. Both land on the balls of the feet, under where
		-- the hips end up, and the hips stay level.
		local landed = hips + travel
		local first: Side = if travel:Dot(right) >= 0 then "Right" else "Left"
		local firstSpot = landed + travelDir * (halfWidth + Footwork.SIDESTEP_LEAD_AHEAD)
		local secondSpot = landed - travelDir * halfWidth
		local second: Side = if first == "Right" then "Left" else "Right"
		planStep(first, firstSpot, 0, Footwork.SIDESTEP_FIRST_AT, -toePitch, -toePitch)
		planStep(
			second,
			secondSpot,
			Footwork.SIDESTEP_FIRST_AT * 0.5,
			Footwork.SIDESTEP_SECOND_AT,
			-toePitch,
			-toePitch
		)
	else
		-- Plain gather: both feet end up under the hips as they are at the bottom of the dip.
		-- If the body barely slides (a standing shot) the feet just stay put.
		local shift = slide(lowest * dipDuration)
		-- (After an approach the LEFT foot has just planted exactly where it should be, and the
		-- right one is about to swing: neither is moved.)
		if shift.Magnitude > Footwork.DIP_MIN_SLIDE and not (motionStyle == "Layup" and hadApproach) then
			-- The foot further along the direction of travel lands first.
			local rightAhead = (dipFeet.Right.current - dipFeet.Left.current):Dot(shift) >= 0
			for _, side in SIDES do
				local leads = (side == "Right") == rightAhead
				local land = Footwork.DIP_FEET_LAND_AT + (if leads then -0.05 else 0.05)
				planStep(side, dipFeet[side].current + shift, 0, land, 0, 0)
			end
		end
		if motionStyle == "Layup" and hadApproach then
			-- After running steps the LEFT foot is normally already planted. But if the hips will
			-- slide past it during the dip (a fast drive, e.g. a running dunk), the plant is made
			-- a quick heel-first step to a spot that the hips reach halfway through the dip, so
			-- the foot is under the body at takeoff instead of being dragged behind it.
			local plantSpot = hips + slide(0.5 * dipDuration) - right * (halfWidth * 0.8)
			local behind = (plantSpot - dipFeet.Left.current):Dot(travelDir)
			if behind > Footwork.DIP_MIN_SLIDE then
				planStep(
					"Left",
					plantSpot,
					0,
					Footwork.DIP_FEET_LAND_AT * 0.6,
					math.rad(Footwork.APPROACH_PLANT_TOE_UP),
					0
				)
			end
		elseif motionStyle == "Layup" then
			-- A close layup (no running steps): the LEFT foot makes the plant inside the dip,
			-- heel first, just ahead of the hips; the right leg swings forward later.
			local plant = hips + slide(Footwork.DIP_FEET_LAND_AT * dipDuration)
			planStep(
				"Left",
				plant - right * halfWidth * 0.8 + look * Footwork.PLANT_AHEAD,
				0,
				Footwork.DIP_FEET_LAND_AT,
				math.rad(Footwork.APPROACH_PLANT_TOE_UP),
				0
			)
		end
	end
	freeLegRel = rootCFrame:PointToObjectSpace(
		Vector3.new(dipFeet.Right.current.X, floorY + ankleHeights.Right, dipFeet.Right.current.Z)
	)
	feet = nil
end

-- The running gather steps before a layup or running dunk (called when the sequence starts,
-- `duration` seconds before startDip). The legs take over from the run animation at `drift`
-- (flat world velocity) and step so that the LAST two contacts before the dip are a long
-- RIGHT gather step (the hips drop a little) and then the LEFT plant, which lands heel first,
-- slightly ahead of the hips, exactly as startDip is called.
function LegController.startApproach(duration: number, drift: Vector3, motionStyle: Shooting.MotionStyle)
	local parts = CharacterRef.get()
	if not parts or duration <= 0 then
		return
	end
	local _ = motionStyle -- (one-foot takeoffs only: both Layup and running dunks use the same gather)
	local now = os.clock()
	local speed = math.max(flat(drift).Magnitude, 1)
	local gatherTime = math.clamp(
		Footwork.GATHER_STEP_LENGTH / speed,
		Footwork.APPROACH_STEP_MIN_TIME,
		Footwork.APPROACH_STEP_MAX_TIME
	)
	local plantTime = math.clamp(
		Footwork.GATHER_STEP_LENGTH * Footwork.PLANT_STEP_SHARE / speed,
		Footwork.APPROACH_STEP_MIN_TIME,
		Footwork.APPROACH_STEP_MAX_TIME
	)
	local steps = GaitMath.approachSchedule(duration, gatherTime, plantTime, 0.05)
	local started: { boolean } = {}
	for i = 1, #steps do
		started[i] = false
	end
	-- The hips drop across the right gather step (or the plant, if there is no gather step).
	local dropStep = steps[#steps - 1] or steps[#steps]
	approach = {
		startedAt = now,
		steps = steps,
		started = started,
		dropFrom = if dropStep then dropStep.startAt else 0,
		dropTo = if dropStep then dropStep.landAt else duration,
		startCrouch = crouch,
	}
	scripted = false
	moveCrouch = 0
	hipsPath = nil
	ensureFeet(parts, now)
end

-- The player left the ground: straighten the legs (or, on a layup, drive the knee up).
function LegController.takeoff()
	takeoffAt = os.clock()
	phase = "Air"
	apexAt = nil
	peakFall = 0
	takeoffPower = 0
	fadeBlend = 0
	PostureController.setDipHinge(0) -- the chest rises to vertical by the release
end

-- The knees absorb a landing of `strength` (0-1): a crouch that recovers, plus a quick dip
-- of the trunk. Called on every landing from a jump; the step-back move calls it too.
function LegController.absorbLanding(strength: number)
	landedAt = os.clock()
	landStrength = math.clamp(strength, 0, 1)
	PostureController.absorbLanding(landStrength)
end

-- The player landed (or the shot was cancelled): back to footwork on the ground. The feet
-- stay where they came down (they ease onto the floor), the knees absorb the landing.
function LegController.land()
	local wasAirborne = phase == "Air"
	phase = "Off"
	approach = nil
	PostureController.setDipHinge(0)
	local parts = CharacterRef.get()
	feet = nil -- pick the feet up from wherever they landed
	if parts and wasAirborne then
		local now = os.clock()
		feet = readFeet(parts, floorHeight(parts), Footwork.LAND_FOOT_BLEND, now)
		local strength = math.clamp(peakFall / math.max(Footwork.LAND_FALL_SPEED_REF, 1), Footwork.LAND_MIN_STRENGTH, 1)
		LegController.absorbLanding(strength)
	end
end

-- DRIBBLE MOVE FOOTWORK (called by SkillController) ----------------------------------------

-- true while a dribble move places the feet itself: no automatic steps, so the feet stay
-- exactly where the move puts them. false hands them back to the automatic footwork.
function LegController.setScripted(on: boolean)
	scripted = on
	if not on then
		hipsPath = nil
		if feet then
			for _, side in SIDES do
				feet[side].pivot = false
			end
		end
	end
end

-- Extra studs to lower the hips during a dribble move (0 = back to the normal stance).
function LegController.setMoveCrouch(amount: number)
	moveCrouch = amount
end

-- A move that carries the hips along its own path (the spin) tells the legs where the hips
-- will be `seconds` from now (flat world position), so steps land where the body WILL be.
-- Pass nil to go back to extrapolating the body's velocity.
function LegController.setHipsPath(path: ((seconds: number) -> Vector3)?)
	hipsPath = path
end

-- Where `side`'s foot is planted, or lands if it is mid-step (flat world position), or nil
-- if the feet aren't being tracked (e.g. the run animation has them).
function LegController.getFootPosition(side: Side): Vector3?
	local parts = CharacterRef.get()
	if not parts then
		return nil
	end
	local foot = ensureFeet(parts, os.clock())[side]
	return if foot.stepping then foot.to else foot.position
end

-- Steps `side`'s foot over `duration` seconds, rising `lift` studs at the middle of the
-- step, to land at `offset` from the hips (x = studs right, z = studs forward) as they are
-- when it lands. `frame` = which way right/forward are (nil = the way the body faces, read
-- each frame; the spin passes its starting facing because the body turns underneath).
-- `bulge` (flat) sweeps the foot out that way mid-step; with `bulgeInBodySpace` it is in the
-- body's own frame (x right, z forward) and so turns with it.
function LegController.stepFoot(
	side: Side,
	offset: Vector3,
	duration: number,
	lift: number,
	frame: CFrame?,
	bulge: Vector3?,
	bulgeInBodySpace: boolean?
)
	local parts = CharacterRef.get()
	if not parts or phase ~= "Off" then
		return
	end
	local now = os.clock()
	local foot = ensureFeet(parts, now)[side]
	local aim: Aim = { offset = offset, frame = frame, ahead = Footwork.MOVE_LAND_AHEAD, keepApart = false }
	beginStep(foot, aim, foot.position, duration, lift, 0, now)
	foot.bulge = if bulge then flat(bulge) else Vector3.zero
	foot.bulgeBody = bulgeInBodySpace == true
end

-- Like stepFoot, but lands on a fixed spot in the world (flat) instead of beside the hips.
function LegController.stepFootTo(
	side: Side,
	spot: Vector3,
	duration: number,
	lift: number,
	bulge: Vector3?,
	bulgeInBodySpace: boolean?
)
	local parts = CharacterRef.get()
	if not parts or phase ~= "Off" then
		return
	end
	local now = os.clock()
	local foot = ensureFeet(parts, now)[side]
	local target = flat(spot)
	local aim: Aim = { offset = Vector3.zero, frame = nil, ahead = 0, keepApart = false, world = target }
	beginStep(foot, aim, target, duration, lift, 0, now)
	foot.bulge = if bulge then flat(bulge) else Vector3.zero
	foot.bulgeBody = bulgeInBodySpace == true
end

-- Makes `side`'s planted foot twist on the ball of the foot as the body turns (the spin's
-- pivot foot): the ball stays where it is and the heel swings round. Returns the ball of the
-- foot (flat world position), the point the body turns about. Pass false to stop pivoting.
function LegController.pivotFoot(side: Side, on: boolean): Vector3?
	local parts = CharacterRef.get()
	if not parts then
		return nil
	end
	local foot = ensureFeet(parts, os.clock())[side]
	if on then
		-- (A foot still in the air pivots on the spot it is about to land on.)
		local base = if foot.stepping then foot.to else foot.position
		foot.stepping = false
		foot.position = base
		foot.pivot = true
		foot.pivotYawOffset = GaitMath.angleDelta(wantedYaw(side, yawOf(parts.root.CFrame)), foot.yaw)
		foot.ballPoint = base + forwardOf(foot.yaw) * Footwork.FOOT_BALL_FORWARD
		return foot.ballPoint
	end
	foot.pivot = false
	return nil
end

-- One frame of footwork on the ground. Sets how much each leg should follow its IK target
-- in `legGoals` (1 = footwork, 0 = Roblox's animation, e.g. running forward).
local function updateGround(parts: CharacterRef.Parts, dt: number, now: number, floorY: number)
	local humanoid = parts.humanoid
	local rootCFrame = parts.root.CFrame
	local turn = facing(rootCFrame)
	local bodyYaw = yawOf(turn)
	local right, look = turn.RightVector, turn.LookVector
	local velocity = flat(MovementController.getVelocity())
	local speed = velocity.Magnitude
	lastSpeed = speed
	local hasBall = BallController.getMode() == "Dribble"
	local approaching = approach ~= nil

	-- Who drives the legs: running forward → the run animation; in the air (a jump, a fall)
	-- → the animation; otherwise (standing, shuffling, backpedalling, dribble moves, the
	-- approach to a layup) → us. Entering the run animation takes more speed and straightness
	-- than staying in it, so near the edge the legs don't flip back and forth.
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local forwardness = if speed > 1e-3 then velocity.Unit:Dot(look) else 0
	if animationRunning then
		if speed < Footwork.ANIMATION_RUN_EXIT_SPEED or forwardness < Footwork.ANIMATION_RUN_EXIT_DOT then
			animationRunning = false
		end
	elseif speed > Footwork.ANIMATION_RUN_SPEED and forwardness > Footwork.ANIMATION_RUN_DOT then
		animationRunning = true
	end
	local goal = if approaching or (grounded and (scripted or not animationRunning)) then 1 else 0
	local sideways = velocity:Dot(right)
	local alongLook = velocity:Dot(look)
	local shuffling = speed > 0.5 and math.abs(sideways) > math.abs(alongLook)
	local backpedalling = speed > 0.5 and not shuffling and alongLook < -0.5

	-- Hips: crouch into the stance (only while the footwork has the legs: the run animation
	-- expects standing height). During an approach they drop for the gather step instead.
	if approach then
		local a = approach
		local elapsed = now - a.startedAt
		-- From the stance crouch the approach started in, to the gather's hip drop.
		local drop = ease((elapsed - a.dropFrom) / math.max(a.dropTo - a.dropFrom, 0.05))
		crouch = a.startCrouch + (Footwork.GATHER_HIP_DROP - a.startCrouch) * drop
	else
		local shuffleCrouch = if shuffling and hasBall and not scripted then Footwork.SHUFFLE_CROUCH else 0
		local targetCrouch = (if hasBall then Footwork.DRIBBLE_CROUCH else Footwork.NO_BALL_CROUCH) * goal
			+ moveCrouch
			+ shuffleCrouch
		crouch += (targetCrouch - crouch) * MovementMath.smoothingAlpha(Footwork.CROUCH_SHARPNESS, dt)
	end
	local extraCrouch = landExtra(now)
	if standingHipHeight > 0 then
		parts.humanoid.HipHeight = standingHipHeight - crouch - extraCrouch
	end
	-- Published for BallController / ArmController: the ball in the hand comes down with
	-- the shoulders (a lower stance = a lower dribble).
	humanoid:SetAttribute("RoHoopsCrouch", crouch)
	-- Chest forward over the ball (PostureController eases it, and drops it while shooting).
	PostureController.setStanceLean(-(if hasBall then Footwork.DRIBBLE_LEAN else Footwork.NO_BALL_LEAN) * goal)

	if goal == 0 then
		feet = nil -- the animation has the feet; pick them up from there when we take over
		legGoals.Right, legGoals.Left = 0, 0
		detectAnimationPlants(parts, floorY, now)
		return
	end
	legGoals.Right, legGoals.Left = 1, 1
	animationLifted.Right, animationLifted.Left = false, false
	local current = ensureFeet(parts, now)

	local hips = flat(rootCFrame.Position)
	if speed > 0.5 then
		stillSince = now
	end
	local ballHand: Side? = if hasBall then BallController.getHand() else nil
	local stepTime = GaitMath.stepDuration(speed, Footwork)
	-- The velocity to plan steps with: where the body is heading. When it's slowing down
	-- (e.g. stopping after a move) that's less than its current speed, so the feet don't
	-- land past where it will stop.
	local heading = flat(MovementController.getTargetVelocity())
	local travelVelocity = if heading.Magnitude < speed then (velocity + heading) / 2 else velocity
	local reach = currentReach(extraCrouch)

	-- The stance offset (x right, z forward from the hips) of `side`'s foot. `fresh` = use
	-- the stagger the ball hand wants now; otherwise a hand switch's small change is ignored.
	local function stanceOffset(side: Side, fresh: boolean): Vector3
		local x, z = GaitMath.homeOffset(side, ballHand, Footwork)
		if not fresh then
			z = GaitMath.effectiveStagger(z, current[side].staggerZ, Footwork.STAGGER_RESTEP)
		end
		return Vector3.new(x, 0, z + Footwork.FEET_FORWARD)
	end
	-- Where the hips will be `seconds` from now (flat).
	local function hipsIn(seconds: number): Vector3
		local path = hipsPath
		if path then
			return flat(path(math.max(seconds, 0)))
		end
		return hips + travelVelocity * math.max(seconds, 0)
	end
	-- `side`'s hip joint `seconds` from now (flat).
	local function hipJointIn(side: Side, seconds: number): Vector3
		return hipsIn(seconds) + hipOffsets[side]
	end
	-- Where `aim` puts `side`'s foot when it lands `seconds` from now, before the keep-apart
	-- check. Never further than the real reach from under its hip at that moment (so the leg
	-- can actually reach it when it lands). A fixed world spot is left alone.
	local function aimSpot(side: Side, aim: Aim, seconds: number): Vector3
		if aim.world then
			return aim.world
		end
		local frame = aim.frame or turn
		local spot = hipsIn(seconds + aim.ahead) + frame.RightVector * aim.offset.X + frame.LookVector * aim.offset.Z
		return withinReach(spot, hipJointIn(side, seconds), reach)
	end
	-- `spot` for `side`'s foot moved out so it doesn't land across the other foot (measured
	-- sideways from the hips, against where the other foot is or will land).
	local function apart(side: Side, spot: Vector3): Vector3
		local other = current[if side == "Right" then "Left" else "Right"]
		local otherSpot = if other.stepping then other.to else other.position
		local x = (spot - hips):Dot(right)
		local apartX = GaitMath.keepApart(side, x, (otherSpot - hips):Dot(right), Footwork.MIN_FOOT_GAP)
		return spot + right * (apartX - x)
	end
	-- Limits a step to `aim.maxStep` from where the foot left.
	local function capped(foot: Foot, aim: Aim, spot: Vector3): Vector3
		local limit = aim.maxStep
		if limit then
			local delta = flat(spot - foot.from)
			if delta.Magnitude > limit then
				return foot.from + delta.Unit * limit
			end
		end
		return spot
	end

	-- Starts `side`'s foot stepping to its stance spot, landing a little ahead when moving.
	local function startStep(side: Side)
		local foot = current[side]
		local offset = stanceOffset(side, true)
		foot.staggerZ = offset.Z - Footwork.FEET_FORWARD
		if shuffling then
			-- Step-slide: the lead foot reaches out wide, the trail foot slides in close to it
			-- (keepApart stops them touching), so the base opens and closes each cycle.
			local leads = (side == "Right") == (sideways > 0)
			local widen = if leads then Footwork.SHUFFLE_LEAD_OUT else -Footwork.SHUFFLE_TRAIL_IN
			offset += Vector3.new(GaitMath.sign(side) * widen, 0, 0)
		end
		local aim: Aim = {
			offset = offset,
			frame = nil,
			ahead = stepTime * Footwork.LAND_AHEAD,
			keepApart = true,
			world = nil,
			maxStep = if backpedalling then Footwork.BACKPEDAL_MAX_STEP else nil,
		}
		local spot = apart(side, aimSpot(side, aim, stepTime))
		foot.from = foot.position -- (so `capped` measures from here)
		spot = capped(foot, aim, spot)
		local lift = if shuffling
			then Footwork.SHUFFLE_LIFT
			else GaitMath.liftFor(
				(spot - foot.position).Magnitude,
				Footwork.LIFT_PER_STUD,
				Footwork.MIN_LIFT,
				Footwork.MAX_LIFT
			)
		local landPitch = if backpedalling then -math.rad(Footwork.BACKPEDAL_TOE_DOWN) else 0
		beginStep(foot, aim, spot, stepTime, lift, landPitch, now)
	end

	local wanted: { [Side]: number } = { Right = wantedYaw("Right", bodyYaw), Left = wantedYaw("Left", bodyYaw) }
	local twistLimit = math.rad(Footwork.FOOT_TWIST_LIMIT)

	-- The approach to a layup: start each running step when its time comes, and keep a
	-- planted foot from being left behind out of reach (it slides, like a stance foot in a run).
	local a = approach
	if a then
		local elapsed = now - a.startedAt
		for i, step in a.steps do
			if not a.started[i] and elapsed >= step.startAt then
				a.started[i] = true
				local foot = current[step.side]
				local isPlant = i == #a.steps
				local ahead = if isPlant then Footwork.PLANT_AHEAD else Footwork.GATHER_AHEAD
				local lateral = GaitMath.sign(step.side) * (math.abs(hipOffsets[step.side]:Dot(right)) + 0.05)
				local aim: Aim = {
					offset = Vector3.new(lateral, 0, ahead),
					frame = nil,
					ahead = 0,
					keepApart = false,
				}
				local flight = math.max(step.landAt - step.startAt, 0.05)
				local landPitch = if isPlant then math.rad(Footwork.APPROACH_PLANT_TOE_UP) else 0
				beginStep(foot, aim, foot.position, flight, Footwork.APPROACH_STEP_LIFT, landPitch, now)
			end
		end
		for _, side in SIDES do
			local foot = current[side]
			if not foot.stepping then
				foot.position = withinReach(foot.position, hips + hipOffsets[side], reach)
			end
		end
	end

	-- Safety: a planted foot left too far behind (out of the leg's real reach) steps at once.
	-- This also applies during dribble moves, so a foot is never dragged along the floor.
	if not approaching then
		for _, side in SIDES do
			local foot = current[side]
			if not foot.stepping and not foot.pivot then
				local hipSpot = hips + hipOffsets[side]
				if flat(foot.position - hipSpot).Magnitude > reach then
					startStep(side)
				end
			end
		end
	end

	if not scripted and not approaching then
		-- Normal steps: the foot furthest from its spot goes first (in a shuffle the LEAD foot
		-- goes first). The next foot may leave once the stepping one is far enough through
		-- its step: STEP_OVERLAP (quick feet when moving fast), or SHUFFLE_TRAIL_DELAY for
		-- the trail foot of a step-slide.
		local overlap = if shuffling then Footwork.SHUFFLE_TRAIL_DELAY else Footwork.STEP_OVERLAP
		local function ready(foot: Foot): boolean
			return not foot.stepping or (now - foot.startedAt) / foot.duration >= overlap
		end
		if ready(current.Right) and ready(current.Left) then
			local moving = speed > 0.5
			local threshold = if moving
				then Footwork.STEP_TRIGGER
				elseif now - stillSince > Footwork.SETTLE_DELAY then Footwork.SETTLE_TRIGGER
				else math.huge
			-- A foot already in the air can't be picked again.
			local function distanceFromSpot(side: Side): number
				local foot = current[side]
				if foot.stepping then
					return 0
				end
				local offset = stanceOffset(side, false)
				local spot = hipsIn(stepTime * 0.5) + right * offset.X + look * offset.Z
				local miss = (foot.position - spot).Magnitude
				-- A foot pointing too far off from the body (it has turned) steps to straighten.
				if math.abs(GaitMath.angleDelta(wanted[side], foot.yaw)) > twistLimit then
					miss = math.max(miss, 1)
				end
				return miss
			end
			local lead: Side? = if shuffling then (if sideways > 0 then "Right" else "Left") else nil
			local side = GaitMath.pickStepper(distanceFromSpot("Right"), distanceFromSpot("Left"), threshold, lead)
			if side then
				startStep(side)
			end
		end
	end

	-- Re-aim every foot that's in the air at where its spot will be when it lands.
	for _, side in SIDES do
		local foot = current[side]
		local aim = foot.aim
		if foot.stepping and aim then
			local spot = aimSpot(side, aim, foot.startedAt + foot.duration - now)
			spot = if aim.keepApart then apart(side, spot) else spot
			foot.to = capped(foot, aim, spot)
		end
	end

	-- Move the feet through their steps and place them.
	for _, side in SIDES do
		local foot = current[side]
		local height = settleOf(foot, now)
		local pitch = 0
		local yawWanted = wanted[side]
		if foot.stepping then
			local progress = (now - foot.startedAt) / foot.duration
			local along, rise = GaitMath.swing(progress)
			local bulge = foot.bulge
			if foot.bulgeBody then
				bulge = turn:VectorToWorldSpace(Vector3.new(bulge.X, 0, -bulge.Z)) -- body space → world
			end
			foot.position = foot.from:Lerp(foot.to, along) + bulge * rise
			-- A foot in the air still hangs from its hip: never further out than the leg reaches
			-- (read from the live hip joint, so it holds even while the body turns in a spin).
			foot.position = withinReach(foot.position, hips + hipOffsets[side], reach)
			height += foot.fromHeight * (1 - along) + foot.lift * rise
			foot.yaw = foot.yawFrom + GaitMath.angleDelta(foot.yawFrom, yawWanted) * along
			pitch = math.rad(Footwork.SWING_TOE_UP) * rise
			if progress >= 1 then
				-- Touchdown.
				foot.position = foot.to
				foot.yaw = yawWanted
				foot.stepping = false
				foot.landPitch = foot.pendingLandPitch
				foot.landedAt = now
				recordPlant(side, now)
			end
		else
			if foot.pivot then
				-- Twisting on the ball of the foot: the ball stays, the heel swings round.
				foot.yaw = yawWanted + foot.pivotYawOffset
				foot.position = foot.ballPoint - forwardOf(foot.yaw) * Footwork.FOOT_BALL_FORWARD
			elseif scripted then
				-- A dribble move turns the body but the foot must not point too far from it:
				-- drag the direction along (a twist on the spot) rather than stepping.
				local off = GaitMath.angleDelta(yawWanted, foot.yaw)
				if math.abs(off) > twistLimit then
					foot.yaw = yawWanted + math.clamp(off, -twistLimit, twistLimit)
				end
			end
			-- Right after touchdown the foot's pitch (toe-first or heel-first) eases flat.
			local since = now - foot.landedAt
			if since < Footwork.TOE_LAND_TIME then
				pitch = foot.landPitch * (1 - since / Footwork.TOE_LAND_TIME)
			end
		end
		local leg = legs[side]
		if leg then
			LimbIK.pinToWorld(leg, true) -- planted feet stay put in the world
			leg.target.WorldCFrame = footCFrame(side, foot.position, height, foot.yaw, pitch, floorY)
			leg.pole.WorldPosition = kneePole(side, foot.position, look, right, floorY)
		end
	end
end

-- One frame of the dip: the hips go down and up while the feet land where the gather says
-- and then stay planted. Returns nothing; sets the leg goals.
local function updateDip(parts: CharacterRef.Parts, now: number, floorY: number)
	local rootCFrame = parts.root.CFrame
	local turn = facing(rootCFrame)
	local right, look = turn.RightVector, turn.LookVector
	local bodyYaw = yawOf(turn)
	local progress = (now - dipStartedAt) / dipDuration
	refreshHips(parts)

	-- From the crouch the player was in, down to the dip's lowest point, then back up to
	-- standing at takeoff.
	local lowest = math.clamp(Motion.DIP_LOWEST_POINT, 0.05, 0.95)
	local drop = if progress < lowest
		then dipStartDrop + (dipDeepest - dipStartDrop) * ease(progress / lowest)
		else dipDeepest * dipAmount(progress)
	parts.humanoid.HipHeight = standingHipHeight - drop
	crouch = drop
	parts.humanoid:SetAttribute("RoHoopsCrouch", crouch)

	-- The chest goes forward as the knees bend (instead of straightening): a hinge in
	-- proportion to how deep the dip is.
	local hinge = if style == "Layup"
		then Footwork.LAYUP_DIP_HINGE
		elseif style == "Dunk" then Footwork.DUNK_DIP_HINGE
		else Footwork.DIP_HINGE
	PostureController.setDipHinge(hinge * math.clamp(drop / math.max(dipDeepest, 0.05), 0, 1))

	local reach = currentReach(0)
	local twistLimit = math.rad(Footwork.FOOT_TWIST_LIMIT)
	for _, side in SIDES do
		local df = dipFeet[side]
		local leg = legs[side]
		if df and leg then
			local height = 0
			local pitch = 0
			local step = df.step
			if step and progress < step.landAt then
				if progress >= step.startAt then
					local p = (progress - step.startAt) / (step.landAt - step.startAt)
					local along, rise = GaitMath.swing(p)
					df.current = step.from:Lerp(step.to, along)
					height = step.lift * rise
					pitch = math.rad(Footwork.SWING_TOE_UP) * rise
				end
			else
				if step then
					df.current = step.to -- the step has landed: it stays here from now on
					local since = (progress - step.landAt) * dipDuration
					local decay = math.max(1 - since / Footwork.TOE_LAND_TIME, 0)
					pitch = step.holdPitch + (step.landPitch - step.holdPitch) * decay
				end
				-- Planted: never stay further than a leg can reach from the hip, as the body slides.
				df.current = withinReach(df.current, flat(rootCFrame.Position) + hipOffsets[side], reach)
			end
			-- Planted feet keep their direction but stay within the twist limit of the body.
			local wantYaw = wantedYaw(side, bodyYaw)
			local off = GaitMath.angleDelta(wantYaw, df.yaw)
			if math.abs(off) > twistLimit then
				df.yaw = wantYaw + math.clamp(off, -twistLimit, twistLimit)
			end

			local cframe = footCFrame(side, df.current, height, df.yaw, pitch, floorY)
			if style == "Layup" and side == "Right" and progress >= Footwork.LAYUP_DRIVE_START then
				-- The free leg: the right foot leaves the floor and swings forward into the knee
				-- drive, which the air phase carries on. Done in the body's own space so it
				-- moves with the body.
				local u = 0.5 * ease((progress - Footwork.LAYUP_DRIVE_START) / (1 - Footwork.LAYUP_DRIVE_START))
				local rest = rootCFrame:PointToObjectSpace(cframe.Position)
				local drive = toObjectSpace(Footwork.LAYUP_KNEE_DRIVE_ANKLE)
				freeLegRel = rest:Lerp(drive, u)
				LimbIK.pinToWorld(leg, false)
				leg.target.WorldCFrame = rootCFrame
					* CFrame.new(freeLegRel)
					* CFrame.Angles(-math.rad(Footwork.AIR_TOE_POINT) * u, 0, 0)
				leg.pole.WorldPosition = rootCFrame:PointToWorldSpace(toObjectSpace(Footwork.LAYUP_KNEE_DRIVE_POLE))
			else
				LimbIK.pinToWorld(leg, true) -- planted: the target must not move down with the hips
				leg.target.WorldCFrame = cframe
				leg.pole.WorldPosition = kneePole(side, df.current, look, right, floorY)
				if side == "Right" then
					freeLegRel = rootCFrame:PointToObjectSpace(cframe.Position)
				end
			end
		end
	end
	legGoals.Right, legGoals.Left = 1, 1
end

-- One frame in the air: reachable legs (knees slightly bent, toes pointed), the layup's knee
-- drive, the dunk's tuck, and the reach for the floor just before landing.
local function updateAir(parts: CharacterRef.Parts, dt: number, now: number, floorY: number)
	local root = parts.root
	local rootCFrame = root.CFrame
	parts.humanoid.HipHeight = standingHipHeight
	crouch = 0
	local since = now - takeoffAt

	-- Track the jump: how fast it launched, when it peaked, how fast it is falling.
	local vy = root.AssemblyLinearVelocity.Y
	if since < 0.1 then
		takeoffPower = math.max(takeoffPower, vy)
	end
	peakFall = math.max(peakFall, -vy)
	if not apexAt and since > 0.05 and vy <= 0 then
		apexAt = now
	end

	-- Fadeaway: drifting backward, the feet swing forward as a counterweight.
	local backward = -MovementController.getVelocity():Dot(facing(rootCFrame).LookVector)
	local fadeGoal = if backward > Footwork.FADE_BACK_SPEED then 1 else 0
	fadeBlend += (fadeGoal - fadeBlend) * MovementMath.smoothingAlpha(10, dt)

	-- Just before touchdown (falling and close to the floor) the legs reach for it.
	local clearance = root.Position.Y - floorY - (standingHipHeight + root.Size.Y / 2)
	local timeToFloor = if vy < -1 then clearance / -vy else math.huge
	local prepare = ease(1 - timeToFloor / math.max(Footwork.LAND_PREPARE_TIME, 0.01))

	-- A one-foot jump that took off hard is a dunk: after the top the knees tuck.
	local tuck = 0
	if style == "Layup" and takeoffPower > Footwork.DUNK_TUCK_MIN_POWER and apexAt then
		tuck = ease((now - apexAt) / math.max(Footwork.DUNK_KNEE_TUCK_TIME, 0.01))
	end

	-- Measure from the leaned body, so the legs tilt with it.
	local bodyCFrame = PostureController.getBodyCFrame(rootCFrame)
	local toePoint = -math.rad(Footwork.AIR_TOE_POINT)
	for _, side in SIDES do
		local leg = legs[side]
		if leg then
			LimbIK.pinToWorld(leg, false) -- in the air: the target moves with the body
			local sign = GaitMath.sign(side)
			local hip = hipRel[side]
			-- The hanging leg: a reachable spot just short of straight, a little ahead of the hip.
			local forward = Footwork.AIR_FEET_FORWARD + fadeBlend * Footwork.FADE_FEET_FORWARD
			local down = legLength - Footwork.AIR_KNEE_BEND
			local drop = math.sqrt(math.max(down * down - forward * forward, 0))
			local ankle = hip + Vector3.new(sign * Footwork.AIR_FEET_SPREAD, -drop, -forward)
			local pole = Vector3.new(hip.X, 0, 0) + toObjectSpace(Footwork.AIR_KNEE_POLE)
			local pitch = toePoint

			if style == "Layup" and side == "Right" then
				-- Knee drive: the right ankle comes up from where the dip left it to the knee-up spot.
				local drive = ease(since / math.max(Footwork.LAYUP_KNEE_DRIVE_TIME, 0.01))
				local halfway = toObjectSpace(Footwork.LAYUP_KNEE_DRIVE_ANKLE)
				ankle = freeLegRel:Lerp(halfway, drive)
				pole = toObjectSpace(Footwork.LAYUP_KNEE_DRIVE_POLE)
				pitch = toePoint * 0.5
			elseif style == "Layup" then
				-- Takeoff leg: trailing a little behind, slightly bent.
				ankle = toObjectSpace(Footwork.LAYUP_TRAIL_ANKLE)
			end
			if tuck > 0 then
				local tucked = toObjectSpace(Footwork.DUNK_KNEE_TUCK_ANKLE)
				tucked = Vector3.new(sign * math.abs(tucked.X), tucked.Y, tucked.Z)
				ankle = ankle:Lerp(tucked, tuck)
				pole = pole:Lerp(Vector3.new(hip.X, 0, 0) + toObjectSpace(Footwork.DUNK_KNEE_TUCK_POLE), tuck)
			end
			if prepare > 0 then
				-- Legs straight down to the floor, feet flat.
				local reachDown = Vector3.new(hip.X + sign * Footwork.AIR_FEET_SPREAD, hip.Y - legLength, hip.Z)
				ankle = ankle:Lerp(reachDown, prepare)
				pitch *= 1 - prepare
			end
			-- Feet keep the body's angle (tilted with the lean).
			leg.target.WorldCFrame = bodyCFrame * CFrame.new(ankle) * CFrame.Angles(pitch, 0, 0)
			leg.pole.WorldPosition = bodyCFrame:PointToWorldSpace(pole)
		end
	end
	legGoals.Right, legGoals.Left = 1, 1
end

-- Runs every frame.
local function update(dt: number)
	local parts = CharacterRef.get()
	if not parts or not ensureLegs(parts.humanoid, parts.character) then
		return
	end

	local now = os.clock()
	local floorY = floorHeight(parts)
	refreshHips(parts)
	local alpha = MovementMath.smoothingAlpha(Motion.LEG_BLEND_SHARPNESS, dt)

	if phase == "Dip" then
		updateDip(parts, now, floorY)
	elseif phase == "Air" then
		updateAir(parts, dt, now, floorY)
	else
		updateGround(parts, dt, now, floorY)
	end

	for _, side in SIDES do
		local leg = legs[side]
		if leg then
			LimbIK.blend(leg, legGoals[side], alpha, 0) -- no smoothing: planted feet must not slide
		end
	end
end

function LegController.start()
	CharacterRef.onSpawn(function()
		for _, leg in legs do
			LimbIK.destroy(leg)
		end
		legs = {}
		hipAttachments = {}
		nextRetryAt = 0
		phase = "Off"
		approach = nil
		feet = nil
		scripted = false
		hipsPath = nil
		moveCrouch = 0
		crouch = 0
		animationRunning = false
		landedAt = -math.huge
		table.clear(plantTimes)
		standingHipHeight = 0 -- read from the new character once its legs are set up
	end)
	-- Runs before the arms and ball so the hips are in their dipped position this frame.
	RunService:BindToRenderStep("RoHoopsLegs", Enum.RenderPriority.Character.Value, update)
end

return LegController
