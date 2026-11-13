--!strict

--[[
	Replication
	@author DistractedGames

	Replicates day/night cycle state from the server to clients using attributes, so late
	joiners receive the current state automatically and no RemoteEvents are needed.

	Attributes are limited (strings and names to 50 characters, and only the first 64
	attributes of an instance replicate under Server Authority), so:
	- The clock state is one short packed string (see ClockStateCodec) on a host instance
	  (the DayNightCycle module's script). One value keeps it atomic.
	- Each time event is its own number attribute on the host, named `TimeEvent_<eventName>`.
	- Public state (`Day`, `IsPaused`) is stored as plain attributes on `Lighting` so HUDs
	  and other scripts can read them without requiring the module.
]]

const Lighting = game:GetService("Lighting")

const ClockStateCodec = require("./ClockStateCodec")
const Types = require("./Types")

const CLOCK_STATE_ATTRIBUTE = "ClockState"
const TIME_EVENT_PREFIX = "TimeEvent_"

const MAX_ATTRIBUTE_NAME_LENGTH = 50
const MAX_EVENT_NAME_LENGTH = MAX_ATTRIBUTE_NAME_LENGTH - #TIME_EVENT_PREFIX

-- Only the first 64 attributes of an instance replicate; one is taken by the clock state.
const MAX_TIME_EVENTS = 63

-- The attribute names set on `Lighting`. Prefixed to avoid colliding with other systems.
const PublicAttributes = table.freeze({
	Day = "DayNightCycle_Day",
	IsPaused = "DayNightCycle_IsPaused",
})

const Replication = {
	PublicAttributes = PublicAttributes,
	MaxTimeEvents = MAX_TIME_EVENTS,
}

--[[
	Asserts that an event name can be used as part of an attribute name.
]]
function Replication.assertEventName(eventName: string)
	assert(typeof(eventName) == "string", "eventName must be a string")
	assert(
		string.match(eventName, "^[%w_]+$") ~= nil,
		`Time event name '{eventName}' may only contain letters, numbers and underscores.`
	)
	assert(
		#eventName <= MAX_EVENT_NAME_LENGTH,
		`Time event name '{eventName}' must be at most {MAX_EVENT_NAME_LENGTH} characters.`
	)
end

--[[
	[Server] Publishes the clock state to clients.
	@param host The instance holding the internal attributes.
	@return The state exactly as clients will decode it, for the Server to use as well.
]]
function Replication.publishClockState(host: Instance, state: Types.ClockState): Types.ClockState
	const quantized = ClockStateCodec.quantize(state)
	host:SetAttribute(CLOCK_STATE_ATTRIBUTE, ClockStateCodec.encode(quantized))

	return quantized
end

--[[
	[Server] Publishes a time event to clients, or removes it when `eventHour` is nil.
	@param host The instance holding the internal attributes.
]]
function Replication.publishTimeEvent(host: Instance, eventName: string, eventHour: number?)
	host:SetAttribute(TIME_EVENT_PREFIX .. eventName, eventHour)
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
		const state = ClockStateCodec.decode(host:GetAttribute(CLOCK_STATE_ATTRIBUTE))
		if state then
			callback(state)
		end
	end

	const connection = host:GetAttributeChangedSignal(CLOCK_STATE_ATTRIBUTE):Connect(onChanged)
	onChanged()

	return connection
end

--[[
	[Client] Calls `callback` for every time event the server has published, and again
	every time one is added, changed or removed (`eventHour` is nil when removed).
	Never yields.
	@param host The instance holding the internal attributes.
	@return The connection watching for changes.
]]
function Replication.observeTimeEvents(
	host: Instance,
	callback: (eventName: string, eventHour: number?) -> ()
): RBXScriptConnection
	local function report(attributeName: string)
		if string.sub(attributeName, 1, #TIME_EVENT_PREFIX) ~= TIME_EVENT_PREFIX then
			return
		end

		const eventName = string.sub(attributeName, #TIME_EVENT_PREFIX + 1)
		const eventHour = host:GetAttribute(attributeName)
		callback(eventName, if typeof(eventHour) == "number" then eventHour else nil)
	end

	const connection = host.AttributeChanged:Connect(report)
	for attributeName in host:GetAttributes() do
		report(attributeName)
	end

	return connection
end

return table.freeze(Replication)
