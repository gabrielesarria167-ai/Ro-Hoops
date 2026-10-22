--!strict
-- SHOT CONTROLLER (the E key, and double-click to dunk)
-- Pressing E:
--   1. picks the shot type from your position and movement (ShotMath.classify):
--      jump shot, pull-up, fadeaway, side shot, layup or close shot,
--   2. starts the timing meter, eases your momentum into the shot's DIP drift, turns you
--      smoothly to face the rim (a jump shooter stands turned SHOT_BODY_YAW to one side),
--      and starts the shooting motion: knees dip (LegController) while the ball comes up
--      to the forehead (BallController.hold). The dip's footwork depends on the shot: a
--      pull-up brakes to a stop, a side shot steps sideways (the
--      "gather" option of LegController.startDip). A layup or running dunk from further
--      out first DRIVES IN at your own speed (LegController.startApproach: the running
--      gather steps, with the ball gathered in both hands) and only then dips; the meter
--      is stretched to match, so the green zone is still at the top of the jump,
--   3. jumps at the end of the dip. The dip is timed (ShotMath.dipTime) so the perfect
--      release comes APEX_OFFSET seconds after the top of the jump: at it for most shots,
--      just after for a close shot, just before for a layup. In the air the body carries
--      the shot type's (small) air DRIFT, and leans by LEAN (a fadeaway tilts back ~14°)
--      and SIDE_LEAN (a side shot tilts ~12° sideways, the same way it steps), fully
--      leaned at the perfect release (PostureController.leanTo).
-- Drift is split in two: DIP_DRIFT is the body's velocity while it gathers on the ground
-- (the feet follow it), DRIFT is the velocity it carries after takeoff.
-- Releasing E:
--   4. grades the timing (ShotMath.grade) and turns it into an aim error (ShotMath.aimError),
--   5. solves the arc to that target (ShotMath.launchVelocity) and launches the ball.
-- Double-click (beginDunk): if you're close enough and attacking the rim
-- (ShotMath.canDunk), drive in, gather, and jump exactly high enough that the ball is over
-- the rim at the top of the jump (ShotMath.jumpPowerFor), where it's slammed down through
-- it automatically (ShotMath.slamVelocity). No meter.
-- Leg styles: a jump shot is a two-foot dip; a layup is a one-foot takeoff off the left foot
-- with the right knee driving up, and so is a RUNNING dunk; only a standing dunk uses the deep
-- two-foot load.
-- Tuning values: src/shared/Config/Shooting.luau (timing, aim, shot types, dip limits, body
-- turn) and src/shared/Config/Motion.luau (dip lowest point, drift blending, lean times).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Ball = require(ReplicatedStorage.Shared.Config.Ball)
local Court = require(ReplicatedStorage.Shared.Config.Court)
local Motion = require(ReplicatedStorage.Shared.Config.Motion)
local Shooting = require(ReplicatedStorage.Shared.Config.Shooting)
local MovementMath = require(ReplicatedStorage.Shared.MovementMath)
local ShotMath = require(ReplicatedStorage.Shared.ShotMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local BallController = require(script.Parent.BallController)
local HudController = require(script.Parent.HudController)
local InputController = require(script.Parent.InputController)
local LegController = require(script.Parent.LegController)
local PostureController = require(script.Parent.PostureController)
local MovementController = require(script.Parent.MovementController)

-- Ready     = can shoot
-- Gathering = E is held, meter filling
-- Airborne  = ball released, waiting for the player to land
type Phase = "Ready" | "Gathering" | "Airborne"

-- How a shot (or dunk) plays out, worked out when it starts. Times are seconds.
type Plan = {
	approach: number, -- driving in before the dip starts (0 = dip straight away)
	dipTime: number, -- from the start of the dip to takeoff
	releaseAfterDip: number, -- from the start of the dip to the perfect release (a dunk: the slam)
	jumpPower: number, -- upward speed at takeoff, studs/s
	dipDrift: Vector3, -- velocity through the drive and the dip (flat, studs/s)
	-- Velocity while driving in, before the dip, if different from dipDrift (flat, studs/s;
	-- nil = dipDrift). A running dunk drives in at full speed, then brakes on the plant.
	approachDrift: Vector3?,
	dipRate: number?, -- how fast the velocity eases to dipDrift, studs/s² (nil = Motion.DRIFT_BLEND_RATE)
	airDrift: Vector3, -- velocity from takeoff on (flat, studs/s)
	driftSide: number, -- 1 if drifting to the player's right, -1 if left (the side lean tilts the same way)
	legStyle: Shooting.MotionStyle, -- the legs' motion (a running dunk uses the layup's one-foot takeoff)
	dipOptions: LegController.DipOptions, -- the gather footwork, dip drift and depth for LegController.startDip
	lowSwing: boolean, -- standing dunk: the ball swings down toward the knees in the dip
	bodyYaw: number, -- degrees the body faces left of the rim line (a jump shooter's turned stance)
	isDunk: boolean,
}

-- The shot in progress.
type ActiveShot = {
	config: Shooting.ShotTypeConfig, -- the settings of the chosen shot type
	-- Set when the drive in used a different velocity (Plan.approachDrift): the dip's drift
	-- and braking rate, switched to when the dip starts. nil = nothing to switch.
	dipSwitch: { drift: Vector3, rate: number? }?,
	isDunk: boolean, -- a dunk: no meter; it slams itself through the rim at releaseAt
	startedAt: number, -- clock time when E was pressed (or the double-click), seconds
	-- Seconds for the meter to reach progress 1: the type's FILL_TIME, stretched by a long
	-- layup's drive in so the perfect release is still at IDEAL_RELEASE.
	fillTime: number,
	dipAt: number, -- clock time the dip (gather) starts; until then you're still driving in
	dipStarted: boolean, -- true once the dip has been started
	dipTime: number, -- seconds from the start of the dip to takeoff
	legStyle: Shooting.MotionStyle, -- see Plan
	dipOptions: LegController.DipOptions, -- see Plan
	jumpPower: number, -- upward speed at takeoff, studs/s
	airDrift: Vector3, -- see Plan
	bodyYaw: number, -- see Plan
	jumpAt: number, -- clock time when the jump should happen
	releaseAt: number, -- clock time of the perfect release (the body is fully leaned by then)
	driftSide: number, -- 1 if drifting to the player's right, -1 if left (the side lean tilts the same way)
	jumpedAt: number?, -- clock time when the jump actually happened (nil = still on the ground)
	leftGround: boolean, -- true once the player has actually been seen in the air
}

local SHOOT_KEY = Enum.KeyCode.E -- change this to rebind shooting
local DUNK_BUTTON = Enum.UserInputType.MouseButton1 -- double-click this to dunk
local MIN_AIR_TIME = 0.2 -- seconds; ignore "on the ground" readings right after takeoff
-- If the player somehow never leaves the ground after jumping, end the shot after this
-- many seconds anyway so controls don't stay locked.
local JUMP_FAILSAFE = 1.5
-- Landing detection (see heightAboveStanding), all in studs or studs/s:
local AIRBORNE_CLEARANCE = 0.3 -- hips this far above standing height = seen in the air
local LAND_CLEARANCE = 0.15 -- hips back within this of standing height = on the floor

local ShotController = {}

local phase: Phase = "Ready" -- where we are in the shot
local shot: ActiveShot? = nil -- the shot in progress, or nil
local random = Random.new() -- random numbers for the sideways aim error
local lastClickAt = -math.huge -- clock time of a click that a second click would make a double-click

-- From `position`, returns the flat distance to the rim (studs) plus two directions:
-- `toward` points at the rim, `lateral` points to its right (across the court).
local function rimAxes(position: Vector3): (number, Vector3, Vector3)
	local offset = Court.RIM_POSITION - position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	local toward = if distance > 1e-3 then flat / distance else -Vector3.zAxis
	return distance, toward, toward:Cross(Vector3.yAxis)
end

-- Leaves the ground with `power` (upward speed, studs/s).
local function jump(humanoid: Humanoid, power: number)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = power
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end

-- How far the hips are above where they'd be standing on the floor right below (studs;
-- about 0 when standing, positive in the air). A ray finds the floor; during a shot
-- LegController keeps HipHeight at the standing value once airborne, so floor +
-- HipHeight + half the root part is the standing hip height.
local function heightAboveStanding(parts: CharacterRef.Parts): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { parts.character }
	params.RespectCanCollide = true -- only solid ground (not the ball)
	local hit = workspace:Raycast(parts.root.Position, Vector3.new(0, -20, 0), params)
	if not hit then
		return math.huge -- nothing below: definitely not on the floor
	end
	return parts.root.Position.Y - hit.Position.Y - (parts.humanoid.HipHeight + parts.root.Size.Y / 2)
