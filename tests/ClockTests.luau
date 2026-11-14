--!strict

const Clock = require("../src/DayNightCycle/Clock")
const Harness = require("./Harness")
const Timeline = require("../src/DayNightCycle/Timeline")
const Types = require("../src/DayNightCycle/Types")

-- A 180 minute day: 8 game minutes per real second, so one game hour per 450 real seconds.
const DAY_LENGTH_SECONDS = 10800
const SECONDS_PER_GAME_HOUR = 450

-- With no phases, time passes at a constant speed.
const UNIFORM = Timeline.create({}, {})

-- Day (6-18) gets 3 shares and Night (18-6) gets 1. The cycle position is 0.125 at 6:00,
-- 0.5 at 12:00 and 0.875 at 18:00.
const VARIABLE = Timeline.create({
	{ Name = "Day", StartEvent = "Dawn", TimeShare = 3 },
	{ Name = "Night", StartEvent = "Dusk", TimeShare = 1 },
}, { Dawn = 6, Dusk = 18 })

local function getTime(state: Types.ClockState, serverNow: number): (number, number)
	return Clock.getTime(state, serverNow, UNIFORM)
end

local function reanchor(
	state: Types.ClockState,
	serverNow: number,
	changes: Clock.Changes
): Types.ClockState
	return Clock.reanchor(state, serverNow, UNIFORM, changes)
end

print("Clock")

Harness.test("getTime returns the anchor hour and day at the anchor", function()
	const state = Clock.create(6, 3, DAY_LENGTH_SECONDS, 1000)
	const hour, day = getTime(state, 1000)

	Harness.expectNear(hour, 6)
	Harness.expectEqual(day, 3)
end)

Harness.test("getTime advances at the configured rate", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 1000)
	const hour = getTime(state, 1000 + SECONDS_PER_GAME_HOUR * 2)

	Harness.expectNear(hour, 8)
end)

Harness.test("getTime wraps past midnight and increments the day", function()
	const state = Clock.create(23, 5, DAY_LENGTH_SECONDS, 0)
	const hour, day = getTime(state, SECONDS_PER_GAME_HOUR * 3)

	Harness.expectNear(hour, 2)
	Harness.expectEqual(day, 6)
end)

Harness.test("getTime counts multiple whole days", function()
	const state = Clock.create(0, 1, DAY_LENGTH_SECONDS, 0)
	const hour, day = getTime(state, DAY_LENGTH_SECONDS * 2.5)

	Harness.expectNear(hour, 12)
	Harness.expectEqual(day, 3)
end)

Harness.test("getTime does not run backwards when server time steps back", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 1000)
	const hour = getTime(state, 999.5)

	Harness.expectNear(hour, 6)
end)

Harness.test("create normalizes an hour of 24 to 0", function()
	const state = Clock.create(24, 1, DAY_LENGTH_SECONDS, 0)

	Harness.expectNear(state.AnchorHour, 0)
end)

Harness.test("a paused clock does not advance", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 0)
	const paused = reanchor(state, SECONDS_PER_GAME_HOUR, { Paused = true })
	const hour = getTime(paused, SECONDS_PER_GAME_HOUR * 50)

	Harness.expectNear(hour, 7)
end)

Harness.test("resuming continues from the paused hour", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 0)
	const paused = reanchor(state, SECONDS_PER_GAME_HOUR, { Paused = true })
	const resumed = reanchor(paused, SECONDS_PER_GAME_HOUR * 50, { Paused = false })
	const hour = getTime(resumed, SECONDS_PER_GAME_HOUR * 51)

	Harness.expectNear(hour, 8)
end)

Harness.test("reanchor keeps the current time unless an hour is given", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 0)
	const reanchored = reanchor(state, SECONDS_PER_GAME_HOUR * 4, {})
	const hour = getTime(reanchored, SECONDS_PER_GAME_HOUR * 4)

	Harness.expectNear(hour, 10)
	Harness.expectEqual(reanchored.Revision, state.Revision + 1)
end)

Harness.test("reanchor with an hour jumps within the current day", function()
	const state = Clock.create(23, 4, DAY_LENGTH_SECONDS, 0)
	-- Two hours later it is 1:00 on day 5; jumping to 15 stays on day 5.
	const reanchored = reanchor(state, SECONDS_PER_GAME_HOUR * 2, { Hour = 15 })
	const hour, day = getTime(reanchored, SECONDS_PER_GAME_HOUR * 2)

	Harness.expectNear(hour, 15)
	Harness.expectEqual(day, 5)
end)

Harness.test("reanchor with a new day length keeps the current hour", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 0)
	const reanchored =
		reanchor(state, SECONDS_PER_GAME_HOUR * 2, { DayLengthSeconds = DAY_LENGTH_SECONDS / 2 })

	Harness.expectNear((getTime(reanchored, SECONDS_PER_GAME_HOUR * 2)), 8)
	-- The new day is twice as fast: one game hour per 225 real seconds.
	Harness.expectNear(
		(getTime(reanchored, SECONDS_PER_GAME_HOUR * 2 + SECONDS_PER_GAME_HOUR / 2)),
		9
	)
end)

Harness.test("FireSkippedEvents applies only to the anchor it was requested on", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 0)
	const jumped = reanchor(state, 10, { Hour = 12, FireSkippedEvents = true })
	const later = reanchor(jumped, 20, { Paused = true })

	Harness.expectEqual(jumped.FireSkippedEvents, true)
	Harness.expectEqual(later.FireSkippedEvents, nil)
end)

