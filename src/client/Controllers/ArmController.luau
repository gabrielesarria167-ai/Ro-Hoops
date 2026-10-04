--!strict
-- ARM CONTROLLER
-- Makes the hands handle the ball instead of the ball floating next to the body. It uses
-- Roblox's IKControl ("inverse kinematics"): you give it a target point and it bends the
-- shoulder and elbow so the wrist reaches that point, on top of the normal animations.
-- (IKControl moves the wrist joint, not the palm, so targets are wrist positions.)
--
--   Dribble – the right hand rides on top of the ball and waits at waist height while the
--             ball bounces down and back up.
--   Held    – shooting hand behind and under the ball, guide hand on its side, moving
--             with the ball as it rises to the set point.
--   Flight  – the guide hand comes off, the shooting arm extends toward the rim
--             (follow-through), holds, then relaxes back to normal animation.
--
-- Only works for R15 characters (the default); R6 characters just skip it.
-- Tuning values: src/shared/Config/Motion.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ball = require(ReplicatedStorage.Shared.Config.Ball)
local Motion = require(ReplicatedStorage.Shared.Config.Motion)
local MovementMath = require(ReplicatedStorage.Shared.MovementMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local BallController = require(script.Parent.BallController)

-- One arm's IK setup.
type Arm = {
	ik: IKControl, -- bends the arm so the hand reaches `target`
	target: Attachment, -- where the wrist should go (we move this every frame)
	pole: Attachment, -- which way the elbow should point
}

local ArmController = {}

-- The current character's arms, or nil if it has none we can drive (e.g. R6).
local rightArm: Arm? = nil -- shooting / dribbling hand
local leftArm: Arm? = nil -- guide hand

-- Converts a Motion-config offset (right, up, forward) to Roblox's object space, where
-- forward is -Z.
local function toObjectSpace(offset: Vector3): Vector3
	return Vector3.new(offset.X, offset.Y, -offset.Z)
end

-- A point given relative to the hips (and turning with the player), in world space.
local function fromHips(rootCFrame: CFrame, offset: Vector3): Vector3
	return rootCFrame:PointToWorldSpace(toObjectSpace(offset))
end

-- Creates the IK for one arm ("Right" or "Left"). Returns nil if the rig lacks the parts.
local function makeArm(humanoid: Humanoid, character: Model, side: string): Arm?
	local upperArm = character:FindFirstChild(side .. "UpperArm")
	local hand = character:FindFirstChild(side .. "Hand")
	local wrist = hand and hand:FindFirstChild(side .. "WristRigAttachment")
	if not upperArm or not wrist then
		return nil
	end

	-- Target and pole points live on the terrain so we can place them anywhere in the world.
	local target = Instance.new("Attachment")
	target.Name = "RoHoops" .. side .. "HandTarget"
	target.Parent = workspace.Terrain
	local pole = Instance.new("Attachment")
	pole.Name = "RoHoops" .. side .. "ElbowPole"
	pole.Parent = workspace.Terrain

	local ik = Instance.new("IKControl")
	ik.Name = "RoHoops" .. side .. "Arm"
	ik.Type = Enum.IKControlType.Position -- move the wrist to the target; the hand keeps its own angle
	ik.ChainRoot = upperArm -- the chain is upper arm → lower arm
	ik.EndEffector = wrist -- the wrist joint is the point placed on the target
	ik.Target = target
	ik.Pole = pole
	ik.SmoothTime = Motion.IK_SMOOTH_TIME
	ik.Weight = 0 -- start relaxed; weights blend up in update()
	ik.Parent = humanoid

	return { ik = ik, target = target, pole = pole }
end

-- Removes one arm's IK and its helper points.
local function destroyArm(arm: Arm?)
	if arm then
		arm.ik:Destroy()
		arm.target:Destroy()
		arm.pole:Destroy()
	end
end

-- Moves an arm's weight toward `goal` (0 = normal animation, 1 = wrist on target) smoothly.
local function blendWeight(arm: Arm, goal: number, alpha: number)
	arm.ik.Weight += (goal - arm.ik.Weight) * alpha
	arm.ik.SmoothTime = Motion.IK_SMOOTH_TIME -- re-read so live tuning applies
end

-- Runs every frame after the ball has been positioned.
local function update(dt: number)
	local parts = CharacterRef.get()
	local right, left = rightArm, leftArm
	if not parts or not right or not left then
		return
	end

	local rootCFrame = parts.root.CFrame
	local ballPosition = BallController.getPosition()
	local mode = BallController.getMode()
	local rightGoal, leftGoal = 0, 0 -- how much each arm should follow its target this frame

	if mode == "Dribble" then
		-- Hand on top of the ball, but the wrist never lower than DRIBBLE_WRIST_MIN_HEIGHT.
		local floorY = rootCFrame.Position.Y - parts.humanoid.HipHeight - parts.root.Size.Y / 2
		local wristY =
			math.max(ballPosition.Y + Ball.RADIUS + Motion.DRIBBLE_WRIST_GAP, floorY + Motion.DRIBBLE_WRIST_MIN_HEIGHT)
		right.target.WorldPosition = Vector3.new(ballPosition.X, wristY, ballPosition.Z)
		right.pole.WorldPosition = fromHips(rootCFrame, Motion.DRIBBLE_ELBOW)
		rightGoal = 1
	elseif mode == "Held" then
		-- Both hands on the ball: each wrist sits out from the ball's centre in its hand's
		-- direction, turned to match the player's facing.
		local ballFrame = CFrame.new(ballPosition) * rootCFrame.Rotation
		local shootingWrist = Motion.SHOOTING_HAND.Unit * (Ball.RADIUS + Motion.SHOOTING_WRIST_GAP)
		local guideWrist = Motion.GUIDE_HAND.Unit * (Ball.RADIUS + Motion.GUIDE_WRIST_GAP)
		right.target.WorldPosition = ballFrame:PointToWorldSpace(toObjectSpace(shootingWrist))
		left.target.WorldPosition = ballFrame:PointToWorldSpace(toObjectSpace(guideWrist))
		right.pole.WorldPosition = fromHips(rootCFrame, Motion.SHOOTING_ELBOW)
		left.pole.WorldPosition = fromHips(rootCFrame, Motion.GUIDE_ELBOW)
		rightGoal, leftGoal = 1, 1
	elseif os.clock() - BallController.getLaunchTime() < Motion.FOLLOW_THROUGH_TIME then
		-- Follow-through: shooting arm reaches toward the rim; guide hand lets go.
		right.target.WorldPosition = fromHips(rootCFrame, Motion.FOLLOW_THROUGH)
		right.pole.WorldPosition = fromHips(rootCFrame, Motion.SHOOTING_ELBOW)
		rightGoal = 1
	end

	local alpha = MovementMath.smoothingAlpha(Motion.IK_BLEND_SHARPNESS, dt)
	blendWeight(right, rightGoal, alpha)
	blendWeight(left, leftGoal, alpha)
end

function ArmController.start()
	CharacterRef.onSpawn(function(parts)
		destroyArm(rightArm)
		destroyArm(leftArm)
		rightArm = makeArm(parts.humanoid, parts.character, "Right")
		leftArm = makeArm(parts.humanoid, parts.character, "Left")
	end)
	-- Runs just after BallController (Character + 1) so the hands use this frame's ball position.
	RunService:BindToRenderStep("RoHoopsArms", Enum.RenderPriority.Character.Value + 2, update)
end

return ArmController