end

-- Turns the body a little further toward the rim (called every frame during a shot), plus
-- `bodyYaw` degrees to the left of the rim line: a jump shooter is turned, shooting side
-- forward. A positive turn about the up axis is to the LEFT when facing the rim.
-- MovementController.faceRim is given the same yaw so the two agree.
local function turnTowardRim(root: BasePart, dt: number, bodyYaw: number)
	local distance, toward = rimAxes(root.Position)
	if distance < 1 then
		return -- right under the rim: no clear direction, keep the current facing
	end
	local facingRim = CFrame.lookAt(root.Position, root.Position + toward) * CFrame.Angles(0, math.rad(bodyYaw), 0)
	local alpha = MovementMath.smoothingAlpha(Shooting.SHOT_TURN_SHARPNESS, dt)
	root.CFrame = root.CFrame:Lerp(facingRim, alpha)
end

-- Starts a shot or dunk following `plan`: momentum eases into the dip drift, the ball is
-- gathered (in the pocket when the hips are lowest, at the forehead at takeoff, at the
-- release point at the perfect release), and step() starts the dip and the jump when it's
-- time.
local function startSequence(config: Shooting.ShotTypeConfig, plan: Plan)
	local now = os.clock()
	local dipAt = now + math.max(plan.approach, 0)
	local releaseAt = dipAt + plan.releaseAfterDip
	local approachDrift = if plan.approach > 0 then plan.approachDrift else nil
	if approachDrift then
		MovementController.setOverride(approachDrift) -- drive in; the dip's drift comes at dipAt
	else
		MovementController.setOverride(plan.dipDrift, plan.dipRate)
	end
	MovementController.setFacingYaw(plan.bodyYaw)
	if plan.approach > 0 then
		-- Driving in first (a layup or running dunk from further out): the legs take running
		-- gather steps timed so the last plant lands exactly as the dip starts.
		LegController.startApproach(plan.approach, approachDrift or plan.dipDrift, plan.legStyle)
	end
	PostureController.setShooting(true) -- stay upright, eyes on the rim
	-- A dunk is right under the rim: only glance up at it (full strength cranks the neck).
	PostureController.setHeadLook(if plan.isDunk then Motion.DUNK_HEAD_LOOK_WEIGHT else nil)
	-- config.MOTION picks the jump shot, layup or dunk version of the ball path and hands.
	-- toSet = seconds until takeoff: the ball is at the forehead then, so the arms rise
	-- together with the legs (research: the wrist is already at forehead height at takeoff).
	BallController.hold(
		dipAt - now + plan.dipTime * Motion.DIP_LOWEST_POINT,
		releaseAt - now,
		config.MOTION,
		{ toSet = dipAt - now + plan.dipTime, lowSwing = plan.lowSwing }
	)
	shot = {
		config = config,
		dipSwitch = if approachDrift then { drift = plan.dipDrift, rate = plan.dipRate } else nil,
		isDunk = plan.isDunk,
		startedAt = now,
		fillTime = (releaseAt - now) / Shooting.IDEAL_RELEASE,
		dipAt = dipAt,
		dipStarted = false,
		dipTime = plan.dipTime,
		legStyle = plan.legStyle,
		dipOptions = plan.dipOptions,
		jumpPower = plan.jumpPower,
		airDrift = plan.airDrift,
		bodyYaw = plan.bodyYaw,
		jumpAt = dipAt + plan.dipTime,
		releaseAt = releaseAt,
		driftSide = plan.driftSide,
		jumpedAt = nil,
		leftGround = false,
	}
	phase = "Gathering"
	HudController.beginShot(config.LABEL, not plan.isDunk)
