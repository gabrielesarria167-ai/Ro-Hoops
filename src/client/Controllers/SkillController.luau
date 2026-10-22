--!strict
-- SKILL CONTROLLER (dribble moves)
-- Inputs:
--   H key                          – HandSwitch: a quick, simple change of hands.
--   Flick toward the empty hand    – Crossover: the wide, Allen Iverson style crossover.
--   Flick toward the ball's hand   – Stab: a hard dribble out to that hand's side,
--                                    stepping that way.
--   Flick backward                 – StepBack: one step back, pulling the ball with you.
--   Draw a circle (a quick half     – Spin: a 360 reverse pivot the way you drew it; the
--   circle is enough)                  ball hand pulls the ball round, bounces it as the
--                                    turn ends, and the other hand takes it off the bounce.
-- No button to hold; slow cursor movement does nothing.
--
-- The mouse is locked in the middle of the screen (crosshair style, see lockMouse; the
-- crosshair itself is drawn by HudController). It can't move, but Roblox still reports
-- how far it WOULD have moved (InputObject.Delta), so every movement is added to a virtual
-- cursor (cursorX / cursorY) and the gestures are read from that path.
--
-- Gestures:
--   1. every virtual cursor movement is recorded (in screen heights, so any screen size works);
--   2. once the cursor stops (STROKE_END_GAP with no movement) the whole stroke is judged:
--      SkillMath.detectCircle first (a circle is a spin), then SkillMath.detectSwipe (a
--      fast straight stroke is a flick). Judging the whole stroke is what stops the start
--      of a circle being read as a flick;
--   3. a flick is turned from a screen direction into the player's own directions (toward
--      their right / the way they face), so "flick left" sends the ball toward the left
--      of the screen whichever way the player is facing, and SkillMath.chooseMove picks
--      the move;
--   4. BallController moves the ball; this controller moves the body in time with it.
--
-- The body follows a short timeline of "beats" per move (values in Config/Skills.luau):
--   Crossover – SELL: plant, lean over the ball and toward it. EXPLODE: whip the lean to
--               the new side and take one step that way.
--   Stab      – lean into the ball's side and step that way as the ball is pounded out.
--   StepBack  – plant, lean back, one step straight back.
--   Spin      – plant (while the ball is pounded), bend low, then turn a full circle AROUND
--               the planted pivot foot (the hips orbit it and drift Footwork.SPIN_TRAVEL
--               toward its side); the head leads the turn.
-- The feet are placed by LegController, following each move's real-life footwork
-- (Config/Footwork.luau, MOVE FOOTWORK): e.g. the crossover's jab, head fake and push-off,
-- the step-back's flat hop and "1-2" landing, the spin's pivot foot (twisting on the ball
-- of the foot) and low swing leg. Move beat times come from Config/Skills.luau (the shared
-- clock with BallController); foot and head values from Config/Footwork.luau.
-- Every move takes at most one step, then movement goes back to the keys. The body keeps
-- facing the rim throughout (MovementController.faceRim), apart from the spin's turn,
-- which sets the facing itself every frame and ends facing the same way it started.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Footwork = require(ReplicatedStorage.Shared.Config.Footwork)
local Skills = require(ReplicatedStorage.Shared.Config.Skills)
local GaitMath = require(ReplicatedStorage.Shared.GaitMath)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local BallController = require(script.Parent.BallController)
local LegController = require(script.Parent.LegController)
local MovementController = require(script.Parent.MovementController)
local PostureController = require(script.Parent.PostureController)

-- Something the body does at a moment in a move.
type Beat = {
	at: number, -- seconds after the move starts
	run: (parts: CharacterRef.Parts) -> (),
}

