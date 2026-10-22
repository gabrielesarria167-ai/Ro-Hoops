--!strict
-- ARM CONTROLLER
-- Makes the hands handle the ball instead of the ball floating next to the body, using
-- arm IK (see src/client/LimbIK.luau): each frame we say where each palm goes, which way
-- it faces and where the fingers point, and the arm bends (and the wrist turns) to match,
-- on top of the normal animations.
--
-- SMOOTH HANDS. Whenever a hand is NOT touching the ball, its target (position, facing,
-- fingers and elbow) goes through a critically damped spring (Motion.HAND_SPRING_FREQUENCY),
-- measured relative to the body so it doesn't lag when the player runs. So the hands glide
-- between poses (arm bar ↔ catch spot, release → follow-through, dribble → shot hold)
-- instead of popping. A hand taking hold of the ball fades from the spring onto the ball
-- (placeHand below), and once on the ball it follows it exactly, with no lag.
--
--   Dribble – the dribbling hand (right or left) meets the ball on its way UP, rides it,
--             pushes it down with a wrist snap, then hovers where it will meet it again
--             (BallController says which part of the bounce it is: Handling.contact /
--             hover / push). The arm never stretches past straight (SkillMath.softReach).
--             In a dribble move (H switch or crossover) the other hand waits where it will
--             catch the ball, and the hand that let go relaxes. In the wide crossover the
--             palm holds the ball's outer side instead of its top. The free hand holds up
--             an arm bar to protect the ball (Motion.ARM_BAR_...: upper arm ~45° out,
--             elbow ~90°, forearm across the front), gently swaying and bobbing with the
--             dribble; when running it swings opposite the legs, in step with the footfalls.
--   Held    – shooting hand behind the ball in the dip, sliding under it as it rises to the
--             release point above the head; guide hand on the side the whole way.
--   Flight  – the shooting arm stays up toward the rim with the wrist flexed ~40° (the
--             follow-through), held ~0.6 s, then falls forward and relaxes back to normal
--             animation; the guide hand peels off sideways.
--   Layups use their own hand spots: the shooting palm scoops under the ball (palm up,
--   fingers forward) as it is carried up the right side so the ball rolls off the fingertips,
--   and the guide hand comes off the ball at head height into a bent arm bar. On a layup
--   follow-through the right arm stays up, wrist flicked.
--   Dunks are two-handed: both palms on the ball (mirrored), from its sides to behind it
--   overhead and out over the rim, reaching the overhead pose together with the ball; after
--   the slam both hands come down on the front of the rim for a moment, then fall.
-- Hand poses are measured from the leaned body (PostureController.getBodyCFrame, the hips
-- with the pelvis share of the lean; the arm bar uses getChestCFrame), so on a fadeaway the
-- arms tilt back with the body.
--
-- Only works for R15 characters (the default); R6 characters just skip it.
-- Tuning values: src/shared/Config/Motion.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ball = require(ReplicatedStorage.Shared.Config.Ball)
local Court = require(ReplicatedStorage.Shared.Config.Court)
local Motion = require(ReplicatedStorage.Shared.Config.Motion)
local Skills = require(ReplicatedStorage.Shared.Config.Skills)
local MovementMath = require(ReplicatedStorage.Shared.MovementMath)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local LimbIK = require(script.Parent.Parent.LimbIK)
local BallController = require(script.Parent.BallController)
local MovementController = require(script.Parent.MovementController)
local PostureController = require(script.Parent.PostureController)

local ArmController = {}

