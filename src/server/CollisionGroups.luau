--!strict
-- The ball passes through players (only the hoop and floor should affect a shot), so
-- characters go in their own collision group that doesn't collide with the ball's.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ball = require(ReplicatedStorage.Shared.Config.Ball)

local CollisionGroups = {}

local function assign(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = Ball.PLAYER_COLLISION_GROUP
	end
end

local function onCharacter(character: Model)
	for _, descendant in character:GetDescendants() do
		assign(descendant)
	end
	character.DescendantAdded:Connect(assign)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

function CollisionGroups.setup()
	PhysicsService:RegisterCollisionGroup(Ball.COLLISION_GROUP)
	PhysicsService:RegisterCollisionGroup(Ball.PLAYER_COLLISION_GROUP)
	PhysicsService:CollisionGroupSetCollidable(Ball.COLLISION_GROUP, Ball.PLAYER_COLLISION_GROUP, false)

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return CollisionGroups
