--!strict

--[[
	Types
	@author DistractedGames

	Shared type definitions for the DayNightCycle modules.
]]

--[[
	A dictionary mapping event names to game hours (0-24).
]]
export type TimeEventMap = { [string]: number }

--[[
	The source-editable configuration (see Config.luau).
	- DayLengthInMinutes: Real-world minutes for a full 24-hour game day.
	- StartTimeOfDay: Optional start time in hours (0-24). If nil, uses the current Lighting time.
	- StartDay: The value of `Day` when the cycle starts. Each game decides what a "day" means.
	- TimeEvents: A dictionary mapping event names to game hours (0-24).
]]
export type Config = {
	DayLengthInMinutes: number,
	StartTimeOfDay: number?,
	StartDay: number,
	TimeEvents: TimeEventMap,
}

--[[
	The authoritative clock, published by the server and observed by clients.
	Every machine derives the current time from `workspace:GetServerTimeNow()`, so the
	state only needs to be republished when the clock is re-anchored (paused, resumed,
	set to a new time, or given a new day length).
	- Revision: Increases by one each time the clock is re-anchored.
	- AnchorServerTime: The server time (seconds) at which the clock was anchored.
	- AnchorHour: The game hour (0-24) at the anchor.
	- AnchorDay: The day number at the anchor.
	- DayLengthSeconds: Real-world seconds for a full 24-hour game day.
	- Paused: Whether game time is frozen at the anchor hour.
	- FireSkippedEvents: True if this anchor came from `SetTime` and the events between the
	  previous time and the new time should fire.
]]
export type ClockState = {
	Revision: number,
	AnchorServerTime: number,
	AnchorHour: number,
	AnchorDay: number,
	DayLengthSeconds: number,
	Paused: boolean,
	FireSkippedEvents: boolean?,
}

const Types = {}

return Types
