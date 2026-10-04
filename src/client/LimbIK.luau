--!strict
-- LIMB IK
-- Shared helper for driving an arm or a leg with Roblox's IKControl ("inverse
-- kinematics"): you move a target and IKControl bends the limb's joints (shoulder, elbow,
-- wrist or hip, knee) so the limb reaches it, on top of the normal animations.
-- Used by ArmController and LegController.
--
-- Two kinds of limb:
--   * legs use position-only IK: the ankle joint goes to a point.
--   * arms use full transform IK through `placeHand`: you say where the PALM should be,
--     which way it faces and which way the fingers point, and the hand is placed and
--     angled to match. That's what lets a hand sit flat on the ball.

local Motion = require(game:GetService("ReplicatedStorage").Shared.Config.Motion)

export type Limb = {
	ik: IKControl, -- bends the limb so its end joint reaches `target`
	target: Attachment, -- where the end joint should go (moved every frame by the controller)
	pole: Attachment, -- which way the middle joint (elbow / knee) should point
	-- For hands: offset from the wrist joint to the palm, in the hand's own space. Lets
	-- placeHand work out where the wrist must be for the palm to land on a point.
	palmOffset: Vector3,
}

local LimbIK = {}

-- Creates IK for one limb. Returns nil if the character doesn't have the parts yet (the
-- avatar may still be loading) or at all (R6 characters).
--   name       label for the created instances, e.g. "RightArm"
--   chainRoot  first part of the limb, e.g. "RightUpperArm"
--   endPart    last part, e.g. "RightHand"
--   endJoint   attachment on the last part marking the end joint, e.g. "RightWristRigAttachment"
--   palm       (hands only) attachment marking the palm, e.g. "RightGripAttachment"
function LimbIK.make(
	humanoid: Humanoid,
	character: Model,
	name: string,
	chainRoot: string,
	endPart: string,
	endJoint: string,
	palm: string?
): Limb?
	local root = character:FindFirstChild(chainRoot)
	local last = character:FindFirstChild(endPart)
	local joint = last and last:FindFirstChild(endJoint) :: Attachment?
	local palmAttachment = if last and palm then last:FindFirstChild(palm) :: Attachment? else nil
	if not root or not joint or (palm and not palmAttachment) then
		return nil
	end

	-- Target and pole points live on the terrain so they can be placed anywhere in the world.
	local target = Instance.new("Attachment")
	target.Name = "RoHoops" .. name .. "Target"
	target.Parent = workspace.Terrain
	local pole = Instance.new("Attachment")
	pole.Name = "RoHoops" .. name .. "Pole"
	pole.Parent = workspace.Terrain

	local ik = Instance.new("IKControl")
	ik.Name = "RoHoops" .. name
	-- Hands: match position AND angle. Legs: match position only.
	ik.Type = if palmAttachment then Enum.IKControlType.Transform else Enum.IKControlType.Position
	ik.ChainRoot = root
	ik.EndEffector = joint
	ik.Target = target
	ik.Pole = pole
	ik.SmoothTime = Motion.IK_SMOOTH_TIME
	ik.Weight = 0 -- start relaxed; controllers blend it up
	ik.Parent = humanoid

	return {
		ik = ik,
		target = target,
		pole = pole,
		palmOffset = if palmAttachment and joint then palmAttachment.Position - joint.Position else Vector3.zero,
	}
end

-- Removes a limb's IK and its helper points.
function LimbIK.destroy(limb: Limb?)
	if limb then
		limb.ik:Destroy()
		limb.target:Destroy()
		limb.pole:Destroy()
	end
end

-- True if `limb` is still attached to body parts inside `character`. When the avatar's
-- appearance loads, Roblox swaps in new body parts, which leaves an old IK attached to
-- parts that no longer exist.
function LimbIK.isAttached(limb: Limb?, character: Model): boolean
	if not limb or not limb.ik.Parent then
		return false
	end
	local chainRoot, endEffector = limb.ik.ChainRoot, limb.ik.EndEffector
	return chainRoot ~= nil
		and endEffector ~= nil
		and chainRoot:IsDescendantOf(character)
		and endEffector:IsDescendantOf(character)
end

-- Turns off the avatar's joint-angle limits on the given joints (e.g. "RightWrist").
-- Newer avatars have limits meant for ragdoll physics; they stop the wrist bending back
-- far enough to hold a ball. Only affects how this player's own character is posed.
function LimbIK.freeJoints(character: Model, joints: { string })
	for _, joint in joints do
		local socket = character:FindFirstChild(joint .. "BallSocket", true)
		if socket and socket:IsA("BallSocketConstraint") then
			socket.LimitsEnabled = false
		end
	end
end

-- Hands: puts the palm at `palm`, facing `facing` (the direction the palm points), with
-- the fingers pointing as close to `fingers` as possible. All in world space.
function LimbIK.placeHand(limb: Limb, palm: Vector3, facing: Vector3, fingers: Vector3)
	local look = facing.Unit
	-- The hand's "up" axis runs from the fingertips back to the wrist, so it's the opposite
	-- of the fingers, made perpendicular to the palm direction.
	local fingersFlat = fingers - look * fingers:Dot(look)
	if fingersFlat.Magnitude < 1e-3 then
		fingersFlat = if math.abs(look.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis
	end
	local up = -fingersFlat.Unit
	local back = -look
	local rotation = CFrame.fromMatrix(Vector3.zero, up:Cross(back), up, back)
	local wrist = palm - rotation:VectorToWorldSpace(limb.palmOffset)
	limb.target.WorldCFrame = CFrame.new(wrist) * rotation
end

-- Moves a limb's weight toward `goal` (0 = normal animation, 1 = fully on target).
-- `alpha` (0 to 1) is how far to move this frame. `smoothTime` is how long the limb
-- takes to catch up with its target (defaults to Motion.IK_SMOOTH_TIME, read every frame
-- so live tuning applies).
function LimbIK.blend(limb: Limb, goal: number, alpha: number, smoothTime: number?)
	limb.ik.Weight += (goal - limb.ik.Weight) * alpha
	limb.ik.SmoothTime = smoothTime or Motion.IK_SMOOTH_TIME
end

return LimbIK
