--!strict
-- LIVE TUNING (Studio only)
-- Copies every number and true/false value of a config table onto attributes of a folder
-- at ReplicatedStorage.Tuning.<name>, and copies your edits back into the table. Since
-- the controllers read config values every frame, editing an attribute while playing
-- changes the game immediately.
--
-- Edits are NOT saved. When you find values you like, copy them into the config file
-- under src/shared/Config/.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Tunable = {}

-- Puts each value of `config` on `folder` as an attribute and keeps them in sync.
-- Nested tables (like Shooting.Types.JumpShot) get their own sub-folder.
local function mirror(folder: Instance, config: any)
	for key, value in config do
		local kind = typeof(value) -- "number", "boolean", "table", "string", ...
		if kind == "number" or kind == "boolean" then
			folder:SetAttribute(key, value)
			-- When you edit the attribute, write it back into the config table.
			folder:GetAttributeChangedSignal(key):Connect(function()
				local edited = folder:GetAttribute(key)
				if typeof(edited) == kind then
					config[key] = edited
				end
			end)
		elseif kind == "table" then
			local child = Instance.new("Folder")
			child.Name = key
			mirror(child, value)
			child.Parent = folder
		end
		-- Other kinds (strings, Vector3s, functions) are skipped.
	end
end

-- Makes `config` editable under ReplicatedStorage.Tuning.<name>. Does nothing in a
-- published game, so players can never change tuning values.
function Tunable.bind(name: string, config: any)
	if not RunService:IsStudio() then
		return
	end

	-- One shared "Tuning" folder holds a sub-folder per config.
	local root = ReplicatedStorage:FindFirstChild("Tuning")
	if not root then
		root = Instance.new("Folder")
		root.Name = "Tuning"
		root.Parent = ReplicatedStorage
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	mirror(folder, config)
	folder.Parent = root
end

return Tunable
