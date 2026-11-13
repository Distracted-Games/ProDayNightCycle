--!strict
--[[
	DayNightCycle
	@author DistractedGames
	@version 4.0.0

	Runs a game's day/night cycle from server start to shutdown, driven by a configurable
	real-world duration (see Config.luau). Fires named events at specific times of day
	(e.g. "Dawn", "Sunset") on both the Server and the Clients.

	The Server owns the clock and replicates it with attributes. Every machine derives the
	current time from `workspace:GetServerTimeNow()`, so there is no per-frame network
	traffic and late joiners are in sync immediately. Clients apply the time to `Lighting`.

	Public state for HUDs is published as attributes on `Lighting`
	(see `DayNightCycle.AttributeNames`):
	- Day: The current day number. Each game decides what a "day" means.
	- IsPaused: Whether game time is paused.
--]]

const Lighting = game:GetService("Lighting")
const RunService = game:GetService("RunService")

const Clock = require("./DayNightCycle/Clock")
const Config = require("./DayNightCycle/Config")
const Logger = require("./DayNightCycle/Logger")
const Replication = require("./DayNightCycle/Replication")
const Signal = require("./DayNightCycle/Signal")
const TimeEvents = require("./DayNightCycle/TimeEvents")
const Types = require("./DayNightCycle/Types")

const HOURS_PER_DAY = 24
const SECONDS_PER_MINUTE = 60
const MINUTES_PER_HOUR = 60

const IS_SERVER = RunService:IsServer()
const IS_CLIENT = RunService:IsClient()

export type DayNightCycleConfig = Types.Config

const logger = Logger.new({
	Debug = false, -- Toggles verbose logging for this module.
	Prefix = "DayNightCycle",
})

const timeEvent: Signal.Signal<string, number> = Signal.new()

-- The Server owns the events (seeded from Config); Clients receive them from the Server.
local timeEvents: Types.TimeEventMap = if IS_SERVER then table.clone(Config.TimeEvents) else {}
local clockState: Types.ClockState? = nil
local previousHour = 0
local publishedDay: number? = nil
local lastRevision: number? = nil
local hasStarted = false
local heartbeatConnection: RBXScriptConnection? = nil

const DayNightCycle = {
	--[[
		Fires when a configured time is reached, on both the Server and the Clients.
		Passes `eventName: string` and `eventHour: number`.
	]]
	TimeEvent = timeEvent,

	-- The names of the attributes published on `Lighting`.
	AttributeNames = Replication.PublicAttributes,
}

--[[
	Asserts that the source configuration is usable. Runs on the Server when the cycle starts.
]]
local function validateConfig(config: Types.Config)
	assert(
		config.DayLengthInMinutes > 0 and config.DayLengthInMinutes < math.huge,
		"Config.DayLengthInMinutes must be a positive number."
	)

	const startTimeOfDay = config.StartTimeOfDay
	assert(
		startTimeOfDay == nil or (startTimeOfDay >= 0 and startTimeOfDay <= HOURS_PER_DAY),
		"Config.StartTimeOfDay must be nil or a number between 0 and 24."
	)

	for eventName, eventHour in config.TimeEvents do
		assert(
			eventHour >= 0 and eventHour < HOURS_PER_DAY,
			`Config.TimeEvents.{eventName} must be a number between 0 and 23.99.`
		)
	end
end

local function getServerTime(): number
	return workspace:GetServerTimeNow()
end

local function fireTimeEvent(eventName: string, eventHour: number)
	timeEvent:Fire(eventName, eventHour)
	logger:debug(`Time event triggered: '{eventName}' at {string.format("%.2f", eventHour)}h.`)
end

--[[
	Runs every frame on both the Server and the Clients: fires crossed events, applies the
	time to Lighting (Clients only), and publishes the day number (Server only).
]]
local function onHeartbeat()
	const state = clockState
	if not state then
		return
	end

	const currentHour, currentDay = Clock.getTime(state, getServerTime())
	previousHour = TimeEvents.advance(timeEvents, previousHour, currentHour, fireTimeEvent)

	if IS_CLIENT then
		Lighting:SetMinutesAfterMidnight(currentHour * MINUTES_PER_HOUR)
	end

	if IS_SERVER and currentDay ~= publishedDay then
		publishedDay = currentDay
		Replication.publishDay(currentDay)
	end