Harness.test("variable speed: time passes at each phase's own rate", function()
	-- A 1000 second day: the cycle position moves 0.001 per second.
	const state = Clock.create(6, 1, 1000, 0)

	-- 6:00 is position 0.125. 500s later is position 0.625, two thirds of the way through
	-- the day phase (0.125 to 0.875): 6 + 2/3 * 12 = 14:00.
	Harness.expectNear((Clock.getTime(state, 500, VARIABLE)), 14)

	-- 750s later is position 0.875, the start of the night.
	Harness.expectNear((Clock.getTime(state, 750, VARIABLE)), 18)
end)

Harness.test("variable speed: the night passes faster per hour than the day", function()
	const dayState = Clock.create(6, 1, 1000, 0)
	const nightState = Clock.create(18, 1, 1000, 0)
	const dayHours = Clock.getTime(dayState, 100, VARIABLE) - 6
	const nightHours = Clock.getTime(nightState, 100, VARIABLE) - 18

	-- 100s is a tenth of the cycle. The day phase takes 0.75 of the cycle for 12 hours (16
	-- hours per cycle); the night takes 0.25 for 12 hours (48 hours per cycle).
	Harness.expectNear(dayHours, 1.6)
	Harness.expectNear(nightHours, 4.8)
end)

Harness.test("variable speed: wraps past midnight through both night segments", function()
	-- 23:00 is position 0.875 + 0.0625 * (5 / 6). 100s later is a tenth of a cycle on.
	const state = Clock.create(23, 1, 1000, 0)
	const hour, day = Clock.getTime(state, 100, VARIABLE)
	const startPosition = 0.875 + 0.125 * 5 / 6

	Harness.expectEqual(day, 2)
	Harness.expectNear(hour, (startPosition + 0.1 - 1) / 0.125 * 6)
end)

Harness.test("variable speed: a day takes exactly the day length", function()
	const state = Clock.create(6, 1, 1000, 0)
	const hour, day = Clock.getTime(state, 1000, VARIABLE)

	Harness.expectNear(hour, 6)
	Harness.expectEqual(day, 2)
end)

Harness.test("variable speed: reanchoring keeps the current hour", function()
	const state = Clock.create(6, 1, 1000, 0)
	const paused = Clock.reanchor(state, 500, VARIABLE, { Paused = true })

	Harness.expectNear((Clock.getTime(paused, 900, VARIABLE)), 14)
end)

Harness.test("variable speed: jumping to a phase start lands exactly in that phase", function()
	const state = Clock.create(0, 1, 1000, 0)
	const jumped = Clock.reanchor(state, 10, VARIABLE, { Hour = 6, Paused = true })
	const hour = Clock.getTime(jumped, 10, VARIABLE)

	Harness.expectEqual(hour, 6)
	Harness.expectEqual(Timeline.getPhase(VARIABLE, hour), "Day")
end)

Harness.test("reanchor sets the day without changing the time", function()
	const state = Clock.create(6, 3, DAY_LENGTH_SECONDS, 1000)
	const changed = reanchor(state, 1000 + SECONDS_PER_GAME_HOUR, { Day = 40 })
	const hour, day = getTime(changed, 1000 + SECONDS_PER_GAME_HOUR)

	Harness.expectNear(hour, 7)
	Harness.expectEqual(day, 40)
end)

Harness.test("reanchor keeps counting days from a day it was set to", function()
	const state = Clock.create(23, 3, DAY_LENGTH_SECONDS, 0)
	const changed = reanchor(state, 0, { Day = 40 })
	const _hour, day = getTime(changed, 2 * SECONDS_PER_GAME_HOUR)

	Harness.expectEqual(day, 41)
end)

Harness.test("getEventStartHour keeps the previous hour for a normal step", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 1000)
	const fromHour = Clock.getEventStartHour(state, UNIFORM, 6.0001, 1000.5, 1000.52, 30)

	Harness.expectEqual(fromHour, 6.0001)
end)

Harness.test("getEventStartHour keeps the previous hour for a step within the window", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 1000)
	const fromHour = Clock.getEventStartHour(state, UNIFORM, 6.1, 1045, 1075, 30)

	Harness.expectEqual(fromHour, 6.1)
end)

Harness.test("getEventStartHour only reaches back one window after a stall", function()
	const state = Clock.create(6, 1, DAY_LENGTH_SECONDS, 1000)
	-- The previous step was 1000 seconds ago; only the last 30 seconds are recent.
	const fromHour = Clock.getEventStartHour(state, UNIFORM, 6.0, 1000, 2000, 30)

	Harness.expectNear(fromHour, 6 + (2000 - 30 - 1000) / SECONDS_PER_GAME_HOUR)
end)

Harness.test("getEventStartHour follows the variable speed of the timeline", function()
	const state = Clock.create(6, 1, 1000, 0)
	const fromHour = Clock.getEventStartHour(state, VARIABLE, 6, 0, 500, 100)

	-- 400 seconds in is position 0.125 + 0.4 = 0.525. Day spans 0.125 to 0.875 for its 12
	-- hours, so that is 6 + 0.4 / 0.75 * 12 = 12.4.
	Harness.expectNear(fromHour, 12.4)
end)

Harness.test("getEventStartHour never reaches back more than half a day", function()
	const state = Clock.create(0, 1, 100, 0)
	const fromHour = Clock.getEventStartHour(state, UNIFORM, 0, 0, 90, 80)

	-- The window is limited to 50 seconds (half of the day), so 40 seconds in is hour 9.6.
	Harness.expectNear(fromHour, 9.6)
end)

-- Modules must return a value; the tests register themselves with the harness on require.
return true
