--!strict

--[[
	Timeline
	@author DistractedGames

	Maps between game hours and a cycle position so that each phase of the day can pass at
	its own speed. The position runs from 0 (midnight) up to 1 (the next midnight) at a
	constant real-world rate, and each phase takes up a slice of it sized by its `TimeShare`.
	A phase that crosses midnight is split into two segments.

	Pure and free of Roblox services so it can be tested outside of Studio.
]]

const Types = require("./Types")

const HOURS_PER_DAY = 24

-- Phase names are published as attributes, which limit string values to 50 characters.
const MAX_PHASE_NAME_LENGTH = 50

--[[
	A stretch of the day with one phase and one speed. Segments are sorted, contiguous and
	cover hours 0-24 and positions 0-1.
	- Phase: The phase name, or nil if no phases are configured.
]]
export type Segment = {
	Phase: string?,
	StartHour: number,
	EndHour: number,
	StartPosition: number,
	EndPosition: number,
}

--[[
	A configured phase, with where it starts and how long it lasts in game hours.
	- StartHour: The hour (0-24) the phase starts.
	- LengthHours: Game hours until the next phase starts (24 if it is the only phase).
]]
export type PhaseInfo = {
	Name: string,
	StartHour: number,
	LengthHours: number,
}

--[[
	- Segments: The stretches of the day, in order.
	- Phases: The configured phases, sorted by start hour. Empty if none are configured.
]]
export type Timeline = {
	Segments: { Segment },
	Phases: { PhaseInfo },
}

type ResolvedPhase = {
	Name: string,
	StartHour: number,
	TimeShare: number?,
}

type Piece = {
	Phase: string?,
	StartHour: number,
	EndHour: number,
	Weight: number,
}

const Timeline = {}

--[[
	Looks up each phase's start hour, checks the phases, and sorts them by start hour.
]]
local function resolvePhases(
	phases: { Types.PhaseConfig },
	eventHours: Types.TimeEventMap
): { ResolvedPhase }
	const resolved: { ResolvedPhase } = {}
	const usedNames: { [string]: boolean } = {}

	for _, phase in phases do
		const name = phase.Name
		assert(typeof(name) == "string" and name ~= "", "Every phase needs a name.")
		assert(
			#name <= MAX_PHASE_NAME_LENGTH,
			`Phase '{name}' must have a name of at most {MAX_PHASE_NAME_LENGTH} characters.`
		)
		assert(not usedNames[name], `Phase '{name}' is listed more than once.`)
		usedNames[name] = true

		const startHour = eventHours[phase.StartEvent]
		assert(
			startHour ~= nil,
			`Phase '{name}' starts at event '{phase.StartEvent}', which is not in Config.TimeEvents.`
		)

		const timeShare = phase.TimeShare
		assert(
			timeShare == nil or (timeShare > 0 and timeShare < math.huge),
			`Phase '{name}' must have a TimeShare greater than 0.`
		)

		table.insert(resolved, { Name = name, StartHour = startHour, TimeShare = timeShare })
	end

	table.sort(resolved, function(first: ResolvedPhase, second: ResolvedPhase)
		return first.StartHour < second.StartHour
	end)

	for index = 2, #resolved do
		assert(
			resolved[index].StartHour ~= resolved[index - 1].StartHour,
			`Phases '{resolved[index - 1].Name}' and '{resolved[index].Name}' start at the same hour.`
		)
	end

	return resolved
end

