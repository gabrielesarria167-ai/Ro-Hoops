--!strict
-- Pure movement math with no Roblox APIs, so it can be unit tested with Lune.
-- Velocities are planar (x, z) number pairs.

local MovementMath = {}

-- Moves the current velocity toward the target by a fixed rate. Speeding up uses `accel`,
-- slowing down uses `decel`, and reversing (target opposes current) uses `turnAccel` so
-- direction changes stay snappy. Linear stepping keeps the result frame-rate independent.
function MovementMath.stepVelocity(
	vx: number,
	vz: number,
	tx: number,
	tz: number,
	accel: number,
	decel: number,
	turnAccel: number,
	dt: number
): (number, number)
	local currentSpeed = math.sqrt(vx * vx + vz * vz)
	local targetSpeed = math.sqrt(tx * tx + tz * tz)

	local rate
	if vx * tx + vz * tz < 0 then
		rate = turnAccel
	elseif targetSpeed < currentSpeed then
		rate = decel
	else
		rate = accel
	end

	local dx, dz = tx - vx, tz - vz
	local gap = math.sqrt(dx * dx + dz * dz)
	local step = rate * dt
	if gap <= step then
		return tx, tz
	end
	local scale = step / gap
	return vx + dx * scale, vz + dz * scale
end

-- Lerp factor for exponential smoothing that behaves the same at any frame rate.
function MovementMath.smoothingAlpha(sharpness: number, dt: number): number
	return 1 - math.exp(-sharpness * dt)
end

return MovementMath
