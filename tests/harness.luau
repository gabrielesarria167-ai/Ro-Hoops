--!strict
-- Minimal test harness for Lune. Specs call `test(name, fn)` and use the assertion helpers;
-- `finish()` prints a summary and fails the process if anything failed.

local process = require("@lune/process")

local harness = {}

local passed, failed = 0, 0

function harness.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok    " .. name)
	else
		failed += 1
		print("  FAIL  " .. name .. "\n        " .. tostring(err))
	end
end

function harness.describe(name: string, fn: () -> ())
	print(name)
	fn()
end

function harness.equal(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(
			string.format(
				"%sexpected %s, got %s",
				if message then message .. ": " else "",
				tostring(expected),
				tostring(actual)
			),
			2
		)
	end
end

function harness.near(actual: number, expected: number, tolerance: number, message: string?)
	if math.abs(actual - expected) > tolerance then
		error(
			string.format(
				"%sexpected %.5f ± %g, got %.5f",
				if message then message .. ": " else "",
				expected,
				tolerance,
				actual
			),
			2
		)
	end
end

function harness.truthy(value: any, message: string?)
	if not value then
		error(message or "expected a truthy value", 2)
	end
end

function harness.finish()
	print(string.format("\n%d passed, %d failed", passed, failed))
	if failed > 0 then
		process.exit(1)
	end
end

return harness
