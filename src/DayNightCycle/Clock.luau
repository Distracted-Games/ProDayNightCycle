--!strict

--[[
	Clock
	@author DistractedGames

	Pure time math for the day/night cycle. Holds no state of its own: every function
	takes a `ClockState` and a server time and returns the game hour and day number.
	Keeping this free of Roblox services makes it testable outside of Studio.
]]

const Timeline = require("./Timeline")
const Types = require("./Types")

const HOURS_PER_DAY = 24

--[[
	Describes what should change when the clock is re-anchored. Anything left nil is
	carried over from the current state.
	- Hour: Jump to this game hour (0-24) on the current day.
- Day: Set the day number.
	- DayLengthSeconds: Use a new real-world day length.
	- Paused: Freeze or unfreeze game time.
	- FireSkippedEvents: Marks the anchor as one whose skipped events should fire.
]]
export type Changes = {
	Hour: number?,
	Day: number?,
	DayLengthSeconds: number?,
	Paused: boolean?,
	FireSkippedEvents: boolean?,
}

const Clock = {}

--[[
	Creates the initial clock state.
	@param startHour The game hour (0-24) to start at.
	@param startDay The day number to start at.
	@param dayLengthSeconds Real-world seconds for a full 24-hour game day.
	@param serverNow The current server time in seconds.
]]
function Clock.create(
	startHour: number,
	startDay: number,
	dayLengthSeconds: number,
	serverNow: number
): Types.ClockState
	return {
		Revision = 1,
		AnchorServerTime = serverNow,
		AnchorHour = startHour % HOURS_PER_DAY,
		AnchorDay = startDay,
		DayLengthSeconds = dayLengthSeconds,
		Paused = false,
	}
end

--[[
	Calculates the game time at a given server time.
	@param state The clock state.
	@param serverNow The current server time in seconds.
	@param timeline Maps the cycle position to a game hour (see Timeline).
	@return The game hour (0-24) and the day number.
]]
function Clock.getTime(
	state: Types.ClockState,
	serverNow: number,
	timeline: Timeline.Timeline
): (number, number)
	-- Server time can step back slightly when the engine re-syncs it; never run backwards.
	const elapsedSeconds = if state.Paused
		then 0
		else math.max(serverNow - state.AnchorServerTime, 0)

	-- The cycle position advances at a constant rate; the timeline turns it into an hour.
	const totalPosition = Timeline.hourToPosition(timeline, state.AnchorHour)
		+ elapsedSeconds / state.DayLengthSeconds
	const wholeDays = math.floor(totalPosition)

	return Timeline.positionToHour(timeline, totalPosition - wholeDays), state.AnchorDay + wholeDays
end

--[[
	Limits how far back event detection reaches after a stall. Events are detected from the
	hour at the previous step to the current hour; if the previous step was long ago (a
	backgrounded app, a loading hitch), only events from the last `windowSeconds` are still
	recent enough to fire, and the older ones are skipped.
	@param state The clock state that was running at the previous step.
	@param previousHour The game hour at the previous step.
	@param previousServerTime The server time of the previous step.
	@param serverNow The current server time in seconds.
	@param windowSeconds How many real-world seconds back events may still fire.
	@return The hour to detect events from.
]]
function Clock.getEventStartHour(
	state: Types.ClockState,
	timeline: Timeline.Timeline,
	previousHour: number,
	previousServerTime: number,
	serverNow: number,
	windowSeconds: number
): number
	-- Never reach back over half a day, where "forward" and "backward" cannot be told apart.
	const reachSeconds = math.min(windowSeconds, state.DayLengthSeconds / 2)
	if serverNow - previousServerTime <= reachSeconds then
		return previousHour
	end

	const startHour = Clock.getTime(state, serverNow - reachSeconds, timeline)
	return startHour
end

--[[
	Creates a new clock state anchored at the current moment, applying the given changes.
	The game time does not jump unless `changes.Hour` is given.
	@param state The current clock state.
	@param serverNow The current server time in seconds.
	@param timeline Maps the cycle position to a game hour (see Timeline).
	@param changes What to change about the clock.
]]
function Clock.reanchor(
	state: Types.ClockState,
	serverNow: number,
	timeline: Timeline.Timeline,
	changes: Changes
): Types.ClockState
	const currentHour, currentDay = Clock.getTime(state, serverNow, timeline)

	return {
		Revision = state.Revision + 1,
		AnchorServerTime = serverNow,
		AnchorHour = (if changes.Hour then changes.Hour else currentHour) % HOURS_PER_DAY,
		AnchorDay = if changes.Day then changes.Day else currentDay,
		DayLengthSeconds = if changes.DayLengthSeconds
			then changes.DayLengthSeconds
			else state.DayLengthSeconds,
		Paused = if changes.Paused ~= nil then changes.Paused else state.Paused,
		FireSkippedEvents = changes.FireSkippedEvents,
	}
end

return table.freeze(Clock)
