--!strict
local moduleTable = {}

for _, child in script.Controllers:GetChildren() do
	if child:IsA("ModuleScript") then
		moduleTable[child.Name] = (require)(child)
	end
end

for _,item in moduleTable do
    item:Init()
end

for _,item in moduleTable do
    task.spawn(item:Start())
end