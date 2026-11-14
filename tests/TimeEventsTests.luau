--!strict

const Harness = require("./Harness")
const TimeEvents = require("../src/DayNightCycle/TimeEvents")

const EVENTS = {
	Dawn = 4.75,
	Midday = 12,
	Dusk = 18.25,
	Midnight = 0,
}

local function crossed(events: { [string]: number }, fromHour: number, toHour: number): { string }
	const fired: { string } = {}
	TimeEvents.forEachCrossed(events, fromHour, toHour, function(eventName)
		table.insert(fired, eventName)
	end)

	return fired
end

local function expectFired(actual: { string }, expected: { string })
	Harness.expectEqual(table.concat(actual, ","), table.concat(expected, ","))
end

print("TimeEvents")

Harness.test("fires an event crossed this step", function()
	expectFired(crossed(EVENTS, 11.9, 12.1), { "Midday" })
end)

Harness.test("does not fire when no event is crossed", function()
	expectFired(crossed(EVENTS, 8, 9), {})
end)

Harness.test("fires an event exactly at the current hour", function()
	expectFired(crossed(EVENTS, 11, 12), { "Midday" })
end)

Harness.test("does not fire an event exactly at the previous hour again", function()
	expectFired(crossed(EVENTS, 12, 12.5), {})
end)

Harness.test("does not fire while the hour is unchanged", function()
	expectFired(crossed(EVENTS, 12, 12), {})
end)

Harness.test("fires events at midnight when the day wraps", function()
	expectFired(crossed({ Midnight = 0, Late = 23.995 }, 23.99, 0.01), { "Late", "Midnight" })
end)

Harness.test("an event at hour 0 does not fire mid-day", function()
	expectFired(crossed(EVENTS, 10, 11), {})
end)

Harness.test("fires events spanning the wrap in the order crossed", function()
	-- From 23:00 to 5:00 crosses Midnight and Dawn.
	expectFired(crossed(EVENTS, 23, 5), { "Midnight", "Dawn" })
end)

Harness.test("fires every event of a long forward step, with no jitter guessing", function()
	-- 14:00 to 4:00 is a 14 hour step. It crosses Midnight and nothing else.
	expectFired(crossed(EVENTS, 14, 4), { "Dusk", "Midnight" })
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
