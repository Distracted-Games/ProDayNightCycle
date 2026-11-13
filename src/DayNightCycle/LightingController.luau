--!strict

--[[
	LightingController
	@author DistractedGames

	[Client] Applies the phases' looks to `Lighting` and its effects, blending from one look
	to the next as the day moves through the phases. Blending is driven by the game hour (not
	by tweens), so it follows the variable speed of time, pausing and `SetTime` exactly.
	Effects missing from `Lighting` are created locally.
]]

const Lighting = game:GetService("Lighting")
const RunService = game:GetService("RunService")

const LookBlend = require("./LookBlend")
const LookTargets = require("./LookTargets")
const Timeline = require("./Timeline")
const Types = require("./Types")

-- Lighting changes slowly, so there is no need to touch the properties every frame.
const UPDATES_PER_SECOND = 12
const UPDATE_INTERVAL_SECONDS = 1 / UPDATES_PER_SECOND

const LightingController = {}

--[[
	Blends two property values. Numbers and colors blend smoothly; anything else switches at
	the halfway point.
]]
local function blendValues(from: unknown, to: unknown, alpha: number): unknown
	if alpha >= 1 then
		return to
	end

	if typeof(from) == "number" and typeof(to) == "number" then
		return from + (to - from) * alpha
	end

	if typeof(from) == "Color3" and typeof(to) == "Color3" then
		return from:Lerp(to, alpha)
	end

	return if alpha < 0.5 then from else to
end

--[[
	Returns the instance a look target changes: `Lighting` itself, or the matching effect
	inside it (created if it does not exist).
]]
local function findOrCreateTarget(targetName: string): Instance
	const className = LookTargets[targetName].ClassName
	if className == nil then
		return Lighting
	end

	const existing = Lighting:FindFirstChildWhichIsA(className)
	if existing then
		return existing
	end

	const created = Instance.new(className)
	created.Parent = Lighting

	return created
end

--[[
	Starts applying the looks. The connection lives for the rest of the session.
	@param timeline The timeline built from `phases`.
	@param phases The configured phases.
	@param getHour Returns the current game hour, or nil if it is not known yet.
	@return The connection driving the updates.
]]
function LightingController.start(
	timeline: Timeline.Timeline,
	phases: { Types.PhaseConfig },
	getHour: () -> number?
): RBXScriptConnection
	const resolvedLooks = LookBlend.resolve(timeline, phases)
	const blendHours = LookBlend.getBlendHours(phases)
	const targets: { [string]: Instance } = {}

	local appliedPhase: string? = nil
	local appliedAlpha = -1
	local secondsSinceUpdate = 0

	local function getTarget(targetName: string): Instance
		const existing = targets[targetName]
		if existing and (existing == Lighting or existing.Parent == Lighting) then
			return existing
		end

		const target = findOrCreateTarget(targetName)
		targets[targetName] = target

		return target
	end

	local function update()
		const hour = getHour()
		if hour == nil then
			return
		end

		const blend = LookBlend.getBlend(timeline, blendHours, hour)
		if not blend then
			return
		end
		if blend.Phase == appliedPhase and blend.Alpha == appliedAlpha then
			return
		end
		appliedPhase = blend.Phase
		appliedAlpha = blend.Alpha

		const previousLook = resolvedLooks[blend.PreviousPhase]
		for targetName, properties in resolvedLooks[blend.Phase] do
			-- Property names are checked against LookTargets when the Config is loaded, so
			-- the instance can be written to by name.
			const target: any = getTarget(targetName)
			const previousProperties = previousLook[targetName]

			for propertyName, value in properties do
				target[propertyName] =
					blendValues(previousProperties[propertyName], value, blend.Alpha)
			end
		end
	end

	update()

	return RunService.PreRender:Connect(function(deltaSeconds: number)
		secondsSinceUpdate += deltaSeconds
		if secondsSinceUpdate < UPDATE_INTERVAL_SECONDS then
			return
		end

		secondsSinceUpdate = 0
		update()
	end)
end

return table.freeze(LightingController)
