--!strict
-- ARM CONTROLLER
-- Makes the hands handle the ball instead of the ball floating next to the body, using
-- arm IK (see src/client/LimbIK.luau): each frame we say where each palm goes, which way
-- it faces and where the fingers point, and the arm bends (and the wrist turns) to match,
-- on top of the normal animations.
--
--   Dribble – the right palm rides on top of the ball and waits at waist height while the
--             ball bounces down and back up.
--   Held    – shooting hand behind the ball in the dip, sliding under it as it rises to the
--             release point above the head; guide hand on the side the whole way.
--   Flight  – both arms reach up and forward toward the rim with the shooting wrist
--             flicked (the follow-through), hold, fall forward, then relax back to
--             normal animation.
--
-- Only works for R15 characters (the default); R6 characters just skip it.
-- Tuning values: src/shared/Config/Motion.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ball = require(ReplicatedStorage.Shared.Config.Ball)
local Motion = require(ReplicatedStorage.Shared.Config.Motion)
local MovementMath = require(ReplicatedStorage.Shared.MovementMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local LimbIK = require(script.Parent.Parent.LimbIK)
local BallController = require(script.Parent.BallController)

local ArmController = {}

-- The current character's arms, or nil if they aren't set up (yet).
local rightArm: LimbIK.Limb? = nil -- shooting / dribbling hand
local leftArm: LimbIK.Limb? = nil -- guide hand

-- How often (seconds) to retry setting up arms that couldn't be found, e.g. while the
-- avatar is still loading or on an R6 character that will never have them.
local RETRY_INTERVAL = 0.5
local nextRetryAt = 0 -- clock time of the next retry

-- Converts a Motion-config offset (right, up, forward) to Roblox's object space, where
-- forward is -Z.
local function toObjectSpace(offset: Vector3): Vector3
	return Vector3.new(offset.X, offset.Y, -offset.Z)
end

-- A point given relative to the hips (and turning with the player), in world space.
local function fromHips(rootCFrame: CFrame, offset: Vector3): Vector3
	return rootCFrame:PointToWorldSpace(toObjectSpace(offset))
end

-- Makes sure both arms have working IK on the current body parts, rebuilding them if the
-- parts were missing or replaced. Returns true when both arms are ready.
local function ensureArms(humanoid: Humanoid, character: Model): boolean
	if LimbIK.isAttached(rightArm, character) and LimbIK.isAttached(leftArm, character) then
		return true
	end
	local now = os.clock()
	if now < nextRetryAt then
		return false
	end
	nextRetryAt = now + RETRY_INTERVAL

	LimbIK.destroy(rightArm)
	LimbIK.destroy(leftArm)
	rightArm = LimbIK.make(
		humanoid,
		character,
		"RightArm",
		"RightUpperArm",
		"RightHand",
		"RightWristRigAttachment",
		"RightGripAttachment"
	)
	leftArm = LimbIK.make(
		humanoid,
		character,
		"LeftArm",
		"LeftUpperArm",
		"LeftHand",
		"LeftWristRigAttachment",
		"LeftGripAttachment"
	)
	-- Let the wrists bend back far enough to hold the ball (see LimbIK.freeJoints).
	LimbIK.freeJoints(
		character,
		{ "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }
	)
	return rightArm ~= nil and leftArm ~= nil
end

-- Eases 0→1 gently at both ends (smoothstep), for motion that starts and stops softly.
local function ease(p: number): number
	p = math.clamp(p, 0, 1)
	return p * p * (3 - 2 * p)
end

-- Puts `arm`'s palm on the ball at `direction` (from the ball's centre, world space),
-- facing the centre, fingers pointing `fingers`.
local function palmOnBall(arm: LimbIK.Limb, ballPosition: Vector3, direction: Vector3, fingers: Vector3)
	local dir = direction.Unit
	LimbIK.placeHand(arm, ballPosition + dir * (Ball.RADIUS + Motion.PALM_GAP), -dir, fingers)
end

-- Runs every frame after the ball has been positioned.
local function update(dt: number)
	local parts = CharacterRef.get()
	if not parts or not ensureArms(parts.humanoid, parts.character) then
		return
	end
	local right, left = rightArm :: LimbIK.Limb, leftArm :: LimbIK.Limb

	local rootCFrame = parts.root.CFrame
	-- Turns a Motion-config direction (right, up, forward) into a world direction.
	local function bodyDirection(offset: Vector3): Vector3
		return rootCFrame:VectorToWorldSpace(toObjectSpace(offset))
	end
	local ballPosition = BallController.getPosition()
	local mode = BallController.getMode()
	local sinceRelease = os.clock() - BallController.getLaunchTime()
	local rightGoal, leftGoal = 0, 0 -- how much each arm should follow its target this frame

	if mode == "Dribble" then
		-- Palm on top of the ball (facing down), but never lower than DRIBBLE_PALM_MIN_HEIGHT.
		local floorY = rootCFrame.Position.Y - parts.humanoid.HipHeight - parts.root.Size.Y / 2
		local palmY = math.max(ballPosition.Y + Ball.RADIUS + Motion.PALM_GAP, floorY + Motion.DRIBBLE_PALM_MIN_HEIGHT)
		local palm = Vector3.new(ballPosition.X, palmY, ballPosition.Z)
		LimbIK.placeHand(right, palm, -Vector3.yAxis, bodyDirection(Motion.DRIBBLE_FINGERS))
		right.pole.WorldPosition = fromHips(rootCFrame, Motion.DRIBBLE_ELBOW)
		rightGoal = 1
	elseif mode == "Held" then
		-- How far the ball has risen from the dip pocket (0) to the release point (1). The
		-- shooting hand slides from behind the ball to under it over that range.
		local ballHeight = rootCFrame:PointToObjectSpace(ballPosition).Y
		local rise = math.clamp(
			(ballHeight - Motion.DIP_POCKET.Y) / math.max(Motion.RELEASE_POINT.Y - Motion.DIP_POCKET.Y, 0.01),
			0,
			1
		)
		local shootingSpot = Motion.SHOOTING_HAND_LOW:Lerp(Motion.SHOOTING_HAND_HIGH, rise)
		local shootingFingers = Motion.SHOOTING_FINGERS_LOW:Lerp(Motion.SHOOTING_FINGERS_HIGH, rise)
		palmOnBall(right, ballPosition, bodyDirection(shootingSpot), bodyDirection(shootingFingers))
		palmOnBall(left, ballPosition, bodyDirection(Motion.GUIDE_HAND), bodyDirection(Motion.GUIDE_FINGERS))
		right.pole.WorldPosition = fromHips(rootCFrame, Motion.SHOOTING_ELBOW)
		left.pole.WorldPosition = fromHips(rootCFrame, Motion.GUIDE_ELBOW)
		rightGoal, leftGoal = 1, 1
	elseif sinceRelease < Motion.FOLLOW_THROUGH_TIME then
		-- Follow-through: arms reach up and forward toward the rim, hold for the first
		-- FOLLOW_THROUGH_HOLD of the time, then fall forward to the END positions.
		-- `fall` goes 0 (arms up) → 1 (arms fallen forward).
		local progress = sinceRelease / Motion.FOLLOW_THROUGH_TIME
		local hold = math.clamp(Motion.FOLLOW_THROUGH_HOLD, 0, 0.95)
		local fall = ease((progress - hold) / (1 - hold))
		LimbIK.placeHand(
			right,
			fromHips(rootCFrame, Motion.FOLLOW_THROUGH:Lerp(Motion.FOLLOW_THROUGH_END, fall)),
			bodyDirection(Motion.FOLLOW_THROUGH_FACING),
			bodyDirection(Motion.FOLLOW_THROUGH_FINGERS:Lerp(Motion.FOLLOW_THROUGH_END_FINGERS, fall))
		)
		LimbIK.placeHand(
			left,
			fromHips(rootCFrame, Motion.GUIDE_FOLLOW_THROUGH:Lerp(Motion.GUIDE_FOLLOW_THROUGH_END, fall)),
			bodyDirection(Motion.GUIDE_FOLLOW_THROUGH_FACING),
			bodyDirection(Motion.GUIDE_FINGERS:Lerp(Motion.FOLLOW_THROUGH_END_FINGERS, fall))
		)
		right.pole.WorldPosition = fromHips(rootCFrame, Motion.SHOOTING_ELBOW)
		left.pole.WorldPosition = fromHips(rootCFrame, Motion.GUIDE_ELBOW)
		rightGoal, leftGoal = 1, 1
	end

	-- Take hold quickly, let go slowly (so the arms settle down instead of dropping).
	local function alphaFor(goal: number, arm: LimbIK.Limb): number
		local sharpness = if goal < arm.ik.Weight then Motion.IK_RELAX_SHARPNESS else Motion.IK_BLEND_SHARPNESS
		return MovementMath.smoothingAlpha(sharpness, dt)
	end
	LimbIK.blend(right, rightGoal, alphaFor(rightGoal, right))
	LimbIK.blend(left, leftGoal, alphaFor(leftGoal, left))
end

function ArmController.start()
	-- On a new character, drop the old arms; update() sets up the new ones once the
	-- character's body parts exist.
	CharacterRef.onSpawn(function()
		LimbIK.destroy(rightArm)
		LimbIK.destroy(leftArm)
		rightArm, leftArm = nil, nil
		nextRetryAt = 0
	end)
	-- Runs just after BallController (Character + 1) so the hands use this frame's ball position.
	RunService:BindToRenderStep("RoHoopsArms", Enum.RenderPriority.Character.Value + 2, update)
end

return ArmController
