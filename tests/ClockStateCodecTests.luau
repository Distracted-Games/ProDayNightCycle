--!strict

const Harness = require("./Harness")
const ClockStateCodec = require("../src/DayNightCycle/ClockStateCodec")
const Types = require("../src/DayNightCycle/Types")

const MAX_ATTRIBUTE_STRING_LENGTH = 50

local function createState(): Types.ClockState
	return {
		Revision = 3,
		AnchorServerTime = 1762950123.456,
		AnchorHour = 17.25,
		AnchorDay = 12,
		DayLengthSeconds = 10800,
		Paused = false,
	}
end

print("ClockStateCodec")

Harness.test("round-trips a state", function()
	const decoded = ClockStateCodec.decode(ClockStateCodec.encode(createState()))

	assert(decoded, "expected a decoded state")
	Harness.expectEqual(decoded.Revision, 3)
	Harness.expectNear(decoded.AnchorServerTime, 1762950123.456)
	Harness.expectNear(decoded.AnchorHour, 17.25)
	Harness.expectEqual(decoded.AnchorDay, 12)
	Harness.expectEqual(decoded.DayLengthSeconds, 10800)
	Harness.expectEqual(decoded.Paused, false)
	Harness.expectEqual(decoded.FireSkippedEvents, nil)
end)

Harness.test("round-trips the flags", function()
	const state = createState()
	state.Paused = true
	state.FireSkippedEvents = true
	const decoded = ClockStateCodec.decode(ClockStateCodec.encode(state))

	assert(decoded, "expected a decoded state")
	Harness.expectEqual(decoded.Paused, true)
	Harness.expectEqual(decoded.FireSkippedEvents, true)
end)

Harness.test("fits in an attribute string for realistic values", function()
	const state = createState()
	state.Revision = 99999
	state.AnchorDay = 99999
	state.AnchorHour = 23.99999
	state.DayLengthSeconds = 86400
	state.FireSkippedEvents = true

	Harness.expectEqual(#ClockStateCodec.encode(state) <= MAX_ATTRIBUTE_STRING_LENGTH, true)
end)

Harness.test("quantize returns what clients will decode", function()
	const state = createState()
	state.AnchorHour = 1 / 3
	const quantized = ClockStateCodec.quantize(state)
	const decoded = ClockStateCodec.decode(ClockStateCodec.encode(state))

	assert(decoded, "expected a decoded state")
	Harness.expectEqual(quantized.AnchorHour, decoded.AnchorHour)
end)

Harness.test("rejects invalid values", function()
	Harness.expectEqual(ClockStateCodec.decode(nil), nil)
	Harness.expectEqual(ClockStateCodec.decode(5), nil)
	Harness.expectEqual(ClockStateCodec.decode(""), nil)
	Harness.expectEqual(ClockStateCodec.decode("1|2|3"), nil)
	Harness.expectEqual(ClockStateCodec.decode("1|2|3|4|abc|0"), nil)
	Harness.expectEqual(ClockStateCodec.decode("1|2|3|4|0|0"), nil)
end)

Harness.test("an hour that rounds up to 24 becomes the start of the next day", function()
	const state = createState()
	state.AnchorHour = 23.999996
	state.AnchorDay = 5
	const quantized = ClockStateCodec.quantize(state)

	Harness.expectEqual(quantized.AnchorHour, 0)
	Harness.expectEqual(quantized.AnchorDay, 6)
end)

Harness.test("an hour that rounds down below 24 keeps its day", function()
	const state = createState()
	state.AnchorHour = 23.999994
	state.AnchorDay = 5
	const quantized = ClockStateCodec.quantize(state)

	Harness.expectNear(quantized.AnchorHour, 23.99999)
	Harness.expectEqual(quantized.AnchorDay, 5)
end)

return true
