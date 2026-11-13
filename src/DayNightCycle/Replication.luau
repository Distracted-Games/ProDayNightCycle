--!strict

--[[
	Replication
	@author DistractedGames

	Replicates day/night cycle state from the server to clients using attributes, so late
	joiners receive the current state automatically and no RemoteEvents are needed.

	- Internal state (`ClockState`, `TimeEvents`) is stored as JSON attributes on a host
	  instance (the DayNightCycle module's script). Each is a single attribute so clients
	  never observe a half-updated value.
	- Public state (`Day`, `IsPaused`) is stored as plain attributes on `Lighting` so HUDs
	  and other scripts can read them without requiring the module.
]]

const HttpService = game:GetService("HttpService")
const Lighting = game:GetService("Lighting")

const Types = require("./Types")

const CLOCK_STATE_ATTRIBUTE = "ClockState"
const TIME_EVENTS_ATTRIBUTE = "TimeEvents"

-- The attribute names set on `Lighting`. Prefixed to avoid colliding with other systems.
const PublicAttributes = table.freeze({
	Day = "DayNightCycle_Day",
	IsPaused = "DayNightCycle_IsPaused",
})

const Replication = {
	PublicAttributes = PublicAttributes,
}

-- `JSONDecode` returns `any`; every field is type-checked by the callers before use.
local function decodeJson(encoded: unknown): any
	if typeof(encoded) ~= "string" then
		return nil
	end

	const success, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not success then
		return nil
	end

	return decoded
end

local function decodeClockState(encoded: unknown): Types.ClockState?
	const decoded = decodeJson(encoded)
	if typeof(decoded) ~= "table" then
		return nil
	end

	const revision = decoded.Revision
	const anchorServerTime = decoded.AnchorServerTime
	const anchorHour = decoded.AnchorHour
	const anchorDay = decoded.AnchorDay
	const dayLengthSeconds = decoded.DayLengthSeconds
	const paused = decoded.Paused
	const fireSkippedEvents = decoded.FireSkippedEvents

	if
		typeof(revision) ~= "number"
		or typeof(anchorServerTime) ~= "number"
		or typeof(anchorHour) ~= "number"
		or typeof(anchorDay) ~= "number"
		or typeof(dayLengthSeconds) ~= "number"
		or typeof(paused) ~= "boolean"
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
		Paused = paused,
		FireSkippedEvents = if typeof(fireSkippedEvents) == "boolean"
			then fireSkippedEvents
			else nil,
	}
end

local function decodeTimeEvents(encoded: unknown): Types.TimeEventMap?
	const decoded = decodeJson(encoded)
	if typeof(decoded) ~= "table" then
		return nil
	end

	const events: Types.TimeEventMap = {}
	for eventName, eventHour in decoded do
		if typeof(eventName) == "string" and typeof(eventHour) == "number" then
			events[eventName] = eventHour
		end
	end

	return events
end

--[[
	[Server] Publishes the clock state to clients.
	@param host The instance holding the internal attributes.
]]
function Replication.publishClockState(host: Instance, state: Types.ClockState)
	host:SetAttribute(CLOCK_STATE_ATTRIBUTE, HttpService:JSONEncode(state))
end

--[[
	[Server] Publishes the time event table to clients.
	@param host The instance holding the internal attributes.
]]
function Replication.publishTimeEvents(host: Instance, events: Types.TimeEventMap)
	host:SetAttribute(TIME_EVENTS_ATTRIBUTE, HttpService:JSONEncode(events))
end

--[[
	[Server] Publishes the current day number on `Lighting`.
]]
function Replication.publishDay(day: number)
	Lighting:SetAttribute(PublicAttributes.Day, day)
end

--[[
	[Server] Publishes whether the clock is paused on `Lighting`.
]]
function Replication.publishIsPaused(isPaused: boolean)
	Lighting:SetAttribute(PublicAttributes.IsPaused, isPaused)
end

--[[
	[Client] Calls `callback` with the current clock state, if the server has published
	one, and again every time it changes. Never yields.
	@param host The instance holding the internal attributes.
	@return The connection watching for changes.
]]
function Replication.observeClockState(
	host: Instance,
	callback: (state: Types.ClockState) -> ()
): RBXScriptConnection
	local function onChanged()
		const state = decodeClockState(host:GetAttribute(CLOCK_STATE_ATTRIBUTE))
		if state then
			callback(state)
		end
	end

	const connection = host:GetAttributeChangedSignal(CLOCK_STATE_ATTRIBUTE):Connect(onChanged)
	onChanged()

	return connection
end

--[[
	[Client] Calls `callback` with the current time events, if the server has published
	them, and again every time they change. Never yields.
	@param host The instance holding the internal attributes.
	@return The connection watching for changes.
]]
function Replication.observeTimeEvents(
	host: Instance,
	callback: (events: Types.TimeEventMap) -> ()
): RBXScriptConnection
	local function onChanged()
		const events = decodeTimeEvents(host:GetAttribute(TIME_EVENTS_ATTRIBUTE))
		if events then
			callback(events)
		end
	end

	const connection = host:GetAttributeChangedSignal(TIME_EVENTS_ATTRIBUTE):Connect(onChanged)
	onChanged()

	return connection
end

return table.freeze(Replication)
