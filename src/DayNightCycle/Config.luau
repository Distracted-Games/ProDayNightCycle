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
}

return Config
