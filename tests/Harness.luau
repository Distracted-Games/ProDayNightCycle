--!strict

--[[
	Harness
	A minimal test harness for running the pure DayNightCycle modules under Lune.
]]

const Harness = {}

local passedCount = 0
const failures: { string } = {}

function Harness.test(name: string, body: () -> ())
	const success, message = pcall(body)
	if success then
		passedCount += 1
		print(`  PASS  {name}`)
	else
		table.insert(failures, `{name}: {message}`)
		print(`  FAIL  {name}\n        {message}`)
	end
end

function Harness.expectEqual(actual: unknown, expected: unknown)
	if actual ~= expected then
		error(`expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

function Harness.expectNear(actual: number, expected: number)
	if math.abs(actual - expected) > 1e-6 then
		error(`expected {expected}, got {actual}`, 2)
	end
end

--[[
	Returns the number of failed tests after printing a summary.
]]
function Harness.finish(): number
	print(`\n{passedCount} passed, {#failures} failed`)
	return #failures
end

return Harness
