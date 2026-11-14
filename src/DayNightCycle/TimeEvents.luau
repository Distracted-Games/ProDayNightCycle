--!strict

--[[
	TimeEvents
	@author DistractedGames

	Pure detection of which named time events were crossed as the clock moved forward.
	An event is crossed when its hour lies in the half-open range (fromHour, toHour], which
	handles the midnight wrap and removes any need to remember which events already fired.
	The caller must only pass ranges that moved forward by less than a day (the Server time
	it derives them from never runs backwards).
	Keeping this free of Roblox services makes it testable outside of Studio.
]]

const Types = require("./Types")

const HOURS_PER_DAY = 24

export type EventCallback = (eventName: string, eventHour: number) -> ()

type CrossedEvent = {
	Name: string,
	Hour: number,
	Offset: number,
}

const TimeEvents = {}

local function isEarlier(first: CrossedEvent, second: CrossedEvent): boolean
	if first.Offset ~= second.Offset then
		return first.Offset < second.Offset
	end

	return first.Name < second.Name
end

--[[
	Finds the events crossed moving forward from `fromHour` to `toHour`, sorted in the order
	they were crossed. Returns nil, without allocating, when none were crossed.
]]
local function findCrossedEvents(
	events: Types.TimeEventMap,
	fromHour: number,
	toHour: number
): { CrossedEvent }?
	const span = (toHour - fromHour) % HOURS_PER_DAY
	local crossedEvents: { CrossedEvent }? = nil

	for eventName, eventHour in events do
		const offset = (eventHour - fromHour) % HOURS_PER_DAY
		if offset <= 0 or offset > span then
			continue
		end

		const crossedEvent: CrossedEvent = { Name = eventName, Hour = eventHour, Offset = offset }
		if crossedEvents then
			table.insert(crossedEvents, crossedEvent)
		else
			crossedEvents = { crossedEvent }
		end
	end

	if crossedEvents then
		table.sort(crossedEvents, isEarlier)
	end

	return crossedEvents
end

--[[
	Calls `callback` for every event crossed moving forward from `fromHour` to `toHour`
	(wrapping past midnight if `toHour` is earlier), in the order they were crossed.
	Events built on each other can therefore rely on their hour order.
	Allocates only when at least one event was crossed.
]]
function TimeEvents.forEachCrossed(
	events: Types.TimeEventMap,
	fromHour: number,
	toHour: number,
	callback: EventCallback
)
	const crossedEvents = findCrossedEvents(events, fromHour, toHour)
	if not crossedEvents then
		return
	end

	for _, crossedEvent in crossedEvents do
		callback(crossedEvent.Name, crossedEvent.Hour)
	end
end

return table.freeze(TimeEvents)
