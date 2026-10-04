--!strict
-- POSTURE CONTROLLER
-- Keeps the shooter's body square and eyes on the rim during a shot:
--   * Upright torso – Roblox's default animations bend the body forward: jump and fall
--     lean the torso ~28° and drop the head ~40°, and run leans it ~18°. A shooter stays
--     tall, so while shooting we stop jump/fall and turn walk/run down to nothing (they're
--     restored afterwards). Nothing else is lost: the arms and legs are already driven by
--     ArmController and LegController.
--   * Eyes on the rim – a head IK (IKControl, "LookAt") turns the head to face the rim.
-- ShotController switches it on when a shot starts and off when the player lands.
--
-- Only works for R15 characters (the default); R6 characters just skip the head part.
-- Tuning values: src/shared/Config/Motion.luau (HEAD_LOOK_WEIGHT, IK blend speeds).

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
