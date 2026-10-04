--!strict
-- COLLISION GROUPS (runs on the server)
-- Roblox decides what can bump into what using "collision groups". We want the ball to
-- pass straight through players (only the hoop and floor should affect a shot), so:
--   * the ball is in the "Ball" group (set in src/client/Controllers/BallController.luau)
--   * every part of every character is put in the "Players" group (done here)
--   * those two groups are told not to collide.
-- The group names live in src/shared/Config/Ball.luau.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ball = require(ReplicatedStorage.Shared.Config.Ball)

local CollisionGroups = {}

-- Puts one part into the players' group (anything that isn't a part is ignored).
local function assign(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = Ball.PLAYER_COLLISION_GROUP
	end
end

-- Handles every part already in a character, plus parts added later (e.g. accessories).
local function onCharacter(character: Model)
	for _, descendant in character:GetDescendants() do
		assign(descendant)
	end
	character.DescendantAdded:Connect(assign)
end

-- Handles a player's current character and every character they get after respawning.
local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

-- Creates the two groups, stops them colliding, and starts tracking players.
function CollisionGroups.setup()
	PhysicsService:RegisterCollisionGroup(Ball.COLLISION_GROUP)
	PhysicsService:RegisterCollisionGroup(Ball.PLAYER_COLLISION_GROUP)
	PhysicsService:CollisionGroupSetCollidable(Ball.COLLISION_GROUP, Ball.PLAYER_COLLISION_GROUP, false)

	Players.PlayerAdded:Connect(onPlayer)
	-- Players who joined before this script ran (common in Studio's Play mode).
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return CollisionGroups
