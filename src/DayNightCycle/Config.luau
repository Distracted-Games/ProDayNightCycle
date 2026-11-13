--!strict

--[[
	Config
	@author DistractedGames

	The one file meant to be edited by the developer. These values are read by the server
	when the cycle starts and are not changeable by editing this file at runtime.
	Runtime changes go through the DayNightCycle API (SetDayLength, SetTime, ...).
]]

const Types = require("./Types")

const Config: Types.Config = {
	DayLengthInMinutes = 180, -- A 3 hour day/night cycle.
	StartTimeOfDay = nil, -- Uses the existing Lighting time by default.
	StartDay = 1,
	TimeEvents = {
		Dawn = 4.75, -- 4:45 AM
		Sunrise = 5.75, -- 5:45 AM
		Midday = 12.0, -- 12:00 PM
		Sunset = 17.6, -- 5:36 PM
		Dusk = 18.25, -- 6:15 PM
		Midnight = 0.0, -- 12:00 AM
	},

	--[[
		The parts of the day. Each phase starts at the hour of its `StartEvent` and lasts until
		the next phase starts. `TimeShare` is the phase's relative share of the real-world day
		length (only the ratios matter), so it sets how fast the phase passes. These defaults
		make dusk and dawn linger briefly and the night pass faster than the day.

		Phase start events are owned by the phases: AddTimeEvent and RemoveTimeEvent refuse
		to change them. Set `Phases = {}` for a constant speed all day.
	]]
	Phases = {
		{ Name = "Night", StartEvent = "Dusk", TimeShare = 28 },
		{ Name = "Dawn", StartEvent = "Dawn", TimeShare = 4 },
		{ Name = "Day", StartEvent = "Sunrise", TimeShare = 65 },
		{ Name = "Dusk", StartEvent = "Sunset", TimeShare = 3 },
	},
}

return Config
