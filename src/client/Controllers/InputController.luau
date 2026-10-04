--!strict
-- Movement input. Roblox's default controls are disabled and the keys are polled each
-- frame instead, which keeps input-to-motion latency to a single frame.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local CharacterRef = require(script.Parent.Parent.CharacterRef)

local InputController = {}

-- X = screen right, Y = screen up (toward the rim).
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

local function isTyping(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

local function disableDefaultControls()
	local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule") :: ModuleScript) :: any
	playerModule:GetControls():Disable()
end

-- Unit-length (or zero) direction from WASD / arrow keys. Opposite keys cancel out.
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

function InputController.isRunning(): boolean
	return not isTyping()
		and (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift))
end

function InputController.start()
	disableDefaultControls()
	-- The default control module can come back on respawn, so disable it again each time.
	CharacterRef.onSpawn(function()
		disableDefaultControls()
	end)
end

return InputController
