--!strict
-- INPUT CONTROLLER
-- Reads the movement keys (WASD / arrows) and Shift. Roblox's default controls are
-- switched off and the keys are checked every frame instead, so a key press affects
-- movement on the very next frame. The E key is handled in ShotController.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local CharacterRef = require(script.Parent.Parent.CharacterRef)

local InputController = {}

-- Which direction each key pushes. X = right on screen, Y = up on screen (toward the rim).
local MOVE_KEYS: { [Enum.KeyCode]: Vector2 } = {
	[Enum.KeyCode.W] = Vector2.new(0, 1),
	[Enum.KeyCode.Up] = Vector2.new(0, 1),
	[Enum.KeyCode.S] = Vector2.new(0, -1),
	[Enum.KeyCode.Down] = Vector2.new(0, -1),
	[Enum.KeyCode.A] = Vector2.new(-1, 0),
	[Enum.KeyCode.Left] = Vector2.new(-1, 0),
	[Enum.KeyCode.D] = Vector2.new(1, 0),
	[Enum.KeyCode.Right] = Vector2.new(1, 0),
}

-- True while the player is typing in chat (or any text box), so keys don't move them.
local function isTyping(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

-- Turns off Roblox's built-in WASD movement and Space jump so ours is the only one.
local function disableDefaultControls()
	local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule") :: ModuleScript) :: any
	playerModule:GetControls():Disable()
end

-- Returns the direction the player is pressing, with length 1 (or zero if nothing is
-- pressed). Diagonals are normalised so they aren't faster. Opposite keys cancel out.
function InputController.getMoveIntent(): Vector2
	if isTyping() then
		return Vector2.zero
	end
	local intent = Vector2.zero
	for key, direction in MOVE_KEYS do
		if UserInputService:IsKeyDown(key) then
			intent += direction
		end
	end
	if intent.Magnitude < 1e-3 then
		return Vector2.zero
	end
	return intent.Unit
end

-- True while either Shift key is held (and the player isn't typing).
function InputController.isRunning(): boolean
	return not isTyping()
		and (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift))
end

function InputController.start()
	disableDefaultControls()
	-- The default controls can switch back on after respawning, so turn them off again.
	CharacterRef.onSpawn(function()
		disableDefaultControls()
	end)
end

return InputController
