--!strict
-- Tracks the local player's current character so controllers don't each re-resolve it
-- every frame, and lets them reset their state when a new character spawns.

local Players = game:GetService("Players")

local player = Players.LocalPlayer

export type Parts = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
}

local CharacterRef = {}

local current: Parts? = nil
local spawnCallbacks: { (Parts) -> () } = {}

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	if player.Character ~= character then
		return
	end

	local parts: Parts = { character = character, humanoid = humanoid, root = root }
	current = parts
	humanoid.Died:Connect(function()
		if current == parts then
			current = nil
		end
	end)
	for _, callback in spawnCallbacks do
		task.spawn(callback, parts)
	end
end

function CharacterRef.get(): Parts?
	return current
end

function CharacterRef.onSpawn(callback: (Parts) -> ())
	table.insert(spawnCallbacks, callback)
	if current then
		task.spawn(callback, current)
	end
end

function CharacterRef.start()
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function()
		current = nil
	end)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return CharacterRef
