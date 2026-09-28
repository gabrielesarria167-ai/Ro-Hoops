--!strict
-- configuring general player attributes
local categories = { "Finishing", "Shooting", "Playmaking", "Defense", "Physicals", "Athleticism" }
local list = {
	{ "Three", "Three-Point Shot", category = "Shooting" },
	{ "Mid", "Mid-range Shot", category = "Shooting" },
	{ "Fade", "Fadeaway Shot", category = "Shooting" },
	{ "Tough", "Tough Shot", category = "Shooting" },

	{ "Layup", "Layup", category = "Finishing" },
	{ "MovingDunk", "Moving Dunk", category = "Finishing" },
	{ "StandingDunk", "Standing Dunk", category = "Finishing" },
	{ "Floater", "Floater", category = "Finishing" },

	{ "Pass", "Passing", category = "Playmaking" },
	{ "SpeedBall", "Speed With Ball", category = "Playmaking" },
	{ "Handle", "Ball Handling", category = "Playmaking" },

	{ "PerimeterD", "Perimeter Defense", category = "Defense" },
	{ "InsideD", "Inside Defense", category = "Defense" },
	{ "OffD", "Off-Ball Defense", category = "Defense" },
	{ "OnD", "On-Ball Defense", category = "Defense" },
	{ "Steal", "Steal", category = "Defense" },
	{ "Block", "Block", category = "Defense" },

	{ "Strength", "Strength", category = "Physicals" },
	{ "Post", "Post-Up", category = "Physicals" },
	{ "Box", "Box Out", category = "Physicals" },

	{ "Speed", "Speed", category = "Athleticism" },
	{ "Rebound", "Rebounding", category = "Athleticism" },
	{ "Vertical", "Vertical", category = "Athleticism" },
	{ "Stamina", "Stamina", category = "Athleticism" },
	{ "Acceleration", "Acceleration", category = "Athleticism" },
}

local MIN_RATING = 30
local MAX_RATING = 99

return table.freeze({ Categories = categories, List = list, MIN_RATING = MIN_RATING, MAX_RATING = MAX_RATING })