-- A spin's turn: the body's facing AND position are set every frame from this. The body
-- turns around its planted pivot foot (see GaitMath.spinHips).
type Turn = {
	from: CFrame, -- facing (rotation only) when the turn started
	startPosition: Vector3, -- where the hips were when the move started (flat)
	pivot: Vector3?, -- the ball of the pivot foot (flat world), set when the turn starts
	startsAt: number, -- seconds after the move starts
	duration: number, -- seconds for the whole turn
	radians: number, -- how far to turn (positive = counterclockwise from above)
}

-- The body side of a dribble move in progress.
type BodyMove = {
	startedAt: number, -- clock time the move started
	beats: { Beat }, -- in time order
	nextBeat: number, -- index of the next beat to run
	total: number, -- seconds until the move is over
	turn: Turn?, -- the spin's turn, or nil
}

local SWITCH_KEY = Enum.KeyCode.H -- change this to rebind the quick hand switch

local SkillController = {}

-- The current stroke's cursor readings, oldest first (at most CIRCLE_WINDOW seconds' worth).
local samples: { SkillMath.Sample } = {}
local body: BodyMove? = nil -- the dribble move's body motion, or nil
-- The virtual cursor, pixels: where the mouse would be if it weren't locked in the middle.
-- Only changes between readings matter, so it starts at 0, 0 and is never reset.
local cursorX, cursorY = 0, 0

-- A flat world velocity relative to `rootCFrame`: `side` studs/s toward its right
-- (negative = left) plus `forward` studs/s the way it faces.
local function bodyVelocity(rootCFrame: CFrame, side: number, forward: number): Vector3
	local right, look = rootCFrame.RightVector, rootCFrame.LookVector
	return Vector3.new(right.X, 0, right.Z).Unit * side + Vector3.new(look.X, 0, look.Z).Unit * forward
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Footwork shared by every move (Config/Skills.luau, FOOTWORK).
local function plant() -- stop dead
	MovementController.setOverride(Vector3.zero, Skills.STEP_RATE)
end
local function stepToward(direction: Vector3) -- one quick step in a flat world direction
	MovementController.setOverride(direction.Unit * Skills.STEP_SPEED, Skills.STEP_RATE)
end
local function releaseFeet() -- movement back to the keys (no key held = slow to a stop)
	MovementController.setOverride(nil)
end

-- Footwork helpers (LegController places the feet; Config/Footwork.luau).
-- Half the stance width: how far each foot normally is from the middle of the hips.
local function halfStance(): number
	return Footwork.STANCE_WIDTH / 2
end
local function sideName(sign: number): SkillMath.Hand
	return if sign > 0 then "Right" else "Left"
end
-- Takes the feet over for a move: no automatic steps, hips `extraCrouch` studs lower.
local function scriptFeet(extraCrouch: number)
	LegController.setScripted(true)
	LegController.setMoveCrouch(extraCrouch)
end
-- Gives the feet back to the automatic footwork (which then tidies up the stance).
local function unscriptFeet()
	LegController.setScripted(false)
	LegController.setMoveCrouch(0)
end
-- Steps the foot on `sign`'s side (+1 right, -1 left) so it lands beside the hips (as
-- they are when it lands): the normal stance width plus `out` studs further out that side,
-- `forward` studs ahead. `frame` / `bulge`: see LegController.stepFoot.
local function stepFoot(
	sign: number,
	out: number,
	forward: number,
	duration: number,
	lift: number,
	frame: CFrame?,
	bulge: Vector3?
)
	local offset = Vector3.new(sign * (halfStance() + out), 0, forward)
	LegController.stepFoot(sideName(sign), offset, duration, lift, frame, bulge)
end

-- Where the hips are `t` seconds after a spin starts (flat world position): the body turns
-- around the ball of the pivot foot while the weight moves over it and carries on past it
-- (Footwork.SPIN_TRAVEL in all). GaitMath.spinHips does the geometry.
local function spinHipsAt(turn: Turn, pivot: Vector3, t: number): Vector3
	local progress = math.clamp((t - turn.startsAt) / math.max(turn.duration, 0.05), 0, 1)
	local angle = turn.radians * GaitMath.turnProgress(progress)
	local shift = GaitMath.spinShift(progress, Footwork.SPIN_SHIFT_SHARPNESS)
	local x, z = GaitMath.spinHips(
		pivot.X,
		pivot.Z,
		turn.startPosition.X,
		turn.startPosition.Z,
		Footwork.SPIN_TRAVEL,
		shift,
		angle
	)
	return Vector3.new(x, 0, z)
