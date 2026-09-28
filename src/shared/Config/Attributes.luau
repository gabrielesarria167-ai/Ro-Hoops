--!strict
-- configuring general player attributes
local categories = table.freeze({ "Finishing", "Shooting", "Playmaking", "Defense", "Physicals", "Athleticism" })
local list = {
	{ id = "Three", displayName = "Three-Point Shot", category = "Shooting" },
	{ id = "Mid", displayName = "Mid-range Shot", category = "Shooting" },
	{ id = "Fade", displayName = "Fadeaway Shot", category = "Shooting" },
	{ id = "Tough", displayName = "Tough Shot", category = "Shooting" },

	{ id = "Layup", displayName = "Layup", category = "Finishing" },
	{ id = "MovingDunk", displayName = "Moving Dunk", category = "Finishing" },
	{ id = "StandingDunk", displayName = "Standing Dunk", category = "Finishing" },
	{ id = "Floater", displayName = "Floater", category = "Finishing" },

	{ id = "Pass", displayName = "Passing", category = "Playmaking" },
	{ id = "SpeedBall", displayName = "Speed With Ball", category = "Playmaking" },
	{ id = "Handle", displayName = "Ball Handling", category = "Playmaking" },

	{ id = "PerimeterD", displayName = "Perimeter Defense", category = "Defense" },
	{ id = "InsideD", displayName = "Inside Defense", category = "Defense" },
	{ id = "OffD", displayName = "Off-Ball Defense", category = "Defense" },
	{ id = "OnD", displayName = "On-Ball Defense", category = "Defense" },
	{ id = "Steal", displayName = "Steal", category = "Defense" },
	{ id = "Block", displayName = "Block", category = "Defense" },

	{ id = "Strength", displayName = "Strength", category = "Physicals" },
	{ id = "Post", displayName = "Post-Up", category = "Physicals" },
	{ id = "Box", displayName = "Box Out", category = "Physicals" },

	{ id = "Speed", displayName = "Speed", category = "Athleticism" },
	{ id = "Rebound", displayName = "Rebounding", category = "Athleticism" },
	{ id = "Vertical", displayName = "Vertical", category = "Athleticism" },
	{ id = "Stamina", displayName = "Stamina", category = "Athleticism" },
	{ id = "Acceleration", displayName = "Acceleration", category = "Athleticism" },
}

for _, attribute in list do
	table.freeze(attribute)
end

local MIN_RATING = 30
local MAX_RATING = 99

return table.freeze({ Categories = categories, List = list, MIN_RATING = MIN_RATING, MAX_RATING = MAX_RATING })