end

local function ensureHeartbeat()
	if not heartbeatConnection then
		heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
	end
end

--[[
	[Server] Re-anchors the clock at the current moment, applying `changes`, and publishes it.
]]
local function reanchorClock(changes: Clock.Changes)
	const state = clockState
	if not state then
		logger:warn("The cycle has not been started yet.")
		return
	end

	const serverTime = getServerTime()
	const currentHour = Clock.getTime(state, serverTime)
	const newState = Clock.reanchor(state, serverTime, changes)

	if changes.Hour and changes.FireSkippedEvents then
		TimeEvents.forEachCrossed(timeEvents, currentHour, changes.Hour, fireTimeEvent)
	end

	clockState = newState
	previousHour = Clock.getTime(newState, serverTime)

	Replication.publishClockState(script, newState)
	Replication.publishIsPaused(newState.Paused)
end

--[[
	[Client] Handles the Server publishing a clock state (first sync, or a re-anchor).
]]
local function onClockStateReplicated(newState: Types.ClockState)
	const serverTime = getServerTime()
	const currentHour = Clock.getTime(newState, serverTime)

	-- A client that joined after the re-anchor never saw the old time, so nothing was skipped.
	const isReanchor = lastRevision ~= nil and newState.Revision > lastRevision
	if isReanchor and newState.FireSkippedEvents then
		TimeEvents.forEachCrossed(timeEvents, previousHour, currentHour, fireTimeEvent)
	end

	-- Time may have jumped; resume event detection from the new hour without firing.
	lastRevision = newState.Revision
	clockState = newState
	previousHour = currentHour

	ensureHeartbeat()
end

local function startServer()
	validateConfig(Config)

	const startHour = if Config.StartTimeOfDay
		then Config.StartTimeOfDay
		else Lighting:GetMinutesAfterMidnight() / MINUTES_PER_HOUR
	const dayLengthSeconds = Config.DayLengthInMinutes * SECONDS_PER_MINUTE
	const newState = Clock.create(startHour, Config.StartDay, dayLengthSeconds, getServerTime())

	clockState = newState
	previousHour = newState.AnchorHour

	Replication.publishTimeEvents(script, timeEvents)
	Replication.publishClockState(script, newState)
	Replication.publishIsPaused(false)
	ensureHeartbeat()

	logger:debug(
		`Day/Night cycle started. A game day lasts {Config.DayLengthInMinutes} real-world minutes.`
	)
end

-- Connections live for the lifetime of the module, as the cycle runs for the whole server.
local function startClient()
	Replication.observeTimeEvents(script, function(events: Types.TimeEventMap)
		timeEvents = events
	end)
	Replication.observeClockState(script, onClockStateReplicated)

	logger:debug("Waiting for the Server's day/night cycle state...")
end

--[[
	Returns whether the caller is the Server, warning if not.
]]
local function requireServer(functionName: string): boolean
	if IS_SERVER then
		return true
	end

	logger:warn(`{functionName} can only be called on the Server.`)
	return false
end

--[[
	[Public Method]
	Starts the day/night cycle. On the Server this starts the clock; on a Client this
	begins following the Server's clock, including when joining a cycle already in progress.
	Call this once on the Server and once on each Client.
]]
function DayNightCycle.Start()
	if hasStarted then
		logger:warn("Start called but the cycle has already been started.")
		return
	end
	hasStarted = true

	if IS_SERVER then
		startServer()
	else
		startClient()
	end
end

--[[
	[Public Method] [Server only]
	Adds or updates a custom time event. Replicates to all Clients.
	@param eventName The unique name for the event.
	@param eventHour The hour (0-24) to trigger the event.
]]
function DayNightCycle.AddTimeEvent(eventName: string, eventHour: number)
	if not requireServer("AddTimeEvent") then
		return
	end

	assert(typeof(eventName) == "string", "eventName must be a string")
	assert(
		typeof(eventHour) == "number" and eventHour >= 0 and eventHour < HOURS_PER_DAY,
		"eventHour must be a number between 0 and 23.99"
	)

	timeEvents[eventName] = eventHour
	Replication.publishTimeEvents(script, timeEvents)

	logger:debug(`Added time event: '{eventName}' at {string.format("%.2f", eventHour)}h.`)
