--!strict
-- BALL CONTROLLER
-- Owns the test ball and decides makes and misses. The ball is in one of three modes:
--   Dribble – bouncing beside the player (positioned by code, not physics), in the right
--             or left hand. One bounce is a cycle (SkillMath.dribbleProfile): the hand
--             meets the ball on its way UP, rides it, pushes it down (the "contact" part),
--             then the ball falls, bounces (restitution ~0.85) and rises into the hand
--             again (the "flight" part). Standing still it bounces ~1.6 times a second beside
--             the ball-side foot; when moving it is phase-locked to the footsteps
--             (LegController calls notifyFootPlant on every plant): one bounce per stride /
--             shuffle cycle, the ball reaching the floor on a plant, pushed ahead in the
--             direction of travel and higher the faster you go. Every bounce is a little
--             different (jitter). While dribbling it also twists the upper body in time with
--             the push (PostureController.setDribbleTwist).
--             A dribble move (BallController.startMove, started by SkillController) carries
--             the ball along a few waypoints (a move asked for while the ball is in flight
--             waits, up to Ball.MOVE_MAX_WAIT, for the hand to meet it, and the first leg keeps
--             the ball's current speed, so it never skates along the floor):
--               HandSwitch (H key)   – down and across, one bounce on the centre line, up
--                                      into the other hand;
--               Crossover (flick)    – the wide Iverson crossover: out wide on its side
--                                      (the sell), pounded down to a low bounce on the
--                                      centre line (the old hand keeps it through most of
--                                      the push), caught low on the other side, then back
--                                      up into a normal dribble;
--               StepBack (flick back) – pulled back to a bounce between the feet, up into
--                                      the same hand;
--               Stab (flick to the ball's side) – pounded out to a bounce just outside the
--                                      jab foot, up into the same hand;
--               Spin (circle)        – one hard pound beside the ball hand's foot, then
--                                      that same hand pulls it round at its hip while
--                                      the body turns, pushes it down across the feet as
--                                      the turn ends, and the other hand takes it off the
--                                      bounce (never two hands on it: no double dribble;
--                                      the path is measured from the hips, so the ball
--                                      goes round with them).
--             Once no hand holds the ball (the crossover's push and rise, the hand switch's
--             rise, the spin's catch) its path is fixed in the WORLD at that moment, aimed at
--             where the body will be when it arrives, so a body burst doesn't drag it.
--   Held    – the shooting motion while E is held. The ball follows a smooth curve through
--             the pocket (belt, at the bottom of the dip), the SET point (forehead, reached at
--             takeoff: arms and legs rise together) and the release point, still moving as it
--             arrives, so the launch is seamless. A jump shot is released above the head; a
--             layup is carried up the right side from the hip to a high release in front; a
--             dunk is held in both hands, swung up overhead (a standing dunk first swings the
--             ball down toward the knees), cocked behind the head near the top, swung out over
--             the rim, then slammed through.
--   Flight  – a shot in the air
--
-- How a shot flies: the ball follows its exact arc in code, then switches to real physics
-- just before the hoop so the rim and backboard decide close calls. Flying it in code
-- matters: Roblox moves a lone ball in 1/60 s steps, which makes it fall ~0.3 studs short
-- of the planned arc over a jump shot – enough to turn a perfect release into front rim.
-- A shot counts as made when the ball's centre passes down through the rim circle.
--
-- The ball only exists on this player's computer. That's fine for solo testing; it will
-- move to the server once there are opponents. Tuning values: src/shared/Config/Ball.luau
-- (size, bounce, dribble) and src/shared/Config/Motion.luau (the gather paths).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ball = require(ReplicatedStorage.Shared.Config.Ball)
local Court = require(ReplicatedStorage.Shared.Config.Court)
local Motion = require(ReplicatedStorage.Shared.Config.Motion)
local Shooting = require(ReplicatedStorage.Shared.Config.Shooting)
local Skills = require(ReplicatedStorage.Shared.Config.Skills)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local MovementController = require(script.Parent.MovementController)
local PostureController = require(script.Parent.PostureController)

type Mode = "Dribble" | "Held" | "Flight"

-- Everything about the shot currently in the air.
type Flight = {
	origin: Vector3, -- where the ball was released
	launchVelocity: Vector3, -- its velocity at release, studs/s
	gravity: number, -- downward pull used for the arc, studs/s²
	scripted: boolean, -- true while code flies the ball; false once physics has taken over
	previous: Vector3, -- ball position last frame (to detect passing through the rim)
	startedAt: number, -- clock time of the release, seconds
	resolved: boolean, -- true once the shot has been decided as made or missed
	onResolved: (made: boolean) -> (), -- called once with the result (ShotController updates the HUD)
}

-- One stop on a dribble move's path. The ball travels from the previous stop to `spot`.
type Waypoint = {
	-- Where the ball arrives: (out, height, forward). `out` = studs toward the hand the
	-- ball STARTED in (negative = toward the new hand), height = studs above the floor,
	-- forward = studs in front of the hips. Measured from the hips every frame, so the
	-- path moves with the player (except while no hand holds it: see HandMove.freeTargets).
	spot: Vector3,
	duration: number, -- seconds to get there
	ease: (number) -> number, -- how the speed changes along the way (0→1 in, 0→1 out)
	-- Which hand is on the ball on the way here: the one it started in, the new one, or
	-- none (bouncing between hands).
	holder: "From" | "To" | nil,
	-- If set (0-1), the `holder` lets go after this share of the leg (the crossover's old
	-- hand keeps the ball through most of the push, then whips it away).
	holderUntil: number?,
	-- How the palm holds the ball on the way here, from → to: 0 = on top (a dribble),
	-- 1 = on its outer side (pulling it wide / whipping it across), negative = inner side.
	grip: Vector2,
}

-- A dribble move in progress: the ball's trip from its hand to the hand it ends in (the
-- same hand for a step-back).
type HandMove = {
	move: SkillMath.Move, -- which move
	fromHand: SkillMath.Hand, -- the hand it started in
	toHand: SkillMath.Hand, -- the hand it ends in
	startedAt: number, -- clock time the move started
	path: { Waypoint },
	catchAt: number, -- index of the waypoint where the new hand catches the ball (0 = same hand)
	waitFrom: number, -- index of the waypoint from which the new hand waits for it (before that it's free)
	-- True if the move ends with a hand carrying the ball (the dribble then carries on from
	-- the top of the ride); false if it ends with the ball rising free into the hand (the
	-- dribble then starts at the catch).
	endsInHand: boolean,
	startVelocity: Vector3, -- the ball's velocity when the move started, relative to the hips (studs/s)
	legIndex: number, -- which waypoint the ball is travelling to (0 = none yet)
	legFromLocal: Vector3, -- where the current leg started, relative to the hips
	legFromWorld: Vector3, -- ...and in the world (for free legs)
	-- World spots for the legs where no hand holds the ball, fixed when the first such leg
	-- starts, aimed at where the body will be on arrival (index = waypoint number).
	freeTargets: { [number]: Vector3 },
}

-- What the hands should be doing this frame (for ArmController).
export type Handling = {
	holder: SkillMath.Hand?, -- the hand on the ball (nil while it bounces between hands)
	waiting: SkillMath.Hand?, -- the hand waiting to catch it (nil when there's no dribble move)
	waitPoint: Vector3?, -- where that hand waits: where the ball will arrive (world space)
	grip: number, -- 0 = palm on top of the ball (dribble), 1 = palm on its outer side
	-- True while the holder's palm is on the ball (it then follows the ball exactly). False in
	-- a dribble while the ball is in flight: the hand hovers at `hover` waiting to meet it.
	contact: boolean,
	hover: Vector3?, -- where the dribbling hand waits (ball-centre equivalent, world); nil in a move
	push: number, -- 0-1: how far through the push the dribbling hand is (the wrist snaps at 1)
	-- 0-1: how much this is a running dribble (the free arm swings, the trunk twists).
	run: number,
}

-- Where the shooting motion's ball path passes: a spot (relative to the body), the time
-- (seconds after E) it gets there, and its velocity there (studs/s, relative to the body).
type HoldKey = {
	position: Vector3,
	time: number,
	tangent: Vector3,
}

-- Optional extras for BallController.hold.
export type HoldOptions = {
	toSet: number?, -- seconds from now until takeoff: the ball should be at the SET point then
	lowSwing: boolean?, -- standing dunk: swing the ball down toward the knees in the dip, then up fast
}

local BallController = {}

local ball: Part -- the ball part itself, created in start()
local mode: Mode = "Dribble" -- what the ball is doing right now
local flight: Flight? = nil -- the shot in the air, or nil
local launchedAt = 0 -- clock time of the last release (ArmController times the follow-through from it)

-- The dribble cycle (see SkillMath.dribbleProfile).
local cyclePhase = 0 -- 0 to 1 through the current bounce: 0 = the hand meets the ball (rising)
local cycleStage: SkillMath.DribbleStage = "Ride" -- which part of the bounce the last frame was in
local cycleNudge = 0 -- timing error from the footsteps still to be corrected, in cycles
local jitterRate, jitterHeight, jitterSide, jitterForward = 0, 0, 0, 0 -- this bounce's random variation
local random = Random.new()
-- The latest foot plant (BallController.notifyFootPlant).
local lastPlantAt = -math.huge -- clock time
local lastPlantSide: SkillMath.Hand = "Left"
local stepPeriod: number? = nil -- seconds between consecutive plants, nil if unknown
local plantToLock: SkillMath.Hand? = nil -- a plant not yet used to correct the dribble's timing
-- When the ball has just returned to the dribble from a move, it is placed by the dribble
-- model plus this world offset, which fades away so the ball never pops.
local settleOffset = Vector3.zero
local needSettle = false -- true for one frame after a move: work out the offset
-- The ball's velocity in the world (studs/s), measured every frame.
local ballVelocity = Vector3.zero
local lastBallPosition = Vector3.zero
local twisting = false -- true while PostureController has a dribble twist from us

-- Dribbling hand and dribble moves.
local hand: SkillMath.Hand = "Right" -- the hand dribbling the ball; switches at the end of a dribble move
local handMove: HandMove? = nil -- the dribble move in progress, or nil
-- A move asked for while the ball is in flight, waiting for the hand to meet it.
local pendingMove: { move: SkillMath.Move, since: number }? = nil
-- What the hands should do this frame; updated every frame, read by ArmController.
local handling: Handling = { holder = "Right", grip = 0, contact = true, push = 0, run = 0 }

-- The shooting motion (Held mode): dribble → pocket → set → release.
local gatherStartedAt = 0 -- clock time when E was pressed
local gatherFrom = Vector3.zero -- ball position when E was pressed, relative to the (pelvis) body frame
local holdKeys: { HoldKey } = {} -- the path (object space), see BallController.hold; the first is the pocket
local holdRise = 0 -- 0 (in the pocket) to 1 (at the release point), by time, for the hands
-- Which motion the current (or last) shot uses; picks the ball path and, in
-- ArmController, the hand positions and follow-through.
local style: Shooting.MotionStyle = "JumpShot"
-- Increased whenever a pending "give the ball back" timer should be cancelled; a timer
-- only fires if the counter hasn't changed since it was started.
local returnToken = 0

-- Creates the ball. It starts anchored (frozen in place) because code positions it.
local function createBall(): Part
	local part = Instance.new("Part")
	part.Name = "LocalBall"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * Ball.RADIUS * 2
	part.Color = Ball.COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.CollisionGroup = Ball.COLLISION_GROUP
	part.Parent = workspace
	return part
end

-- Switches a shot from the scripted arc to real physics at `position` with `velocity`.
local function handToPhysics(current: Flight, position: Vector3, velocity: Vector3)
	current.scripted = false
	ball.CFrame = CFrame.new(position)
	ball.CustomPhysicalProperties = PhysicalProperties.new(Ball.DENSITY, Ball.FRICTION, Ball.ELASTICITY, 1, 1)
	-- Set again here in case the group hadn't reached this client when the ball was created.
	ball.CollisionGroup = Ball.COLLISION_GROUP
	ball.Anchored = false
	ball.CanCollide = true
	ball.AssemblyLinearVelocity = velocity

	-- Backspin: spin around the axis that points sideways relative to the shot.
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	ball.AssemblyAngularVelocity = if flat.Magnitude > 1e-3
		then flat.Unit:Cross(Vector3.yAxis) * Ball.BACKSPIN
		else Vector3.zero
end

-- Moves the ball along its exact arc for this frame, or hands it to physics near the hoop.
local function fly(current: Flight)
	local t = os.clock() - current.startedAt -- seconds since release
	local gravity = Vector3.yAxis * current.gravity
	-- Standard projectile motion: start + velocity × time − ½ × gravity × time².
	local position = current.origin + current.launchVelocity * t - gravity * (0.5 * t * t)
	local velocity = current.launchVelocity - gravity * t

	local rim = Court.RIM_POSITION
	local nearHoop = (position - rim).Magnitude <= Ball.HANDOFF_DISTANCE
	-- Way-off shots never get near the hoop; let physics take them as they come down.
	local comingDown = velocity.Y < 0 and position.Y <= rim.Y + 1
	if nearHoop or comingDown then
		handToPhysics(current, position, velocity)
	else
		ball.CFrame = CFrame.new(position)
	end
end

-- Converts a Motion-config offset (right, up, forward) to Roblox's object space, where
-- forward is -Z.
local function toObjectSpace(offset: Vector3): Vector3
	return Vector3.new(offset.X, offset.Y, -offset.Z)
end

-- Eases 0→1 gently at both ends (smoothstep), for motion that starts and stops softly.
local function ease(p: number): number
	p = math.clamp(p, 0, 1)
	return p * p * (3 - 2 * p)
end

-- Builds the shooting motion's ball path (see BallController.hold). Returns the stops in
-- time order, in the body's object space; the first is the pocket. Every stop has a
-- velocity so the ball glides through it instead of stopping:
--   * at the pocket: 0 (the bottom of the motion);
--   * in between: SkillMath.monotoneTangent of the speeds either side (never overshoots);
--   * at the release: Motion.RELEASE_END_SPEED along the style's end direction (up and
--     forward, like the launch).
-- `toPocket`, `toSet`, `toRelease` = seconds after E when the ball is at each of those.
local function buildHoldKeys(
	motionStyle: Shooting.MotionStyle,
	toPocket: number,
	toSet: number,
	toRelease: number,
	lowSwing: boolean
): { HoldKey }
	local stops: { { position: Vector3, time: number } }
	local endDirection: Vector3
	if motionStyle == "Layup" then
		-- Hip → shoulder/ear (takeoff) → high in front of the right shoulder.
		stops = {
			{ position = Motion.LAYUP_POCKET, time = toPocket },
			{ position = Motion.LAYUP_SET_POINT, time = toSet },
			{ position = Motion.LAYUP_RELEASE_POINT, time = toRelease },
		}
		endDirection = Motion.LAYUP_END_DIRECTION
	elseif motionStyle == "Dunk" then
		-- (Low swing to the knees, or the right hip) → overhead at takeoff → cocked behind the
		-- head near the top → out over the rim.
		local cockTime = toSet + math.clamp(Motion.DUNK_COCK_AT, 0.1, 0.9) * (toRelease - toSet)
		stops = {
			{ position = if lowSwing then Motion.DUNK_LOW_SWING else Motion.DUNK_RUN_POCKET, time = toPocket },
			{ position = Motion.DUNK_SET_POINT, time = toSet },
			{ position = Motion.DUNK_COCK, time = cockTime },
			{ position = Motion.DUNK_REACH, time = toRelease },
		}
		endDirection = Motion.DUNK_END_DIRECTION
	else
		-- Belt → forehead (takeoff) → above the head.
		stops = {
			{ position = Motion.DIP_POCKET, time = toPocket },
			{ position = Motion.SET_POINT, time = toSet },
			{ position = Motion.RELEASE_POINT, time = toRelease },
		}
		endDirection = Motion.RELEASE_END_DIRECTION
	end

	-- Average velocity of each stretch between two stops (object space).
	local slopes: { Vector3 } = {}
	for i = 1, #stops - 1 do
		local duration = math.max(stops[i + 1].time - stops[i].time, 1e-3)
		slopes[i] = (toObjectSpace(stops[i + 1].position) - toObjectSpace(stops[i].position)) / duration
	end
	local keys: { HoldKey } = {}
	for i, stop in stops do
		local tangent: Vector3
		if i == 1 then
			tangent = Vector3.zero
		elseif i == #stops then
			tangent = toObjectSpace(endDirection.Unit) * Motion.RELEASE_END_SPEED
		else
			local before, after = slopes[i - 1], slopes[i]
			tangent = Vector3.new(
				SkillMath.monotoneTangent(before.X, after.X),
				SkillMath.monotoneTangent(before.Y, after.Y),
				SkillMath.monotoneTangent(before.Z, after.Z)
			)
		end
		keys[i] = { position = toObjectSpace(stop.position), time = stop.time, tangent = tangent }
	end
	return keys
end

-- Where the ball is during the shooting motion, relative to the body (so it moves, dips,
-- turns and leans with the player):
--   1. from where it was in the dribble into the pocket, arriving as the hips reach the
--      bottom of the dip;
--   2. then along the smooth path through the set point (takeoff) to the release point,
--      arriving exactly at the perfect release moment and still moving.
-- Holding E past the perfect release keeps the ball at the release point.
-- Also updates `holdRise` (0-1 through the rise, by time) for the hands.
local function gatherPosition(bodyCFrame: CFrame): Vector3
	local elapsed = os.clock() - gatherStartedAt
	local first = holdKeys[1]
	local last = holdKeys[#holdKeys]
	local localPosition: Vector3
	if elapsed < first.time then
		holdRise = 0
		localPosition = gatherFrom:Lerp(first.position, ease(elapsed / first.time))
	elseif elapsed >= last.time then
		holdRise = 1
		localPosition = last.position
	else
		holdRise = (elapsed - first.time) / math.max(last.time - first.time, 0.05)
		-- The stretch of the path we're in.
		local index = 1
		while index < #holdKeys - 1 and elapsed >= holdKeys[index + 1].time do
			index += 1
		end
		local from, to = holdKeys[index], holdKeys[index + 1]
		local duration = math.max(to.time - from.time, 1e-3)
		local u = math.clamp((elapsed - from.time) / duration, 0, 1)
		localPosition = Vector3.new(
			SkillMath.hermite(from.position.X, from.tangent.X, to.position.X, to.tangent.X, duration, u),
			SkillMath.hermite(from.position.Y, from.tangent.Y, to.position.Y, to.tangent.Y, duration, u),
			SkillMath.hermite(from.position.Z, from.tangent.Z, to.position.Z, to.tangent.Z, duration, u)
		)
	end
	return bodyCFrame:PointToWorldSpace(localPosition)
end

-- Height of the floor under the player (from the hips down).
local function floorHeight(parts: CharacterRef.Parts): number
	return parts.root.Position.Y - parts.humanoid.HipHeight - parts.root.Size.Y / 2
end

-- How far the player's hips are lowered into their stance right now, studs (LegController
-- publishes it as the Humanoid's "RoHoopsCrouch" attribute).
local function crouchOf(parts: CharacterRef.Parts): number
	local crouch = parts.humanoid:GetAttribute("RoHoopsCrouch")
	return if type(crouch) == "number" then crouch else 0
end

-- A ball height above the floor (studs, to the ball's centre), lowered for the crouch:
-- crouching lowers the shoulders and hands, so the ball in the hand comes down by the same
-- amount, like a real low dribble. A ball on the floor stays there; anything at the top of
-- a normal dribble or higher comes down by the whole crouch. (Used by dribble MOVE paths;
-- the plain dribble's heights already include the stance.)
local function lowered(height: number, crouch: number): number
	local inHand = math.clamp((height - Ball.RADIUS) / math.max(Ball.DRIBBLE_HEIGHT, 0.01), 0, 1)
	return height - crouch * inHand
end

-- Ease curves: how a value goes from 0 to 1 as `p` goes from 0 to 1.
local function linear(p: number): number
	return p
end
local function easeIn(p: number): number -- starts slow, speeds up (a ball thrown down)
	return p * p
end
local function easeOut(p: number): number -- starts fast, slows to a stop (a ball rising off a bounce)
	return 1 - (1 - p) * (1 - p)
end

-- A waypoint's spot, in the hips' space. `fromSign` is +1 if the ball started in the right
-- hand, -1 if in the left; `floor` is the floor's height in the hips' space; `crouch` =
-- how far the hips are lowered (see lowered).
local function spotToLocal(spot: Vector3, fromSign: number, floor: number, crouch: number): Vector3
	return Vector3.new(spot.X * fromSign, floor + lowered(spot.Y, crouch), -spot.Z)
end

-- The start of a leg of a dribble move: remembers where the ball is now (so each leg starts
-- exactly where the last one ended, whatever the body did) and, the first time a leg with no
-- hand on the ball starts, fixes that stretch of the path in the WORLD, aimed at where the
-- body will be when the ball arrives (its velocity now, blended with where it is heading).
local function beginLeg(
	current: HandMove,
	index: number,
	rootCFrame: CFrame,
	floor: number,
	crouch: number,
	left: number
)
	current.legIndex = index
	current.legFromLocal = rootCFrame:PointToObjectSpace(ball.Position)
	current.legFromWorld = ball.Position
	if current.path[index].holder ~= nil or current.freeTargets[index] ~= nil then
		return
	end
	local fromSign = if current.fromHand == "Right" then 1 else -1
	local bodyVelocity = (MovementController.getVelocity() + MovementController.getTargetVelocity()) / 2
	local ahead = left -- seconds from now until the ball reaches waypoint j
	for j = index, #current.path do
		local waypoint = current.path[j]
		if waypoint.holder ~= nil then
			break
		end
		if j > index then
			ahead += waypoint.duration
		end
		local predicted = rootCFrame + bodyVelocity * ahead -- the hips then (same turn as now)
		current.freeTargets[j] = predicted:PointToWorldSpace(spotToLocal(waypoint.spot, fromSign, floor, crouch))
	end
end

-- Where the ball is during a dribble move (world space), or nil once it has finished. Also
-- fills in `handling` for ArmController.
local function handMovePosition(current: HandMove, rootCFrame: CFrame, floorY: number, crouch: number): Vector3?
	local fromSign = if current.fromHand == "Right" then 1 else -1
	local floor = floorY - rootCFrame.Position.Y -- the floor's height in the hips' space
	local elapsed = os.clock() - current.startedAt
	for index, waypoint in current.path do
		if elapsed < waypoint.duration then
			local progress = elapsed / waypoint.duration
			if current.legIndex ~= index then
				beginLeg(current, index, rootCFrame, floor, crouch, waypoint.duration - elapsed)
			end
			local holder = waypoint.holder
			if waypoint.holderUntil and progress >= waypoint.holderUntil then
				holder = nil
			end
			handling.holder = if holder == "From"
				then current.fromHand
				elseif holder == "To" then current.toHand
				else nil
			handling.contact = handling.holder ~= nil
			handling.hover, handling.push, handling.run = nil, 0, 0
			-- Until the new hand has caught the ball it waits where the ball will arrive
			-- (from waypoint `waitFrom` on; before that it's free, e.g. the spin's arm bar).
			if index >= current.waitFrom and index <= current.catchAt then
				handling.waiting = current.toHand
				handling.waitPoint = current.freeTargets[current.catchAt]
					or rootCFrame:PointToWorldSpace(
						spotToLocal(current.path[current.catchAt].spot, fromSign, floor, crouch)
					)
			else
				handling.waiting, handling.waitPoint = nil, nil
			end
			handling.grip = waypoint.grip.X + (waypoint.grip.Y - waypoint.grip.X) * progress

			local freeTarget = current.freeTargets[index]
			if waypoint.holder == nil and freeTarget then
				-- No hand on it: a path fixed in the world.
				return current.legFromWorld:Lerp(freeTarget, waypoint.ease(progress))
			end
			local target = spotToLocal(waypoint.spot, fromSign, floor, crouch)
			local position = current.legFromLocal:Lerp(target, waypoint.ease(progress))
			if index == 1 then
				-- The first leg keeps the ball's speed from before the move (fading out by the
				-- end of the leg), so it doesn't restart from rest.
				local fade = progress * (1 - progress) * (1 - progress)
				position += current.startVelocity * (waypoint.duration * fade)
			end
			return rootCFrame:PointToWorldSpace(position)
		end
		elapsed -= waypoint.duration
	end
	return nil
end

-- Stops any dribble move. The ball belongs to the hand it was heading to, and the dribble
-- carries on from the right point of its bounce: the top of the ride if a hand was carrying
-- it, the moment the hand meets it if it was rising free.
local function endHandMove()
	local current = handMove
	if current then
		hand = current.toHand
		cyclePhase = if current.endsInHand then Ball.DRIBBLE_CONTACT_SHARE * Ball.DRIBBLE_RIDE_SHARE else 0
		cycleNudge = 0
		plantToLock = nil -- plants during the move don't count
	end
	handMove = nil
end

-- Picks this bounce's random variation (every bounce is a little different).
local function rollJitter()
	local jitter = Ball.DRIBBLE_JITTER
	jitterRate = (random:NextNumber() * 2 - 1) * jitter
	jitterHeight = (random:NextNumber() * 2 - 1) * jitter
	jitterSide = (random:NextNumber() * 2 - 1) * jitter * 1.5 -- studs
	jitterForward = (random:NextNumber() * 2 - 1) * jitter * 1.5
end

-- How far the ball is pushed ahead (0-1 of the lead distance) at a point in the bounce: it
-- is pushed out as it leaves the hand, furthest when it hits the floor, then the body
-- catches up with it as it rises, and the hand carries it back toward the body.
local function leadWeight(stage: SkillMath.DribbleStage, u: number): number
	if stage == "Ride" then
		return 0.35
	elseif stage == "Push" then
		return 0.35 - 0.25 * u
	elseif stage == "Down" then
		return 0.1 + 0.9 * easeOut(u)
	end
	return 1 - 0.65 * u
end

-- Tells PostureController how much to twist the upper body (0, 0 = none).
local function setTwist(yaw: number, roll: number)
	PostureController.setDribbleTwist(yaw, roll)
	twisting = yaw ~= 0 or roll ~= 0
end

-- The plain dribble, every frame: advances the bounce (locked to the footsteps when moving),
-- places the ball and says what the hands should do (`handling`).
local function updateDribble(dt: number, rootCFrame: CFrame, floorY: number)
	local now = os.clock()
	local velocity = MovementController.getVelocity()
	local speed = velocity.Magnitude
	local look, right = rootCFrame.LookVector, rootCFrame.RightVector
	local forwardSpeed, sideSpeed = velocity:Dot(look), velocity:Dot(right)
	local sideSign = if hand == "Right" then 1 else -1
	local runDribble = math.clamp((forwardSpeed - Ball.DRIBBLE_RUN_SPEED * 0.5) / (Ball.DRIBBLE_RUN_SPEED * 0.5), 0, 1)

	-- Speed of the bounce: locked to the footsteps while they are known (one bounce per two
	-- steps), otherwise a speed-based rate that doesn't climb too far.
	local period = stepPeriod
	local locked = period ~= nil and now - lastPlantAt < Ball.DRIBBLE_FOOTFALL_STALE and speed > 2
	local rate
	if locked and period then
		rate = math.clamp(1 / (2 * period), Ball.DRIBBLE_LOCKED_MIN_RATE, Ball.DRIBBLE_LOCKED_MAX_RATE)
	else
		rate = math.min(Ball.DRIBBLE_RATE + speed * Ball.DRIBBLE_RATE_PER_SPEED, Ball.DRIBBLE_MAX_RATE)
	end
	rate *= 1 + jitterRate

	-- The shape of this bounce: higher the faster you go, but kept low when shuffling sideways.
	local heightShare = math.clamp(speed / math.max(Ball.DRIBBLE_HEIGHT_SPEED, 1), 0, 1)
	local shuffleShare =
		math.clamp((math.abs(sideSpeed) - math.abs(forwardSpeed)) / math.max(Ball.DRIBBLE_SHUFFLE_SPEED, 0.1), 0, 1)
	local speedCatch = Ball.DRIBBLE_CATCH_HEIGHT
		+ (Ball.DRIBBLE_RUN_CATCH_HEIGHT - Ball.DRIBBLE_CATCH_HEIGHT) * heightShare
	local catch = (speedCatch + (Ball.DRIBBLE_SHUFFLE_CATCH_HEIGHT - speedCatch) * shuffleShare) * (1 + jitterHeight)
	local cycle = 1 / rate
	local profile = SkillMath.dribbleProfile({
		floor = Ball.RADIUS,
		catch = catch,
		release = math.min(Ball.DRIBBLE_RELEASE_HEIGHT * (1 + jitterHeight * 0.5), catch - 0.05),
		ride = Ball.DRIBBLE_RIDE_UP,
		rideShare = Ball.DRIBBLE_RIDE_SHARE,
		contactTime = cycle * Ball.DRIBBLE_CONTACT_SHARE,
		flightTime = cycle * (1 - Ball.DRIBBLE_CONTACT_SHARE),
		restitution = Ball.DRIBBLE_RESTITUTION,
	})

	-- A foot just planted: if it's the foot the ball should hit the floor with, nudge the
	-- bounce's timing toward that (a share of the error each plant, eased in below).
	local plant = plantToLock
	if plant then
		plantToLock = nil
		local lockSide: SkillMath.Hand
		if math.abs(sideSpeed) > math.abs(forwardSpeed) then
			lockSide = if sideSpeed > 0 then "Right" else "Left" -- a shuffle: the lead foot
		else
			lockSide = if hand == "Right" then "Left" else "Right" -- a run / backpedal: the foot opposite the hand
		end
		if locked and plant == lockSide then
			local floorPhase = (profile.rideTime + profile.pushTime + profile.downTime) / profile.total
			cycleNudge += SkillMath.wrapSigned(cyclePhase, floorPhase) * Ball.DRIBBLE_LOCK_STRENGTH
		end
	end
	local advance = dt * rate
	local nudge = math.max(cycleNudge * math.min(1, dt * 10), -0.7 * advance) -- never run backwards
	cycleNudge -= nudge
	cyclePhase += advance + nudge
	if cyclePhase >= 1 then
		cyclePhase %= 1
		rollJitter()
	end
	local height, stage, progress = SkillMath.dribbleHeight(profile, cyclePhase * profile.total)
	cycleStage = stage

	-- Where the ball is, beside the ball-side foot; pushed ahead in the direction of travel
	-- (behind you when backpedalling), but never in under the body.
	local backShare = math.clamp(-forwardSpeed / 5, 0, 1)
	local forward = Ball.DRIBBLE_FORWARD + (Ball.DRIBBLE_BACK_FORWARD - Ball.DRIBBLE_FORWARD) * backShare
	local direction = if speed > 0.5 then velocity / speed else Vector3.zero
	local lead = math.min(speed * Ball.DRIBBLE_LEAD_PER_SPEED, Ball.DRIBBLE_MAX_LEAD) * leadWeight(stage, progress)
	local offset = right * (Ball.DRIBBLE_SIDE * sideSign + jitterSide)
		+ look * (forward + jitterForward)
		+ direction * lead
	local outside = offset:Dot(right) * sideSign
	local nearest = Ball.DRIBBLE_SIDE * 0.9
	if outside < nearest then
		offset += right * (sideSign * (nearest - outside))
	end
	local flat = rootCFrame.Position + offset
	local modelPosition = Vector3.new(flat.X, floorY + height, flat.Z)

	-- Coming back from a move: start where the ball was and fade into the model.
	if needSettle then
		needSettle = false
		settleOffset = ball.Position - modelPosition
	else
		settleOffset *= math.exp(-Ball.DRIBBLE_SETTLE_RATE * dt)
	end
	local position = modelPosition + settleOffset
	ball.CFrame = CFrame.new(position)

	-- The hands: the holder is on the ball while it rides and pushes it, then hovers at the
	-- height where it will meet the ball again.
	handling.holder, handling.waiting, handling.waitPoint = hand, nil, nil
	handling.grip = 0
	handling.contact = stage == "Ride" or stage == "Push"
	handling.hover = Vector3.new(position.X, floorY + catch, position.Z)
	handling.push = if stage == "Push" then progress elseif stage == "Down" then 1 - progress else 0
	handling.run = runDribble

	-- The upper body twists with the arm: running, the shoulders turn in time with the push;
	-- standing, the ball-side shoulder drops at the push.
	local yaw = -sideSign * Motion.DRIBBLE_TWIST_YAW * (2 * handling.push - 1) * runDribble
	local roll = sideSign * Motion.DRIBBLE_TWIST_ROLL * handling.push * (1 - runDribble)
	setTwist(yaw, roll)
end

-- The path of each dribble move, as a list of waypoints (see the Waypoint type), plus the
-- index of the waypoint where the other hand catches the ball (0 = it stays in the same
-- hand) and, optionally, the index of the waypoint from which that hand waits for it
-- (default 1: from the start). `height` = how high the ball is in its bounce when the move
-- starts (0 = floor, 1 = top). All moves end at a spot the dribble can carry on from: the
-- catch (the hand meets the ball rising) or the top of the ride (a hand is carrying it).
local function buildPath(move: SkillMath.Move, height: number): ({ Waypoint }, number, number?)
	local top = Ball.DRIBBLE_CATCH_HEIGHT + Ball.DRIBBLE_RIDE_UP -- ball height at the top of the ride
	-- Every move ends in the new hand or the same one.
	local newHandTop = Vector3.new(-Ball.DRIBBLE_SIDE, top, Ball.DRIBBLE_FORWARD)
	local newHandCatch = Vector3.new(-Ball.DRIBBLE_SIDE, Ball.DRIBBLE_CATCH_HEIGHT, Ball.DRIBBLE_FORWARD)
	local sameHandTop = Vector3.new(Ball.DRIBBLE_SIDE, top, Ball.DRIBBLE_FORWARD)
	if move == "Stab" then
		-- Pounded hard down and out to just outside the jab foot (the hand rolls from the
		-- inside-top, over the top, to the outside-top), then back up into the same hand
		-- (the body steps that way meanwhile, so the ball ends up beside it again).
		return {
			{
				spot = Vector3.new(Skills.STAB_BOUNCE_OUT, Ball.RADIUS, Skills.STAB_BOUNCE_FORWARD),
				duration = Skills.STAB_PUSH_TIME,
				ease = easeIn,
				holder = "From",
				grip = Vector2.new(Skills.STAB_GRIP_START, Skills.STAB_GRIP_PUSH_END),
			},
			{
				spot = sameHandTop,
				duration = Skills.STAB_RISE_TIME,
				ease = easeOut,
				holder = "From",
				grip = Vector2.new(Skills.STAB_GRIP_PUSH_END, 0),
			},
		},
			0
	elseif move == "StepBack" then
		-- Pulled back with the body: down to a bounce between the feet (inside the ball-side
		-- foot, a little ahead), then up.
		return {
			{
				spot = Vector3.new(Skills.STEPBACK_BOUNCE_OUT, Ball.RADIUS, Skills.STEPBACK_BOUNCE_FORWARD),
				duration = Skills.STEPBACK_PULL_TIME,
				ease = easeIn,
				holder = "From",
				grip = Vector2.zero,
			},
			{
				spot = sameHandTop,
				duration = Skills.STEPBACK_RISE_TIME,
				ease = easeOut,
				holder = "From",
				grip = Vector2.zero,
			},
		},
			0
	elseif move == "Spin" then
		-- A legal reverse-pivot spin: one hand on the ball at a time, and a bounce before
		-- the other hand touches it (Config/Skills.luau, SPIN). Everything is measured from
		-- the hips, so while the body turns the ball goes round with it; the path below is
		-- what it does relative to the body. The turn starts after SPIN_GATHER_TIME and
		-- lasts SPIN_TIME (SkillController); the timings make the exit bounce land exactly
		-- as the turn ends, so the ball is never on the floor while the body spins over it.
		local pocket = Skills.SPIN_POCKET
		-- The hand holds the ball at its hip for whatever is left of the turn after it has
		-- caught it and before it has to push it down.
		local carryTime = math.max(Skills.SPIN_TIME - Skills.SPIN_PULL_TIME - Skills.SPIN_DROP_TIME, 0.02)
		return {
			{ -- 1. POUND: planted, one hard dribble beside the ball hand's own foot
				spot = Vector3.new(Skills.SPIN_POUND_OUT, Ball.RADIUS, Skills.SPIN_POUND_FORWARD),
				duration = math.max(Skills.SPIN_GATHER_TIME, 0.04),
				ease = easeIn,
				holder = "From",
				grip = Vector2.zero,
			},
			{ -- 2. PULL: turning; the same hand meets it on the way up, palm sliding round to
				-- the ball's side, and pulls it in against its hip
				spot = pocket,
				duration = math.max(Skills.SPIN_PULL_TIME, 0.04),
				ease = easeOut,
				holder = "From",
				grip = Vector2.new(0, 1),
			},
			{ -- ...held tight there as the body comes round (the other hand stays off it,
				-- up as an arm bar)
				spot = pocket,
				duration = carryTime,
				ease = linear,
				holder = "From",
				grip = Vector2.new(1, 1),
			},
			{ -- 3. DROP: coming out of the turn, the same hand pushes it down across the front
				-- of the feet; it bounces just over on the new hand's side as the turn ends
				spot = Vector3.new(-Skills.SPIN_BOUNCE_ACROSS, Ball.RADIUS, Skills.SPIN_BOUNCE_FORWARD),
				duration = math.max(Skills.SPIN_DROP_TIME, 0.04),
				ease = easeIn,
				holder = "From",
				grip = Vector2.new(1, 0),
			},
			{ -- 4. CATCH: up off the bounce, with no hand on it, into the new hand
				spot = newHandCatch,
				duration = math.max(Skills.SPIN_RISE_TIME, 0.05),
				ease = easeOut,
				holder = nil,
				grip = Vector2.zero,
			},
		},
			5, -- the new hand only takes the ball after the exit bounce
			4 -- ...and only reaches for it once the drop starts (until then it's the arm bar)
	end
	if move == "Crossover" then
		-- The wide Iverson crossover (all values in Config/Skills.luau).
		local sell, catch = Skills.WIDE_SELL_SPOT, Skills.WIDE_CATCH_SPOT
		return {
			{ -- 1. sell: pulled out wide and low on its side, palm sliding round to the outside
				spot = sell,
				duration = Skills.WIDE_SELL_TIME,
				ease = ease,
				holder = "From",
				grip = Vector2.new(0, 1),
			},
			{ -- 2. pounded down to a low bounce on the centre line: the old hand keeps it
				-- through most of the push, on its upper-outside, and whips it away
				spot = Vector3.new(0, Ball.RADIUS, Skills.WIDE_BOUNCE_FORWARD),
				duration = Skills.WIDE_PUSH_TIME,
				ease = easeIn,
				holder = "From",
				holderUntil = Skills.WIDE_HOLD_SHARE,
				grip = Vector2.new(1, 1),
			},
			{ -- 3. up off the bounce, caught low outside the new foot (no hand on it)
				spot = Vector3.new(-catch.X, catch.Y, catch.Z),
				duration = Skills.WIDE_RISE_TIME,
				ease = easeOut,
				holder = nil,
				grip = Vector2.new(1, 1),
			},
			{ -- 4. carried back up into a normal dribble, palm sliding back on top
				spot = newHandTop,
				duration = Skills.WIDE_RECOVER_TIME,
				ease = ease,
				holder = "To",
				grip = Vector2.new(1, 0),
			},
		},
			3
	end
	-- HandSwitch: thrown down and across to a bounce on the centre line (the sending hand
	-- whips it from the upper-outside), up into the other hand, which waits low and meets
	-- it on the rise. A ball that's already low gets a shorter push down, so it always
	-- starts instantly.
	return {
		{
			spot = Vector3.new(0, Ball.RADIUS, Ball.SWITCH_FORWARD),
			duration = math.max(Ball.SWITCH_TIME * Ball.SWITCH_DOWN_SHARE * height, 0.04),
			ease = easeIn,
			holder = "From",
			grip = Vector2.new(Ball.SWITCH_GRIP_FROM, Ball.SWITCH_GRIP_TO),
		},
		{
			spot = newHandCatch,
			duration = math.max(Ball.SWITCH_TIME * (1 - Ball.SWITCH_DOWN_SHARE), 0.05),
			ease = easeOut,
			holder = nil,
			grip = Vector2.zero,
		},
	},
		2
end

-- Starts a move now. `waited` = seconds it was held back waiting for the hand to meet the
-- ball: the first leg is made that much shorter so the ball stays in step with the body,
-- which started its part of the move when the move was asked for.
local function beginMove(move: SkillMath.Move, waited: number)
	local parts = CharacterRef.get()
	if not parts then
		return
	end
	local floorY = floorHeight(parts)
	-- How far up its bounce the ball is (0 = floor, 1 = top of the ride).
	local topHeight = Ball.DRIBBLE_CATCH_HEIGHT + Ball.DRIBBLE_RIDE_UP
	local height = math.clamp((ball.Position.Y - floorY - Ball.RADIUS) / math.max(topHeight - Ball.RADIUS, 0.01), 0, 1)
	local path, catchAt, waitFrom = buildPath(move, height)
	if waited > 0 then
		path[1].duration = math.max(path[1].duration - waited, 0.04)
	end
	local otherHand: SkillMath.Hand = if hand == "Right" then "Left" else "Right"
	-- The ball's velocity relative to the body (so a running dribble's speed carries into the
	-- move), limited so a stray reading can't throw the ball.
	local relative = ballVelocity - MovementController.getVelocity()
	local carry = parts.root.CFrame:VectorToObjectSpace(relative)
	if carry.Magnitude > Ball.MOVE_MAX_CARRY_SPEED then
		carry = carry.Unit * Ball.MOVE_MAX_CARRY_SPEED
	end
	handMove = {
		move = move,
		fromHand = hand,
		toHand = if catchAt > 0 then otherHand else hand,
		startedAt = os.clock(),
		path = path,
		catchAt = catchAt,
		waitFrom = waitFrom or 1,
		endsInHand = path[#path].holder ~= nil,
		startVelocity = carry,
		legIndex = 0,
		legFromLocal = Vector3.zero,
		legFromWorld = ball.Position,
		freeTargets = {},
	}
end

-- Runs every frame: positions the ball for the current mode. `dt` = seconds since last frame.
local function update(dt: number)
	if dt > 0 then
		ballVelocity = (ball.Position - lastBallPosition) / dt
	end
	lastBallPosition = ball.Position

	if mode == "Flight" then
		local current = flight
		if current and current.scripted then
			fly(current)
		end
		return
	end
	local parts = CharacterRef.get()
	if not parts then
		return
	end

	local rootCFrame = parts.root.CFrame -- the character's hip position and facing
	if mode == "Held" then
		ball.CFrame = CFrame.new(gatherPosition(PostureController.getBodyCFrame(rootCFrame)))
		return
	end

	local floorY = floorHeight(parts)
	local crouch = crouchOf(parts)

	-- A move that was waiting for the hand to meet the ball starts once it does (or when it
	-- has waited long enough).
	local waiting = pendingMove
	if waiting and not handMove then
		local waited = os.clock() - waiting.since
		if cycleStage == "Ride" or cycleStage == "Push" or waited >= Ball.MOVE_MAX_WAIT then
			pendingMove = nil
			beginMove(waiting.move, waited)
		end
	end

	local current = handMove
	if current then
		if twisting then
			setTwist(0, 0) -- moves lean the body themselves (SkillController)
		end
		local position = handMovePosition(current, rootCFrame, floorY, crouch)
		if position then
			ball.CFrame = CFrame.new(position)
			return
		end
		-- Dribble move finished: carry on dribbling from where the move left the ball.
		endHandMove()
		needSettle = true
	end
	updateDribble(dt, rootCFrame, floorY)
end

-- Decides the shot (once) and schedules the ball's return to the player.
local function resolve(current: Flight, made: boolean)
	if current.resolved then
		return
	end
	current.resolved = true
	current.onResolved(made)

	returnToken += 1
	local token = returnToken
	task.delay(Ball.RETURN_DELAY, function()
		if token == returnToken then
			BallController.giveBack()
		end
	end)
end

-- Runs every frame after physics: watches the shot in the air for a make or a miss.
local function track()
	local current = flight
	if not current or current.resolved then
		return
	end

	local position = ball.Position
	local previous = current.previous
	current.previous = position

	-- MAKE: between last frame and this one, the ball dropped through the rim's height.
	-- Work out exactly where it crossed and check that point is inside the rim circle.
	local rim = Court.RIM_POSITION
	if previous.Y >= rim.Y and position.Y < rim.Y then
		local t = (previous.Y - rim.Y) / (previous.Y - position.Y)
		local crossing = previous:Lerp(position, t)
		local dx, dz = crossing.X - rim.X, crossing.Z - rim.Z
		if math.sqrt(dx * dx + dz * dz) < Court.RIM_INNER_RADIUS then
			resolve(current, true)
			return
		end
	end

	-- MISS: the ball is falling well below the rim, or the shot took too long.
	local fallingBelowRim = position.Y < previous.Y and position.Y < rim.Y - Ball.MISS_DEPTH
	if fallingBelowRim or os.clock() - current.startedAt > Ball.SHOT_TIMEOUT then
		resolve(current, false)
	end
end

-- True if the player has the ball (it isn't in the air).
function BallController.hasBall(): boolean
	return mode ~= "Flight"
end

-- Where the ball is right now.
function BallController.getPosition(): Vector3
	return ball.Position
end

-- What the ball is doing: "Dribble", "Held" or "Flight".
function BallController.getMode(): Mode
	return mode
end

-- Clock time of the most recent release.
function BallController.getLaunchTime(): number
	return launchedAt
end

-- The hand dribbling the ball: "Right" or "Left". During a dribble move it's still the hand
-- the ball started in, until the move ends.
function BallController.getHand(): SkillMath.Hand
	return hand
end

-- What the hands should be doing this frame: which one is on the ball, which one is
-- waiting to catch it and where, and how the palm holds it. See the Handling type.
function BallController.getHandling(): Handling
	return handling
end

-- True while a dribble move (hand switch, crossover, step-back, spin) is in progress, or has
-- been asked for and is waiting for the hand to meet the ball.
function BallController.isMoving(): boolean
	return handMove ~= nil or pendingMove ~= nil
end

-- Tells the ball a foot just touched the floor (LegController calls this on every plant:
-- walking, shuffling, scripted move steps and under the run animation). `side` = the foot,
-- `period` = the estimated seconds between consecutive plants (nil if unknown, e.g. just
-- starting to move). While dribbling and moving, the ball locks to these: one bounce per
-- two steps, hitting the floor with the right foot. Cheap, ignored outside a dribble, and
-- the dribble works fine if it is never called (it falls back to a speed-based rate).
function BallController.notifyFootPlant(side: SkillMath.Hand, period: number?)
	if mode ~= "Dribble" then
		return
	end
	lastPlantAt = os.clock()
	lastPlantSide = side
	stepPeriod = period
	plantToLock = if handMove then nil else side -- (a move controls the ball itself)
end

-- The latest foot plant: which foot, how many seconds ago, and the estimated seconds between
-- plants (nil if unknown or the last plant is too old). ArmController uses it to swing the
-- free arm opposite the legs when running.
function BallController.getFootfall(): (SkillMath.Hand?, number, number?)
	local since = os.clock() - lastPlantAt
	if since > Ball.DRIBBLE_FOOTFALL_STALE then
		return nil, since, nil
	end
	return lastPlantSide, since, stepPeriod
end

-- Starts a dribble move ("HandSwitch", "Crossover", "Stab", "StepBack" or "Spin"). Returns false
-- (and does nothing) unless the player is dribbling and not already mid-move. If the ball is in
-- flight (falling to the floor or rising to the hand) the move starts when the hand next
-- meets it, at most Ball.MOVE_MAX_WAIT later; either way this returns true.
function BallController.startMove(move: SkillMath.Move): boolean
	local parts = CharacterRef.get()
	if mode ~= "Dribble" or handMove or pendingMove or not parts then
		return false
	end
	if cycleStage == "Down" or cycleStage == "Up" then
		pendingMove = { move = move, since = os.clock() }
	else
		beginMove(move, 0)
	end
	return true
end

-- Which motion the current (or last) shot uses: "JumpShot", "Layup" or "Dunk".
function BallController.getStyle(): Shooting.MotionStyle
	return style
end

-- During the shooting motion: how far through the rise the ball is, 0 (in the pocket) to
-- 1 (at the release point), by time. ArmController uses it to turn the hands in step with
-- the ball (the same for every motion, so a dunk's hands reach their overhead pose with the
-- ball).
function BallController.getRise(): number
	return holdRise
end

-- Starts the shooting motion. Times are seconds from now (ShotController works them out
-- from the jump timing):
--   toPocket    – when the ball should be in the pocket (the bottom of the dip)
--   toRelease   – when it should reach the release point (the perfect release moment)
--   motionStyle – which motion's ball path to follow ("JumpShot", "Layup" or "Dunk")
--   options     – optional:
--     toSet     – when the player leaves the ground: the ball is at the SET point (forehead)
--                 then, and keeps rising to the release (arms and legs rise together). If
--                 missing, a share (Motion.SET_TIME_SHARE) of the way from pocket to release.
--     lowSwing  – a standing dunk: the ball swings DOWN toward the knees in the dip (instead
--                 of being gathered at the hip), then up fast overhead at takeoff.
function BallController.hold(
	toPocket: number,
	toRelease: number,
	motionStyle: Shooting.MotionStyle,
	options: HoldOptions?
)
	if mode ~= "Dribble" then
		return
	end
	style = motionStyle
	pendingMove = nil
	endHandMove() -- shooting out of a dribble move: the gather starts from wherever the ball is
	if twisting then
		setTwist(0, 0)
	end
	local parts = CharacterRef.get()
	if parts then
		gatherFrom = PostureController.getBodyCFrame(parts.root.CFrame):PointToObjectSpace(ball.Position)
	end
	gatherStartedAt = os.clock()
	local pocketTime = math.max(toPocket, 0.05)
	local releaseTime = math.max(toRelease, pocketTime + 0.1)
	local setTime = if options and options.toSet
		then options.toSet
		else pocketTime + (releaseTime - pocketTime) * Motion.SET_TIME_SHARE
	setTime = math.clamp(setTime, pocketTime + 0.03, releaseTime - 0.05)
	holdKeys = buildHoldKeys(motionStyle, pocketTime, setTime, releaseTime, options ~= nil and options.lowSwing == true)
	holdRise = 0
	mode = "Held"
end

-- Shoots the ball from where it is.
--   velocity    launch velocity, studs/s (solved by ShotMath.launchVelocity)
--   gravity     downward pull, studs/s² (Workspace.Gravity)
--   onResolved  called once with true (made) or false (missed)
function BallController.launch(velocity: Vector3, gravity: number, onResolved: (made: boolean) -> ())
	mode = "Flight"
	launchedAt = os.clock()
	local from = ball.Position
	flight = {
		origin = from,
		launchVelocity = velocity,
		gravity = gravity,
		scripted = true,
		previous = from,
		startedAt = os.clock(),
		resolved = false,
		onResolved = onResolved,
	}
end

-- Puts the ball back in the player's hands immediately.
function BallController.giveBack()
	returnToken += 1 -- cancels any pending return timer
	flight = nil
	pendingMove = nil
	endHandMove()
	-- The dribble picks up as the hand meets the ball, with no fade from the hoop.
	cyclePhase = 0
	cycleNudge = 0
	needSettle = false
	settleOffset = Vector3.zero
	mode = "Dribble"
	ball.Anchored = true
	ball.CanCollide = false
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
end

function BallController.start()
	ball = createBall()
	lastBallPosition = ball.Position
	rollJitter()
	CharacterRef.onSpawn(function()
		BallController.giveBack()
		hand = "Right"
	end)
	-- Positioning runs before each frame is drawn; make/miss tracking runs after physics.
	RunService:BindToRenderStep("RoHoopsBall", Enum.RenderPriority.Character.Value + 1, update)
	RunService.Heartbeat:Connect(track)
end

return BallController