--[[
	Returns how many game hours the phase at `index` lasts, and whether it crosses midnight.
]]
local function measurePhase(phases: { ResolvedPhase }, index: number): (number, boolean)
	const startHour = phases[index].StartHour
	const nextStartHour = phases[index % #phases + 1].StartHour
	const wrapsMidnight = nextStartHour <= startHour

	return if wrapsMidnight
		then HOURS_PER_DAY - startHour + nextStartHour
		else nextStartHour - startHour,
		wrapsMidnight
end

--[[
	Splits the sorted phases into pieces that each sit within a single day, weighting each
	piece by its share of the phase's time.
]]
local function createPieces(phases: { ResolvedPhase }): { Piece }
	const pieces: { Piece } = {}

	for index, phase in phases do
		const nextStartHour = phases[index % #phases + 1].StartHour
		const phaseHours, wrapsMidnight = measurePhase(phases, index)
		const timeShare = if phase.TimeShare ~= nil then phase.TimeShare else phaseHours

		if wrapsMidnight then
			table.insert(pieces, {
				Phase = phase.Name,
				StartHour = phase.StartHour,
				EndHour = HOURS_PER_DAY,
				Weight = timeShare * (HOURS_PER_DAY - phase.StartHour) / phaseHours,
			})
			if nextStartHour > 0 then
				table.insert(pieces, {
					Phase = phase.Name,
					StartHour = 0,
					EndHour = nextStartHour,
					Weight = timeShare * nextStartHour / phaseHours,
				})
			end
		else
			table.insert(pieces, {
				Phase = phase.Name,
				StartHour = phase.StartHour,
				EndHour = nextStartHour,
				Weight = timeShare,
			})
		end
	end

	table.sort(pieces, function(first: Piece, second: Piece)
		return first.StartHour < second.StartHour
	end)

	return pieces
end

local function findSegmentByHour(timeline: Timeline, hour: number): Segment
	for _, segment in timeline.Segments do
		if hour < segment.EndHour then
			return segment
		end
	end

	return timeline.Segments[#timeline.Segments]
end

local function findSegmentByPosition(timeline: Timeline, position: number): Segment
	for _, segment in timeline.Segments do
		if position < segment.EndPosition then
			return segment
		end
	end

	return timeline.Segments[#timeline.Segments]
end

--[[
	Builds a timeline. Asserts if the phases are invalid.
	@param phases The configured phases. If empty, time passes at a constant speed.
	@param eventHours The hours of the time events, used to find where each phase starts.
]]
function Timeline.create(phases: { Types.PhaseConfig }, eventHours: Types.TimeEventMap): Timeline
	const resolved = if #phases == 0 then {} else resolvePhases(phases, eventHours)
	const pieces: { Piece } = if #resolved == 0
		then { { StartHour = 0, EndHour = HOURS_PER_DAY, Weight = 1 } }
		else createPieces(resolved)

	const phaseInfos: { PhaseInfo } = {}
	for index, phase in resolved do
		const lengthHours = measurePhase(resolved, index)
		table.insert(
			phaseInfos,
			{ Name = phase.Name, StartHour = phase.StartHour, LengthHours = lengthHours }
		)
	end

	local totalWeight = 0
	for _, piece in pieces do
		totalWeight += piece.Weight
	end

	const segments: { Segment } = {}
	local elapsedWeight = 0
	for index, piece in pieces do
		const startPosition = elapsedWeight / totalWeight
		elapsedWeight += piece.Weight

		table.insert(segments, {
			Phase = piece.Phase,
			StartHour = piece.StartHour,
			EndHour = piece.EndHour,
			StartPosition = startPosition,
			-- Exactly 1 at the end, so floating point error cannot leave a gap.
			EndPosition = if index == #pieces then 1 else elapsedWeight / totalWeight,
		})
	end

	return { Segments = segments, Phases = phaseInfos }
end

--[[
	Converts a game hour to a cycle position.
	@param hour The game hour (any value; it wraps into 0-24).
	@return The position, from 0 (midnight) up to but not including 1.
]]
function Timeline.hourToPosition(timeline: Timeline, hour: number): number
	const wrappedHour = hour % HOURS_PER_DAY
	const segment = findSegmentByHour(timeline, wrappedHour)
	const progress = (wrappedHour - segment.StartHour) / (segment.EndHour - segment.StartHour)

	return segment.StartPosition + progress * (segment.EndPosition - segment.StartPosition)
end

--[[
	Converts a cycle position to a game hour.
	@param position The position, from 0 (midnight) up to but not including 1.
	@return The game hour (0-24).
]]
function Timeline.positionToHour(timeline: Timeline, position: number): number
	const segment = findSegmentByPosition(timeline, position)
	const progress = (position - segment.StartPosition)
		/ (segment.EndPosition - segment.StartPosition)

	return segment.StartHour + progress * (segment.EndHour - segment.StartHour)
end

--[[
	Returns the phase at a game hour, or nil if no phases are configured.
]]
function Timeline.getPhase(timeline: Timeline, hour: number): string?
	return findSegmentByHour(timeline, hour % HOURS_PER_DAY).Phase
end

return table.freeze(Timeline)
