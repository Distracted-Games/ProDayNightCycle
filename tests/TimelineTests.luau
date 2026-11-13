--!strict

const Harness = require("./Harness")
const Timeline = require("../src/DayNightCycle/Timeline")
const Types = require("../src/DayNightCycle/Types")

const EVENTS = { Dawn = 6, Dusk = 18 }

-- Night is split at midnight into three segments: hours 0-6 (positions 0-0.125),
-- the day (0.125-0.875) and hours 18-24 (0.875-1).
const PHASES: { Types.PhaseConfig } = {
	{ Name = "Day", StartEvent = "Dawn", TimeShare = 3 },
	{ Name = "Night", StartEvent = "Dusk", TimeShare = 1 },
}

local function expectInvalid(phases: { Types.PhaseConfig }, events: Types.TimeEventMap)
	const success = pcall(Timeline.create, phases, events)
	Harness.expectEqual(success, false)
end

print("Timeline")

Harness.test("with no phases the timeline is uniform", function()
	const timeline = Timeline.create({}, {})

	Harness.expectNear(Timeline.hourToPosition(timeline, 6), 0.25)
	Harness.expectNear(Timeline.positionToHour(timeline, 0.75), 18)
	Harness.expectEqual(Timeline.getPhase(timeline, 12), nil)
end)

Harness.test("splits a phase that crosses midnight into two segments", function()
	const timeline = Timeline.create(PHASES, EVENTS)

	Harness.expectEqual(#timeline.Segments, 3)
	Harness.expectEqual(timeline.Segments[1].Phase, "Night")
	Harness.expectEqual(timeline.Segments[2].Phase, "Day")
	Harness.expectEqual(timeline.Segments[3].Phase, "Night")
end)

Harness.test("positions follow the time shares", function()
	const timeline = Timeline.create(PHASES, EVENTS)

	Harness.expectNear(Timeline.hourToPosition(timeline, 0), 0)
	Harness.expectNear(Timeline.hourToPosition(timeline, 6), 0.125)
	Harness.expectNear(Timeline.hourToPosition(timeline, 12), 0.5)
	Harness.expectNear(Timeline.hourToPosition(timeline, 18), 0.875)
	Harness.expectNear(Timeline.hourToPosition(timeline, 24), 0)
end)

Harness.test("positionToHour is the inverse of hourToPosition", function()
	const timeline = Timeline.create(PHASES, EVENTS)

	for hour = 0, 23.75, 0.25 do
		const position = Timeline.hourToPosition(timeline, hour)
		Harness.expectNear(Timeline.positionToHour(timeline, position), hour)
	end
end)

Harness.test("phase boundaries map exactly", function()
	const timeline = Timeline.create(PHASES, EVENTS)

	const dawnPosition = Timeline.hourToPosition(timeline, 6)
	const duskPosition = Timeline.hourToPosition(timeline, 18)
	Harness.expectEqual(Timeline.positionToHour(timeline, dawnPosition), 6)
	Harness.expectEqual(Timeline.positionToHour(timeline, duskPosition), 18)
end)

Harness.test("getPhase returns the phase at an hour, including boundaries", function()
	const timeline = Timeline.create(PHASES, EVENTS)

	Harness.expectEqual(Timeline.getPhase(timeline, 0), "Night")
	Harness.expectEqual(Timeline.getPhase(timeline, 5.99), "Night")
	Harness.expectEqual(Timeline.getPhase(timeline, 6), "Day")
	Harness.expectEqual(Timeline.getPhase(timeline, 17.99), "Day")
	Harness.expectEqual(Timeline.getPhase(timeline, 18), "Night")
	Harness.expectEqual(Timeline.getPhase(timeline, 23.99), "Night")
end)

Harness.test("phases may be listed in any order", function()
	const reversed: { Types.PhaseConfig } = {
		{ Name = "Night", StartEvent = "Dusk", TimeShare = 1 },
		{ Name = "Day", StartEvent = "Dawn", TimeShare = 3 },
	}
	const timeline = Timeline.create(reversed, EVENTS)

	Harness.expectNear(Timeline.hourToPosition(timeline, 12), 0.5)
end)

Harness.test("TimeShare defaults to the phase length in hours", function()
	const timeline = Timeline.create({
		{ Name = "Day", StartEvent = "Dawn" },
		{ Name = "Night", StartEvent = "Dusk" },
	}, EVENTS)

	-- Both phases last 12 hours, so the day is uniform.
	Harness.expectNear(Timeline.hourToPosition(timeline, 6), 0.25)
	Harness.expectNear(Timeline.hourToPosition(timeline, 12), 0.5)
end)

Harness.test("a phase that starts at midnight is one segment", function()
	const timeline = Timeline.create({
		{ Name = "Early", StartEvent = "Midnight" },
		{ Name = "Late", StartEvent = "Noon" },
	}, { Midnight = 0, Noon = 12 })

	Harness.expectEqual(#timeline.Segments, 2)
	Harness.expectEqual(Timeline.getPhase(timeline, 0), "Early")
	Harness.expectEqual(Timeline.getPhase(timeline, 12), "Late")
end)

Harness.test("a single phase covers the whole day", function()
	const timeline = Timeline.create({
		{ Name = "Always", StartEvent = "Dawn" },
	}, EVENTS)

	Harness.expectEqual(Timeline.getPhase(timeline, 3), "Always")
	Harness.expectEqual(Timeline.getPhase(timeline, 20), "Always")
	Harness.expectNear(Timeline.hourToPosition(timeline, 12), 0.5)
end)

Harness.test("segments cover the whole day without gaps", function()
	const timeline = Timeline.create(PHASES, EVENTS)
	const segments = timeline.Segments

	Harness.expectEqual(segments[1].StartHour, 0)
	Harness.expectEqual(segments[1].StartPosition, 0)
	for index = 2, #segments do
		Harness.expectEqual(segments[index].StartHour, segments[index - 1].EndHour)
		Harness.expectEqual(segments[index].StartPosition, segments[index - 1].EndPosition)
	end
	Harness.expectEqual(segments[#segments].EndHour, 24)
	Harness.expectEqual(segments[#segments].EndPosition, 1)
end)

Harness.test("rejects invalid phases", function()
	expectInvalid({ { Name = "Day", StartEvent = "Missing" } }, EVENTS)
	expectInvalid({ { Name = "", StartEvent = "Dawn" } }, EVENTS)
	expectInvalid({ { Name = string.rep("x", 51), StartEvent = "Dawn" } }, EVENTS)
	expectInvalid({
		{ Name = "Day", StartEvent = "Dawn" },
		{ Name = "Day", StartEvent = "Dusk" },
	}, EVENTS)
	expectInvalid({
		{ Name = "Day", StartEvent = "Dawn" },
		{ Name = "Night", StartEvent = "Same" },
	}, { Dawn = 6, Same = 6 })
	expectInvalid({ { Name = "Day", StartEvent = "Dawn", TimeShare = 0 } }, EVENTS)
	expectInvalid({ { Name = "Day", StartEvent = "Dawn", TimeShare = -1 } }, EVENTS)
end)

-- Modules must return a value; the tests register themselves with the harness on require.
return true
