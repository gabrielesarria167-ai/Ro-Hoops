--!strict
-- server initializer, finds modulescripts and inserts them inside the table

local moduleTable = {}

for _, child in script.Services:GetChildren() do
	if child:IsA("ModuleScript") then
		moduleTable[child.Name] = (require)(child)
	end
end

-- initializes every modulescript, and then starts them up

for _, item in moduleTable do
	item:Init()
end

for _, item in moduleTable do
	task.spawn(item.Start, item)
end
