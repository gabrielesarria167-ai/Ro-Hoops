--!strict
-- MOVEMENT MATH
-- Plain math with no Roblox APIs, so it can be unit tested outside Studio with Lune
-- (tests/MovementMath.spec.luau). Velocities are passed as separate x and z numbers
-- because movement only happens on the flat floor (y is up and handled by Roblox).

local MovementMath = {}

-- Moves the current velocity (vx, vz) toward the target velocity (tx, tz) by at most
-- `rate × dt` this frame, and returns the new velocity.
--
--   vx, vz     current velocity, studs/s
--   tx, tz     velocity the player wants (input direction × walk/run speed), studs/s
--   accel      rate used when speeding up
--   decel      rate used when slowing down
--   turnAccel  rate used when the target points against the current velocity (a reversal)
--   dt         seconds since the last frame
--
-- Stepping by a fixed amount per second (not per frame) means 30 FPS and 240 FPS players
-- get exactly the same movement.
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

	-- Pick how fast to change. A negative dot product means the target points more than
	-- 90° away from where we're going: a reversal.
	local rate
	if vx * tx + vz * tz < 0 then
		rate = turnAccel
	elseif targetSpeed < currentSpeed then
		rate = decel
	else
		rate = accel
	end

	-- `gap` is how far the velocity still has to change; `step` is how much it may change
	-- this frame. If we can close the gap this frame, land exactly on the target.
	local dx, dz = tx - vx, tz - vz
	local gap = math.sqrt(dx * dx + dz * dz)
	local step = rate * dt
	if gap <= step then
		return tx, tz
	end
	local scale = step / gap
	return vx + dx * scale, vz + dz * scale
end

-- How far (0 to 1) to move a smoothed value toward its target this frame, e.g. the camera
-- catching up to the player. `sharpness` is how fast it catches up; using exp() keeps the
-- result identical at any frame rate.
function MovementMath.smoothingAlpha(sharpness: number, dt: number): number
	return 1 - math.exp(-sharpness * dt)
end

return MovementMath
