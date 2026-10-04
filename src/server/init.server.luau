--!strict
-- SERVER ENTRY POINT
-- Rojo turns this file into ServerScriptService.Server, a Script that runs once when the
-- game starts. The other files in src/server/ become ModuleScripts inside it.

local CollisionGroups = require(script.CollisionGroups)
local HoopBuilder = require(script.HoopBuilder)

CollisionGroups.setup() -- make the ball pass through players
HoopBuilder.build() -- create the floor, backboard, rim and spawn
