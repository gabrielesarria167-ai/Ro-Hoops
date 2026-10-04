--!strict
-- CHARACTER REFERENCE
-- Keeps track of the local player's current character (its Humanoid and root part) so
-- every controller can grab it cheaply each frame, and lets controllers reset their
-- state whenever a new character spawns (after a reset or death).

local Players = game:GetService("Players")

local player = Players.LocalPlayer -- the player running this client

-- The pieces of a character the controllers need.
export type Parts = {
	character: Model, -- the whole character model
	humanoid: Humanoid, -- controls walking, jumping and health
	root: BasePart, -- HumanoidRootPart: the invisible box at the hips that moves the character
}

local CharacterRef = {}

-- The live character, or nil while dead / respawning.
local current: Parts? = nil
-- Functions to call each time a new character spawns (registered with onSpawn).
local spawnCallbacks: { (Parts) -> () } = {}

-- Called for every new character: waits for its key parts, stores them, notifies listeners.
local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	-- If the player respawned again while we were waiting, this character is stale.
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

-- Returns the current character's parts, or nil if there is no living character.
function CharacterRef.get(): Parts?
	return current
end

-- Runs `callback` for the current character (if any) and every future one.
function CharacterRef.onSpawn(callback: (Parts) -> ())
	table.insert(spawnCallbacks, callback)
	if current then
		task.spawn(callback, current)
	end
end

-- Starts listening for characters. Called once from init.client.luau.
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
