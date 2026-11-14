--!strict

--[[
	ClockStateCodec
	@author DistractedGames

	Packs a `ClockState` into one short string, and back. Attribute string values are
	limited to 50 characters, so the state is stored as delimited numbers rather than JSON.
	A single value keeps the state atomic: clients never observe a half-updated clock.

	Format: `revision|anchorServerTime|anchorHour|anchorDay|dayLengthSeconds|flags`
	Free of Roblox services so it can be tested outside of Studio.
]]

const Types = require("./Types")

const SEPARATOR = "|"
const FIELD_COUNT = 6
const MAX_ENCODED_LENGTH = 50

-- Bit flags packed into the last field.
const PAUSED_FLAG = 1
const FIRE_SKIPPED_EVENTS_FLAG = 2

const HOURS_PER_DAY = 24
const HOUR_FORMAT = "%.5f"

const ClockStateCodec = {}

--[[
	Rounds the anchor hour the way it is encoded. An hour that rounds up to a full day is the
	start of the next day, so it becomes hour 0 of the following day instead of losing the day.
	@return The rounded anchor hour (0 up to but not including 24) and the anchor day.
]]
local function roundAnchor(anchorHour: number, anchorDay: number): (number, number)
	const roundedHour = tonumber(string.format(HOUR_FORMAT, anchorHour))
	assert(roundedHour, "The anchor hour must be a number.")

	if roundedHour >= HOURS_PER_DAY then
		return 0, anchorDay + 1
	end

	return roundedHour, anchorDay
end

--[[
	Encodes a clock state. Numbers are rounded (milliseconds for the anchor time), so use
	`quantize` to get the state exactly as clients will decode it.
]]
function ClockStateCodec.encode(state: Types.ClockState): string
	const flags = (if state.Paused then PAUSED_FLAG else 0)
		+ (if state.FireSkippedEvents then FIRE_SKIPPED_EVENTS_FLAG else 0)
	const anchorHour, anchorDay = roundAnchor(state.AnchorHour, state.AnchorDay)

	const encoded = string.format(
		"%d|%.3f|" .. HOUR_FORMAT .. "|%.10g|%.10g|%d",
		state.Revision,
		state.AnchorServerTime,
		anchorHour,
		anchorDay,
		state.DayLengthSeconds,
		flags
	)
	assert(#encoded <= MAX_ENCODED_LENGTH, `Encoded clock state is too long: {encoded}`)

	return encoded
end

--[[
	Decodes a clock state. Returns nil if the value is not a valid encoded state.
]]
function ClockStateCodec.decode(encoded: unknown): Types.ClockState?
	if typeof(encoded) ~= "string" then
		return nil
	end

	const fields = string.split(encoded, SEPARATOR)
	if #fields ~= FIELD_COUNT then
		return nil
	end

	const revision = tonumber(fields[1])
	const anchorServerTime = tonumber(fields[2])
	const anchorHour = tonumber(fields[3])
	const anchorDay = tonumber(fields[4])
	const dayLengthSeconds = tonumber(fields[5])
	const flags = tonumber(fields[6])

	if
		revision == nil
		or anchorServerTime == nil
		or anchorHour == nil
		or anchorDay == nil
		or dayLengthSeconds == nil
		or flags == nil
		or dayLengthSeconds <= 0
	then
		return nil
	end

	return {
		Revision = revision,
		AnchorServerTime = anchorServerTime,
		AnchorHour = anchorHour,
		AnchorDay = anchorDay,
		DayLengthSeconds = dayLengthSeconds,
		Paused = bit32.band(flags, PAUSED_FLAG) ~= 0,
		FireSkippedEvents = if bit32.band(flags, FIRE_SKIPPED_EVENTS_FLAG) ~= 0 then true else nil,
	}
end

--[[
	Returns the state exactly as clients will decode it. The Server uses this so that every
	machine computes the time from identical numbers.
]]
function ClockStateCodec.quantize(state: Types.ClockState): Types.ClockState
	const quantized = ClockStateCodec.decode(ClockStateCodec.encode(state))
	assert(quantized, "A clock state failed to decode after encoding.")

	return quantized
end

return table.freeze(ClockStateCodec)
