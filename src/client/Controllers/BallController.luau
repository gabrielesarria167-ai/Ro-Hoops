--!strict
-- BALL CONTROLLER
-- Owns the test ball and decides makes and misses. The ball is in one of three modes:
--   Dribble – bouncing beside the player (positioned by code, not physics), in the right
--             or left hand. A hand move (BallController.switchHands, started by
--             SkillController) carries it to the other hand along a few waypoints:
--               HandSwitch (H key)  – down and across, one bounce on the centre line, up
--                                     into the other hand;
--               Crossover (flick)   – the wide Iverson crossover: out wide on its side
--                                     (the sell), pounded down to a low bounce on the
--                                     centre line, caught wide and low on the other side,
--                                     then back up into a normal dribble.
--   Held    – the shooting motion while E is held: into the dip, then up to the release point
--             (a jump shot rises past the face to above the head; a layup is carried up
--             the right side to a high release in front)
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

-- One stop on a hand move's path. The ball travels from the previous stop to `spot`.
type Waypoint = {
	-- Where the ball arrives: (out, height, forward). `out` = studs toward the hand the
	-- ball STARTED in (negative = toward the new hand), height = studs above the floor,
	-- forward = studs in front of the hips. Measured from the hips every frame, so the
	-- path moves with the player.
	spot: Vector3,
	duration: number, -- seconds to get there
	ease: (number) -> number, -- how the speed changes along the way (0→1 in, 0→1 out)
	-- Which hand is on the ball on the way here: the one it started in, the new one, or
	-- none (bouncing between hands).
	holder: "From" | "To" | nil,
	-- How the palm holds the ball on the way here, from → to: 0 = on top (a dribble),
	-- 1 = on its outer side (pulling it wide / whipping it across).
	grip: Vector2,
}

-- A hand move in progress: the ball's trip from one hand to the other.
type HandMove = {
	move: SkillMath.Move, -- which move
	from: Vector3, -- where the ball was when the move started, relative to the hips
	fromHand: SkillMath.Hand, -- the hand it started in
	toHand: SkillMath.Hand, -- the hand it's going to
	startedAt: number, -- clock time the move started
	path: { Waypoint },
	catchAt: number, -- index of the waypoint where the new hand catches the ball
}

