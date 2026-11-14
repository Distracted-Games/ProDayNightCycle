--!strict
--[[
	DayNightCycle
	@author DistractedGames
	@version 4.0.1

	Runs a game's day/night cycle from server start to shutdown, driven by a configurable
	real-world duration (see Config.luau). Fires named events at specific times of day
	(e.g. "Dawn", "Sunset") on both the Server and the Clients.

	The Server owns the clock and replicates it with attributes. Every machine derives the
	current time from `workspace:GetServerTimeNow()`, so there is no per-frame network
	traffic and late joiners are in sync immediately. Clients apply the time to `Lighting`.

	The day is divided into phases (see Config.luau), each with a `TimeShare` that sets how
	fast it passes in real-world time, so that e.g. the night can pass faster than the day.
	Each phase can also have a `Look`: on Clients the lighting blends from one phase's look to
	the next (set `Config.Lighting.Enabled = false` to control the lighting yourself).

	Public state for HUDs is published as attributes on `Lighting`
	(see `DayNightCycle.AttributeNames`):
	- Day: The current day number. Each game decides what a "day" means.
	- IsPaused: Whether game time is paused.
	- Phase: The name of the current phase of the day (not set if no phases are configured).
--]]

const Lighting = game:GetService("Lighting")
const RunService = game:GetService("RunService")

const Clock = require("./DayNightCycle/Clock")
const Config = require("./DayNightCycle/Config")
const LightingController = require("./DayNightCycle/LightingController")
const Logger = require("./DayNightCycle/Logger")
const LookBlend = require("./DayNightCycle/LookBlend")
const Replication = require("./DayNightCycle/Replication")
const Signal = require("./DayNightCycle/Signal")
const TimeEvents = require("./DayNightCycle/TimeEvents")
const Timeline = require("./DayNightCycle/Timeline")
const Types = require("./DayNightCycle/Types")

const HOURS_PER_DAY = 24

-- After a stall (a backgrounded app, a long hitch), only time events from the last this many
-- real-world seconds still fire; older ones are skipped instead of replayed all at once.
const CATCH_UP_SECONDS = 30
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
const phaseChanged: Signal.Signal<string, string> = Signal.new()

-- Maps the cycle position to game hours so each phase passes at its own speed.
const timeline = Timeline.create(Config.Phases, Config.TimeEvents)
LookBlend.validate(Config.Phases)

-- The events that start phases. They are owned by the phases and cannot be changed.
const phaseEventNames: { [string]: boolean } = {}
for _, phase in Config.Phases do
	phaseEventNames[phase.StartEvent] = true
end

-- The Server owns the events (seeded from Config); Clients receive them from the Server.
local timeEvents: Types.TimeEventMap = if IS_SERVER then table.clone(Config.TimeEvents) else {}
local clockState: Types.ClockState? = nil
local previousHour = 0
local previousServerTime = 0
local latestServerTime = 0
local fireSkippedEventsPending = false
local publishedDay: number? = nil
local currentPhase: string? = nil
local lastRevision: number? = nil
local hasStarted = false
local heartbeatConnection: RBXScriptConnection? = nil

