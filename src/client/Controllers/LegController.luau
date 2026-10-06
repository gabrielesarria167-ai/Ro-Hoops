--!strict
-- LEG CONTROLLER
-- Everything the legs do, using leg IK (see src/client/LimbIK.luau):
--   Ground – procedural footwork (Config/Footwork.luau). Each foot is planted on the floor
--            and stays put until it steps; GaitMath decides when and where:
--              * the dribbling stance: knees bent, feet a bit wider than the hips, the
--                ball-side foot slightly back;
--              * sideways = a shuffle (lead foot, then trail foot, never crossing),
--                backward = a backpedal, standing still = the stance squares itself up;
--              * running forward hands the legs to Roblox's run animation instead;
--              * dribble moves place the feet themselves (SkillController calls stepFoot,
--                setScripted and setMoveCrouch), e.g. the spin's pivot and swing leg.
--   Dip    – the hips drop (by lowering the Humanoid's HipHeight) while the feet stay
--            planted, so the knees bend; then the legs drive back up into the takeoff.
--   Air    – jump shot: both legs reach straight down (extended, like a real jumper).
--            Layup: the right knee drives up while the left leg (the one you jumped off)
--            stays straight and trails slightly behind.
--            Either way the legs follow the body's lean (PostureController), so on a
--            fadeaway the feet swing forward as the body tilts back, in one straight line.
-- ShotController tells it when each shot phase starts (startDip / takeoff / land).
--
-- The feet are placed with full transform IK, so they stay flat on the floor, pointing
-- the way the body faces (a planted pivot foot turns with the body, like on the ball of
-- the foot).
--
-- Only works for R15 characters (the default); R6 characters just skip it.
-- Tuning values: src/shared/Config/Footwork.luau (ground), src/shared/Config/Motion.luau
-- (DIP_DEPTH, DIP_LOWEST_POINT, KNEE_POLE, LAYUP_DIP_DEPTH, LAYUP_KNEE_DRIVE_...).

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

-- Where a step is aimed: a spot beside the hips at the moment the foot lands. It's worked
-- out again every frame of the step from where the hips are and where they're heading, so
-- the foot lands in the right place even though the body is still moving.
type Aim = {
	offset: Vector3, -- from the hips: x = studs to the right, z = studs forward (y unused)
	frame: CFrame?, -- which way "right" and "forward" are (nil = the way the body faces now)
	ahead: number, -- land this many extra seconds of travel ahead (so the body moves over the foot)
	keepApart: boolean, -- never land across the other foot (automatic steps)
}

-- One foot on the ground (the Ground phase). Positions are flat (y = 0); the floor height
-- is added when the foot is placed.
type Foot = {
	position: Vector3, -- where the foot is now (planted, or partway through a step)
	stepping: boolean, -- in the air, on its way from `from` to `to`
	from: Vector3,
	to: Vector3, -- where it will land (updated every frame from `aim`)
	aim: Aim?,
	startedAt: number, -- clock time the step started
	duration: number, -- seconds the step takes
	lift: number, -- studs the foot rises at the middle of the step
	bulge: Vector3, -- sideways sweep at the middle of the step (the spin's swing leg)
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

local phase: Phase = "Off"
local dipStartedAt = 0 -- clock time when the dip began
local dipDuration = 0.2 -- seconds from the start of the dip to takeoff
local dipStartDrop = 0 -- how far the hips were already lowered (the crouch) when the dip began
local takeoffAt = 0 -- clock time of the takeoff
local style: Shooting.MotionStyle = "JumpShot" -- which motion the current shot uses
-- Where each ankle was when the dip began: in world space (the feet stay there during the
-- dip) and relative to the hips (the spread the legs keep in the air).
local plantedWorld: { [Side]: Vector3 } = {}
local plantedAnkles: { [Side]: Vector3 } = {}

-- GROUND STATE
local feet: { [Side]: Foot }? = nil -- nil = take the feet from wherever they are now
local crouch = 0 -- how far the hips are lowered right now, studs
local scripted = false -- a dribble move is placing the feet (no automatic steps)
local moveCrouch = 0 -- extra crouch asked for by the current dribble move, studs
local stillSince = 0 -- clock time the player stopped moving (for squaring up the stance)

-- Converts a Motion-config offset (right, up, forward) to Roblox's object space, where
-- forward is -Z.
local function toObjectSpace(offset: Vector3): Vector3
	return Vector3.new(offset.X, offset.Y, -offset.Z)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
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
	end
	-- New body parts = Roblox has just worked out the standing HipHeight for them.
	standingHipHeight = humanoid.HipHeight
	crouch = 0
	feet = nil
	-- Let the hips bend far enough for the layup's knee drive and the ankles turn for a
	-- pivot (newer avatars limit joints for ragdolls, see LimbIK.freeJoints).
	LimbIK.freeJoints(character, { "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" })
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

-- Starts the dip. `duration` = seconds until takeoff; `motionStyle` = which motion the
-- shot uses (a layup has a shallower dip and a knee drive in the air).
function LegController.startDip(duration: number, motionStyle: Shooting.MotionStyle)
	local parts = CharacterRef.get()
	if not parts then
		return
	end
	-- The dip starts from the crouch the player is already in.
	dipStartDrop = math.max(standingHipHeight - parts.humanoid.HipHeight, 0)

	-- Remember where each ankle is now, so the feet stay put while the hips drop.
	for _, side in SIDES do
		local foot = parts.character:FindFirstChild(side .. "Foot")
		local ankle = foot and foot:FindFirstChild(side .. "AnkleRigAttachment") :: Attachment?
		if ankle then
			plantedWorld[side] = ankle.WorldPosition
			plantedAnkles[side] = parts.root.CFrame:PointToObjectSpace(ankle.WorldPosition)
		end
	end

	dipStartedAt = os.clock()
	dipDuration = math.max(duration, 0.05)
	style = motionStyle
	phase = "Dip"
	scripted = false
	moveCrouch = 0
end

-- The player left the ground: straighten the legs (or, on a layup, drive the knee up).
function LegController.takeoff()
	takeoffAt = os.clock()
	phase = "Air"
end

-- The player landed (or the shot was cancelled): back to footwork on the ground.
function LegController.land()
	phase = "Off"
	feet = nil -- pick the feet up from wherever they landed
end

-- DRIBBLE MOVE FOOTWORK (called by SkillController) ----------------------------------------

-- true while a dribble move places the feet itself: no automatic steps, so the feet stay
-- exactly where the move puts them. false hands them back to the automatic footwork.
function LegController.setScripted(on: boolean)
	scripted = on
end

-- Extra studs to lower the hips during a dribble move (0 = back to the normal stance).
function LegController.setMoveCrouch(amount: number)
	moveCrouch = amount
end

-- Steps `side`'s foot over `duration` seconds, rising `lift` studs at the middle of the
-- step, to land at `offset` from the hips (x = studs right, z = studs forward) as they are
-- when it lands. `frame` = which way right/forward are (nil = the way the body faces, read
-- each frame; the spin passes its starting facing because the body turns underneath).
-- `bulge` (world, flat) sweeps the foot out that way mid-step, e.g. the spin's leg
-- swinging round behind.
function LegController.stepFoot(
	side: Side,
	offset: Vector3,
	duration: number,
	lift: number,
	frame: CFrame?,
	bulge: Vector3?
)
	local foot = feet and feet[side]
	if not foot or phase ~= "Off" then
		return
	end
	foot.stepping = true
	foot.from = foot.position
	foot.aim = { offset = offset, frame = frame, ahead = Footwork.MOVE_LAND_AHEAD, keepApart = false }
	foot.startedAt = os.clock()
	foot.duration = math.max(duration, 0.03)
	foot.lift = lift
	foot.bulge = if bulge then flat(bulge) else Vector3.zero
end

-- GROUND FOOTWORK ---------------------------------------------------------------------------

-- Starts an automatic step for `foot` aimed at `aim`, taking `duration` seconds.
-- `estimatedTarget` (flat world) is roughly where it will land, to size the lift.
local function autoStep(foot: Foot, aim: Aim, estimatedTarget: Vector3, duration: number)
	local length = (estimatedTarget - foot.position).Magnitude
	foot.stepping = true
	foot.from = foot.position
	foot.to = estimatedTarget
	foot.aim = aim
	foot.startedAt = os.clock()
	foot.duration = duration
	foot.lift = GaitMath.liftFor(length, Footwork.LIFT_PER_STUD, Footwork.MIN_LIFT, Footwork.MAX_LIFT)
	foot.bulge = Vector3.zero
end

-- Where each foot is right now (flat), read from the body (used to start the footwork from
-- whatever pose the body is in, e.g. after landing or after running).
local function readFeet(parts: CharacterRef.Parts): { [Side]: Foot }
	local result = {}
	for _, side in SIDES do
		local foot = parts.character:FindFirstChild(side .. "Foot")
		local ankle = foot and foot:FindFirstChild(side .. "AnkleRigAttachment") :: Attachment?
		local position = if ankle
			then flat(ankle.WorldPosition)
			else flat(parts.root.CFrame:PointToWorldSpace(Vector3.new(GaitMath.sign(side) * 0.5, 0, 0)))
		result[side] = {
			position = position,
			stepping = false,
			from = position,
			to = position,
			aim = nil,
			startedAt = 0,
			duration = 0.1,
			lift = 0,
			bulge = Vector3.zero,
		}
	end
	return result
end

-- One frame of footwork on the ground. Returns how much the legs should follow their IK
-- targets (1 = footwork, 0 = Roblox's animation, e.g. running forward or in the air).
local function updateGround(parts: CharacterRef.Parts, dt: number): number
	local humanoid = parts.humanoid
	local rootCFrame = parts.root.CFrame
	local turn = facing(rootCFrame)
	local right, look = turn.RightVector, turn.LookVector
	local velocity = flat(MovementController.getVelocity())
	local speed = velocity.Magnitude
	local hasBall = BallController.getMode() == "Dribble"
	local now = os.clock()

	-- Who drives the legs: running forward → the run animation; in the air (a jump, a fall)
	-- → the animation; otherwise (standing, shuffling, backpedalling, dribble moves) → us.
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local forwardness = if speed > 1e-3 then velocity.Unit:Dot(look) else 0
	local runningForward = speed > Footwork.ANIMATION_RUN_SPEED and forwardness > Footwork.ANIMATION_RUN_DOT
	local goal = if grounded and (scripted or not runningForward) then 1 else 0

	-- Hips: crouch into the stance (only while the footwork has the legs: the run animation
	-- expects standing height).
	local targetCrouch = (if hasBall then Footwork.DRIBBLE_CROUCH else Footwork.NO_BALL_CROUCH) * goal + moveCrouch
	crouch += (targetCrouch - crouch) * MovementMath.smoothingAlpha(Footwork.CROUCH_SHARPNESS, dt)
	if standingHipHeight > 0 then
		humanoid.HipHeight = standingHipHeight - crouch
	end
	-- Published for BallController / ArmController: the ball in the hand comes down with
	-- the shoulders (a lower stance = a lower dribble).
	humanoid:SetAttribute("RoHoopsCrouch", crouch)
	-- Chest forward over the ball (PostureController eases it, and drops it while shooting).
	PostureController.setStanceLean(-(if hasBall then Footwork.DRIBBLE_LEAN else Footwork.NO_BALL_LEAN) * goal)

	if goal == 0 then
		feet = nil -- the animation has the feet; pick them up from there when we take over
		return 0
	end
	if not feet then
		feet = readFeet(parts)
	end
	local current = feet :: { [Side]: Foot }

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
	-- The stance offset (x right, z forward from the hips) of `side`'s foot.
	local function stanceOffset(side: Side): Vector3
		local x, z = GaitMath.homeOffset(side, ballHand, Footwork)
		return Vector3.new(x, 0, z + Footwork.FEET_FORWARD)
	end
	-- Where the hips will be `seconds` from now (flat).
	local function hipsIn(seconds: number): Vector3
		return hips + travelVelocity * math.max(seconds, 0)
	end
	-- Where `aim` puts `side`'s foot when it lands `seconds` from now, before the keep-apart
	-- check. Never further than MAX_REACH from under its hip at that moment (so the leg can
	-- actually reach it when it lands).
	local function aimSpot(side: Side, aim: Aim, seconds: number): Vector3
		local frame = aim.frame or turn
		local spot = hipsIn(seconds + aim.ahead) + frame.RightVector * aim.offset.X + frame.LookVector * aim.offset.Z
		local hipJoint = hipsIn(seconds) + right * (GaitMath.sign(side) * 0.5)
		local reach = spot - hipJoint
		if reach.Magnitude > Footwork.MAX_REACH then
			spot = hipJoint + reach.Unit * Footwork.MAX_REACH
		end
		return spot
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

	if not scripted then
		-- Starts `side`'s foot stepping to its stance spot, landing a little ahead when moving.
		local function startStep(side: Side)
			local aim: Aim = {
				offset = stanceOffset(side),
				frame = nil,
				ahead = stepTime * Footwork.LAND_AHEAD,
				keepApart = true,
			}
			autoStep(current[side], aim, apart(side, aimSpot(side, aim, stepTime)), stepTime)
		end

		-- Safety: a planted foot left too far behind (out of the leg's reach) steps at once.
		for _, side in SIDES do
			local foot = current[side]
			local hipSpot = hips + right * (GaitMath.sign(side) * 0.5)
			if not foot.stepping and (foot.position - hipSpot).Magnitude > Footwork.MAX_REACH then
				startStep(side)
			end
		end

		-- Normal steps: the foot furthest from its spot goes first. The next foot may leave
		-- once the stepping one is STEP_OVERLAP of the way through (quick feet when moving
		-- fast: the trail foot follows as the lead foot lands).
		local function ready(foot: Foot): boolean
			return not foot.stepping or (now - foot.startedAt) / foot.duration >= Footwork.STEP_OVERLAP
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
				local offset = stanceOffset(side)
				local spot = hipsIn(stepTime * 0.5) + right * offset.X + look * offset.Z
				return (foot.position - spot).Magnitude
			end
			local sideways = velocity:Dot(right)
			local lead: Side? = if sideways > 0.5 then "Right" elseif sideways < -0.5 then "Left" else nil
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
			foot.to = if aim.keepApart then apart(side, spot) else spot
		end
	end

	-- Move the feet through their steps and place them.
	local floorY = floorHeight(parts)
	for _, side in SIDES do
		local foot = current[side]
		local height = 0
		if foot.stepping then
			local progress = (now - foot.startedAt) / foot.duration
			local along, rise = GaitMath.swing(progress)
			foot.position = foot.from:Lerp(foot.to, along) + foot.bulge * rise
			height = foot.lift * rise
			if progress >= 1 then
				foot.position = foot.to
				foot.stepping = false
			end
		end
		local leg = legs[side]
		if leg then
			LimbIK.pinToWorld(leg, true) -- planted feet stay put in the world
			local ankle = Vector3.new(foot.position.X, floorY + ankleHeights[side] + height, foot.position.Z)
			leg.target.WorldCFrame = CFrame.new(ankle) * turn -- flat, pointing the way the body faces
			leg.pole.WorldPosition = foot.position
				+ look * Footwork.KNEE_FORWARD
				+ right * (GaitMath.sign(side) * Footwork.KNEE_OUT)
				+ Vector3.new(0, floorY + 1, 0)
		end
	end
	return 1
end

-- Runs every frame.
local function update(dt: number)
	local parts = CharacterRef.get()
	if not parts or not ensureLegs(parts.humanoid, parts.character) then
		return
	end

	local rootCFrame = parts.root.CFrame
	local goal = 0 -- how much the legs follow their IK targets this frame
	local alpha = MovementMath.smoothingAlpha(Motion.LEG_BLEND_SHARPNESS, dt)

	if phase == "Dip" then
		local progress = (os.clock() - dipStartedAt) / dipDuration
		local depth = if style == "Layup" then Motion.LAYUP_DIP_DEPTH else Motion.DIP_DEPTH
		-- From the crouch the player was in, down to the dip's lowest point, then back up
		-- to standing at takeoff.
		local deepest = math.max(depth, dipStartDrop)
		local lowest = math.clamp(Motion.DIP_LOWEST_POINT, 0.05, 0.95)
		local drop = if progress < lowest
			then dipStartDrop + (deepest - dipStartDrop) * ease(progress / lowest)
			else deepest * dipAmount(progress)
		parts.humanoid.HipHeight = standingHipHeight - drop
		crouch = drop
		local turn = facing(rootCFrame)
		for _, side in SIDES do
			local planted = plantedWorld[side]
			local leg = legs[side]
			if planted and leg then
				LimbIK.pinToWorld(leg, true) -- planted: the target must not move down with the hips
				-- Feet stay exactly where they were while the hips move down and up.
				leg.target.WorldCFrame = CFrame.new(planted) * turn
				leg.pole.WorldPosition = rootCFrame:PointToWorldSpace(
					toObjectSpace(Motion.KNEE_POLE) + Vector3.new(plantedAnkles[side].X, 0, 0)
				)
			end
		end
		goal = 1
	elseif phase == "Air" then
		parts.humanoid.HipHeight = standingHipHeight
		crouch = 0
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
				-- Feet keep the body's angle (tilted with the lean).
				leg.target.WorldCFrame = bodyCFrame * CFrame.new(ankle)
				leg.pole.WorldPosition = bodyCFrame:PointToWorldSpace(pole)
			end
		end
		goal = 1
	else
		goal = updateGround(parts, dt)
	end

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
		feet = nil
		scripted = false
		moveCrouch = 0
		crouch = 0
		standingHipHeight = 0 -- read from the new character once its legs are set up
	end)
	-- Runs before the arms and ball so the hips are in their dipped position this frame.
	RunService:BindToRenderStep("RoHoopsLegs", Enum.RenderPriority.Character.Value, update)
end

return LegController
