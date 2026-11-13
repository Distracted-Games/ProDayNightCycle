--!strict

const Harness = require("./Harness")
const TimeEvents = require("../src/DayNightCycle/TimeEvents")

const EVENTS = {
	Dawn = 4.75,
	Midday = 12,
	Dusk = 18.25,
	Midnight = 0,
}

--[[
	Runs `advance` and returns the names of the fired events, in order, along with the
	hour to use next.
]]
local function advance(
	events: { [string]: number },
	previousHour: number,
	currentHour: number
): ({ string }, number)
	const fired: { string } = {}
	const nextHour = TimeEvents.advance(events, previousHour, currentHour, function(eventName)
		table.insert(fired, eventName)
	end)

	return fired, nextHour
end

local function expectFired(actual: { string }, expected: { string })
	Harness.expectEqual(table.concat(actual, ","), table.concat(expected, ","))
end

print("TimeEvents")

Harness.test("fires an event crossed this step", function()
	const fired, nextHour = advance(EVENTS, 11.9, 12.1)

	expectFired(fired, { "Midday" })
	Harness.expectNear(nextHour, 12.1)
end)

Harness.test("does not fire when no event is crossed", function()
	const fired = advance(EVENTS, 8, 9)

	expectFired(fired, {})
end)

Harness.test("fires an event exactly at the current hour", function()
	expectFired((advance(EVENTS, 11, 12)), { "Midday" })
end)

Harness.test("does not fire an event exactly at the previous hour again", function()
	expectFired((advance(EVENTS, 12, 12.5)), {})
end)

Harness.test("does not fire while the hour is unchanged", function()
	expectFired((advance(EVENTS, 12, 12)), {})
end)

Harness.test("fires events at midnight when the day wraps", function()
	const fired = advance({ Midnight = 0, Late = 23.995 }, 23.99, 0.01)

	expectFired(fired, { "Late", "Midnight" })
end)

Harness.test("an event at hour 0 does not fire mid-day", function()
	expectFired((advance(EVENTS, 10, 11)), {})
end)

Harness.test("fires events spanning the wrap in the order crossed", function()
	-- From 23:00 to 5:00 crosses Midnight and Dawn.
	const fired = advance(EVENTS, 23, 5)

	expectFired(fired, { "Midnight", "Dawn" })
end)

Harness.test("ignores a small backwards step and keeps the previous hour", function()
	const fired, nextHour = advance(EVENTS, 12.001, 12)

	expectFired(fired, {})
	Harness.expectNear(nextHour, 12.001)
end)

Harness.test("does not repeat an event after a small backwards step", function()
	const events = { Midday = 12 }
	const firedFirst, hourAfterFirst = advance(events, 11.999, 12.001)
	const firedBack, hourAfterBack = advance(events, hourAfterFirst, 12)
	const firedAgain = advance(events, hourAfterBack, 12.002)

	expectFired(firedFirst, { "Midday" })
	expectFired(firedBack, {})
	expectFired(firedAgain, {})
end)

Harness.test("forEachCrossed fires in hour order across a large forward jump", function()
	const fired: { string } = {}
	TimeEvents.forEachCrossed(EVENTS, 10, 3, function(eventName)
		table.insert(fired, eventName)
	end)

	-- 10 -> 24 -> 3 crosses Midday, Dusk, then Midnight (but not Dawn at 4.75).
	expectFired(fired, { "Midday", "Dusk", "Midnight" })
end)

Harness.test("forEachCrossed passes the event hour", function()
	local receivedHour = -1
	TimeEvents.forEachCrossed({ Sunset = 17.6 }, 17, 18, function(_eventName, eventHour)
		receivedHour = eventHour
	end)

	Harness.expectNear(receivedHour, 17.6)
end)

Harness.test("forEachCrossed tolerates callbacks that change the events", function()
	const events: { [string]: number } = { First = 1, Second = 2 }
	const fired: { string } = {}
	TimeEvents.forEachCrossed(events, 0, 3, function(eventName)
		table.insert(fired, eventName)
		table.clear(events)
	end)

	expectFired(fired, { "First", "Second" })
end)

-- Modules must return a value; the tests register themselves with the harness on require.
return true
