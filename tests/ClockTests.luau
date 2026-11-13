--!strict

const Clock = require("../src/DayNightCycle/Clock")
const Harness = require("./Harness")

-- A 180 minute day: 8 game minutes per real second, so one game hour per 450 real seconds.
const DAY_LENGTH_SECONDS = 10800
const SECONDS_PER_GAME_HOUR = 450

print("Clock")

Harness.test("getTime returns the anchor hour and day at the anchor", function()
	const state = Clock.create(6, 3, DAY_LENGTH_SECONDS, 1000)
	const hour, day = Clock.getTime(state, 1000)

	Harness.expectNear(hour, 6)
	Harness.expectEqual(day, 3)
end)

Harness.test("getTime advances at the configured rate", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 1000)
	const hour = Clock.getTime(state, 1000 + SECONDS_PER_GAME_HOUR * 2)

	Harness.expectNear(hour, 8)
end)

Harness.test("getTime wraps past midnight and increments the day", function()
	const state = Clock.create(23, 5, DAY_LENGTH_SECONDS, 0)
	const hour, day = Clock.getTime(state, SECONDS_PER_GAME_HOUR * 3)

	Harness.expectNear(hour, 2)
	Harness.expectEqual(day, 6)
end)

Harness.test("getTime counts multiple whole days", function()
	const state = Clock.create(0, 1, DAY_LENGTH_SECONDS, 0)
	const hour, day = Clock.getTime(state, DAY_LENGTH_SECONDS * 2.5)

	Harness.expectNear(hour, 12)
	Harness.expectEqual(day, 3)
end)

Harness.test("getTime does not run backwards when server time steps back", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 1000)
	const hour = Clock.getTime(state, 999.5)

	Harness.expectNear(hour, 6)
end)

Harness.test("create normalizes an hour of 24 to 0", function()
	const state = Clock.create(24, 1, DAY_LENGTH_SECONDS, 0)

	Harness.expectNear(state.AnchorHour, 0)
end)

Harness.test("a paused clock does not advance", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 0)
	const paused = Clock.reanchor(state, SECONDS_PER_GAME_HOUR, { Paused = true })
	const hour = Clock.getTime(paused, SECONDS_PER_GAME_HOUR * 50)

	Harness.expectNear(hour, 7)
end)

Harness.test("resuming continues from the paused hour", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 0)
	const paused = Clock.reanchor(state, SECONDS_PER_GAME_HOUR, { Paused = true })
	const resumed = Clock.reanchor(paused, SECONDS_PER_GAME_HOUR * 50, { Paused = false })
	const hour = Clock.getTime(resumed, SECONDS_PER_GAME_HOUR * 51)

	Harness.expectNear(hour, 8)
end)

Harness.test("reanchor keeps the current time unless an hour is given", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 0)
	const reanchored = Clock.reanchor(state, SECONDS_PER_GAME_HOUR * 4, {})
	const hour = Clock.getTime(reanchored, SECONDS_PER_GAME_HOUR * 4)

	Harness.expectNear(hour, 10)
	Harness.expectEqual(reanchored.Revision, state.Revision + 1)
end)

Harness.test("reanchor with an hour jumps within the current day", function()
	const state = Clock.create(23, 4, DAY_LENGTH_SECONDS, 0)
	-- Two hours later it is 1:00 on day 5; jumping to 15 stays on day 5.
	const reanchored = Clock.reanchor(state, SECONDS_PER_GAME_HOUR * 2, { Hour = 15 })
	const hour, day = Clock.getTime(reanchored, SECONDS_PER_GAME_HOUR * 2)

	Harness.expectNear(hour, 15)
	Harness.expectEqual(day, 5)
end)

Harness.test("reanchor with a new day length keeps the current hour", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 0)
	const reanchored = Clock.reanchor(
		state,
		SECONDS_PER_GAME_HOUR * 2,
		{ DayLengthSeconds = DAY_LENGTH_SECONDS / 2 }
	)

	Harness.expectNear((Clock.getTime(reanchored, SECONDS_PER_GAME_HOUR * 2)), 8)
	-- The new day is twice as fast: one game hour per 225 real seconds.
	Harness.expectNear(
		(Clock.getTime(reanchored, SECONDS_PER_GAME_HOUR * 2 + SECONDS_PER_GAME_HOUR / 2)),
		9
	)
end)

Harness.test("FireSkippedEvents applies only to the anchor it was requested on", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 0)
	const jumped = Clock.reanchor(state, 10, { Hour = 12, FireSkippedEvents = true })
	const later = Clock.reanchor(jumped, 20, { Paused = true })

	Harness.expectEqual(jumped.FireSkippedEvents, true)
	Harness.expectEqual(later.FireSkippedEvents, nil)
end)

-- Modules must return a value; the tests register themselves with the harness on require.
return true