const DayNightCycle = {
	--[[
		Fires when a configured time is reached, on both the Server and the Clients.
		Passes `eventName: string` and `eventHour: number`.
	]]
	TimeEvent = timeEvent,

	--[[
		Fires when the day moves into a new phase, on both the Server and the Clients.
		Passes `newPhase: string` and `previousPhase: string`. It also fires when the phase
		changes because of `SetTime`, so it always reflects the current state. When a
		frame brings both a phase change and time events, this fires first.
	]]
	PhaseChanged = phaseChanged,

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

	local eventCount = 0
	for eventName, eventHour in config.TimeEvents do
		Replication.assertEventName(eventName)
		assert(
			eventHour >= 0 and eventHour < HOURS_PER_DAY,
			`Config.TimeEvents.{eventName} must be a number between 0 and 23.99.`
		)
		eventCount += 1
	end

	assert(
		eventCount <= Replication.MaxTimeEvents,
		`Config.TimeEvents can have at most {Replication.MaxTimeEvents} events.`
	)
end

local function countTimeEvents(): number
	local eventCount = 0
	for _ in timeEvents do
		eventCount += 1
	end

	return eventCount
end

--[[
	Returns the server time, which never runs backwards. The engine can step its estimate of
	the server time back slightly when it re-syncs; holding the latest value keeps the game
	time, the lighting and the time events from ever moving backwards with it.
]]
local function getServerTime(): number
	latestServerTime = math.max(latestServerTime, workspace:GetServerTimeNow())
	return latestServerTime
end

--[[
	Returns the current game hour. Before the cycle has started (or, on a Client, before the
	Server's state arrives), this is the current Lighting time.
]]
local function getCurrentHour(): number
	const state = clockState
	if not state then
		return Lighting:GetMinutesAfterMidnight() / MINUTES_PER_HOUR
	end

	const currentHour = Clock.getTime(state, getServerTime(), timeline)
	return currentHour
end

local function fireTimeEvent(eventName: string, eventHour: number)
	timeEvent:Fire(eventName, eventHour)
	logger:debug(`Time event triggered: '{eventName}' at {string.format("%.2f", eventHour)}h.`)
end

type PhaseChange = {
	New: string,
	Previous: string,
}

--[[
	Tracks the current phase and publishes it (Server only). Does nothing if no phases are
	configured. Signals are fired separately (see `firePhaseChange`) so that all of the state
	is up to date before any listener runs.
	@return The change, or nil if the phase is the same. The first phase is not a change.
]]
local function commitPhase(hour: number): PhaseChange?
	const phaseName = Timeline.getPhase(timeline, hour)
	if phaseName == nil or phaseName == currentPhase then
		return nil
	end

	const previousPhase = currentPhase
	currentPhase = phaseName

	if IS_SERVER then
		Replication.publishPhase(phaseName)
	end

	if previousPhase == nil then
		return nil
	end

	return { New = phaseName, Previous = previousPhase }
end

local function firePhaseChange(change: PhaseChange?)
	if change == nil then
		return
	end

	phaseChanged:Fire(change.New, change.Previous)
	logger:debug(`Phase changed from '{change.Previous}' to '{change.New}'.`)
end

--[[
	Publishes the day number when it changes (Server only).
]]
local function publishDay(day: number)
	if not IS_SERVER or day == publishedDay then
		return
	end

	publishedDay = day
	Replication.publishDay(day)
end

--[[
	Applies the game hour to `Lighting` (Clients only).
]]
local function applyClientTime(hour: number)
	if IS_CLIENT then
		Lighting:SetMinutesAfterMidnight(hour * MINUTES_PER_HOUR)
	end
end

--[[
	Returns the current game hour, or nil until the clock has been received from the Server.
]]
local function getSyncedHour(): number?
	if not clockState then
		return nil
	end

	return getCurrentHour()
end

--[[
	Runs every frame on both the Server and the Clients. All of the state a listener could look
	at (the time, the day, the phase and the Lighting) is brought up to date first, and only
	then are the phase change and the crossed events fired. Listeners can therefore read the
	current state, and call functions like `SetTime`, without their changes being overwritten.
]]
local function onHeartbeat()
	const state = clockState
	if not state then
		return
	end

	-- A new frame: re-anchors from now on are replicated separately from earlier ones.
	fireSkippedEventsPending = false

	const serverNow = getServerTime()
	const currentHour, currentDay = Clock.getTime(state, serverNow, timeline)
	const fromHour = Clock.getEventStartHour(
		state,
		timeline,
		previousHour,
		previousServerTime,
		serverNow,
		CATCH_UP_SECONDS
	)
	previousHour = currentHour
	previousServerTime = serverNow

	applyClientTime(currentHour)
	publishDay(currentDay)
	const phaseChange = commitPhase(currentHour)

	firePhaseChange(phaseChange)
	TimeEvents.forEachCrossed(timeEvents, fromHour, currentHour, fireTimeEvent)
end

local function ensureHeartbeat()
	if not heartbeatConnection then
		heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
	end
end

--[[
	[Server] Re-anchors the clock at the current moment, applying `changes`, and publishes it.
	The new state is committed before any event fires, so listeners see it and can safely
	change the clock again.
]]
local function reanchorClock(changes: Clock.Changes)
	const state = clockState
	if not state then
		logger:warn("The cycle has not been started yet.")
		return
	end

	-- Attribute changes made in the same frame replicate as only the last one. So a re-anchor
	-- that leaves the time alone (e.g. Pause) keeps a `SetTime(hour, true)` from this frame
	-- marked, or Clients would never fire its skipped events.
	if changes.Hour ~= nil then
		fireSkippedEventsPending = changes.FireSkippedEvents == true
	elseif fireSkippedEventsPending then
		changes.FireSkippedEvents = true
	end

	const serverTime = getServerTime()
	const hourBeforeChange = Clock.getTime(state, serverTime, timeline)
	const newState = Clock.reanchor(state, serverTime, timeline, changes)

	-- Use the state exactly as clients will receive it, so every machine agrees on the time.
	const publishedState = Replication.publishClockState(script, newState)
	clockState = publishedState

	const newHour, newDay = Clock.getTime(publishedState, serverTime, timeline)
	previousHour = newHour
	previousServerTime = serverTime

	Replication.publishIsPaused(publishedState.Paused)
	publishDay(newDay)
	const phaseChange = commitPhase(newHour)

	firePhaseChange(phaseChange)
	if changes.Hour ~= nil and changes.FireSkippedEvents then
		TimeEvents.forEachCrossed(timeEvents, hourBeforeChange, newHour, fireTimeEvent)
	end
end

--[[
	[Client] Handles the Server publishing a clock state (first sync, or a re-anchor).
]]
local function onClockStateReplicated(newState: Types.ClockState)
	const serverNow = getServerTime()
	const currentHour = Clock.getTime(newState, serverNow, timeline)

	-- A client that joined after the re-anchor never saw the old time, so nothing was skipped.
	const oldState = clockState
	const isReanchor = lastRevision ~= nil and newState.Revision > lastRevision
	local skippedFromHour: number? = nil
	if oldState and isReanchor and newState.FireSkippedEvents then
		-- The jump skips everything after the moment the Server re-anchored. Events before that
		-- moment already fired, or (after a stall) are too old to fire, so start from whichever
		-- is later: the last step or the re-anchor.
		skippedFromHour = if previousServerTime >= newState.AnchorServerTime
			then previousHour
			else Clock.getTime(oldState, newState.AnchorServerTime, timeline)
	end

	-- Time may have jumped; resume event detection from the new hour without firing.
	lastRevision = newState.Revision
	clockState = newState
	previousHour = currentHour
	previousServerTime = serverNow

	applyClientTime(currentHour)
	const phaseChange = commitPhase(currentHour)
	ensureHeartbeat()

	firePhaseChange(phaseChange)
	if skippedFromHour ~= nil then
		TimeEvents.forEachCrossed(timeEvents, skippedFromHour, currentHour, fireTimeEvent)
	end
end

local function startServer()
	validateConfig(Config)

	const startHour = if Config.StartTimeOfDay
		then Config.StartTimeOfDay
		else Lighting:GetMinutesAfterMidnight() / MINUTES_PER_HOUR
	const dayLengthSeconds = Config.DayLengthInMinutes * SECONDS_PER_MINUTE
	const serverTime = getServerTime()
	const newState = Clock.create(startHour, Config.StartDay, dayLengthSeconds, serverTime)

	for eventName, eventHour in timeEvents do
		Replication.publishTimeEvent(script, eventName, eventHour)
	end

	const publishedState = Replication.publishClockState(script, newState)
	clockState = publishedState
	previousHour = publishedState.AnchorHour
	previousServerTime = serverTime

	publishDay(publishedState.AnchorDay)
	commitPhase(publishedState.AnchorHour)
	Replication.publishIsPaused(false)
	ensureHeartbeat()

	logger:debug(
		`Day/Night cycle started. A game day lasts {Config.DayLengthInMinutes} real-world minutes.`
	)
end

-- Connections live for the lifetime of the module, as the cycle runs for the whole server.
local function startClient()
	Replication.observeTimeEvents(script, function(eventName: string, eventHour: number?)
		timeEvents[eventName] = eventHour
	end)
	Replication.observeClockState(script, onClockStateReplicated)

	if Config.Lighting.Enabled then
		LightingController.start(timeline, Config.Phases, getSyncedHour)
	end

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

	Replication.assertEventName(eventName)
	if phaseEventNames[eventName] then
		logger:warn(`Cannot change '{eventName}': it starts a phase (see Config.Phases).`)
		return
	end

	assert(
		typeof(eventHour) == "number" and eventHour >= 0 and eventHour < HOURS_PER_DAY,
		"eventHour must be a number between 0 and 23.99"
	)

	if timeEvents[eventName] == nil and countTimeEvents() >= Replication.MaxTimeEvents then
		logger:warn(`Cannot add '{eventName}': at most {Replication.MaxTimeEvents} time events.`)
		return
	end

	timeEvents[eventName] = eventHour
	Replication.publishTimeEvent(script, eventName, eventHour)

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

	if phaseEventNames[eventName] then
		logger:warn(`Cannot remove '{eventName}': it starts a phase (see Config.Phases).`)
		return false
	end

	if timeEvents[eventName] == nil then
		logger:warn(`Attempted to remove non-existent event: '{eventName}'.`)
		return false
	end

	timeEvents[eventName] = nil
	Replication.publishTimeEvent(script, eventName, nil)

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
	Sets the day number, keeping the current time. Useful for restoring a saved day count when
	the server starts, or resetting it between rounds. Time events do not fire.
	@param day The new day number, a whole number.
]]
function DayNightCycle.SetDay(day: number)
	if not requireServer("SetDay") then
		return
	end

	assert(
		typeof(day) == "number" and day == math.floor(day) and math.abs(day) < math.huge,
		"day must be a whole number"
	)

	reanchorClock({ Day = day })
	logger:debug(`Day/Night cycle day set to {day}.`)
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
	return getCurrentHour()
end

--[[
	[Public Method]
	Returns the name of the current phase of the day (e.g. "Night"), or nil if no phases are
	configured. Before the cycle has started this is based on the current Lighting time.
]]
function DayNightCycle.GetPhase(): string?
	return Timeline.getPhase(timeline, getCurrentHour())
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

	const _currentHour, currentDay = Clock.getTime(state, getServerTime(), timeline)
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
