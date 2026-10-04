--!strict
-- Studio-only live tuning. Mirrors a config table's numbers and booleans as attributes on
-- ReplicatedStorage.Tuning.<name>, and writes edits back into the table. Controllers read
-- config values every frame, so changing an attribute during Play takes effect immediately.
-- Edits are not saved: copy values you like back into the config module.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Tunable = {}

local function mirror(folder: Instance, config: any)
	for key, value in config do
		local kind = typeof(value)
		if kind == "number" or kind == "boolean" then
			folder:SetAttribute(key, value)
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
	end
end

function Tunable.bind(name: string, config: any)
	if not RunService:IsStudio() then
		return
	end

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