-- Where the hands hold the rim after a dunk, worked out once per slam (see update).
type RimGrip = {
	launchedAt: number, -- BallController.getLaunchTime() of the slam this belongs to
	right: Vector3, -- world spots on top of the front of the rim
	left: Vector3,
	fingers: Vector3, -- world direction the fingers point (over the rim's front edge)
	rightLetGo: Vector3?, -- each hand's spot relative to the body when it let go (object space)
	leftLetGo: Vector3?,
	rightFrom: Vector3?, -- each hand's spot on the ball at the slam, relative to the body
	leftFrom: Vector3?,
}
local rimGrip: RimGrip? = nil
-- Where each palm was on the ball last frame while holding a dunk, relative to the body
-- (object space): the hands move from there onto the rim after the slam.
local dunkPalmRight: Vector3? = nil
local dunkPalmLeft: Vector3? = nil

-- The current character's arms, or nil if they aren't set up (yet).
local rightArm: LimbIK.Limb? = nil -- shooting / dribbling hand
local leftArm: LimbIK.Limb? = nil -- guide hand

-- One hand's smoothing state (see placeSmoothed). Vectors are relative to the hips, so
-- they stay put while the player runs.
type HandState = {
	valid: boolean, -- false until the hand has been placed once (and again after it relaxes)
	used: boolean, -- true if the hand was placed this frame
	palm: Vector3, -- where the palm is, and how fast it is moving
	palmVelocity: Vector3,
	facing: Vector3, -- which way the palm faces
	facingVelocity: Vector3,
	fingers: Vector3, -- which way the fingers point
	fingersVelocity: Vector3,
	pole: Vector3, -- the elbow aim point
	poleVelocity: Vector3,
	contact: number, -- 0-1: how far the hand has faded from the spring onto the ball
	grabTime: number, -- seconds the current fade onto the ball takes
	wasOnBall: boolean, -- true if the hand was on the ball last frame
}
local function newHandState(): HandState
	return {
		valid = false,
		used = false,
		palm = Vector3.zero,
		palmVelocity = Vector3.zero,
		facing = Vector3.zAxis,
		facingVelocity = Vector3.zero,
		fingers = Vector3.yAxis,
		fingersVelocity = Vector3.zero,
		pole = Vector3.zero,
		poleVelocity = Vector3.zero,
		contact = 0,
		grabTime = 0.1,
		wasOnBall = false,
	}
end
local rightState = newHandState()
local leftState = newHandState()

-- How often (seconds) to retry setting up arms that couldn't be found, e.g. while the
-- avatar is still loading or on an R6 character that will never have them.
local RETRY_INTERVAL = 0.5
local nextRetryAt = 0 -- clock time of the next retry

-- Converts a Motion-config offset (right, up, forward) to Roblox's object space, where
-- forward is -Z.
local function toObjectSpace(offset: Vector3): Vector3
	return Vector3.new(offset.X, offset.Y, -offset.Z)
end

-- A Motion-config right-hand spot or direction mirrored for the left hand.
local function mirrored(offset: Vector3): Vector3
	return Vector3.new(-offset.X, offset.Y, offset.Z)
end

-- A point given relative to the hips (and turning/leaning with the player), in world space.
local function fromHips(bodyCFrame: CFrame, offset: Vector3): Vector3
	return bodyCFrame:PointToWorldSpace(toObjectSpace(offset))
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

-- A critically damped spring on a Vector3 (SkillMath.springStep on each axis). Returns the
-- new value and velocity.
local function springVector(
	value: Vector3,
	velocity: Vector3,
	target: Vector3,
	omega: number,
	dt: number
): (Vector3, Vector3)
	local x, vx = SkillMath.springStep(value.X, velocity.X, target.X, omega, dt)
	local y, vy = SkillMath.springStep(value.Y, velocity.Y, target.Y, omega, dt)
	local z, vz = SkillMath.springStep(value.Z, velocity.Z, target.Z, omega, dt)
	return Vector3.new(x, y, z), Vector3.new(vx, vy, vz)
end

-- Puts one hand where it should be this frame, smoothly. `palm`, `facing`, `fingers` and
-- `pole` (the elbow aim point) are the wanted pose in the world. `onBall` says the palm is
-- (or is taking hold of) the ball or the rim: then the hand fades from the spring onto the
-- target and follows it exactly; otherwise it eases toward it with the spring. All the
-- smoothing is done relative to `frame` (the hips), so a running player's hands don't lag.
local function placeSmoothed(
	arm: LimbIK.Limb,
	state: HandState,
	frame: CFrame,
	dt: number,
	palm: Vector3,
	facing: Vector3,
	fingers: Vector3,
	pole: Vector3,
	onBall: boolean
)
	state.used = true
	local goalPalm = frame:PointToObjectSpace(palm)
	local goalFacing = frame:VectorToObjectSpace(facing.Unit)
	local goalFingers = frame:VectorToObjectSpace(fingers.Unit)
	local goalPole = frame:PointToObjectSpace(pole)

	if not state.valid then
		-- First frame (or the arm was relaxed): start right on the target.
		state.valid = true
		state.palm, state.facing, state.fingers, state.pole = goalPalm, goalFacing, goalFingers, goalPole
		state.palmVelocity, state.facingVelocity = Vector3.zero, Vector3.zero
		state.fingersVelocity, state.poleVelocity = Vector3.zero, Vector3.zero
		state.contact = if onBall then 1 else 0
	else
		local omega = Motion.HAND_SPRING_FREQUENCY
		local palmNow, palmVelocity = springVector(state.palm, state.palmVelocity, goalPalm, omega, dt)
		local facingNow, facingVelocity = springVector(state.facing, state.facingVelocity, goalFacing, omega, dt)
		local fingersNow, fingersVelocity = springVector(state.fingers, state.fingersVelocity, goalFingers, omega, dt)
		if onBall then
			if not state.wasOnBall then
				-- Taking hold: fade in over a time that grows with how far the hand has to go.
				local gap = (state.palm - goalPalm).Magnitude
				state.grabTime = math.max(Motion.HAND_CONTACT_BLEND, gap / math.max(Motion.HAND_GRAB_SPEED, 0.1))
				state.contact = 0
			end
			state.contact = math.min(1, state.contact + dt / state.grabTime)
		else
			state.contact = 0
		end
		local weight = ease(state.contact)
		if weight >= 1 then
			-- On the ball: exactly on it. Keep its speed for the moment the hand lets go.
			local speed = (goalPalm - state.palm) / math.max(dt, 1e-3)
			state.palmVelocity = if speed.Magnitude > 40 then speed.Unit * 40 else speed
			state.palm, state.facing, state.fingers = goalPalm, goalFacing, goalFingers
			state.facingVelocity, state.fingersVelocity = Vector3.zero, Vector3.zero
		else
			state.palm = palmNow:Lerp(goalPalm, weight)
			state.palmVelocity = palmVelocity
			state.facing = facingNow:Lerp(goalFacing, weight)
			state.facingVelocity = facingVelocity
			state.fingers = fingersNow:Lerp(goalFingers, weight)
			state.fingersVelocity = fingersVelocity
		end
		-- The elbow is always smoothed (softer than the hand).
		state.pole, state.poleVelocity =
			springVector(state.pole, state.poleVelocity, goalPole, Motion.HAND_POLE_FREQUENCY, dt)
	end
	state.wasOnBall = onBall

	local worldFacing = frame:VectorToWorldSpace(state.facing)
	if worldFacing.Magnitude < 0.1 then
		worldFacing = facing -- the spring passed through "no direction": use the target
	end
	LimbIK.placeHand(arm, frame:PointToWorldSpace(state.palm), worldFacing, frame:VectorToWorldSpace(state.fingers))
	arm.pole.WorldPosition = frame:PointToWorldSpace(state.pole)
end

-- Where `arm`'s shoulder joint is (world), or nil if the avatar doesn't have the attachment.
local function shoulderPosition(arm: LimbIK.Limb, side: string): Vector3?
	local upperArm = arm.ik.ChainRoot
	local attachment = if upperArm then upperArm:FindFirstChild(side .. "ShoulderRigAttachment") else nil
	if attachment and attachment:IsA("Attachment") then
		return attachment.WorldPosition
	end
	return nil
end

-- Runs every frame after the ball has been positioned.
local function update(dt: number)
	local parts = CharacterRef.get()
	if not parts or not ensureArms(parts.humanoid, parts.character) then
		return
	end
	local right, left = rightArm :: LimbIK.Limb, leftArm :: LimbIK.Limb
	dt = math.min(dt, 0.1) -- a long hitch shouldn't fling the springs

	local rootCFrame = parts.root.CFrame -- the hips, always upright (for the dribble)
	local bodyCFrame = PostureController.getBodyCFrame(rootCFrame) -- the hips, leaned with the body
	local chestCFrame = PostureController.getChestCFrame(rootCFrame) -- the chest (arm bar)
	-- Turns a Motion-config direction (right, up, forward) into a world direction.
	local function bodyDirection(offset: Vector3): Vector3
		return bodyCFrame:VectorToWorldSpace(toObjectSpace(offset))
	end
	-- Puts a hand somewhere this frame (smoothed, see placeSmoothed).
	local function place(
		arm: LimbIK.Limb,
		palm: Vector3,
		facing: Vector3,
		fingers: Vector3,
		pole: Vector3,
		onBall: boolean
	)
		placeSmoothed(
			arm,
			if arm == right then rightState else leftState,
			rootCFrame,
			dt,
			palm,
			facing,
			fingers,
			pole,
			onBall
		)
	end
	-- Puts `arm`'s palm on the ball at `direction` (from the ball's centre, world space),
	-- facing the centre, fingers pointing `fingers`.
	local function palmOnBall(
		arm: LimbIK.Limb,
		ballPosition: Vector3,
		direction: Vector3,
		fingers: Vector3,
		pole: Vector3
	)
		local dir = direction.Unit
		place(arm, ballPosition + dir * (Ball.RADIUS + Motion.PALM_GAP), -dir, fingers, pole, true)
	end

	local ballPosition = BallController.getPosition()
	local mode = BallController.getMode()
	local style = BallController.getStyle()
	local layup = style == "Layup"
	local dunk = style == "Dunk"
	local sinceRelease = os.clock() - BallController.getLaunchTime()
	local rightGoal, leftGoal = 0, 0 -- how much each arm should follow its target this frame

	if mode == "Dribble" then
		local handling = BallController.getHandling()
		-- How much the player is running forward: the free arm swings instead of holding the bar.
		local forwardSpeed = MovementController.getVelocity():Dot(rootCFrame.LookVector)
		local runShare = ease(
			(forwardSpeed - Motion.RUN_ARM_SPEED_START)
				/ math.max(Motion.RUN_ARM_SPEED_FULL - Motion.RUN_ARM_SPEED_START, 0.1)
		)

		-- Puts `side`'s palm on a ball at `at` (or, if it isn't in contact, where the ball will be
		-- when the hand meets it). `grip` says where on the ball:
		--   0 = on top, facing down (a dribble);
		--   1 = on the ball's upper outer side (Skills.WIDE_GRIP), for pulling it wide and
		--       whipping it across in the crossover; negative = the upper inner side.
		-- In between blends. `push` (0-1) snaps the wrist at the end of the push. The left hand
		-- mirrors the right (elbow out to the left). The arm never stretches past straight.
		local function handOnBall(side: SkillMath.Hand, at: Vector3, grip: number, contact: boolean, push: number)
			local arm = if side == "Right" then right else left
			local sideSign = if side == "Right" then 1 else -1
			local wide = Skills.WIDE_GRIP
			local spot = Vector3.new(0, 1, 0):Lerp(Vector3.new(wide.X * sideSign, wide.Y, wide.Z), grip)
			local direction = rootCFrame:VectorToWorldSpace(toObjectSpace(spot)).Unit
			local palm = at + direction * (Ball.RADIUS + Motion.PALM_GAP)
			local shoulder = shoulderPosition(arm, side)
			if shoulder then
				local reach = palm - shoulder
				local distance = reach.Magnitude
				if distance > 1e-3 then
					palm = shoulder
						+ reach.Unit
							* SkillMath.softReach(distance, Motion.DRIBBLE_MAX_REACH, Motion.DRIBBLE_SOFT_REACH)
				end
			end
			-- The wrist snaps at the push: the fingers pitch down about the body's right axis.
			local fingers = rootCFrame:VectorToWorldSpace(toObjectSpace(Motion.DRIBBLE_FINGERS))
			local flex = CFrame.fromAxisAngle(rootCFrame.RightVector, -math.rad(Motion.DRIBBLE_WRIST_FLEX) * push)
			local elbow = Motion.DRIBBLE_ELBOW
			place(
				arm,
				palm,
				-direction,
				flex:VectorToWorldSpace(fingers),
				fromHips(rootCFrame, Vector3.new(elbow.X * sideSign, elbow.Y, elbow.Z)),
				contact
			)
			if side == "Right" then
				rightGoal = 1
			else
				leftGoal = 1
			end
		end

		-- The hand on the ball follows it while in contact and otherwise hovers where it will
		-- meet it; in a hand move the other hand is already waiting where it will catch the
		-- ball, and the ball arrives into it. While the ball bounces between hands, the hand
		-- that let go relaxes back to the normal animation.
		if handling.holder then
			local at = if handling.contact then ballPosition else (handling.hover or ballPosition)
			handOnBall(handling.holder, at, handling.grip, handling.contact, handling.push)
		end
		if handling.waiting and handling.waitPoint then
			handOnBall(handling.waiting, handling.waitPoint, handling.grip, false, 0)
		end

		-- Arm bar: the hand that is neither holding the ball nor waiting for it comes up in
		-- front of the body, on its own side, to protect the ball. (If neither hand is busy,
		-- the ball is loose between them and both stay as they are.)
		local busy = { [handling.holder or ""] = true, [handling.waiting or ""] = true }
		local free: SkillMath.Hand? = if not busy.Left and busy.Right
			then "Left"
			elseif not busy.Right and busy.Left then "Right"
			else nil
		if free then
			local arm = if free == "Right" then right else left
			-- The config's "out" points to the free hand's own side: right for the right hand.
			local sideSign = if free == "Right" then 1 else -1
			local function onFreeSide(v: Vector3): Vector3
				return Vector3.new(v.X * sideSign, v.Y, v.Z)
			end
			-- Alive, not frozen: a slow sway, and a small drop with every push of the dribble.
			local sway = Motion.ARM_BAR_SWAY
				* math.sin(os.clock() * 2 * math.pi * Motion.ARM_BAR_SWAY_RATE + (if free == "Right" then 0 else 1.7))
			local bob = -Motion.ARM_BAR_BOB * handling.push
			local palm = onFreeSide(Motion.ARM_BAR_PALM) + Vector3.new(0, sway + bob, 0)
			local facing = onFreeSide(Motion.ARM_BAR_FACING)
			local fingers = Motion.ARM_BAR_FINGERS
			local elbow = onFreeSide(Motion.ARM_BAR_ELBOW)
			if runShare > 0.001 then
				-- Running: swing opposite the legs. The foot on the other side planting means
				-- this arm is at the front of its swing, and it comes back by the next plant.
				local plantedSide, since, period = BallController.getFootfall()
				local step = period or Motion.RUN_ARM_FALLBACK_STEP
				local forwardAmount: number -- -1 = back, +1 = forward
				if plantedSide then
					forwardAmount = (if plantedSide ~= free then 1 else -1)
						* math.cos(math.pi * math.min(since / step, 1.5))
				else
					forwardAmount = math.sin(os.clock() * math.pi / step + (if free == "Right" then 0 else math.pi))
				end
				local swing =
					onFreeSide(Motion.RUN_ARM_BACK):Lerp(onFreeSide(Motion.RUN_ARM_FORWARD), (forwardAmount + 1) / 2)
				palm = palm:Lerp(swing, runShare)
				facing = facing:Lerp(onFreeSide(Motion.RUN_ARM_FACING), runShare)
				fingers = fingers:Lerp(Motion.RUN_ARM_FINGERS, runShare)
				elbow = elbow:Lerp(onFreeSide(Motion.RUN_ARM_ELBOW), runShare)
			end
			place(
				arm,
				fromHips(chestCFrame, palm),
				chestCFrame:VectorToWorldSpace(toObjectSpace(facing)),
				chestCFrame:VectorToWorldSpace(toObjectSpace(fingers)),
				fromHips(chestCFrame, elbow),
				false
			)
			if free == "Right" then
				rightGoal = 1
			else
				leftGoal = 1
			end
		end
	elseif mode == "Held" and dunk then
		-- Two-handed dunk: both palms on the ball, mirrored, sliding from its sides (at the hip
		-- or the knees) round behind it (overhead and out over the rim) as it rises, in step
		-- with the ball.
		local rise = BallController.getRise()
		local hand = Motion.DUNK_HAND_LOW:Lerp(Motion.DUNK_HAND_HIGH, rise)
		local fingers = Motion.DUNK_FINGERS_LOW:Lerp(Motion.DUNK_FINGERS_HIGH, rise)
		local elbow = Motion.DUNK_ELBOW
		palmOnBall(right, ballPosition, bodyDirection(hand), bodyDirection(fingers), fromHips(bodyCFrame, elbow))
		palmOnBall(
			left,
			ballPosition,
			bodyDirection(mirrored(hand)),
			bodyDirection(fingers),
			fromHips(bodyCFrame, mirrored(elbow))
		)
		-- Remember where the palms are, for the move onto the rim after the slam.
		local onBall = Ball.RADIUS + Motion.PALM_GAP
		dunkPalmRight = bodyCFrame:PointToObjectSpace(ballPosition + bodyDirection(hand).Unit * onBall)
		dunkPalmLeft = bodyCFrame:PointToObjectSpace(ballPosition + bodyDirection(mirrored(hand)).Unit * onBall)
		rightGoal, leftGoal = 1, 1
	elseif mode == "Held" then
		-- How far through the rise the ball is, from the pocket (0) to the release point (1)
		-- by time. The shooting hand turns from its LOW spot to its HIGH spot over that range.
		local rise = BallController.getRise()
		local handLow = if layup then Motion.LAYUP_HAND_LOW else Motion.SHOOTING_HAND_LOW
		local handHigh = if layup then Motion.LAYUP_HAND_HIGH else Motion.SHOOTING_HAND_HIGH
		local fingersLow = if layup then Motion.LAYUP_FINGERS_LOW else Motion.SHOOTING_FINGERS_LOW
		local fingersHigh = if layup then Motion.LAYUP_FINGERS_HIGH else Motion.SHOOTING_FINGERS_HIGH
		palmOnBall(
			right,
			ballPosition,
			bodyDirection(handLow:Lerp(handHigh, rise)),
			bodyDirection(fingersLow:Lerp(fingersHigh, rise)),
			fromHips(bodyCFrame, Motion.SHOOTING_ELBOW)
		)
		local guideElbow = fromHips(bodyCFrame, Motion.GUIDE_ELBOW)
		if layup then
			-- Guide hand on the ball until LAYUP_GUIDE_LET_GO, then off it and up to the shield.
			local letGo = math.clamp(Motion.LAYUP_GUIDE_LET_GO, 0, 0.95)
			local away = ease((rise - letGo) / (1 - letGo))
			local dir = bodyDirection(Motion.LAYUP_GUIDE_HAND).Unit
			local onBall = ballPosition + dir * (Ball.RADIUS + Motion.PALM_GAP)
			place(
				left,
				onBall:Lerp(fromHips(bodyCFrame, Motion.LAYUP_GUIDE_SHIELD), away),
				(-dir):Lerp(bodyDirection(Motion.LAYUP_GUIDE_SHIELD_FACING).Unit, away),
				bodyDirection(Motion.GUIDE_FINGERS):Lerp(bodyDirection(Motion.LAYUP_GUIDE_SHIELD_FINGERS), away),
				guideElbow,
				away <= 0.001
			)
		else
			palmOnBall(
				left,
				ballPosition,
				bodyDirection(Motion.GUIDE_HAND),
				bodyDirection(Motion.GUIDE_FINGERS),
				guideElbow
			)
		end
		rightGoal, leftGoal = 1, 1
	elseif dunk and sinceRelease < Motion.FOLLOW_THROUGH_TIME then
		-- After the slam both hands come down on top of the front of the rim and stay there
		-- (in the world, so the arms straighten as the body drops) for DUNK_RIM_HOLD seconds,
		-- then let go and fall to the END positions.
		local launchedAt = BallController.getLaunchTime()
		local grip = rimGrip
		if not grip or grip.launchedAt ~= launchedAt then
			-- First frame after this slam: pick the grip spots once, on the side of the rim
			-- the player came from, so they can't jump to the back of the rim if the body
			-- carries on under it.
			local rim = Court.RIM_POSITION
			local flat = Vector3.new(rootCFrame.Position.X - rim.X, 0, rootCFrame.Position.Z - rim.Z)
			local towardPlayer = if flat.Magnitude > 1e-3 then flat.Unit else -rootCFrame.LookVector
			-- Along the front of the rim, toward the player's right (so the right hand takes
			-- the right-hand spot and the arms don't cross).
			local across = Vector3.new(0, 1, 0):Cross(towardPlayer)
			local front = rim
				+ towardPlayer * (Court.RIM_INNER_RADIUS + Court.RIM_TUBE / 2)
				+ Vector3.yAxis * (Court.RIM_TUBE / 2 + Motion.PALM_GAP)
			grip = {
				launchedAt = launchedAt,
				right = front + across * Motion.DUNK_RIM_GRIP_SPREAD,
				left = front - across * Motion.DUNK_RIM_GRIP_SPREAD,
				-- Palms face down onto the rim, fingers curled over its front edge.
				fingers = (-towardPlayer - Vector3.yAxis * 0.5).Unit,
				rightLetGo = nil,
				leftLetGo = nil,
				rightFrom = dunkPalmRight,
				leftFrom = dunkPalmLeft,
			}
			rimGrip = grip
		end
		local gripped = grip :: RimGrip
		-- On the rim until the reach plus the hold are over.
		local onRimFor = Motion.DUNK_RIM_REACH_TIME + Motion.DUNK_RIM_HOLD
		local hold = math.clamp(onRimFor / Motion.FOLLOW_THROUGH_TIME, 0, 0.95)
		local progress = sinceRelease / Motion.FOLLOW_THROUGH_TIME
		local fall = ease((progress - hold) / (1 - hold))
		for _, side in { 1, -1 } do
			local arm = if side == 1 then right else left
			local onRim = if side == 1 then gripped.right else gripped.left
			local fallen = if side == 1 then Motion.FOLLOW_THROUGH_END else Motion.GUIDE_FOLLOW_THROUGH_END
			local palm: Vector3
			local from = if side == 1 then gripped.rightFrom else gripped.leftFrom
			local reaching = sinceRelease < Motion.DUNK_RIM_REACH_TIME
			if reaching and from then
				-- Just after the slam: from the ball onto the rim.
				local reach = ease(sinceRelease / math.max(Motion.DUNK_RIM_REACH_TIME, 0.01))
				palm = bodyCFrame:PointToWorldSpace(from):Lerp(onRim, reach)
			elseif progress < hold then
				palm = onRim
			else
				-- Letting go: from where the hand was on the rim, measured from the body at
				-- that moment, so the hand moves with the falling body instead of being
				-- dragged from a spot in the world.
				local letGo = if side == 1 then gripped.rightLetGo else gripped.leftLetGo
				if not letGo then
					letGo = bodyCFrame:PointToObjectSpace(onRim)
					if side == 1 then
						gripped.rightLetGo = letGo
					else
						gripped.leftLetGo = letGo
					end
				end
				palm = bodyCFrame:PointToWorldSpace((letGo :: Vector3):Lerp(toObjectSpace(fallen), fall))
			end
			local elbow = Motion.DUNK_ELBOW
			-- (In contact with the ball, then the rim, until the hands let go.)
			place(
				arm,
				palm,
				(-Vector3.yAxis):Lerp(bodyDirection(Vector3.new(0, -0.5, 0.85)), fall).Unit,
				gripped.fingers:Lerp(bodyDirection(Motion.FOLLOW_THROUGH_END_FINGERS), fall).Unit,
				fromHips(bodyCFrame, if side == 1 then elbow else mirrored(elbow)),
				progress < hold
			)
		end
		rightGoal, leftGoal = 1, 1
	elseif sinceRelease < Motion.FOLLOW_THROUGH_TIME then
		-- Follow-through: the shooting arm reaches up and forward toward the rim with the wrist
		-- flexed ~40°, the guide hand peels off sideways; hold for the first FOLLOW_THROUGH_HOLD
		-- of the time, then fall forward to the END positions. `fall` goes 0 (arms up) → 1
		-- (arms fallen forward). The hands start from where they were at the release (the
		-- spring carries them over), so nothing jumps.
		local progress = sinceRelease / Motion.FOLLOW_THROUGH_TIME
		local hold = math.clamp(Motion.FOLLOW_THROUGH_HOLD, 0, 0.95)
		local fall = ease((progress - hold) / (1 - hold))
		-- Where each arm starts (held up) before falling: a layup keeps the right arm
		-- reaching for the board and the guide hand in its shield.
		local reach = if layup then Motion.LAYUP_FOLLOW_THROUGH else Motion.FOLLOW_THROUGH
		local reachFacing = if layup then Motion.LAYUP_FOLLOW_THROUGH_FACING else Motion.FOLLOW_THROUGH_FACING
		local reachFingers = if layup then Motion.LAYUP_FOLLOW_THROUGH_FINGERS else Motion.FOLLOW_THROUGH_FINGERS
		local guide = if layup then Motion.LAYUP_GUIDE_SHIELD else Motion.GUIDE_FOLLOW_THROUGH
		local guideFacing = if layup then Motion.LAYUP_GUIDE_SHIELD_FACING else Motion.GUIDE_FOLLOW_THROUGH_FACING
		local guideFingers = if layup then Motion.LAYUP_GUIDE_SHIELD_FINGERS else Motion.GUIDE_FINGERS
		place(
			right,
			fromHips(bodyCFrame, reach:Lerp(Motion.FOLLOW_THROUGH_END, fall)),
			bodyDirection(reachFacing),
			bodyDirection(reachFingers:Lerp(Motion.FOLLOW_THROUGH_END_FINGERS, fall)),
			fromHips(bodyCFrame, Motion.SHOOTING_ELBOW),
			false
		)
		place(
			left,
			fromHips(bodyCFrame, guide:Lerp(Motion.GUIDE_FOLLOW_THROUGH_END, fall)),
			bodyDirection(guideFacing),
			bodyDirection(guideFingers:Lerp(Motion.FOLLOW_THROUGH_END_FINGERS, fall)),
			fromHips(bodyCFrame, Motion.GUIDE_ELBOW),
			false
		)
		rightGoal, leftGoal = 1, 1
	end

	-- A relaxed arm forgets its smoothing, so the next time it is used it starts on its target.
	for _, state in { rightState, leftState } do
		if not state.used then
			state.valid = false
		end
		state.used = false
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
		rightState, leftState = newHandState(), newHandState()
		nextRetryAt = 0
	end)
	-- Runs just after BallController (Character + 1) so the hands use this frame's ball position.
	RunService:BindToRenderStep("RoHoopsArms", Enum.RenderPriority.Character.Value + 2, update)
end

return ArmController
