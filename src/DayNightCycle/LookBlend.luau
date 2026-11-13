--!strict

--[[
	LookBlend
	@author DistractedGames

	Pure logic for the phases' lighting looks: checking them, filling in the properties a
	phase leaves out, and working out how far the lighting has blended from the previous
	phase's look to the current one at a given hour. Applying the values to `Lighting` is
	the LightingController's job. Free of Roblox services so it can be tested outside of Studio.
]]

const LookTargets = require("./LookTargets")
const Timeline = require("./Timeline")
const Types = require("./Types")

const HOURS_PER_DAY = 24

-- Game hours spent blending into a phase's look when the phase does not say.
const DEFAULT_BLEND_HOURS = 0.75

--[[
	How far the lighting has moved from one look to the next.
	- Phase: The current phase, whose look is being blended towards.
	- PreviousPhase: The phase before it, whose look is being blended away from.
	- Alpha: 0 (entirely the previous look) to 1 (entirely the current look), eased.
]]
export type Blend = {
	Phase: string,
	PreviousPhase: string,
	Alpha: number,
}

--[[
	Property values by target name, then property name.
]]
export type LookValues = { [string]: { [string]: any } }

const LookBlend = {}

--[[
	Views a look as property values by target and property name, so that the targets and
	properties can be iterated by name.
]]
local function toValues(look: Types.Look): LookValues
	const values: any = look
	return values
end

--[[
	Asserts that the phases' blend times and looks are valid.
]]
function LookBlend.validate(phases: { Types.PhaseConfig })
	for _, phase in phases do
		const blendHours = phase.BlendHours
		assert(
			blendHours == nil or (blendHours >= 0 and blendHours < math.huge),
			`Phase '{phase.Name}' must have a BlendHours of 0 or more.`
		)

		const look = phase.Look
		if look == nil then
			continue
		end

		for targetName, properties in toValues(look) do
			const target = LookTargets[targetName]
			assert(target, `Phase '{phase.Name}' has an unknown look target '{targetName}'.`)

			for propertyName in properties do
				assert(
					target.Properties[propertyName],
					`Phase '{phase.Name}' has an unknown {targetName} property '{propertyName}'.`
				)
			end
		end
	end
end

--[[
	Returns each phase's blend time in game hours, filling in the default.
]]
function LookBlend.getBlendHours(phases: { Types.PhaseConfig }): { [string]: number }
	const blendHours: { [string]: number } = {}
	for _, phase in phases do
		blendHours[phase.Name] = if phase.BlendHours ~= nil
			then phase.BlendHours
			else DEFAULT_BLEND_HOURS
	end

	return blendHours
end

--[[
	Works out the complete look for every phase. A property a phase leaves out takes the value
	from the closest earlier phase (wrapping past midnight) that sets it, so every phase has
	a value for every property that any phase sets.
	@return The look values by phase name.
]]
function LookBlend.resolve(
	timeline: Timeline.Timeline,
	phases: { Types.PhaseConfig }
): { [string]: LookValues }
	const ownValues: { [string]: LookValues } = {}
	const usedProperties: { [string]: { [string]: boolean } } = {}

	for _, phase in phases do
		const values: LookValues = {}
		ownValues[phase.Name] = values

		const look = phase.Look
		if look == nil then
			continue
		end

		for targetName, properties in toValues(look) do
			values[targetName] = table.clone(properties)

			const used = usedProperties[targetName] or {}
			usedProperties[targetName] = used
			for propertyName in properties do
				used[propertyName] = true
			end
		end
	end

	const phaseInfos = timeline.Phases
	const phaseCount = #phaseInfos
	const resolved: { [string]: LookValues } = {}

	for index, info in phaseInfos do
		const values: LookValues = {}
		resolved[info.Name] = values

		for targetName, used in usedProperties do
			const targetValues: { [string]: any } = {}
			values[targetName] = targetValues

			for propertyName in used do
				for stepsBack = 0, phaseCount - 1 do
					const earlierName = phaseInfos[(index - 1 - stepsBack) % phaseCount + 1].Name
					const earlierTarget = ownValues[earlierName][targetName]
					const value = if earlierTarget ~= nil then earlierTarget[propertyName] else nil
					if value ~= nil then
						targetValues[propertyName] = value
						break
					end
				end
			end
		end
	end

	return resolved
end

--[[
	Calculates the blend at a game hour. The lighting blends from the previous phase's look
	to the current phase's over the first `blendHours` of the current phase (limited to its
	length), and then holds the current look.
	@param timeline The timeline built from the same phases.
	@param blendHours Each phase's blend time in game hours (see `getBlendHours`).
	@param hour The game hour.
	@return The blend, or nil if no phases are configured.
]]
function LookBlend.getBlend(
	timeline: Timeline.Timeline,
	blendHours: { [string]: number },
	hour: number
): Blend?
	const phaseInfos = timeline.Phases
	const phaseCount = #phaseInfos
	if phaseCount == 0 then
		return nil
	end

	-- The current phase is the last one to have started; before the first start of the day,
	-- the last phase of the previous day is still running.
	const wrappedHour = hour % HOURS_PER_DAY
	local index = phaseCount
	for candidateIndex, info in phaseInfos do
		if wrappedHour >= info.StartHour then
			index = candidateIndex
		end
	end

	const phase = phaseInfos[index]
	const previousPhase = phaseInfos[(index - 2) % phaseCount + 1]

	const hoursIntoPhase = (wrappedHour - phase.StartHour) % HOURS_PER_DAY
	const blendLength = math.min(blendHours[phase.Name], phase.LengthHours)
	const progress = if blendLength > 0 then math.clamp(hoursIntoPhase / blendLength, 0, 1) else 1

	return {
		Phase = phase.Name,
		PreviousPhase = previousPhase.Name,
		-- Smoothstep, so the lighting eases in and out of each blend.
		Alpha = progress * progress * (3 - 2 * progress),
	}
end

return table.freeze(LookBlend)
