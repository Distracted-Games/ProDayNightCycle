--!strict

--[[
	Runs the pure-module tests with the standalone Luau CLI (exits non-zero on failure):

		luau tests/run.luau
]]

const Harness = require("./Harness")

require("./ClockStateCodecTests")
require("./ClockTests")
require("./TimeEventsTests")

const failedCount = Harness.finish()
if failedCount > 0 then
	error(`{failedCount} test(s) failed`, 0)
end