end

-- E pressed: choose the shot, start the meter and the gather; the jump follows shortly.
local function begin()
	if phase ~= "Ready" or not BallController.hasBall() then
		return
	end
	local parts = CharacterRef.get()
	-- Must be standing on something (FloorMaterial is Air while jumping or falling).
	if not parts or parts.humanoid.FloorMaterial == Enum.Material.Air then
		return
	end
	local root = parts.root

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

	-- Time the dip (the time on the ground before takeoff) so the release comes
	-- config.APEX_OFFSET seconds after the top of the jump (ShotMath.dipTime): jump power p
	-- reaches its top after p / gravity seconds, so dip for the difference, kept between the
	-- MIN_DIP_TIME and MAX_DIP_TIME limits. The meter itself (FILL_TIME) is never touched.
	local idealReleaseTime = config.FILL_TIME * Shooting.IDEAL_RELEASE
	local dipTime = ShotMath.dipTime(
		idealReleaseTime,
		config.JUMP_POWER,
		workspace.Gravity,
		config.APEX_OFFSET,
		config.MIN_DIP_TIME or Shooting.MIN_DIP_TIME,
		Shooting.MAX_DIP_TIME
	)

	-- How the player moves during the dip (dipDrift) and through the air (airDrift).
	local approach = 0
	local dipDrift: Vector3
	local airDrift: Vector3
	local dipRate: number? = nil
	local gather: Shooting.GatherKind = config.GATHER
	local side = if lateralSpeed >= 0 then 1 else -1 -- keep drifting the way you were moving
	if typeId == "Layup" then
		-- Carry the drive toward the rim so the player is LAYUP_RELEASE_FT from it at the
		-- moment of release (from too close the ball goes up into the rim). Close in, the
		-- drive is slowed to fit the layup's own timing; from further out you keep your
		-- speed (at least config.DRIFT) and the extra time is a drive in before the dip.
		local room = distance - Court.ft(Shooting.LAYUP_RELEASE_FT) -- studs to cover before release
		local driveSpeed = math.max(velocity:Dot(toward), config.DRIFT)
		local seconds, speed = ShotMath.finishTiming(room, driveSpeed, idealReleaseTime)
		approach = seconds - idealReleaseTime
		dipDrift = toward * speed -- the drive carries on through the plant and the air
		airDrift = dipDrift
	else
		dipDrift = toward * config.DIP_DRIFT + lateral * side * config.DIP_LATERAL_DRIFT
		airDrift = toward * config.DRIFT + lateral * side * config.LATERAL_DRIFT
		-- Reach the dip drift by takeoff: a pull-up brakes from its speed to a stop over the
		-- dip (rate = speed change / dip time), never slower than the normal drift blend.
		local speedChange = (velocity - dipDrift).Magnitude
		dipRate = math.max(Motion.DRIFT_BLEND_RATE, speedChange / dipTime)
		-- A pull-up from a walk or a standstill has nothing to brake: plant both feet.
		if gather == "PullUp" and velocity.Magnitude < Shooting.PULLUP_GATHER_MIN_SPEED then
			gather = "None"
		end
	end
	-- What LegController needs to place the feet: the flat velocity the body has during the
	-- dip (the pull-up's average over its braking: half the speed it started with).
	local legDrift = if gather == "PullUp" then velocity * 0.5 else dipDrift
	startSequence(config, {
		approach = approach,
		dipTime = dipTime,
		releaseAfterDip = idealReleaseTime,
		jumpPower = config.JUMP_POWER,
		dipDrift = dipDrift,
		dipRate = dipRate,
		airDrift = airDrift,
		driftSide = side,
		legStyle = config.MOTION,
		dipOptions = { gather = gather, drift = legDrift, depthScale = config.DIP_DEPTH_SCALE, rate = dipRate },
		lowSwing = false,
		-- Only a jump shooter stands turned; a layup drives at the rim.
		bodyYaw = if typeId == "Layup" then 0 else Shooting.SHOT_BODY_YAW,
		isDunk = false,
	})
end

-- Double-click: dunk if possible (see Config/Shooting.luau, DUNK), otherwise say why not.
local function beginDunk()
	if phase ~= "Ready" or not BallController.hasBall() then
		return
	end
	local parts = CharacterRef.get()
	if not parts or parts.humanoid.FloorMaterial == Enum.Material.Air then
		return
	end
	local root = parts.root
	local distance, toward, lateral = rimAxes(root.Position)
	local velocity = MovementController.getVelocity()
	local towardSpeed = velocity:Dot(toward)
	local kind = ShotMath.canDunk({
		distanceFeet = distance / Court.STUDS_PER_FOOT,
		towardSpeed = towardSpeed,
		lateralSpeed = velocity:Dot(lateral),
		running = InputController.isRunning(),
	}, Shooting)
	if not kind then
		HudController.notice("TOO FAR TO DUNK")
		return
	end
	local config = Shooting.Types.Dunk

	-- Where the ball is at the top of the jump, from the hips: DUNK_REACH, tilted forward
	-- with the body's lean (config.LEAN, negative = forward).
	local lean = math.rad(-config.LEAN)
	local reach = Motion.DUNK_REACH
	local reachUp = reach.Y * math.cos(lean) - reach.Z * math.sin(lean)
	local reachForward = reach.Z * math.cos(lean) + reach.Y * math.sin(lean)

	-- Jump just high enough that the bottom of the ball clears the rim by DUNK_CLEARANCE.
	-- Measured from standing height: the hips are lowered by the dribbling crouch now
	-- (LegController's "RoHoopsCrouch"), but straighten up into the jump.
	local gravity = workspace.Gravity
	local crouch = parts.humanoid:GetAttribute("RoHoopsCrouch")
	local standingY = root.Position.Y + (if type(crouch) == "number" then crouch else 0)
	local rise = Court.RIM_POSITION.Y + Ball.RADIUS + Shooting.DUNK_CLEARANCE - (standingY + reachUp)
	local jumpPower = ShotMath.jumpPowerFor(rise, gravity)
	if jumpPower > Shooting.DUNK_MAX_JUMP_POWER then
		HudController.notice("CAN'T REACH THE RIM")
		return
	end
	local timeToTop = jumpPower / gravity
	-- A running dunk's dip is the left-foot plant; a standing dunk's is the deep two-foot load.
	local dipTime = if kind == "Running" then Shooting.DUNK_DIP_TIME else Shooting.STANDING_DUNK_DIP_TIME

	-- Cover the ground so that at the top of the jump the ball is over the rim's centre:
	-- on the run at your own speed (driving in first if you're far out), standing just
	-- during the gather and the jump.
	local room = distance - reachForward
	local driveSpeed = if kind == "Running" then towardSpeed else math.huge
	local seconds, speed = ShotMath.finishTiming(room, driveSpeed, dipTime + timeToTop)
	local drift = toward * speed
	-- A running dunk brakes on its plant foot (forward speed turns into height), so the
	-- planted left foot isn't dragged: during the dip only DUNK_PLANT_CARRY of the speed is
	-- kept, braking in the first half of the dip. The air speed makes up the difference, so
	-- the ball still arrives over the rim at the top of the jump.
	local dipDrift, dipRate, airDrift = drift, nil, drift
	if kind == "Running" then
		local plantSpeed = speed * Shooting.DUNK_PLANT_CARRY
		local dipCovered = plantSpeed * dipTime
		local airSpeed = math.max(speed * (dipTime + timeToTop) - dipCovered, 0) / math.max(timeToTop, 0.05)
		dipDrift = toward * plantSpeed
		-- Brake from the speed the player is actually moving at (with no drive in, the plant
		-- starts right now, and that can be well above the planned `speed`).
		local entrySpeed = math.max(speed, Vector3.new(velocity.X, 0, velocity.Z).Magnitude)
		dipRate = math.max(Motion.DRIFT_BLEND_RATE, (entrySpeed - plantSpeed) / math.max(dipTime * 0.5, 0.01))
		airDrift = toward * airSpeed
	end
	startSequence(config, {
		approach = seconds - dipTime - timeToTop,
		dipTime = dipTime,
		releaseAfterDip = dipTime + timeToTop,
		jumpPower = jumpPower,
		dipDrift = dipDrift,
		approachDrift = drift, -- drive in at full speed; brake only on the plant
		dipRate = dipRate,
		airDrift = airDrift,
		driftSide = 1,
		-- On the run: the layup's one-foot takeoff (right-left gather steps, jump off the left
		-- foot, right knee up). Standing: the deep two-foot load.
		legStyle = if kind == "Running" then "Layup" else "Dunk",
		dipOptions = { gather = "None", drift = dipDrift, depthScale = 1, rate = dipRate },
		lowSwing = kind == "Standing", -- the ball swings down toward the knees, then up
		bodyYaw = 0, -- a dunk faces the rim
		isDunk = true,
	})
end

-- E released (or the meter ran out): grade the timing, aim, and launch the ball.
local function release()
	local activeShot = shot
	if phase ~= "Gathering" or not activeShot then
		return
	end
	local config = activeShot.config

	if activeShot.isDunk then
		-- The slam: thrown from the top of the jump down through the rim's centre.
		local from = BallController.getPosition()
		local target = Court.RIM_POSITION - Vector3.yAxis * Shooting.DUNK_SLAM_DEPTH
		local gravity = workspace.Gravity
		local vx, vy, vz = ShotMath.slamVelocity(
			from.X,
			from.Y,
			from.Z,
			target.X,
			target.Y,
			target.Z,
			Shooting.DUNK_SLAM_TIME,
			gravity
		)
		phase = "Airborne"
		-- The rim "catches" you: most of the forward speed goes, so you come down under the
		-- rim instead of flying on past the backboard.
		MovementController.setOverride(activeShot.airDrift * Shooting.DUNK_CARRY_AFTER_SLAM, Shooting.DUNK_STOP_RATE)
		PostureController.setHeadLook(0) -- done watching the rim: the head comes back level
		BallController.launch(Vector3.new(vx, vy, vz), gravity, function(made)
			HudController.shotResolved(made, "Perfect", "SLAM")
		end)
		return
	end

	-- How far through the meter the release was (IDEAL_RELEASE = perfect).
	local progress = (os.clock() - activeShot.startedAt) / activeShot.fillTime
	local offset, grade = ShotMath.grade(progress, Shooting)

	-- Turn the timing miss into a landing spot relative to the rim's centre.
	local from = BallController.getPosition()
	local distance, toward, lateral = rimAxes(from)
	local distanceFeet = distance / Court.STUDS_PER_FOOT
	local difficulty = ShotMath.difficulty(config.DIFFICULTY, distanceFeet, Shooting)
	local depthError, lateralError =
		ShotMath.aimError(offset, difficulty, Shooting, random:NextNumber(), random:NextNumber())
	-- The errors are tuned for a real-size hoop; scale them with the oversized ball and rim
	-- so shooting is exactly as hard as at real size.
	local aimOffset = (toward * depthError + lateral * lateralError) * Court.EQUIPMENT_SCALE
	local target = Court.RIM_POSITION + aimOffset

	-- Solve the throw that lands exactly on that target, with a higher arc from further out.
	local arcHeight = config.ARC_HEIGHT + distanceFeet * Shooting.ARC_PER_FT
	local vx, vy, vz =
		ShotMath.launchVelocity(from.X, from.Y, from.Z, target.X, target.Y, target.Z, arcHeight, workspace.Gravity)

	phase = "Airborne"
	if config.MOTION == "Layup" then
		-- Ease off the drive once the ball is gone, so you come down near the rim instead of
		-- flying on under it.
		MovementController.setOverride(activeShot.airDrift * Shooting.LAYUP_CARRY_AFTER_RELEASE)
	end
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
	MovementController.setFacingYaw(0) -- square to the rim again
	MovementController.setFacingLocked(false) -- (a dunk locks it while in the air)
	LegController.land()
	PostureController.setShooting(false)
	PostureController.setHeadLook(nil)
	PostureController.leanTo(0, Motion.LEAN_RECOVER_TIME) -- straighten back up
end

-- Runs every frame during a shot: turns toward the rim, jumps when it's time, fills the
-- meter while gathering, and watches for landing after release.
local function step(dt: number)
	local activeShot = shot
	local parts = CharacterRef.get()
	if not activeShot or not parts then
		return
	end

	-- A dunker in the air keeps facing the way they jumped: once the hips pass under the
	-- rim, "toward the rim" points backward and turning would swing the body round mid-air.
	local dunkInAir = activeShot.isDunk and activeShot.jumpedAt ~= nil
	if not dunkInAir then
		turnTowardRim(parts.root, dt, activeShot.bodyYaw)
	end

	local now = os.clock()
	-- The drive in (if any) is over: dip into the takeoff.
	if not activeShot.dipStarted and now >= activeShot.dipAt then
		activeShot.dipStarted = true
		local dipOptions = activeShot.dipOptions
		local dipSwitch = activeShot.dipSwitch
		if dipSwitch then
			-- The plant brakes: from the speed actually reached on the drive (it can differ from
			-- the planned one) down to the dip drift within the first half of the dip. The legs
			-- are told the same rate, so the plant foot is placed for the real slide.
			local speedNow = MovementController.getVelocity().Magnitude
			local brakeRate = (speedNow - dipSwitch.drift.Magnitude) / math.max(activeShot.dipTime * 0.5, 0.01)
			local rate = math.max(dipSwitch.rate or 0, brakeRate, Motion.DRIFT_BLEND_RATE)
			MovementController.setOverride(dipSwitch.drift, rate)
			dipOptions = {
				gather = dipOptions.gather,
				drift = dipOptions.drift,
				depthScale = dipOptions.depthScale,
				rate = rate,
			}
		end
		LegController.startDip(activeShot.dipTime, activeShot.legStyle, dipOptions)
	end
	if not activeShot.jumpedAt and now >= activeShot.jumpAt then
		jump(parts.humanoid, activeShot.jumpPower)
		if activeShot.isDunk then
			MovementController.setFacingLocked(true) -- released again in land()
		end
		LegController.takeoff()
		-- From the ground to the air: the dip drift gives way to the (small) air drift.
		MovementController.setOverride(activeShot.airDrift)
		-- Lean into the shot (e.g. back on a fadeaway), fully leaned at the perfect release.
		PostureController.leanTo(
			activeShot.config.LEAN,
			math.max(activeShot.releaseAt - now, Motion.MIN_LEAN_TIME),
			-- Sideways lean, toward the drift: driftSide is +1 drifting right / -1 left, and a
			-- positive side lean tilts right, so moving left→right bends the body left→right.
			activeShot.driftSide * activeShot.config.SIDE_LEAN
		)
		activeShot.jumpedAt = now
	end
	-- On the floor = the hips are back down at standing height. This is measured directly
	-- (heightAboveStanding) because, with the lower jumps (~0.44 s in the air),
	-- Humanoid.FloorMaterial never reports Air and the Humanoid state can say "Landed" a full
	-- stud up, so neither can tell when the jump is over. A landing only counts once the
	-- player has been seen in the air (leftGround), so the low hips right at takeoff don't
	-- end the shot; and a small bounce up on touchdown still counts as landed (otherwise the
	-- legs would fold back into their air pose for a few frames).
	local clearance = heightAboveStanding(parts)
	local grounded = clearance <= LAND_CLEARANCE
	if activeShot.jumpedAt and clearance > AIRBORNE_CLEARANCE then
		activeShot.leftGround = true
	end

	if phase == "Gathering" then
		if activeShot.isDunk then
			-- At the top of the jump: slam it.
			if now >= activeShot.releaseAt then
				release()
			end
			return
		end
		local progress = (now - activeShot.startedAt) / activeShot.fillTime
		HudController.setProgress(progress)
		-- Held too long: the shot goes up on its own (very late) — at the latest when the
		-- feet touch back down, so the ball never leaves the hands after landing (the
		-- grade still comes from how late it was).
		local landedHolding = activeShot.leftGround and grounded
		if progress >= 1 + Shooting.LATE_LIMIT or landedHolding then
			release()
		end
	elseif phase == "Airborne" then
		-- Landed = we jumped, were seen in the air, and are touching the floor again.
		-- (Roblox reports the floor material a few frames late, so right after takeoff it
		-- still says "on the floor"; waiting until we've seen the player airborne avoids
		-- ending the shot mid-air.)
		local jumpedAt = activeShot.jumpedAt
		if jumpedAt and grounded then
			local airTime = now - jumpedAt
			if airTime > MIN_AIR_TIME and (activeShot.leftGround or airTime > JUMP_FAILSAFE) then
				land()
			end
		end
	end
end

function ShotController.start()
	-- Studio only: ReplicatedStorage.RoHoopsDunk lets you try a dunk from the command bar
	-- while playing (client view), as if you had double-clicked:
	--   game.ReplicatedStorage.RoHoopsDunk:Fire()
	if RunService:IsStudio() then
		local dunkEvent = Instance.new("BindableEvent")
		dunkEvent.Name = "RoHoopsDunk"
		dunkEvent.Event:Connect(beginDunk)
		dunkEvent.Parent = ReplicatedStorage
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- gameProcessed = the key was used by Roblox UI (e.g. typing in chat), so ignore it.
		if gameProcessed then
			return
		end
		if input.KeyCode == SHOOT_KEY then
			begin()
		elseif input.UserInputType == DUNK_BUTTON then
			-- A second click within DOUBLE_CLICK_TIME of the first is a double-click.
			local now = os.clock()
			if now - lastClickAt <= Shooting.DOUBLE_CLICK_TIME then
				lastClickAt = -math.huge -- a third click starts counting again
				beginDunk()
			else
				lastClickAt = now
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		-- (A dunk releases itself; letting go of E doesn't touch it.)
		local activeShot = shot
		if input.KeyCode == SHOOT_KEY and not (activeShot and activeShot.isDunk) then
			release()
		end
	end)

	CharacterRef.onSpawn(function()
		phase = "Ready"
		shot = nil
		MovementController.setOverride(nil)
		MovementController.setFacingYaw(0)
		LegController.land()
		PostureController.setShooting(false)
		PostureController.leanTo(0, 0)
	end)
	-- "Input + 2" priority runs right after MovementController each frame.
	RunService:BindToRenderStep("RoHoopsShot", Enum.RenderPriority.Input.Value + 2, step)
end

return ShotController
