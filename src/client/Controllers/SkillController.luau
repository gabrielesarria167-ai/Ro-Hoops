--!strict
-- SKILL CONTROLLER (dribble moves)
-- Inputs:
--   H key                          – HandSwitch: a quick, simple change of hands.
--   Flick toward the empty hand    – Crossover: the wide, Allen Iverson style crossover.
--   Flick backward                 – StepBack: one step back, pulling the ball with you.
--   Draw a circle                  – Spin: a 360 reverse pivot the way you drew it, handing
--                                    the ball to the other hand during the turn.
-- No button to hold; slow cursor movement does nothing.
--
-- Gestures:
--   1. every cursor movement is recorded (in screen heights, so any screen size works);
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
--   StepBack  – plant, lean back, one step straight back.
--   Spin      – plant, bend low, turn a full circle while sliding a short way sideways.
-- Every move takes at most one step, then movement goes back to the keys. The player keeps
-- facing the same way (apart from the spin's turn) during the move, and afterwards until
-- a movement key is pressed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Skills = require(ReplicatedStorage.Shared.Config.Skills)
local SkillMath = require(ReplicatedStorage.Shared.SkillMath)
local CharacterRef = require(script.Parent.Parent.CharacterRef)
local BallController = require(script.Parent.BallController)
local InputController = require(script.Parent.InputController)
local MovementController = require(script.Parent.MovementController)
local PostureController = require(script.Parent.PostureController)

-- Something the body does at a moment in a move.
type Beat = {
	at: number, -- seconds after the move starts
	run: (parts: CharacterRef.Parts) -> (),
}

-- A spin's turn: the body's facing is set every frame from this.
type Turn = {
	from: CFrame, -- facing (rotation only) when the turn started
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
-- True after a move until the player presses a movement key: the body keeps facing the
-- same way meanwhile, instead of swinging round to face the leftover momentum.
local holdFacing = false

-- A flat world velocity relative to `rootCFrame`: `side` studs/s toward its right
-- (negative = left) plus `forward` studs/s the way it faces.
local function bodyVelocity(rootCFrame: CFrame, side: number, forward: number): Vector3
	local right, look = rootCFrame.RightVector, rootCFrame.LookVector
	return Vector3.new(right.X, 0, right.Z).Unit * side + Vector3.new(look.X, 0, look.Z).Unit * forward
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

-- The body's beats for a move. `fromSign` = +1 if the ball is in the right hand, -1 if
-- left; `spinSign` = +1 for a counterclockwise spin, -1 for clockwise (spins only).
local function beatsFor(move: SkillMath.Move, fromSign: number, spinSign: number): ({ Beat }, number, Turn?)
	if move == "Crossover" then
		local toSign = -fromSign
		local sell = Skills.WIDE_SELL_TIME
		return {
			{ -- SELL: plant, lean over the ball and toward it.
				at = 0,
				run = function()
					plant()
					PostureController.leanTo(
						-Skills.WIDE_SELL_FORWARD_LEAN,
						sell,
						fromSign * Skills.WIDE_SELL_SIDE_LEAN
					)
				end,
			},
			{ -- EXPLODE: as the ball is pounded across, whip the lean over and step that way.
				at = sell,
				run = function(parts)
					PostureController.leanTo(
						-Skills.WIDE_CROSS_FORWARD_LEAN,
						Skills.WIDE_PUSH_TIME + Skills.WIDE_RISE_TIME,
						toSign * Skills.WIDE_CROSS_SIDE_LEAN
					)
					stepToward(bodyVelocity(parts.root.CFrame, toSign, Skills.WIDE_STEP_FORWARD))
				end,
			},
			{ at = sell + Skills.STEP_TIME, run = releaseFeet },
		},
			sell + Skills.WIDE_PUSH_TIME + Skills.WIDE_RISE_TIME + Skills.WIDE_RECOVER_TIME
	elseif move == "StepBack" then
		local plantTime = Skills.STEPBACK_PLANT_TIME
		return {
			{ -- Plant and lean back.
				at = 0,
				run = function()
					plant()
					PostureController.leanTo(Skills.STEPBACK_LEAN, plantTime + Skills.STEP_TIME, 0)
				end,
			},
			{ -- One step straight back.
				at = plantTime,
				run = function(parts)
					stepToward(bodyVelocity(parts.root.CFrame, 0, -1))
				end,
			},
			{ at = plantTime + Skills.STEP_TIME, run = releaseFeet },
		},
			math.max(Skills.STEPBACK_PULL_TIME + Skills.STEPBACK_RISE_TIME, plantTime + Skills.STEP_TIME)
	elseif move == "Spin" then
		local gather, spinTime = Skills.SPIN_GATHER_TIME, Skills.SPIN_TIME
		-- A clockwise spin (spinSign -1) slides left, counterclockwise slides right.
		local slideSign = spinSign
		local turn: Turn = {
			from = CFrame.identity, -- filled in when the move starts
			startsAt = gather,
			duration = spinTime,
			radians = spinSign * math.rad(Skills.SPIN_DEGREES),
		}
		return {
			{ -- Plant and get low while the ball comes in to the hip.
				at = 0,
				run = function()
					plant()
					PostureController.leanTo(-Skills.SPIN_LEAN, gather, 0)
				end,
			},
			{ -- Turn (see `turn`) while sliding sideways, in the direction faced at the start.
				at = gather,
				run = function()
					local slide = bodyVelocity(turn.from, slideSign, 0) * (Skills.SPIN_SLIDE / math.max(spinTime, 0.05))
					MovementController.setOverride(slide, Skills.STEP_RATE)
				end,
			},
			{ at = gather + spinTime, run = releaseFeet },
		},
			gather + spinTime + Skills.SPIN_DROP_TIME + Skills.SPIN_RISE_TIME,
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
	end
	-- We control the facing during the move.
	parts.humanoid.AutoRotate = false
	body = { startedAt = os.clock(), beats = beats, nextBeat = 1, total = total, turn = turn }
end

-- Runs every frame: moves the body through the current move's beats.
local function step()
	local parts = CharacterRef.get()
	if not parts then
		return
	end
	-- A shot took over (it handles turning itself), or the player pressed a movement key:
	-- turning toward the movement direction can resume.
	if holdFacing then
		if BallController.getMode() ~= "Dribble" then
			holdFacing = false
		elseif InputController.getMoveIntent().Magnitude > 0 then
			holdFacing = false
			parts.humanoid.AutoRotate = true
		end
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
		return
	end

	local elapsed = os.clock() - current.startedAt
	while current.nextBeat <= #current.beats and elapsed >= current.beats[current.nextBeat].at do
		current.beats[current.nextBeat].run(parts)
		current.nextBeat += 1
	end

	-- The spin's turn: set the facing directly (smooth start and stop).
	local turn = current.turn
	if turn and elapsed >= turn.startsAt then
		local progress = math.clamp((elapsed - turn.startsAt) / math.max(turn.duration, 0.05), 0, 1)
		local eased = progress * progress * (3 - 2 * progress)
		local root = parts.root
		root.CFrame = CFrame.new(root.Position) * turn.from * CFrame.Angles(0, turn.radians * eased, 0)
	end

	if elapsed >= current.total then
		-- Done: straighten up, movement back to the keys. Keep facing the same way until a
		-- movement key is pressed (see holdFacing).
		body = nil
		PostureController.leanTo(0, Skills.WIDE_LEAN_RECOVER_TIME)
		releaseFeet()
		holdFacing = true
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

-- Records a cursor position as part of the current stroke.
local function onCursorMoved(position: Vector3)
	local screenHeight = math.max(workspace.CurrentCamera.ViewportSize.Y, 1)
	local now = os.clock()
	-- Screen y grows downward; flip it so up is positive.
	table.insert(samples, { t = now, x = position.X / screenHeight, y = -position.Y / screenHeight })
	-- Keep only as much as the longest check needs.
	local keep = math.max(Skills.CIRCLE_WINDOW, Skills.SWIPE_WINDOW)
	while #samples > 0 and now - samples[1].t > keep do
		table.remove(samples, 1)
	end
end

function SkillController.start()
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			onCursorMoved(input.Position)
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
		holdFacing = false
	end)
	-- "Input + 3" priority: after MovementController and ShotController each frame.
	RunService:BindToRenderStep("RoHoopsSkills", Enum.RenderPriority.Input.Value + 3, function()
		-- The cursor has been still long enough: the stroke is over.
		local last = samples[#samples]
		if last and os.clock() - last.t >= Skills.STROKE_END_GAP then
			endStroke()
		end
		step()
	end)
end

return SkillController
