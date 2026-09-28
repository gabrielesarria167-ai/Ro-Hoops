--!strict
-- configuring player body limits

local HEIGHT = table.freeze({ min = 69, max = 87 }) -- 5'9 to 7'3
local WEIGHT = table.freeze({ min = 170, max = 300 })
local WINGSPAN_OFFSET = table.freeze({ min = -4, max = 6 })

export type CapRow = { base: number, height: number, weight: number, wingspan: number }

-- Caps: effect = cap change at the max of that body stat (the opposite at the min).
-- base = 99 - sum(|effects|), so only the ideal extreme body reaches 99.
local CAPS: { [string]: CapRow } = {
	-- Shooting: short, light, short arms shoot best (except Fade)
	Three = { base = 80, height = -12, weight = -4, wingspan = -3 },
	Mid = { base = 86, height = -8, weight = -3, wingspan = -2 },
	Fade = { base = 88, height = 6, weight = -3, wingspan = 2 }, -- tall, light, long
	Tough = { base = 83, height = -10, weight = -4, wingspan = -2 },

	-- Finishing
	Layup = { base = 87, height = -4, weight = -4, wingspan = 4 },
	MovingDunk = { base = 77, height = 10, weight = -6, wingspan = 6 }, -- tall but light
	StandingDunk = { base = 70, height = 18, weight = 6, wingspan = 5 },
	Floater = { base = 85, height = -8, weight = -4, wingspan = 2 },

	-- Playmaking
	Pass = { base = 93, height = -6, weight = 0, wingspan = 0 },
	SpeedBall = { base = 79, height = -12, weight = -8, wingspan = 0 },
	Handle = { base = 79, height = -14, weight = -4, wingspan = -2 },

	-- Defense: wingspan matters everywhere
	PerimeterD = { base = 83, height = -4, weight = -4, wingspan = 8 },
	InsideD = { base = 73, height = 14, weight = 8, wingspan = 4 },
	OffD = { base = 87, height = 0, weight = -2, wingspan = 10 },
	OnD = { base = 85, height = -4, weight = -2, wingspan = 8 },
	Steal = { base = 83, height = -6, weight = -2, wingspan = 8 },
	Block = { base = 71, height = 18, weight = 2, wingspan = 8 },

	-- Physicals: weight drives strength
	Strength = { base = 75, height = 4, weight = 20, wingspan = 0 },
	Post = { base = 77, height = 10, weight = 10, wingspan = 2 },
	Box = { base = 77, height = 8, weight = 12, wingspan = 2 },

	-- Athleticism
	Speed = { base = 77, height = -12, weight = -10, wingspan = 0 },
	Rebound = { base = 73, height = 14, weight = 6, wingspan = 6 },
	Vertical = { base = 83, height = -8, weight = 8, wingspan = 0 },
	Acceleration = { base = 80, height = -10, weight = -9, wingspan = 0 },
	Stamina = { base = 82, height = -10, weight = -7, wingspan = 0 },
}

for _, row in CAPS do
	table.freeze(row)
end
return table.freeze({ HEIGHT = HEIGHT, WEIGHT = WEIGHT, WINGSPAN_OFFSET = WINGSPAN_OFFSET, CAPS = CAPS })
