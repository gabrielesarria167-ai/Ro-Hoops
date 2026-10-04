--!strict
-- POSTURE CONTROLLER
-- Keeps the shooter's body square and eyes on the rim during a shot:
--   * Upright torso – Roblox's default animations bend the body forward: jump and fall
--     lean the torso ~28° and drop the head ~40°, and run leans it ~18°. A shooter stays
--     tall, so while shooting we stop jump/fall and turn walk/run down to nothing (they're
--     restored afterwards). Nothing else is lost: the arms and legs are already driven by
--     ArmController and LegController.
--   * Eyes on the rim – a head IK (IKControl, "LookAt") turns the head to face the rim.
--   * Body lean – tilts the whole body back (a fadeaway) or forward (a layup) around the
--     hips, by rotating the root joint that connects the body to the HumanoidRootPart.
--     The HumanoidRootPart itself stays upright, so physics and movement are unaffected.
--     getBodyCFrame() gives the other controllers the leaned body's position, so the
--     ball, hands and legs tilt with it.
-- ShotController switches shooting on when a shot starts and off when the player lands,
-- and sets the lean with leanTo().
--
-- Only works for R15 characters (the default); R6 characters skip the head and the lean.
-- Tuning values: src/shared/Config/Motion.luau (HEAD_LOOK_WEIGHT, LEAN_RECOVER_TIME, IK
-- blend speeds) and src/shared/Config/Shooting.luau (each shot type's LEAN).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Court = require(ReplicatedStorage.Shared.Config.Court)
local Motion = require(ReplicatedStorage.Shared.Config.Motion)
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
local headIK: IKControl? = nil -- turns the head toward `rimTarget`
local rimTarget: Attachment? = nil -- a point at the centre of the rim
local nextRetryAt = 0 -- clock time of the next setup retry

-- Body lean, in degrees (positive = back, negative = forward; the sideways lean is below). It eases from `leanFrom`
-- to `leanGoal` over `leanDuration` seconds starting at `leanStartedAt`; the current
-- value is worked out from the clock (currentLean), so every controller that asks during
-- a frame gets the same angle.
local leanFrom = 0
local leanGoal = 0
-- Sideways lean, in degrees (positive = toward the player's right, negative = left). It
-- eases on the same clock as the back/forward lean, from `sideFrom` to `sideGoal`.
local sideFrom = 0
local sideGoal = 0
local leanStartedAt = 0
local leanDuration = 0
-- The root joint's rest pose: its pivot point at the hips, in HumanoidRootPart space. The
-- lean rotates around it. Read from the character (see applyLean); this default is close.
local hipPivot = CFrame.new(0, -1, 0)
-- Rest pose of each root joint piece we've rotated (a Motor6D's C0, or an Attachment's
-- CFrame), so it can be put back exactly when the lean is over.
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

-- How far the body is leaning right now, degrees (positive = back).
local function currentLean(): number
	local progress = if leanDuration > 0 then (os.clock() - leanStartedAt) / leanDuration else 1
	return leanFrom + (leanGoal - leanFrom) * ease(progress)
end

-- How far the body is leaning sideways right now, degrees (positive = toward the right).
local function currentSideLean(): number
	local progress = if leanDuration > 0 then (os.clock() - leanStartedAt) / leanDuration else 1
	return sideFrom + (sideGoal - sideFrom) * ease(progress)
end

-- The rotation for a lean of `degrees` back (negative = forward) plus `sideDegrees` toward
-- the player's right. Roblox's "forward" is -Z, so turning around the X (right) axis by a
-- positive angle tips the top of the body back toward +Z; turning around the Z (forward)
-- axis by a positive angle tips the top toward -X (left), hence the minus sign for right.
local function leanRotation(degrees: number, sideDegrees: number): CFrame
	return CFrame.Angles(math.rad(degrees), 0, -math.rad(sideDegrees))
end

-- Tilts the body on screen by rotating the root joint (HumanoidRootPart → LowerTorso)
-- around its pivot at the hips. Newer avatars join the body with an AnimationConstraint
-- (rotate its HumanoidRootPart attachment); older ones with a Motor6D (rotate its C0).
local function applyLean(character: Model)
	local lowerTorso = character:FindFirstChild("LowerTorso")
	local joint = lowerTorso and lowerTorso:FindFirstChild("Root")
	-- The piece we rotate, and how to read/write its rest pose.
	local piece: Instance?, getPose: (() -> CFrame)?, setPose: ((CFrame) -> ())? = nil, nil, nil
	if joint and joint:IsA("Motor6D") then
		piece = joint
		getPose = function()
			return joint.C0
		end
		setPose = function(pose)
			joint.C0 = pose
		end
	elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 then
		local attachment = joint.Attachment0 :: Attachment
		piece = attachment
		getPose = function()
			return attachment.CFrame
		end
		setPose = function(pose)
			attachment.CFrame = pose
		end
	end
	if not piece or not getPose or not setPose then
		return -- R6, or the body isn't loaded yet
	end

	local degrees = currentLean()
	local sideDegrees = currentSideLean()
	local rest = restPoses[piece]
	if math.abs(degrees) < 0.01 and math.abs(sideDegrees) < 0.01 then
		-- Upright: put the rest pose back once, then leave the joint alone so Roblox can
		-- change it (e.g. when the avatar is rescaled).
		if rest then
			setPose(rest)
			restPoses[piece] = nil
		end
		hipPivot = getPose()
		return
	end
	if not rest then
		rest = getPose()
		restPoses[piece] = rest
	end
	hipPivot = rest :: CFrame
	setPose((rest :: CFrame) * leanRotation(degrees, sideDegrees))
end

-- Starts leaning the body to `degrees` (positive = back, negative = forward, 0 = upright)
-- and `sideDegrees` sideways (positive = toward the player's right, negative = left, nil = 0),
-- easing in over `duration` seconds from wherever it is now.
function PostureController.leanTo(degrees: number, duration: number, sideDegrees: number?)
	leanFrom = currentLean()
	sideFrom = currentSideLean()
	leanGoal = degrees
	sideGoal = sideDegrees or 0
	leanStartedAt = os.clock()
	leanDuration = math.max(duration, 0)
end

-- Where the (leaned) body is: `rootCFrame` (the HumanoidRootPart, always upright) tilted
-- by the current lean around the hips. Controllers measure the ball path, hand and foot
-- positions from this instead of the root, so they tilt with the body.
function PostureController.getBodyCFrame(rootCFrame: CFrame): CFrame
	local degrees = currentLean()
	local sideDegrees = currentSideLean()
	if math.abs(degrees) < 0.01 and math.abs(sideDegrees) < 0.01 then
		return rootCFrame
	end
	return rootCFrame * hipPivot * leanRotation(degrees, sideDegrees) * hipPivot:Inverse()
end

-- Turns the shooting posture on (shot started) or off (landed / cancelled).
function PostureController.setShooting(active: boolean)
	shooting = active
	if not active then
		unmuteAll()
	end
end

-- Runs every frame.
local function update(dt: number)
	local parts = CharacterRef.get()
	if not parts then
		return
	end

	applyLean(parts.character)

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
		local goal = if shooting then Motion.HEAD_LOOK_WEIGHT else 0
		local sharpness = if goal < ik.Weight then Motion.IK_RELAX_SHARPNESS else Motion.IK_BLEND_SHARPNESS
		ik.Weight += (goal - ik.Weight) * MovementMath.smoothingAlpha(sharpness, dt)
	end
end

function PostureController.start()
	CharacterRef.onSpawn(function(parts)
		shooting = false
		table.clear(mutedTracks)
		table.clear(restPoses)
		leanFrom, leanGoal, leanDuration = 0, 0, 0
		sideFrom, sideGoal = 0, 0
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
