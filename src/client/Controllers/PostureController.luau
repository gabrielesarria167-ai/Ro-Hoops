--!strict
-- POSTURE CONTROLLER
-- Poses the spine, neck and head, and keeps the shooter's body square during a shot:
--   * Upright torso – Roblox's default animations bend the body forward: jump and fall
--     lean the torso ~28° and drop the head ~40°, and run leans it ~18°. A shooter stays
--     tall, so while shooting we stop jump/fall and turn walk/run down to nothing (they're
--     restored afterwards). Nothing else is lost: the arms and legs are already driven by
--     ArmController and LegController.
--   * Spine – every lean (the dribbling stance, a move's or shot's lean, the shot dip's
--     forward hinge, the landing dip, the sideways lean) is ONE number of degrees that is
--     shared out along the spine: the PELVIS (the Root joint, the hips) takes
--     PELVIS_LEAN_SHARE of it and the CHEST (the Waist joint) the rest, like a real
--     hip hinge with a straight back instead of a rigid plank.
--   * Neck – the Neck joint rotates the other way to undo part of the trunk's tilt
--     (NECK_PITCH_COUNTER / NECK_ROLL_COUNTER), so the eyes stay near level in the
--     dribbling stance and in a fadeaway instead of staring at the floor or the roof.
--   * Eyes on the rim – a head IK (IKControl, "LookAt") turns the head to face the rim while
--     shooting; it eases in and out gently and eases off when the rim is steeply above.
--   * Extras layered on top: setDipHinge (chest goes forward as the knees bend),
--     absorbLanding (a quick forward dip on touchdown), setHeadTurn (head leads a spin or
--     fakes a crossover), setDribbleTwist (the chest swings with the dribbling arm).
--     Smooth motion: a leanTo starts from the CURRENT angle AND speed (cubic Hermite), and
--     the stance lean is a critically damped spring, so reversing never pops the chest.
--     The HumanoidRootPart itself stays upright, so physics and movement are unaffected.
--     getBodyCFrame() gives the other controllers the hips' position (pelvis share of the
--     lean only, so the ball, hands and air legs tilt less than the chest) and
--     getChestCFrame() the chest's.
-- ShotController switches shooting on when a shot starts and off when the player lands,
-- and sets the lean with leanTo(); LegController sets the stance lean, the dip hinge and the
-- landing dip; BallController the dribble twist; SkillController the head turn.
--
-- Only works for R15 characters (the default); R6 characters skip the head and the lean.
-- Tuning values: src/shared/Config/Posture.luau (spine shares, neck counter, head look,
-- dynamics), src/shared/Config/Motion.luau (HEAD_LOOK_WEIGHT, LEAN_RECOVER_TIME, the IK relax
-- speed) and src/shared/Config/Shooting.luau (each shot type's LEAN).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Court = require(ReplicatedStorage.Shared.Config.Court)
local Motion = require(ReplicatedStorage.Shared.Config.Motion)
local Posture = require(ReplicatedStorage.Shared.Config.Posture)
local MovementMath = require(ReplicatedStorage.Shared.MovementMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)

local PostureController = {}

-- Names of the Animate script's animations that bend the body forward. They keep these
-- names even when a player uses a different animation pack.
-- Jump/fall are stopped outright (Roblox starts fresh ones on the next jump).
local STOPPED_ANIMATIONS = { JumpAnim = true, FallAnim = true }
-- Walk/run must keep playing (Roblox's Animate script assumes they are), so they're
-- turned down to almost nothing instead, and turned back up after the shot.
local MUTED_ANIMATIONS = { WalkAnim = true, RunAnim = true }
-- Seconds to fade a stopped animation out. 0 = instantly: they're stopped the frame they
-- start, before they've moved the body, so there's nothing visible to fade.
local ANIMATION_FADE = 0
local MUTED_WEIGHT = 0.001 -- how strong a muted animation is (0 can stop it entirely)
local MUTE_FADE = 0.1 -- seconds to fade walk/run out when a shot starts
local UNMUTE_FADE = 0.25 -- seconds to fade them back in after the shot

-- Walk/run tracks we've muted, and the strength each had, to restore after the shot.
local mutedTracks: { [AnimationTrack]: number } = {}
-- How often (seconds) to retry setting up the head IK while the avatar is still loading.
local RETRY_INTERVAL = 0.5

local shooting = false -- true from the start of a shot until landing
-- How strongly the head looks at the rim while shooting (nil = Motion.HEAD_LOOK_WEIGHT).
-- A dunk lowers it (the rim is right above you) and drops it to 0 after the slam.
local headLookWeight: number? = nil
local headIK: IKControl? = nil -- turns the head toward `rimTarget`
local rimTarget: Attachment? = nil -- a point at the centre of the rim
local nextRetryAt = 0 -- clock time of the next setup retry

-- A value that glides to a goal over a set time, starting from its CURRENT value AND
-- current speed (a cubic Hermite curve), so changing the goal mid-glide bends smoothly
-- instead of restarting from a standstill.
type Track = {
	from: number, -- the value when the glide started
	goal: number, -- the value it is gliding to
	speed: number, -- the speed when the glide started, degrees per second
	startedAt: number, -- clock time the glide started
	duration: number, -- seconds the glide takes (0 = jump straight to the goal)
}

local function newTrack(): Track
	return { from = 0, goal = 0, speed = 0, startedAt = 0, duration = 0 }
end

-- The move/shot lean (degrees, positive = back, negative = forward), the sideways lean
-- (positive = toward the player's right) and the head's turn (positive = to the right,
-- relative to the chest). Each glides on its own Track; the current value is worked out
-- from the clock, so every controller that asks during a frame gets the same angle.
local leanTrack = newTrack()
local sideTrack = newTrack()
local headTurnTrack = newTrack()
-- The stance lean, degrees (negative = forward): follows `stanceGoal` (0 while shooting)
-- like a critically damped spring, with its own speed `stanceSpeed` (degrees per second).
local stanceLean = 0
local stanceSpeed = 0
local stanceGoal = 0
-- Extra forward hinge in the shot's dip, degrees (positive = more forward), eased toward
-- the goal LegController sets every frame.
local dipHinge = 0
local dipHingeGoal = 0
-- The landing dip: strength 0-1 and the clock time of the touchdown.
local landingStrength = 0
local landingStartedAt = -math.huge
-- Dribble twist of the chest, degrees: yaw (positive = turn to the right) and roll
-- (positive = tilt to the right), eased toward the goals BallController sets every frame.
local twistYaw, twistRoll = 0, 0
local twistYawGoal, twistRollGoal = 0, 0
-- 0-1: how much the shoulder levelling for shots is blended in (see SHOT_SHOULDER_LEVEL).
local shootLevel = 0
-- The clock time everything above was last stepped to (see advance).
local lastAdvance = os.clock()

-- The root joint's rest pose: its pivot point at the hips, in HumanoidRootPart space. The
-- lean rotates around it. Read from the character (see applyPosture); this default is close.
local hipPivot = CFrame.new(0, -1, 0)
-- Where the Waist joint (the chest's pivot) sits, in HumanoidRootPart space when upright.
local chestPivot = CFrame.new(0, -0.4, 0)
-- Rest pose of each joint piece we've rotated (a Motor6D's C0, or an Attachment's
-- CFrame), so it can be put back exactly when the posture is neutral.
local restPoses: { [Instance]: CFrame } = {}

-- Removes the head IK and its target.
local function destroyHead()
	if headIK then
		headIK:Destroy()
	end
	if rimTarget then
		rimTarget:Destroy()
	end
	headIK, rimTarget = nil, nil
end

-- Makes sure the head IK exists on the current head, rebuilding it if the head was
-- missing or replaced (e.g. when the avatar's appearance loads). Returns it when ready.
local function ensureHead(humanoid: Humanoid, character: Model): IKControl?
	local ik = headIK
	if ik and ik.Parent and ik.ChainRoot and ik.ChainRoot:IsDescendantOf(character) then
		return ik
	end
	local now = os.clock()
	if now < nextRetryAt then
		return nil
	end
	nextRetryAt = now + RETRY_INTERVAL
	destroyHead()

	local head = character:FindFirstChild("Head")
	local face = head and head:FindFirstChild("FaceFrontAttachment")
	if not head or not face then
		return nil
	end

	local target = Instance.new("Attachment")
	target.Name = "RoHoopsRimLookTarget"
	target.WorldPosition = Court.RIM_POSITION
	target.Parent = workspace.Terrain

	local newIK = Instance.new("IKControl")
	newIK.Name = "RoHoopsHeadLook"
	newIK.Type = Enum.IKControlType.LookAt -- point the face at the target
	newIK.ChainRoot = head -- only the neck turns (a longer chain would bend the torso too)
	newIK.EndEffector = face -- the direction the face points
	newIK.Target = target
	newIK.Weight = 0
	newIK.Parent = humanoid

	headIK, rimTarget = newIK, target
	return newIK
end

-- While a shot is in progress: stops `track` if it's jump/fall, mutes it if it's walk/run.
local function suppressIfLeaning(track: AnimationTrack)
	local animation = track.Animation
	if not shooting or not animation then
		return
	end
	if STOPPED_ANIMATIONS[animation.Name] then
		track:Stop(ANIMATION_FADE)
	elseif MUTED_ANIMATIONS[animation.Name] then
		local firstTime = mutedTracks[track] == nil
		if firstTime then
			mutedTracks[track] = math.max(track.WeightTarget, MUTED_WEIGHT)
		end
		-- Fade out gently the first time; after that, hold it down instantly in case the
		-- Animate script tries to turn it back up.
		track:AdjustWeight(MUTED_WEIGHT, if firstTime then MUTE_FADE else 0)
	end
end

-- After the shot: turn the muted walk/run animations back up to where they were.
local function unmuteAll()
	for track, weight in mutedTracks do
		if track.IsPlaying then
			track:AdjustWeight(weight, UNMUTE_FADE)
		end
	end
	table.clear(mutedTracks)
end

-- Eases 0→1 gently at both ends (smoothstep), for motion that starts and stops softly.
local function ease(p: number): number
	p = math.clamp(p, 0, 1)
	return p * p * (3 - 2 * p)
end

-- Where a Track is at clock time `now`, and how fast it is moving (degrees, degrees/second).
local function sampleTrack(track: Track, now: number): (number, number)
	local duration = track.duration
	local p = if duration > 0 then (now - track.startedAt) / duration else 1
	if p >= 1 then
		return track.goal, 0
	end
	p = math.max(p, 0)
	local p2 = p * p
	local p3 = p2 * p
	local startSlope = track.speed * duration -- the starting speed, in Hermite units
	-- Cubic Hermite basis: value = h00*from + h10*slope + h01*goal (end slope 0).
	local value = (2 * p3 - 3 * p2 + 1) * track.from + (p3 - 2 * p2 + p) * startSlope + (-2 * p3 + 3 * p2) * track.goal
	local slope = (6 * p2 - 6 * p) * track.from + (3 * p2 - 4 * p + 1) * startSlope + (-6 * p2 + 6 * p) * track.goal
	return value, slope / duration
end

-- Points `track` at a new goal, continuing from where it is now at the speed it has now.
local function retarget(track: Track, goal: number, duration: number)
	local now = os.clock()
	local value, speed = sampleTrack(track, now)
	track.from, track.speed = value, speed
	track.goal = goal
	track.startedAt = now
	track.duration = math.max(duration, 0)
end

-- Critically damped spring: moves (x, v) toward `goal` with natural frequency `omega`
-- (radians/second) for `dt` seconds. Exact for any dt, so a long frame can't blow it up.
local function springStep(x: number, v: number, goal: number, omega: number, dt: number): (number, number)
	local offset = x - goal
	local decay = math.exp(-omega * dt)
	local carried = (v + omega * offset) * dt
	return goal + (offset + carried) * decay, (v - omega * carried) * decay
end

-- Steps every eased value forward to the current clock time. Called by update() and by the
-- getters, so a controller that asks before our update this frame still sees fresh values.
local function advance()
	local now = os.clock()
	local dt = math.clamp(now - lastAdvance, 0, 0.25)
	lastAdvance = now
	if dt <= 0 then
		return
	end
	-- Stance lean: a spring toward the goal (straight up while shooting: a shooter stays tall).
	local stanceTarget = if shooting then 0 else stanceGoal
	stanceLean, stanceSpeed =
		springStep(stanceLean, stanceSpeed, stanceTarget, 2 * math.pi * Posture.STANCE_SPRING_FREQUENCY, dt)
	dipHinge += (dipHingeGoal - dipHinge) * MovementMath.smoothingAlpha(Posture.DIP_HINGE_SHARPNESS, dt)
	local twistAlpha = MovementMath.smoothingAlpha(Posture.TWIST_SHARPNESS, dt)
	twistYaw += (twistYawGoal - twistYaw) * twistAlpha
	twistRoll += (twistRollGoal - twistRoll) * twistAlpha
	local levelGoal = if shooting then 1 else 0
	shootLevel += (levelGoal - shootLevel) * MovementMath.smoothingAlpha(Posture.SHOT_LEVEL_SHARPNESS, dt)
end

-- The landing dip right now, degrees forward: a quick dip (LANDING_DIP_SHARE of the time)
-- followed by a smooth recovery, over LANDING_RECOVER_TIME.
local function landingHinge(now: number): number
	if landingStrength <= 0 then
		return 0
	end
	local p = (now - landingStartedAt) / math.max(Posture.LANDING_RECOVER_TIME, 0.01)
	if p < 0 or p >= 1 then
		return 0
	end
	local dipShare = math.clamp(Posture.LANDING_DIP_SHARE, 0.01, 0.99)
	local shape = if p < dipShare then ease(p / dipShare) else 1 - ease((p - dipShare) / (1 - dipShare))
	return Posture.LANDING_HINGE * landingStrength * shape
end

-- The angles the joints get right now, all in degrees. Pitch: positive = back, negative =
-- forward. Roll: positive = toward the player's right. Yaw: positive = turn to the right.
type Pose = {
	pelvisPitch: number,
	pelvisRoll: number,
	chestPitch: number,
	chestRoll: number,
	chestYaw: number,
	neckPitch: number,
	neckRoll: number,
	neckYaw: number,
}
local pose: Pose = {
	pelvisPitch = 0,
	pelvisRoll = 0,
	chestPitch = 0,
	chestRoll = 0,
	chestYaw = 0,
	neckPitch = 0,
	neckRoll = 0,
	neckYaw = 0,
}

-- Works out the pose from all the eased values. This is where the lean is shared out along
-- the spine and where the neck cancels part of it. Fills (and returns) the shared `pose`.
local function computePose(): Pose
	advance()
	local now = lastAdvance
	local move = sampleTrack(leanTrack, now)
	local side = sampleTrack(sideTrack, now)
	local headTurn = sampleTrack(headTurnTrack, now)

	-- Total forward/back tilt of the trunk: the move/shot lean + the stance lean, minus the
	-- forward hinges (the dip's and the landing's, which are "positive = forward").
	local pitch = move + stanceLean - dipHinge - landingHinge(now)
	pose.pelvisPitch = pitch * Posture.PELVIS_LEAN_SHARE
	pose.chestPitch = pitch * Posture.CHEST_LEAN_SHARE

	-- Sideways: the chest takes most of it, minus the levelling that keeps a shooter's
	-- shoulders flat, plus the dribble twist's roll.
	pose.pelvisRoll = side * Posture.PELVIS_SIDE_SHARE
	pose.chestRoll = side * Posture.CHEST_SIDE_SHARE * (1 - Posture.SHOT_SHOULDER_LEVEL * shootLevel) + twistRoll
	pose.chestYaw = twistYaw

	-- The neck undoes part of the trunk's total tilt, keeping the eyes near level (it turns
	-- the opposite way, hence the minus signs), and part of the twist's yaw. The head turn
	-- (spin lead, head fake) is then added on top.
	local maxNeck = Posture.NECK_MAX_DEGREES
	pose.neckPitch = math.clamp(-Posture.NECK_PITCH_COUNTER * (pose.pelvisPitch + pose.chestPitch), -maxNeck, maxNeck)
	pose.neckRoll = math.clamp(-Posture.NECK_ROLL_COUNTER * (pose.pelvisRoll + pose.chestRoll), -maxNeck, maxNeck)
	pose.neckYaw =
		math.clamp(headTurn - Posture.NECK_YAW_COUNTER * twistYaw, -Posture.HEAD_TURN_MAX, Posture.HEAD_TURN_MAX)
	return pose
end

-- The rotation for a lean of `degrees` back (negative = forward) plus `sideDegrees` toward
-- the player's right. Roblox's "forward" is -Z, so turning around the X (right) axis by a
-- positive angle tips the top of the body back toward +Z; turning around the Z (forward)
-- axis by a positive angle tips the top toward -X (left), hence the minus sign for right.
local function leanRotation(degrees: number, sideDegrees: number): CFrame
	return CFrame.Angles(math.rad(degrees), 0, -math.rad(sideDegrees))
end

-- A turn about the vertical axis. Positive `degrees` = to the player's right, which is a
-- NEGATIVE rotation about +Y (Roblox turns left for positive angles).
local function yawRotation(degrees: number): CFrame
	return CFrame.Angles(0, -math.rad(degrees), 0)
end

-- True if the angles are all too small to bother rotating a joint for.
local function isNeutral(a: number, b: number, c: number?): boolean
	return math.abs(a) < 0.01 and math.abs(b) < 0.01 and (c == nil or math.abs(c) < 0.01)
end

-- Finds the piece to rotate for one R15 joint: newer avatars join the body with an
-- AnimationConstraint (we rotate its Attachment0, the parent side); older ones with a
-- Motor6D (we rotate its C0). nil on R6 or while the body isn't loaded yet.
local function findJointPiece(character: Model, partName: string, jointName: string): Instance?
	local part = character:FindFirstChild(partName)
	local joint = part and part:FindFirstChild(jointName)
	if joint and joint:IsA("Motor6D") then
		return joint
	elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 then
		return joint.Attachment0
	end
	return nil
end

local function readPose(piece: Instance): CFrame
	if piece:IsA("Motor6D") then
		return piece.C0
	end
	return (piece :: Attachment).CFrame
end

local function writePose(piece: Instance, pivotPose: CFrame)
	if piece:IsA("Motor6D") then
		piece.C0 = pivotPose
	else
		(piece :: Attachment).CFrame = pivotPose
	end
end

-- Rotates one joint by `rotation` around its pivot (its rest pose * rotation). When
-- `neutral` it puts the rest pose back once and then leaves the joint alone so Roblox can
-- change it (e.g. when the avatar is rescaled). Returns the joint's rest pose.
local function poseJoint(piece: Instance, rotation: CFrame, neutral: boolean): CFrame
	local rest = restPoses[piece]
	if neutral then
		if rest then
			writePose(piece, rest)
			restPoses[piece] = nil
		end
		return readPose(piece)
	end
	if not rest then
		rest = readPose(piece)
		restPoses[piece] = rest
	end
	writePose(piece, (rest :: CFrame) * rotation)
	return rest :: CFrame
end

-- The other end of the Root joint (where the LowerTorso attaches to it): Motor6D.C1, or the
-- AnimationConstraint's Attachment1 frame.
local function rootChildFrame(character: Model): CFrame?
	local lowerTorso = character:FindFirstChild("LowerTorso")
	local joint = lowerTorso and lowerTorso:FindFirstChild("Root")
	if joint and joint:IsA("Motor6D") then
		return joint.C1
	elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment1 then
		return joint.Attachment1.CFrame
	end
	return nil
end

-- Poses the three spine joints from the current pose: Root (pelvis), Waist (chest) and
-- Neck. Each one is rotated around its own pivot, so the angles add up down the spine.
local function applyPosture(character: Model)
	local p = computePose()

	local rootPiece = findJointPiece(character, "LowerTorso", "Root")
	if rootPiece then
		hipPivot =
			poseJoint(rootPiece, leanRotation(p.pelvisPitch, p.pelvisRoll), isNeutral(p.pelvisPitch, p.pelvisRoll))
	end

	local waistPiece = findJointPiece(character, "UpperTorso", "Waist")
	if waistPiece then
		local waistRest = poseJoint(
			waistPiece,
			leanRotation(p.chestPitch, p.chestRoll) * yawRotation(p.chestYaw),
			isNeutral(p.chestPitch, p.chestRoll, p.chestYaw)
		)
		-- The waist's pivot in HumanoidRootPart space (for getChestCFrame): root joint frame,
		-- back through the LowerTorso's attachment, out to the waist joint.
		local childFrame = rootChildFrame(character)
		if rootPiece and childFrame then
			chestPivot = hipPivot * childFrame:Inverse() * waistRest
		end
	end

	local neckPiece = findJointPiece(character, "Head", "Neck")
	if neckPiece then
		-- Turn about the chest's vertical axis first, then tilt (the nod happens in the turned head).
		poseJoint(
			neckPiece,
			yawRotation(p.neckYaw) * leanRotation(p.neckPitch, p.neckRoll),
			isNeutral(p.neckPitch, p.neckRoll, p.neckYaw)
		)
	end
end

-- Starts leaning the body to `degrees` (positive = back, negative = forward, 0 = upright)
-- and `sideDegrees` sideways (positive = toward the player's right, negative = left, nil = 0),
-- easing in over `duration` seconds from wherever it is now, at the speed it has now (so
-- reversing a lean in mid-motion bends smoothly instead of restarting from a standstill).
function PostureController.leanTo(degrees: number, duration: number, sideDegrees: number?)
	retarget(leanTrack, degrees, duration)
	retarget(sideTrack, sideDegrees or 0, duration)
end

-- Where the hips are: `rootCFrame` (the HumanoidRootPart, always upright) tilted by the
-- PELVIS share of the current lean around the hips. Controllers measure the ball path, hand
-- and foot positions from this instead of the root, so they tilt with the body (a little
-- less than the chest does: a fadeaway keeps the arm's world angle).
function PostureController.getBodyCFrame(rootCFrame: CFrame): CFrame
	local p = computePose()
	if isNeutral(p.pelvisPitch, p.pelvisRoll) then
		return rootCFrame
	end
	return rootCFrame * hipPivot * leanRotation(p.pelvisPitch, p.pelvisRoll) * hipPivot:Inverse()
end

-- Where the chest is: the hips frame above, further tilted at the waist by the chest share
-- of the lean (plus any dribble twist). Same use as getBodyCFrame, for things attached to
-- the upper body.
function PostureController.getChestCFrame(rootCFrame: CFrame): CFrame
	local p = computePose()
	local hips = PostureController.getBodyCFrame(rootCFrame)
	if isNeutral(p.chestPitch, p.chestRoll, p.chestYaw) then
		return hips
	end
	return hips * chestPivot * leanRotation(p.chestPitch, p.chestRoll) * yawRotation(p.chestYaw) * chestPivot:Inverse()
end

-- Sets the stance lean the body eases toward, degrees (negative = forward). LegController
-- calls it every frame with the dribbling stance's lean (Config/Footwork.luau).
function PostureController.setStanceLean(degrees: number)
	stanceGoal = degrees
end

-- Extra FORWARD hinge of the trunk, degrees (positive = more forward), layered on top of
-- everything else. LegController sets it every frame during the shot's dip (and 0 otherwise):
-- the chest goes forward as the knees bend, instead of straightening up first.
function PostureController.setDipHinge(degrees: number)
	dipHingeGoal = degrees
end

-- A quick forward dip of the trunk on touchdown, `strength` 0-1 (LANDING_HINGE degrees at 1),
-- recovering over LANDING_RECOVER_TIME. LegController calls it on every landing from a jump.
function PostureController.absorbLanding(strength: number)
	landingStrength = math.clamp(strength, 0, 1)
	landingStartedAt = os.clock()
end

-- Turns the head `yawDegrees` away from the chest (positive = to the player's right,
-- clamped to +-HEAD_TURN_MAX), easing there over `duration` seconds. Call again with 0 to
-- bring it back. Used for the spin's head lead and the crossover's head fake.
function PostureController.setHeadTurn(yawDegrees: number, duration: number)
	local limit = Posture.HEAD_TURN_MAX
	retarget(headTurnTrack, math.clamp(yawDegrees, -limit, limit), duration)
end

-- A small twist of the upper body in time with the dribbling arm: `yawDegrees` (positive =
-- turn to the player's right) and `rollDegrees` (positive = tilt to the right). Applied to
-- the chest only, smoothed, and clamped (TWIST_MAX_YAW / TWIST_MAX_ROLL). BallController
-- calls it every frame while dribbling and with 0, 0 otherwise.
function PostureController.setDribbleTwist(yawDegrees: number, rollDegrees: number)
	twistYawGoal = math.clamp(yawDegrees, -Posture.TWIST_MAX_YAW, Posture.TWIST_MAX_YAW)
	twistRollGoal = math.clamp(rollDegrees, -Posture.TWIST_MAX_ROLL, Posture.TWIST_MAX_ROLL)
end

-- Sets how strongly the head looks at the rim during the current shot: 0 = not at all,
-- 1 = eyes locked on it, nil = back to Motion.HEAD_LOOK_WEIGHT. Lowering it mid-shot
-- eases the head back (HEAD_DROP_SHARPNESS); the look is also turned down automatically
-- when the rim is steeply above the head (HEAD_MAX_LOOK_PITCH).
function PostureController.setHeadLook(weight: number?)
	headLookWeight = weight
end

-- Turns the shooting posture on (shot started) or off (landed / cancelled).
function PostureController.setShooting(active: boolean)
	shooting = active
	if active then
		-- Safety: a dribble move's head lead (spin, crossover) mustn't stay on into the shot.
		retarget(headTurnTrack, 0, 0.15)
	else
		unmuteAll()
		dipHingeGoal = 0 -- safety: never leave the dip hinge on after a shot ends
	end
end

-- How much the head look is turned down because the rim is steeply above the head, 0-1:
-- 1 up to HEAD_MAX_LOOK_PITCH degrees of elevation, then fading to 0 over HEAD_PITCH_FALLOFF.
local function steepRimScale(head: BasePart): number
	local toRim = Court.RIM_POSITION - head.Position
	local flat = math.sqrt(toRim.X * toRim.X + toRim.Z * toRim.Z)
	local elevation = math.deg(math.atan2(toRim.Y, math.max(flat, 0.01)))
	return 1 - math.clamp((elevation - Posture.HEAD_MAX_LOOK_PITCH) / math.max(Posture.HEAD_PITCH_FALLOFF, 0.01), 0, 1)
end

-- Runs every frame.
local function update(dt: number)
	local parts = CharacterRef.get()
	if not parts then
		return
	end

	-- Ease the lean values forward and pose the spine and neck.
	advance()
	applyPosture(parts.character)

	-- Upright torso, every frame while shooting: stop/mute any leaning animation that's
	-- playing (including ones that started before the shot did).
	if shooting then
		local animator = parts.humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				suppressIfLeaning(track)
			end
		end
	end

	-- Eyes on the rim: blend the head IK in while shooting, out (slowly) afterwards.
	local ik = ensureHead(parts.humanoid, parts.character)
	if ik then
		local goal = 0
		if shooting then
			goal = headLookWeight or Motion.HEAD_LOOK_WEIGHT
			local head = parts.character:FindFirstChild("Head")
			if head and head:IsA("BasePart") then
				goal *= steepRimScale(head) -- don't crank the neck back at a rim right overhead
			end
		end
		-- Blend in at HEAD_LOOK_SHARPNESS. A drop during the shot (the dunk's slam) eases
		-- down at HEAD_DROP_SHARPNESS, so the head doesn't snap; after the shot the head
		-- relaxes slowly (IK_RELAX_SHARPNESS).
		local sharpness = Posture.HEAD_LOOK_SHARPNESS
		if goal < ik.Weight then
			sharpness = if shooting then Posture.HEAD_DROP_SHARPNESS else Motion.IK_RELAX_SHARPNESS
		end
		ik.Weight += (goal - ik.Weight) * MovementMath.smoothingAlpha(sharpness, dt)
	end
end

function PostureController.start()
	CharacterRef.onSpawn(function(parts)
		shooting = false
		headLookWeight = nil
		table.clear(mutedTracks)
		table.clear(restPoses)
		leanTrack, sideTrack, headTurnTrack = newTrack(), newTrack(), newTrack()
		stanceLean, stanceSpeed, stanceGoal = 0, 0, 0
		dipHinge, dipHingeGoal = 0, 0
		landingStrength = 0
		twistYaw, twistRoll, twistYawGoal, twistRollGoal = 0, 0, 0, 0
		shootLevel = 0
		lastAdvance = os.clock()
		destroyHead()
		nextRetryAt = 0
		-- Upright torso, main check: stop a leaning animation the instant it starts, so it
		-- never gets a single frame to bend the body.
		local animator = parts.humanoid:WaitForChild("Animator", 10)
		if animator and animator:IsA("Animator") then
			animator.AnimationPlayed:Connect(suppressIfLeaning)
		end
	end)
	RunService:BindToRenderStep("RoHoopsPosture", Enum.RenderPriority.Character.Value + 3, update)
end

return PostureController
