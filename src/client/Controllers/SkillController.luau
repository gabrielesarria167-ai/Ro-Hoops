--!strict
-- SKILL CONTROLLER (dribble moves)
-- Two ways to change hands:
--   H key                  – HandSwitch: a quick, simple change of hands.
--   Mouse / trackpad flick – Crossover: the wide, Allen Iverson style crossover. Flick
--                            toward the empty hand (no button to hold; slow cursor
--                            movement does nothing).
-- Flicks:
--   1. every cursor movement is recorded (in screen heights, so any screen size works),
--   2. SkillMath.detectSwipe decides whether the last fraction of a second was a flick,
--   3. the flick is turned from a screen direction into the player's own directions
--      (toward their right / the way they face), so "flick left" sends the ball toward
--      the left of the screen whichever way the player is facing,
--   4. SkillMath.chooseMove picks the move, and BallController moves the ball.
-- The crossover also moves the body, in time with the ball (see Config/Skills.luau):
--   SELL    – plant the feet, lean toward the ball and over it (low);
--   EXPLODE – whip the lean over to the new side and take ONE quick step that way;
--   then movement goes back to the keys, and the body straightens up.
-- The player keeps facing the same way throughout (no turning toward the step), and
-- afterwards until a movement key is pressed.
-- Tuning values: src/shared/Config/Skills.luau (flicks, crossover) and
-- src/shared/Config/Ball.luau (SWITCH_..., the H hand switch).

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

-- The crossover's body motion in progress.
type BodyMove = {
	startedAt: number, -- clock time the crossover started
	fromSign: number, -- +1 if the ball started in the right hand, -1 if in the left
	exploded: boolean, -- true once the EXPLODE beat (the step) has started
	stepped: boolean, -- true once the step is over and movement is back with the keys
}

local SWITCH_KEY = Enum.KeyCode.H -- change this to rebind the quick hand switch

local SkillController = {}

-- Recent cursor readings, oldest first (only the last SWIPE_WINDOW seconds are kept).
local samples: { SkillMath.Sample } = {}
local body: BodyMove? = nil -- the crossover's body motion, or nil
-- True after a crossover until the player presses a movement key: the body keeps facing
-- the same way meanwhile, instead of swinging round to face the leftover momentum.
local holdFacing = false

-- A flat direction relative to the player: `side` studs/s toward their right (negative =
-- left) and `forward` studs/s the way they face, in world space.
local function bodyVelocity(rootCFrame: CFrame, side: number, forward: number): Vector3
	local right, look = rootCFrame.RightVector, rootCFrame.LookVector
	return Vector3.new(right.X, 0, right.Z).Unit * side + Vector3.new(look.X, 0, look.Z).Unit * forward
end

-- Starts the crossover: the ball (BallController) and the SELL beat of the body.
local function startCrossover()
	local parts = CharacterRef.get()
	local fromHand = BallController.getHand()
	if not parts or not BallController.switchHands("Crossover") then
		return
	end
	local fromSign = if fromHand == "Right" then 1 else -1
	body = { startedAt = os.clock(), fromSign = fromSign, exploded = false, stepped = false }
	-- Keep facing the same way while the feet step sideways.
	parts.humanoid.AutoRotate = false
	-- SELL: plant the feet (any momentum stops), lean over the ball and toward it.
	PostureController.leanTo(
		-Skills.WIDE_SELL_FORWARD_LEAN,
		Skills.WIDE_SELL_TIME,
		fromSign * Skills.WIDE_SELL_SIDE_LEAN
	)
	MovementController.setOverride(Vector3.zero, Skills.WIDE_STEP_RATE)
end

-- Runs every frame: moves the body through the crossover's beats in time with the ball.
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
	-- A shot started mid-crossover: the shot takes over the movement and turning, so just
	-- start straightening up.
	if BallController.getMode() ~= "Dribble" then
		body = nil
		PostureController.leanTo(0, Skills.WIDE_LEAN_RECOVER_TIME)
		return
	end

	local elapsed = os.clock() - current.startedAt
	local total = Skills.WIDE_SELL_TIME + Skills.WIDE_PUSH_TIME + Skills.WIDE_RISE_TIME + Skills.WIDE_RECOVER_TIME
	if not current.exploded and elapsed >= Skills.WIDE_SELL_TIME then
		-- EXPLODE: as the ball is pounded across, whip the lean to the new side and take
		-- ONE quick step that way (and a little forward).
		current.exploded = true
		local toSign = -current.fromSign
		PostureController.leanTo(
			-Skills.WIDE_CROSS_FORWARD_LEAN,
			Skills.WIDE_PUSH_TIME + Skills.WIDE_RISE_TIME,
			toSign * Skills.WIDE_CROSS_SIDE_LEAN
		)
		local stepDirection = bodyVelocity(parts.root.CFrame, toSign, Skills.WIDE_STEP_FORWARD).Unit
		MovementController.setOverride(stepDirection * Skills.WIDE_STEP_SPEED, Skills.WIDE_STEP_RATE)
	elseif current.exploded and not current.stepped and elapsed >= Skills.WIDE_SELL_TIME + Skills.WIDE_STEP_TIME then
		-- The step is done: movement goes back to the keys (no key held = slow to a stop).
		current.stepped = true
		MovementController.setOverride(nil)
	elseif elapsed >= total then
		-- Done: straighten up. Keep facing the same way until a movement key is pressed
		-- (see holdFacing).
		body = nil
		PostureController.leanTo(0, Skills.WIDE_LEAN_RECOVER_TIME)
		MovementController.setOverride(nil)
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
	if move == "Crossover" then
		startCrossover()
	end
end

-- Records a cursor position and checks for a flick.
local function onCursorMoved(position: Vector3)
	local screenHeight = math.max(workspace.CurrentCamera.ViewportSize.Y, 1)
	local now = os.clock()
	-- Screen y grows downward; flip it so up is positive.
	table.insert(samples, { t = now, x = position.X / screenHeight, y = -position.Y / screenHeight })
	-- Drop readings older than the window.
	while #samples > 0 and now - samples[1].t > Skills.SWIPE_WINDOW do
		table.remove(samples, 1)
	end

	local dx, dy = SkillMath.detectSwipe(samples, Skills)
	if dx and dy then
		-- One flick = one move: forget this flick so it can't trigger again.
		table.clear(samples)
		onFlick(dx, dy)
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
			BallController.switchHands("HandSwitch")
		end
	end)
	CharacterRef.onSpawn(function()
		table.clear(samples)
		body = nil
		holdFacing = false
	end)
	-- "Input + 3" priority: after MovementController and ShotController each frame.
	RunService:BindToRenderStep("RoHoopsSkills", Enum.RenderPriority.Input.Value + 3, step)
end

return SkillController
