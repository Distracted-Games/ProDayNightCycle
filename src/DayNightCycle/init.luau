--!strict
--[[
    DayNightCycle
    @author DistractedGames
    @version 3.0.0

    Manages the in-game day/night cycle, driven by a configurable real-world
    duration. It provides a robust event system to trigger actions at specific
    times of day (e.g., "Dawn", "Sunset").

    This module now runs seamlessly on both Client and Server.
    The Server tracks time logic and broadcasts state to Clients via a RemoteEvent.
    Clients handle the visual updates (`Lighting:SetMinutesAfterMidnight`) and fire
    local events, while the Server also fires events for Server-side listeners.
--]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Logger = require("./DayNightCycle/Logger")
local Signal = require("./DayNightCycle/Signal")

local isServer = RunService:IsServer()
local isClient = RunService:IsClient()

local logger = Logger.new({
	Debug = true, -- Toggles verbose logging for this module.
	Prefix = "DayNightCycle",
})

local DayNightCycle = {}

--[[
	Type definition for the module's configuration.
	- DayLengthInMinutes: Real-world minutes for a full 24-hour game day.
	- StartTimeOfDay: Optional specific start time in hours (0-24). If nil, uses current lighting.
	- TimeEvents: A dictionary mapping event names to game hours (0-24).
]]
export type DayNightCycleConfig = {
	DayLengthInMinutes: number,
	StartTimeOfDay: number?,
	TimeEvents: { [string]: number },
}

-- Default configuration, can be customized before Start() is called.
local config: DayNightCycleConfig = {
	DayLengthInMinutes = 180, -- A 3 hour day/night cycle.
	StartTimeOfDay = nil, -- Uses existing Lighting time by default.
	TimeEvents = {
		Dawn = 4.75, -- 4:45 AM
		Sunrise = 5.75, -- 5:45 AM
		Midday = 12.0, -- 12:00 PM
		Sunset = 17.6, -- 5:36 PM
		Dusk = 18.25, -- 6:15 PM
		Midnight = 0.0, -- 12:00 AM
	},
}

local connection: RBXScriptConnection?
local isRunning = false
local lastHourTriggered = -1
local triggeredEvents: { [string]: boolean } = {}
local timeRatio = 0
local cycleStartTime = 0
local startMinutesOffset = 0

local MINUTES_IN_DAY = 1440 -- 24 hours * 60 minutes

-- Signals & Networking
local remotesFolder: Folder
if isServer then
	remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not remotesFolder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Remotes"
		newFolder.Parent = ReplicatedStorage
		remotesFolder = newFolder
	end
else
	remotesFolder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local remoteEvent: RemoteEvent
if isServer then
	remoteEvent = remotesFolder:FindFirstChild("DayNightCycleRemote") :: RemoteEvent
	if not remoteEvent then
		remoteEvent = Instance.new("RemoteEvent")
		remoteEvent.Name = "DayNightCycleRemote"
		remoteEvent.Parent = remotesFolder
	end
else
	remoteEvent = remotesFolder:WaitForChild("DayNightCycleRemote") :: RemoteEvent
end

DayNightCycle.TimeEvent = Signal.new()

--[[
	Converts minutes after midnight to a 24-hour format.
	@param minutes The number of minutes past midnight.
	@return The time in hours (0-24).
]]
local function minutesToHours(minutes: number): number
	return minutes / 60
end

--[[
	Checks and fires time-based events based on the current hour.
	Resets triggered events daily at midnight.
	Handles skipped frames/time accurately.
	@param currentHour The current in-game hour.
]]
local function checkTimeEvents(currentHour: number)
	local wrapped = false

	if currentHour < lastHourTriggered then
		-- Midnight has passed, reset all triggered events for the new day.
		wrapped = true
		triggeredEvents = {}
		logger:debug("A new day has begun. Resetting daily time events.")
	end

	for eventName, eventHour in config.TimeEvents do
		if triggeredEvents[eventName] then
			continue
		end

		local shouldTrigger = false

		if wrapped then
			-- If time wrapped, check if the event fell in the remaining time of
			-- yesterday, or the new time of today
			shouldTrigger = (lastHourTriggered <= eventHour and eventHour < 24) or (eventHour <= currentHour)
		else
			-- Normal time progression
			shouldTrigger = (lastHourTriggered <= eventHour and currentHour >= eventHour)
		end

		if shouldTrigger then
			triggeredEvents[eventName] = true
			DayNightCycle.TimeEvent:Fire(eventName, eventHour)
			logger:debug(`Time event triggered: '{eventName}' at {string.format("%.1f", eventHour)}h.`)
		end
	end

	lastHourTriggered = currentHour
end

--[[
	Core update function connected to Heartbeat. Calculates and sets the
	new time of day.
]]
local function onHeartbeat()
	local elapsed = time() - cycleStartTime
	local totalMinutes = (startMinutesOffset + (elapsed * timeRatio)) % MINUTES_IN_DAY

	-- Only the Client manages the visual Lighting property to save network bandwidth
	if isClient then
		Lighting:SetMinutesAfterMidnight(totalMinutes)
	end

	local currentHour = minutesToHours(totalMinutes)
	checkTimeEvents(currentHour)
end

-- Setup Client Remote Listeners
if isClient then
	remoteEvent.OnClientEvent:Connect(function(action: string, ...: any)
		if action == "Sync" or action == "Start" then
			local sentCurrentMinutes, sentTimeRatio, serverTimeEvents = ...

			config.TimeEvents = serverTimeEvents
			timeRatio = sentTimeRatio
			startMinutesOffset = sentCurrentMinutes
			cycleStartTime = time()

			lastHourTriggered = minutesToHours(startMinutesOffset)

			if not isRunning then
				isRunning = true
				connection = RunService.Heartbeat:Connect(onHeartbeat)
			end

			logger:debug(`Client DayNightCycle {action == "Start" and "started" or "synced"}.`)
		elseif action == "Stop" then
			DayNightCycle.StopCycle()
		elseif action == "AddEvent" then
			local eventName, eventHour = ...
			config.TimeEvents[eventName] = eventHour
		elseif action == "RemoveEvent" then
			local eventName = ...
			config.TimeEvents[eventName] = nil
		end
	end)
end

-- Setup Server Remote Listeners
if isServer then
	remoteEvent.OnServerEvent:Connect(function(player: Player, action: string)
		if action == "RequestSync" and isRunning then
			-- Calculate current minutes
			local elapsed = time() - cycleStartTime
			local currentMinutes = (startMinutesOffset + (elapsed * timeRatio)) % MINUTES_IN_DAY

			-- Send current state to the late-joining client
			remoteEvent:FireClient(player, "Sync", currentMinutes, timeRatio, config.TimeEvents)
		end
	end)
end

--[[
	[Public Method]
	Starts the day/night cycle. Connects the update function to RunService.Heartbeat.
	Calling it again will have no effect.
]]
function DayNightCycle.StartCycle()
	if isRunning then
		logger:warn("StartCycle called but the cycle is already running.")
		return
	end
	isRunning = true

	local dayInSeconds = config.DayLengthInMinutes * 60
	timeRatio = MINUTES_IN_DAY / dayInSeconds
	cycleStartTime = time()

	startMinutesOffset = Lighting:GetMinutesAfterMidnight()
	if config.StartTimeOfDay then
		startMinutesOffset = config.StartTimeOfDay * 60
	end

	-- Initialize lastHourTriggered so events don't immediately burst on start
	lastHourTriggered = minutesToHours(startMinutesOffset)

	-- Apply time to lighting if we are on the client (or running local test)
	if isClient then
		Lighting:SetMinutesAfterMidnight(startMinutesOffset)
	end

	connection = RunService.Heartbeat:Connect(onHeartbeat)

	if isServer then
		remoteEvent:FireAllClients("Start", startMinutesOffset, timeRatio, config.TimeEvents)
	end

	logger:debug(`Day/Night cycle started. Game day lasts {config.DayLengthInMinutes} real-world minutes.`)
end

--[[
	[Public Method]
	Stops the day/night cycle.
]]
function DayNightCycle.StopCycle()
	if not isRunning then
		return
	end
	isRunning = false

	if connection then
		connection:Disconnect()
		connection = nil
	end

	if isServer then
		remoteEvent:FireAllClients("Stop")
	end

	logger:debug("Day/Night cycle stopped.")
end

--[[
    [Public Method]
    Adds or updates a custom time event.
    @param eventName The unique name for the event.
    @param eventHour The hour (0-24) to trigger the event.
]]
function DayNightCycle.AddTimeEvent(eventName: string, eventHour: number)
	assert(typeof(eventName) == "string", "eventName must be a string")
	assert(
		typeof(eventHour) == "number" and eventHour >= 0 and eventHour < 24,
		"eventHour must be a number between 0 and 23.99"
	)

	config.TimeEvents[eventName] = eventHour

	if isServer then
		remoteEvent:FireAllClients("AddEvent", eventName, eventHour)
	end

	logger:debug(`Added time event: {eventName} at {string.format("%.1f", eventHour)}h.`)
end

--[[
	[Public Method]
	Removes a time event.
	@param eventName The name of the event to remove.
	@return True if the event was found and removed, false otherwise.
--]]
function DayNightCycle.RemoveTimeEvent(eventName: string): boolean
	if config.TimeEvents[eventName] then
		config.TimeEvents[eventName] = nil

		if isServer then
			remoteEvent:FireAllClients("RemoveEvent", eventName)
		end

		logger:debug(`Removed time event: '{eventName}'.`)
		return true
	end
	logger:warn(`Attempted to remove non-existent event: '{eventName}'.`)
	return false
end

--[[
    [Public Method]
    Returns the current in-game time.
    @return The current time in hours (0-24).
]]
function DayNightCycle.GetCurrentTime(): number
	local elapsed = time() - cycleStartTime
	local totalMinutes = (startMinutesOffset + (elapsed * timeRatio)) % MINUTES_IN_DAY
	return minutesToHours(totalMinutes)
end

--[[
    ModuleLoader Lifecycle: Start
    Starts the actual day/night cycle. This runs after all modules have been
    through their Setup phase.
    
    NOTE: If this module is placed in ReplicatedStorage, the ModuleLoader will
    only automatically call Start() on the Client. You must manually call 
    DayNightCycle.Start() from your ServerStart script (after all modules have started).

	If you're not using the ModuleLoader at all, you will manually need to call
	Start() from both the client and the server.
]]
function DayNightCycle.Start()
	logger:debug(`Starting Day/Night Cycle...`)

	if isServer then
		DayNightCycle.StartCycle()
	else
		-- When the client's module loader starts this, it should request state from the server
		-- in case the cycle is already running.
		remoteEvent:FireServer("RequestSync")
	end
end

return table.freeze(DayNightCycle)