end

-- The body's beats for a move. `fromSign` = +1 if the ball is in the right hand, -1 if
-- left; `spinSign` = +1 for a counterclockwise spin, -1 for clockwise (spins only).
local function beatsFor(move: SkillMath.Move, fromSign: number, spinSign: number): ({ Beat }, number, Turn?)
	local stagger = Footwork.STAGGER / 2 -- the ball-side foot ends this far back, the other this far forward
	if move == "Crossover" then
		local toSign = -fromSign
		local sell = Skills.WIDE_SELL_TIME
		local trailLeaves = sell + Footwork.CROSS_TRAIL_DELAY
		return {
			{ -- SELL: plant, crouch low and lean over the ball and toward it; the ball-side
				-- foot jabs out diagonally (the fake) and the head turns to look that way.
				at = 0,
				run = function()
					plant()
					PostureController.leanTo(
						-Skills.WIDE_SELL_FORWARD_LEAN,
						sell,
						fromSign * Skills.WIDE_SELL_SIDE_LEAN
					)
					scriptFeet(Footwork.CROSS_CROUCH)
					stepFoot(
						fromSign,
						Footwork.CROSS_JAB_OUT,
						Footwork.CROSS_JAB_FORWARD,
						Footwork.CROSS_JAB_TIME,
						Footwork.MIN_LIFT * 2
					)
					PostureController.setHeadTurn(fromSign * Footwork.CROSS_HEAD_FAKE, Footwork.CROSS_HEAD_FAKE_TIME)
				end,
			},
			{ -- The head snaps the other way just before the ball is pounded across.
				at = math.max(sell - Footwork.CROSS_HEAD_SNAP_TIME, Footwork.CROSS_HEAD_FAKE_TIME),
				run = function()
					PostureController.setHeadTurn(-fromSign * Footwork.CROSS_HEAD_SNAP, Footwork.CROSS_HEAD_SNAP_TIME)
				end,
			},
			{ -- EXPLODE: as the ball is pounded across, whip the lean over and push off the
				-- jab foot: the new-side foot steps out the new way (it's the new ball hand's
				-- side, so it ends slightly back)...
				at = sell,
				run = function(parts)
					PostureController.leanTo(
						-Skills.WIDE_CROSS_FORWARD_LEAN,
						Skills.WIDE_PUSH_TIME + Skills.WIDE_RISE_TIME,
						toSign * Skills.WIDE_CROSS_SIDE_LEAN
					)
					stepToward(bodyVelocity(parts.root.CFrame, toSign, Skills.WIDE_STEP_FORWARD))
					stepFoot(toSign, 0, -stagger, Footwork.CROSS_LEAD_TIME, Footwork.MAX_LIFT * 0.7)
				end,
			},
			{ -- ...and the push foot follows (a quick bound).
				at = trailLeaves,
				run = function()
					stepFoot(fromSign, 0, stagger, Footwork.CROSS_TRAIL_TIME, Footwork.MAX_LIFT * 0.6)
				end,
			},
			{ -- The head comes back to the front once the ball has crossed.
				at = sell + Skills.WIDE_PUSH_TIME,
				run = function()
					PostureController.setHeadTurn(0, Skills.WIDE_RISE_TIME + Skills.WIDE_RECOVER_TIME * 0.5)
				end,
			},
			{ at = sell + Skills.STEP_TIME, run = releaseFeet },
			{ at = trailLeaves + Footwork.CROSS_TRAIL_TIME, run = unscriptFeet },
		},
			sell + Skills.WIDE_PUSH_TIME + Skills.WIDE_RISE_TIME + Skills.WIDE_RECOVER_TIME
	elseif move == "Stab" then
		local stabTime = Skills.STAB_PUSH_TIME + Skills.STAB_RISE_TIME
		return {
			{ -- Lean into the ball's side and step that way, straight away: the ball-side
				-- foot stabs out-forward to that side, landing as the ball bounces (it takes
				-- as long as the ball's push down)...
				at = 0,
				run = function(parts)
					PostureController.leanTo(
						-Skills.STAB_FORWARD_LEAN,
						Skills.STAB_PUSH_TIME,
						fromSign * Skills.STAB_SIDE_LEAN
					)
					stepToward(bodyVelocity(parts.root.CFrame, fromSign, Skills.STAB_STEP_FORWARD))
					scriptFeet(Footwork.STAB_CROUCH)
					stepFoot(
						fromSign,
						Footwork.STAB_OUT,
						Footwork.STAB_FORWARD,
						Skills.STAB_PUSH_TIME,
						Footwork.MAX_LIFT * 0.5
					)
				end,
			},
			{ -- ...and the other foot only recovers to the stance (push, pull, recover; never crossing).
				at = Footwork.STAB_TRAIL_DELAY,
				run = function()
					stepFoot(-fromSign, 0, stagger, Footwork.STAB_TRAIL_TIME, Footwork.MIN_LIFT * 2)
				end,
			},
			{ at = Skills.STEP_TIME, run = releaseFeet },
			{ at = Footwork.STAB_TRAIL_DELAY + Footwork.STAB_TRAIL_TIME, run = unscriptFeet },
		},
			math.max(stabTime, Skills.STEP_TIME)
	elseif move == "StepBack" then
		local plantTime = Skills.STEPBACK_PLANT_TIME
		local frontLeaves = plantTime + Footwork.STEPBACK_FRONT_FOOT_DELAY
		local backLands = plantTime + Footwork.STEPBACK_BACK_FOOT_TIME
		return {
			{ -- Plant the front (off) foot hard and lean back.
				at = 0,
				run = function()
					plant()
					PostureController.leanTo(Skills.STEPBACK_LEAN, plantTime + Skills.STEP_TIME, 0)
					scriptFeet(Footwork.STEPBACK_CROUCH)
					stepFoot(
						-fromSign,
						0,
						Footwork.STEPBACK_PLANT_FORWARD,
						Footwork.STEPBACK_PLANT_FOOT_TIME,
						Footwork.MIN_LIFT
					)
				end,
			},
			{ -- Push back off it: one step straight back, landing on both feet, back (ball-
				-- side) foot first...
				at = plantTime,
				run = function(parts)
					stepToward(bodyVelocity(parts.root.CFrame, 0, -1))
					stepFoot(fromSign, 0, -stagger, Footwork.STEPBACK_BACK_FOOT_TIME, Footwork.STEPBACK_LIFT)
				end,
			},
			{ -- ...then the front foot ("1-2"). Both feet are off the floor now: a low, flat hop
				-- (the hips come up a little, but nowhere near a jump).
				at = frontLeaves,
				run = function()
					stepFoot(-fromSign, 0, stagger, Footwork.STEPBACK_FRONT_FOOT_TIME, Footwork.STEPBACK_LIFT * 0.8)
					LegController.setMoveCrouch(Footwork.STEPBACK_CROUCH - Footwork.STEPBACK_HOP_RISE)
				end,
			},
			{ -- The back foot lands: the knees take the landing.
				at = backLands,
				run = function()
					LegController.setMoveCrouch(Footwork.STEPBACK_CROUCH)
					LegController.absorbLanding(Footwork.STEPBACK_LAND_STRENGTH)
				end,
			},
			{ at = plantTime + Skills.STEP_TIME, run = releaseFeet },
			{
				at = math.max(backLands, frontLeaves + Footwork.STEPBACK_FRONT_FOOT_TIME),
				run = unscriptFeet,
			},
		},
			math.max(Skills.STEPBACK_PULL_TIME + Skills.STEPBACK_RISE_TIME, plantTime + Skills.STEP_TIME)
	elseif move == "Spin" then
		local gather, spinTime = Skills.SPIN_GATHER_TIME, Skills.SPIN_TIME
		-- The pivot foot is on the side the body drifts toward: a clockwise spin (spinSign -1)
		-- pivots on the left foot, counterclockwise on the right.
		local slideSign = spinSign
		local pivotSide, swingSide = sideName(slideSign), sideName(-slideSign)
		local turn: Turn = {
			from = CFrame.identity, -- filled in when the move starts
			startPosition = Vector3.zero, -- (same)
			pivot = nil,
			startsAt = gather,
			duration = spinTime,
			radians = spinSign * math.rad(Skills.SPIN_DEGREES),
		}
		local swingLands = Footwork.SPIN_SWING_LANDS_AT * spinTime
		local pivotLeaves = gather + Footwork.SPIN_PIVOT_LIFTS_AT * spinTime
		local pivotTime = math.max(Footwork.SPIN_PIVOT_LANDS_AT - Footwork.SPIN_PIVOT_LIFTS_AT, 0.05) * spinTime
		return {
			{ -- Plant and get low while the ball comes in to the hip. The head turns first,
				-- looking where the body is about to go.
				at = 0,
				run = function()
					plant()
					PostureController.leanTo(-Skills.SPIN_LEAN, gather, 0)
					scriptFeet(Footwork.SPIN_CROUCH)
					PostureController.setHeadTurn(-spinSign * Footwork.SPIN_HEAD_LEAD, gather)
				end,
			},
			{ -- Turn (see `turn`) around the pivot foot, which stays planted and twists on the
				-- ball of the foot. The other leg swings round low and behind, and lands before
				-- the pivot foot comes off the floor.
				at = gather,
				run = function(parts: CharacterRef.Parts)
					-- Re-read where the body is now: plant() brakes over the gather, so from a run
					-- the hips can slide ~1 stud after the move started. Using the start-of-move
					-- spot would snap the body back when the turn begins.
					turn.from = parts.root.CFrame.Rotation
					turn.startPosition = flat(parts.root.Position)
					local right0, look0 = flat(turn.from.RightVector), flat(turn.from.LookVector)
					local ball = LegController.pivotFoot(pivotSide, true)
						or (turn.startPosition + right0 * (slideSign * halfStance()))
					turn.pivot = ball
					-- Tell the legs where the hips are going, so steps land where the body will be.
					local startedAt = os.clock()
					LegController.setHipsPath(function(seconds: number)
						return spinHipsAt(turn, ball, gather + os.clock() - startedAt + seconds)
					end)
					local hipsEnd = spinHipsAt(turn, ball, gather + spinTime)
					local swingSpot = hipsEnd
						- right0 * (slideSign * halfStance())
						+ look0 * Footwork.SPIN_SWING_FORWARD
					LegController.stepFootTo(
						swingSide,
						swingSpot,
						swingLands,
						Footwork.SPIN_LIFT,
						Vector3.new(0, 0, -Footwork.SPIN_SWING_BULGE), -- behind the body, turning with it
						true
					)
				end,
			},
			{ -- The head has finished its lead: it comes back to the front as the body catches up.
				at = gather + 0.35 * spinTime,
				run = function()
					PostureController.setHeadTurn(0, 0.35 * spinTime)
				end,
			},
			{ -- The pivot foot comes off the floor and steps through to finish the stance.
				at = pivotLeaves,
				run = function()
					LegController.pivotFoot(pivotSide, false)
					local pivot = turn.pivot
					if pivot then
						local hipsEnd = spinHipsAt(turn, pivot, gather + spinTime)
						local right0 = flat(turn.from.RightVector)
						LegController.stepFootTo(
							pivotSide,
							hipsEnd + right0 * (slideSign * halfStance()),
							pivotTime,
							Footwork.SPIN_LIFT * 0.7
						)
					end
				end,
			},
			{ at = gather + spinTime, run = releaseFeet },
			{ at = math.max(gather + spinTime, pivotLeaves + pivotTime), run = unscriptFeet },
		},
			-- The ball's exit bounce lands as the turn ends; the move is over once the new
			-- hand has it (BallController, Spin).
			gather + spinTime + Skills.SPIN_RISE_TIME,
			turn
	end
	return {}, 0, nil -- HandSwitch: the body doesn't move
end

-- Starts a move: the ball (BallController) and, for moves that have one, the body.
-- `spinSign` = +1 for a counterclockwise spin, -1 for clockwise (spins only).
local function startMove(move: SkillMath.Move, spinSign: number?)
	local parts = CharacterRef.get()
	local fromHand = BallController.getHand()
	if not parts or not BallController.startMove(move) then
		return
	end
	local beats, total, turn = beatsFor(move, if fromHand == "Right" then 1 else -1, spinSign or 1)
	if #beats == 0 then
		return
	end
	if turn then
		turn.from = parts.root.CFrame.Rotation
		turn.startPosition = flat(parts.root.Position)
	end
	-- Beats run in time order (tuning can reorder them), and the move lasts until its last one.
	table.sort(beats, function(a, b)
		return a.at < b.at
	end)
	total = math.max(total, beats[#beats].at)
	body = { startedAt = os.clock(), beats = beats, nextBeat = 1, total = total, turn = turn }
end

-- Runs every frame: moves the body through the current move's beats.
local function step()
	local parts = CharacterRef.get()
	if not parts then
		return
	end
	local current = body
	if not current then
		return
	end
	-- A shot started mid-move: the shot takes over the movement and turning, so just start
	-- straightening up.
	if BallController.getMode() ~= "Dribble" then
		body = nil
		PostureController.leanTo(0, Skills.WIDE_LEAN_RECOVER_TIME)
		PostureController.setHeadTurn(0, 0.15) -- a spin/crossover head lead mustn't stay on
		unscriptFeet()
		return
	end

	local elapsed = os.clock() - current.startedAt
	while current.nextBeat <= #current.beats and elapsed >= current.beats[current.nextBeat].at do
		current.beats[current.nextBeat].run(parts)
		current.nextBeat += 1
	end

	-- The spin's turn: set the facing directly (fast start, easing into the end), and the
	-- position too, because the body turns around its pivot foot rather than on the spot.
	-- (Only while turning: once the turn is done, movement is already handed back
	-- (releaseFeet), so writing the root here would freeze the player until the ball's
	-- exit bounce is caught.)
	local turn = current.turn
	if turn and elapsed >= turn.startsAt and elapsed <= turn.startsAt + turn.duration then
		local progress = math.clamp((elapsed - turn.startsAt) / math.max(turn.duration, 0.05), 0, 1)
		local angle = turn.radians * GaitMath.turnProgress(progress)
		local root = parts.root
		local position = root.Position
		local pivot = turn.pivot
		if pivot then
			local hips = spinHipsAt(turn, pivot, elapsed)
			position = Vector3.new(hips.X, position.Y, hips.Z)
		end
		root.CFrame = CFrame.new(position) * turn.from * CFrame.Angles(0, angle, 0)
	end

	if elapsed >= current.total then
		-- Done: straighten up, movement and feet back to normal.
		body = nil
		PostureController.leanTo(0, Skills.WIDE_LEAN_RECOVER_TIME)
		releaseFeet()
		unscriptFeet()
	end
end

-- Turns a flick (screen heights, x = right, y = up) into a move and performs it.
local function onFlick(dx: number, dy: number)
	local parts = CharacterRef.get()
	if not parts then
		return
	end
	-- Screen direction → direction on the court → the player's own right / forward.
	local screenUp, screenRight = MovementController.getScreenAxes()
	local onCourt = screenRight * dx + screenUp * dy
	local rootCFrame = parts.root.CFrame
	local towardRight = onCourt:Dot(rootCFrame.RightVector)
	local towardForward = onCourt:Dot(rootCFrame.LookVector)

	local move = SkillMath.chooseMove(towardRight, towardForward, BallController.getHand(), Skills)
	if move then
		startMove(move)
	end
end

-- The cursor stopped: judge the stroke it just made, then start a new one.
local function endStroke()
	local spinSign = SkillMath.detectCircle(samples, Skills)
	local dx, dy = SkillMath.detectSwipe(samples, Skills)
	table.clear(samples)
	if spinSign then
		startMove("Spin", spinSign)
	elseif dx and dy then
		onFlick(dx, dy)
	end
end

-- Moves the virtual cursor by one mouse movement (`delta`, pixels, y pointing down) and
-- records where it ends up as part of the current stroke.
local function onCursorMoved(delta: Vector3)
	cursorX += delta.X
	cursorY += delta.Y
	local screenHeight = math.max(workspace.CurrentCamera.ViewportSize.Y, 1)
	local now = os.clock()
	-- Screen y grows downward; flip it so up is positive.
	table.insert(samples, { t = now, x = cursorX / screenHeight, y = -cursorY / screenHeight })
	-- Keep only as much as the longest check needs.
	local keep = math.max(Skills.CIRCLE_WINDOW, Skills.SWIPE_WINDOW)
	while #samples > 0 and now - samples[1].t > keep do
		table.remove(samples, 1)
	end
end

-- Keeps the mouse locked in the middle of the screen with the system pointer hidden (the
-- HUD draws a crosshair there instead). Run every frame: Roblox unlocks the mouse while its
-- menu (Esc) is open, and this locks it again as soon as the game has it back.
local function lockMouse()
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
	if UserInputService.MouseIconEnabled then
		UserInputService.MouseIconEnabled = false
	end
end

-- Performs `move` straight away, as if its gesture had been made (`spinSign` +1 =
-- counterclockwise spin, -1 = clockwise; spins only). For other input methods, e.g. a
-- gamepad later.
function SkillController.perform(move: SkillMath.Move, spinSign: number?)
	startMove(move, spinSign)
end

function SkillController.start()
	-- Studio only: ReplicatedStorage.RoHoopsPerformMove lets you try a move from the command
	-- bar while playing (client view), e.g.
	--   game.ReplicatedStorage.RoHoopsPerformMove:Fire("Spin", -1)
	if RunService:IsStudio() then
		local performEvent = Instance.new("BindableEvent")
		performEvent.Name = "RoHoopsPerformMove"
		performEvent.Event:Connect(function(move: SkillMath.Move, spinSign: number?)
			SkillController.perform(move, spinSign)
		end)
		performEvent.Parent = ReplicatedStorage
	end

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			-- Delta = how far the mouse moved this time; it still works while the mouse is
			-- locked (Position doesn't: it stays in the middle).
			onCursorMoved(input.Delta)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- gameProcessed = the key was used by Roblox UI (e.g. typing in chat), so ignore it.
		if not gameProcessed and input.KeyCode == SWITCH_KEY then
			startMove("HandSwitch")
		end
	end)
	CharacterRef.onSpawn(function()
		table.clear(samples)
		body = nil
	end)
	-- "Input + 3" priority: after MovementController and ShotController each frame.
	RunService:BindToRenderStep("RoHoopsSkills", Enum.RenderPriority.Input.Value + 3, function()
		lockMouse()
		-- The cursor has been still long enough: the stroke is over.
		local last = samples[#samples]
		if last and os.clock() - last.t >= Skills.STROKE_END_GAP then
			endStroke()
		end
		step()
	end)
end

return SkillController