-- What the hands should be doing this frame (for ArmController).
export type Handling = {
	holder: SkillMath.Hand?, -- the hand on the ball (nil while it bounces between hands)
	waiting: SkillMath.Hand?, -- the hand waiting to catch it (nil when there's no hand move)
	waitPoint: Vector3?, -- where that hand waits: where the ball will arrive (world space)
	grip: number, -- 0 = palm on top of the ball (dribble), 1 = palm on its outer side
}

local BallController = {}

local ball: Part -- the ball part itself, created in start()
local mode: Mode = "Dribble" -- what the ball is doing right now
local dribblePhase = 0 -- 0 to 1 through the current bounce: 0 and 1 = on the floor, 0.5 = top
local flight: Flight? = nil -- the shot in the air, or nil
local launchedAt = 0 -- clock time of the last release (ArmController times the follow-through from it)

-- Dribbling hand and hand moves.
local hand: SkillMath.Hand = "Right" -- the hand dribbling the ball; switches at the end of a hand move
local handMove: HandMove? = nil -- the hand move in progress, or nil
-- What the hands should do this frame; updated every frame, read by ArmController.
local handling: Handling = { holder = "Right", grip = 0 }

-- The shooting motion (Held mode): dribble → dip pocket → release point.
local gatherStartedAt = 0 -- clock time when E was pressed
local pocketTime = 0.1 -- seconds after E until the ball is in the dip pocket (hips lowest)
local releaseTime = 1 -- seconds after E until the ball is at the release point (= the perfect release)
local gatherFrom = Vector3.zero -- ball position when E was pressed, relative to the hips
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

-- The three points of the current motion's ball path (Motion config, right/up/forward):
-- the pocket at the bottom of the dip, the point the rise bends toward, and the release.
local function pathPoints(): (Vector3, Vector3, Vector3)
	if style == "Layup" then
		return Motion.LAYUP_POCKET, Motion.LAYUP_RISE_BEND, Motion.LAYUP_RELEASE_POINT
	end
	return Motion.DIP_POCKET, Motion.RISE_BEND, Motion.RELEASE_POINT
end

-- Where the ball is during the shooting motion, relative to the body (so it moves, dips,
-- turns and leans with the player):
--   1. from where it was in the dribble into the pocket at the chest, arriving as the
--      hips reach the bottom of the dip;
--   2. then up along a curve (bent toward the bend point) to the release point, arriving
--      exactly at the perfect release moment.
local function gatherPosition(bodyCFrame: CFrame): Vector3
	local elapsed = os.clock() - gatherStartedAt
	local pocketPoint, bendPoint, releasePoint = pathPoints()
	local pocket = toObjectSpace(pocketPoint)
	local localPosition: Vector3
	if elapsed < pocketTime then
		localPosition = gatherFrom:Lerp(pocket, ease(elapsed / pocketTime))
	else
		local t = ease((elapsed - pocketTime) / math.max(releaseTime - pocketTime, 0.05))
		local u = 1 - t
		local bend = toObjectSpace(bendPoint)
		local release = toObjectSpace(releasePoint)
		-- Quadratic Bezier curve: pocket → (pulled toward bend) → release point.
		localPosition = pocket * (u * u) + bend * (2 * u * t) + release * (t * t)
	end
	return bodyCFrame:PointToWorldSpace(localPosition)
end

-- Height of the floor under the player (from the hips down).
local function floorHeight(parts: CharacterRef.Parts): number
	return parts.root.Position.Y - parts.humanoid.HipHeight - parts.root.Size.Y / 2
end

-- Where the dribbled ball is beside `side` hand at `bounce` height (0 = on the floor,
-- 1 = top of the bounce), in world space.
local function dribbleSpot(rootCFrame: CFrame, floorY: number, side: SkillMath.Hand, bounce: number): Vector3
	local sideSign = if side == "Right" then 1 else -1 -- the left hand mirrors the right
	local beside = rootCFrame.Position
		+ rootCFrame.RightVector * (Ball.DRIBBLE_SIDE * sideSign)
		+ rootCFrame.LookVector * Ball.DRIBBLE_FORWARD
	return Vector3.new(beside.X, floorY + Ball.RADIUS + bounce * Ball.DRIBBLE_HEIGHT, beside.Z)
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
-- hand, -1 if in the left; `floor` is the floor's height in the hips' space.
local function spotToLocal(spot: Vector3, fromSign: number, floor: number): Vector3
	return Vector3.new(spot.X * fromSign, floor + spot.Y, -spot.Z)
end

-- Where the ball is during a hand move (world space), or nil once it has finished. Also
-- fills in `handling` for ArmController.
local function handMovePosition(current: HandMove, rootCFrame: CFrame, floorY: number): Vector3?
	local fromSign = if current.fromHand == "Right" then 1 else -1
	local floor = floorY - rootCFrame.Position.Y -- the floor's height in the hips' space
	local elapsed = os.clock() - current.startedAt
	local previous = current.from
	for index, waypoint in current.path do
		local target = spotToLocal(waypoint.spot, fromSign, floor)
		if elapsed < waypoint.duration then
			local progress = elapsed / waypoint.duration
			handling.holder = if waypoint.holder == "From"
				then current.fromHand
				elseif waypoint.holder == "To" then current.toHand
				else nil
			-- Until the new hand has caught the ball it waits where the ball will arrive.
			if index <= current.catchAt then
				handling.waiting = current.toHand
				handling.waitPoint =
					rootCFrame:PointToWorldSpace(spotToLocal(current.path[current.catchAt].spot, fromSign, floor))
			else
				handling.waiting, handling.waitPoint = nil, nil
			end
			handling.grip = waypoint.grip.X + (waypoint.grip.Y - waypoint.grip.X) * progress
			return rootCFrame:PointToWorldSpace(previous:Lerp(target, waypoint.ease(progress)))
		end
		elapsed -= waypoint.duration
		previous = target
	end
	return nil
end

-- Stops any hand move. The ball belongs to the hand it was heading to.
local function endHandMove()
	local current = handMove
	if current then
		hand = current.toHand
	end
	handMove = nil
end

-- Runs every frame: positions the ball for the current mode. `dt` = seconds since last frame.
local function update(dt: number)
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
	local current = handMove
	if current then
		local position = handMovePosition(current, rootCFrame, floorY)
		if position then
			ball.CFrame = CFrame.new(position)
			return
		end
		-- Hand move finished: the ball is at the top of its bounce in the other hand, so
		-- carry on dribbling from the top (dribblePhase 0.5).
		endHandMove()
		dribblePhase = 0.5
	end
	handling.holder, handling.waiting, handling.waitPoint, handling.grip = hand, nil, nil, 0

	-- Dribble: one bounce per trip of dribblePhase from 0 to 1. Moving faster bounces faster.
	local speed = MovementController.getVelocity().Magnitude
	dribblePhase = (dribblePhase + dt * (Ball.DRIBBLE_RATE + speed * Ball.DRIBBLE_RATE_PER_SPEED)) % 1
	local bounce = math.sin(dribblePhase * math.pi) -- 0 on the floor, 1 at the top
	ball.CFrame = CFrame.new(dribbleSpot(rootCFrame, floorY, hand, bounce))
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

-- The hand dribbling the ball: "Right" or "Left". During a hand move it's still the hand
-- the ball started in, until the move ends.
function BallController.getHand(): SkillMath.Hand
	return hand
end

-- What the hands should be doing this frame: which one is on the ball, which one is
-- waiting to catch it and where, and how the palm holds it. See the Handling type.
function BallController.getHandling(): Handling
	return handling
end

-- True while a hand move (hand switch or crossover) is in progress.
function BallController.isSwitching(): boolean
	return handMove ~= nil
end

-- The path of each hand move, as a list of waypoints (see the Waypoint type).
-- `height` = how high the ball is in its bounce when the move starts (0 = floor, 1 = top).
local function buildPath(move: SkillMath.Move, height: number): ({ Waypoint }, number)
	local top = Ball.RADIUS + Ball.DRIBBLE_HEIGHT -- ball height at the top of a dribble
	-- The top of a dribble in the new hand (the move always ends there).
	local newHandTop = Vector3.new(-Ball.DRIBBLE_SIDE, top, Ball.DRIBBLE_FORWARD)
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
			{ -- 2. pounded down to a low bounce on the centre line
				spot = Vector3.new(0, Ball.RADIUS, Skills.WIDE_BOUNCE_FORWARD),
				duration = Skills.WIDE_PUSH_TIME,
				ease = easeIn,
				holder = nil,
				grip = Vector2.new(1, 1),
			},
			{ -- 3. up off the bounce, caught wide and low on the other side
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
	-- HandSwitch: down and across to a bounce on the centre line, up into the other hand.
	-- A ball that's already low gets a shorter push down, so it always starts instantly.
	return {
		{
			spot = Vector3.new(0, Ball.RADIUS, Ball.SWITCH_FORWARD),
			duration = math.max(Ball.SWITCH_TIME * Ball.SWITCH_DOWN_SHARE * height, 0.04),
			ease = linear,
			holder = "From",
			grip = Vector2.zero,
		},
		{
			spot = newHandTop,
			duration = math.max(Ball.SWITCH_TIME * (1 - Ball.SWITCH_DOWN_SHARE), 0.05),
			ease = easeOut,
			holder = nil,
			grip = Vector2.zero,
		},
	},
		2
end

-- Starts a hand move ("HandSwitch" or "Crossover") to the other hand. Returns false (and
-- does nothing) unless the player is dribbling and not already mid-move.
function BallController.switchHands(move: SkillMath.Move): boolean
	local parts = CharacterRef.get()
	if mode ~= "Dribble" or handMove or not parts then
		return false
	end
	local floorY = floorHeight(parts)
	local height = math.clamp((ball.Position.Y - floorY - Ball.RADIUS) / math.max(Ball.DRIBBLE_HEIGHT, 0.01), 0, 1)
	local path, catchAt = buildPath(move, height)
	handMove = {
		move = move,
		from = parts.root.CFrame:PointToObjectSpace(ball.Position),
		fromHand = hand,
		toHand = if hand == "Right" then "Left" else "Right",
		startedAt = os.clock(),
		path = path,
		catchAt = catchAt,
	}
	return true
end

-- Which motion the current (or last) shot uses: "JumpShot" or "Layup".
function BallController.getStyle(): Shooting.MotionStyle
	return style
end

-- During the shooting motion: how far the ball has risen from the pocket (0) to the
-- release point (1), by height. ArmController uses it to turn the shooting hand.
function BallController.getRise(bodyCFrame: CFrame): number
	local pocket, _, release = pathPoints()
	local height = bodyCFrame:PointToObjectSpace(ball.Position).Y
	return math.clamp((height - pocket.Y) / math.max(release.Y - pocket.Y, 0.01), 0, 1)
end

-- Starts the shooting motion. Both times are seconds from now (ShotController works them
-- out from the jump timing):
--   toPocket    – when the ball should be in the dip pocket (the bottom of the dip)
--   toRelease   – when it should reach the release point (the perfect release moment)
--   motionStyle – which motion's ball path to follow ("JumpShot" or "Layup")
function BallController.hold(toPocket: number, toRelease: number, motionStyle: Shooting.MotionStyle)
	if mode ~= "Dribble" then
		return
	end
	style = motionStyle
	endHandMove() -- shooting out of a hand move: the gather starts from wherever the ball is
	local parts = CharacterRef.get()
	if parts then
		gatherFrom = PostureController.getBodyCFrame(parts.root.CFrame):PointToObjectSpace(ball.Position)
	end
	gatherStartedAt = os.clock()
	pocketTime = math.max(toPocket, 0.05)
	releaseTime = math.max(toRelease, pocketTime + 0.05)
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
	endHandMove()
	mode = "Dribble"
	ball.Anchored = true
	ball.CanCollide = false
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
end

function BallController.start()
	ball = createBall()
	CharacterRef.onSpawn(function()
		BallController.giveBack()
		hand = "Right"
	end)
	-- Positioning runs before each frame is drawn; make/miss tracking runs after physics.
	RunService:BindToRenderStep("RoHoopsBall", Enum.RenderPriority.Character.Value + 1, update)
	RunService.Heartbeat:Connect(track)
end

return BallController
