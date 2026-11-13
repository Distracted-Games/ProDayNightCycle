--!strict

const Harness = require("./Harness")
const LookBlend = require("../src/DayNightCycle/LookBlend")
const Timeline = require("../src/DayNightCycle/Timeline")
const Types = require("../src/DayNightCycle/Types")

const EVENTS = { Dawn = 6, Dusk = 18 }

-- Day lasts 6-18 and Night lasts 18-6, both 12 hours.
const PHASES: { Types.PhaseConfig } = {
	{
		Name = "Day",
		StartEvent = "Dawn",
		BlendHours = 2,
		Look = { Bloom = { Intensity = 1, Size = 10 }, SunRays = { Intensity = 5 } },
	},
	{
		Name = "Night",
		StartEvent = "Dusk",
		BlendHours = 4,
		Look = { Bloom = { Intensity = 3 } },
	},
}

const TIMELINE = Timeline.create(PHASES, EVENTS)
const BLEND_HOURS = LookBlend.getBlendHours(PHASES)

local function getBlend(hour: number): LookBlend.Blend
	const blend = LookBlend.getBlend(TIMELINE, BLEND_HOURS, hour)
	assert(blend, "expected a blend")

	return blend
end

local function expectInvalid(phases: { Types.PhaseConfig })
	const success = pcall(LookBlend.validate, phases)
	Harness.expectEqual(success, false)
end

print("LookBlend")

Harness.test("getBlend starts entirely on the previous look at a phase start", function()
	const blend = getBlend(6)

	Harness.expectEqual(blend.Phase, "Day")
	Harness.expectEqual(blend.PreviousPhase, "Night")
	Harness.expectEqual(blend.Alpha, 0)
end)

Harness.test("getBlend eases through the blend time", function()
	-- BlendHours is 2, so 1 hour in is halfway, and smoothstep(0.5) is 0.5.
	Harness.expectNear(getBlend(7).Alpha, 0.5)
	-- A quarter of the way: smoothstep(0.25) = 0.15625.
	Harness.expectNear(getBlend(6.5).Alpha, 0.15625)
end)

Harness.test("getBlend holds the current look after the blend time", function()
	Harness.expectEqual(getBlend(8).Alpha, 1)
	Harness.expectEqual(getBlend(17.99).Alpha, 1)
end)

Harness.test("getBlend wraps the night across midnight", function()
	const lateNight = getBlend(23)
	const earlyMorning = getBlend(2)

	Harness.expectEqual(lateNight.Phase, "Night")
	Harness.expectEqual(lateNight.PreviousPhase, "Day")
	Harness.expectEqual(lateNight.Alpha, 1)
	Harness.expectEqual(earlyMorning.Phase, "Night")
	Harness.expectEqual(earlyMorning.Alpha, 1)
	-- The night began at 18:00; 20:00 is two hours in, halfway through its 4 hour blend.
	Harness.expectNear(getBlend(20).Alpha, 0.5)
end)

Harness.test("getBlend limits the blend time to the phase length", function()
	const timeline = Timeline.create({
		{ Name = "Short", StartEvent = "Dawn" },
		{ Name = "Long", StartEvent = "Dusk" },
	}, { Dawn = 6, Dusk = 7 })
	const blend = LookBlend.getBlend(timeline, { Short = 10, Long = 10 }, 7 - 1e-9)

	assert(blend, "expected a blend")
	Harness.expectEqual(blend.Phase, "Short")
	-- Almost the whole 1 hour phase has passed, so the blend is almost complete.
	Harness.expectNear(blend.Alpha, 1)
end)

Harness.test("getBlend treats a zero blend time as instant", function()
	const blend = LookBlend.getBlend(TIMELINE, { Day = 0, Night = 0 }, 6)

	assert(blend, "expected a blend")
	Harness.expectEqual(blend.Alpha, 1)
end)

Harness.test("getBlend is nil with no phases", function()
	const timeline = Timeline.create({}, {})

	Harness.expectEqual(LookBlend.getBlend(timeline, {}, 12), nil)
end)

Harness.test("getBlendHours fills in the default", function()
	const blendHours = LookBlend.getBlendHours({
		{ Name = "Day", StartEvent = "Dawn", BlendHours = 3 },
		{ Name = "Night", StartEvent = "Dusk" },
	})

	Harness.expectEqual(blendHours.Day, 3)
	Harness.expectEqual(blendHours.Night > 0, true)
end)

Harness.test("resolve keeps each phase's own values", function()
	const resolved = LookBlend.resolve(TIMELINE, PHASES)

	Harness.expectEqual(resolved.Day.Bloom.Intensity, 1)
	Harness.expectEqual(resolved.Night.Bloom.Intensity, 3)
end)

Harness.test("resolve fills missing properties from the closest earlier phase", function()
	const resolved = LookBlend.resolve(TIMELINE, PHASES)

	-- Night sets no Size, so it keeps Day's. Day sets no Intensity for SunRays in Night,
	-- and Night never sets it, so Night inherits Day's.
	Harness.expectEqual(resolved.Night.Bloom.Size, 10)
	Harness.expectEqual(resolved.Night.SunRays.Intensity, 5)
end)

Harness.test("resolve wraps around to find values from the end of the day", function()
	const phases: { Types.PhaseConfig } = {
		{ Name = "Day", StartEvent = "Dawn" },
		{ Name = "Night", StartEvent = "Dusk", Look = { Bloom = { Size = 7 } } },
	}
	const resolved = LookBlend.resolve(Timeline.create(phases, EVENTS), phases)

	-- Day sets nothing, so it takes the value from Night, the phase before it.
	Harness.expectEqual(resolved.Day.Bloom.Size, 7)
end)

Harness.test("resolve leaves out properties that no phase sets", function()
	const resolved = LookBlend.resolve(TIMELINE, PHASES)

	Harness.expectEqual(resolved.Day.Atmosphere, nil)
	Harness.expectEqual(resolved.Day.Bloom.Threshold, nil)
end)

Harness.test("resolve does not change the configured looks", function()
	LookBlend.resolve(TIMELINE, PHASES)

	const nightLook = PHASES[2].Look
	assert(nightLook and nightLook.Bloom, "expected the night look")
	Harness.expectEqual(nightLook.Bloom.Size, nil)
end)

Harness.test("validate accepts known targets and properties", function()
	LookBlend.validate(PHASES)
end)

Harness.test("validate rejects unknown targets, properties and blend times", function()
	expectInvalid({
		{ Name = "Day", StartEvent = "Dawn", Look = { Fog = { Intensity = 1 } } },
	})
	expectInvalid({
		{ Name = "Day", StartEvent = "Dawn", Look = { Bloom = { Strength = 1 } } },
	})
	expectInvalid({ { Name = "Day", StartEvent = "Dawn", BlendHours = -1 } })
end)

-- Modules must return a value; the tests register themselves with the harness on require.
return true