end

--[[
	[Public Method] [Server only]
	Removes a time event. Replicates to all Clients.
	@param eventName The name of the event to remove.
	@return True if the event was found and removed, false otherwise.
]]
function DayNightCycle.RemoveTimeEvent(eventName: string): boolean
	if not requireServer("RemoveTimeEvent") then
		return false
	end

	if timeEvents[eventName] == nil then
		logger:warn(`Attempted to remove non-existent event: '{eventName}'.`)
		return false
	end

	timeEvents[eventName] = nil
	Replication.publishTimeEvents(script, timeEvents)

	logger:debug(`Removed time event: '{eventName}'.`)
	return true
end

--[[
	[Public Method] [Server only]
	Freezes game time at the current moment. Time events do not fire while paused.
]]
function DayNightCycle.Pause()
	if not requireServer("Pause") then
		return
	end
	if clockState and clockState.Paused then
		return
	end

	reanchorClock({ Paused = true })
	logger:debug("Day/Night cycle paused.")
end

--[[
	[Public Method] [Server only]
	Resumes game time from where it was paused.
]]
function DayNightCycle.Resume()
	if not requireServer("Resume") then
		return
	end
	if clockState and not clockState.Paused then
		return
	end

	reanchorClock({ Paused = false })
	logger:debug("Day/Night cycle resumed.")
end

--[[
	[Public Method] [Server only]
	Jumps to a time of day on the current day. `Day` is not changed.
	@param hour The hour (0-24) to jump to.
	@param fireSkippedEvents If true, events between the current time and the new time
	(moving forward, wrapping past midnight) fire in order. Otherwise the jump is silent.
]]
function DayNightCycle.SetTime(hour: number, fireSkippedEvents: boolean?)
	if not requireServer("SetTime") then
		return
	end

	assert(
		typeof(hour) == "number" and hour >= 0 and hour <= HOURS_PER_DAY,
		"hour must be a number between 0 and 24"
	)

	reanchorClock({ Hour = hour, FireSkippedEvents = fireSkippedEvents })
	logger:debug(`Day/Night cycle time set to {string.format("%.2f", hour)}h.`)
end

--[[
	[Public Method] [Server only]
	Changes how many real-world minutes a full game day lasts, keeping the current time.
	@param minutes Real-world minutes for a full 24-hour game day.
]]
function DayNightCycle.SetDayLength(minutes: number)
	if not requireServer("SetDayLength") then
		return
	end

	assert(
		typeof(minutes) == "number" and minutes > 0 and minutes < math.huge,
		"minutes must be a positive number"
	)

	reanchorClock({ DayLengthSeconds = minutes * SECONDS_PER_MINUTE })
	logger:debug(`Day/Night cycle day length set to {minutes} real-world minutes.`)
end

--[[
	[Public Method]
	Returns the current in-game time. Before the cycle has started (or, on a Client, before
	the Server's state arrives), this is the current Lighting time.
	@return The current time in hours (0-24).
]]
function DayNightCycle.GetCurrentTime(): number
	const state = clockState
	if not state then
		return Lighting:GetMinutesAfterMidnight() / MINUTES_PER_HOUR
	end

	const currentHour = Clock.getTime(state, getServerTime())
	return currentHour
end

--[[
	[Public Method]
	Returns the current day number, which starts at `Config.StartDay` and increases each
	midnight. Before the cycle has started this is `Config.StartDay`.
]]
function DayNightCycle.GetDay(): number
	const state = clockState
	if not state then
		return Config.StartDay
	end

	const _currentHour, currentDay = Clock.getTime(state, getServerTime())
	return currentDay
end

--[[
	[Public Method]
	Returns whether game time is currently paused.
]]
function DayNightCycle.IsPaused(): boolean
	const state = clockState
	return state ~= nil and state.Paused
end

return table.freeze(DayNightCycle)
