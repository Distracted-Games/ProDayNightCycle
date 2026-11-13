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
	The properties a look can set on `Lighting`. Every property is optional.
]]
export type LightingLook = {
	Ambient: Color3?,
	Brightness: number?,
	ColorShift_Bottom: Color3?,
	ColorShift_Top: Color3?,
	EnvironmentDiffuseScale: number?,
	EnvironmentSpecularScale: number?,
	ExposureCompensation: number?,
	FogColor: Color3?,
	FogEnd: number?,
	FogStart: number?,
	OutdoorAmbient: Color3?,
	ShadowSoftness: number?,
}

export type AtmosphereLook = {
	Color: Color3?,
	Decay: Color3?,
	Density: number?,
	Glare: number?,
	Haze: number?,
	Offset: number?,
}

export type BloomLook = {
	Intensity: number?,
	Size: number?,
	Threshold: number?,
}

export type SunRaysLook = {
	Intensity: number?,
	Spread: number?,
}

export type ColorCorrectionLook = {
	Brightness: number?,
	Contrast: number?,
	Saturation: number?,
	TintColor: Color3?,
}

--[[
	How the lighting should look during a phase. Every target and every property is
	optional: anything a phase leaves out keeps the value from the closest earlier phase
	that sets it. Effects (Atmosphere, Bloom, SunRays, ColorCorrection) are found in
	`Lighting`, or created on the Client if they are missing.
]]
export type Look = {
	Lighting: LightingLook?,
	Atmosphere: AtmosphereLook?,
	Bloom: BloomLook?,
	SunRays: SunRaysLook?,
	ColorCorrection: ColorCorrectionLook?,
}

--[[
	A named part of the day (e.g. "Night"). A phase lasts from the hour of its `StartEvent`
	until the next phase starts, wrapping past midnight.
	- Name: The unique phase name. At most 50 characters (it is published as an attribute).
	- StartEvent: The name of the `Config.TimeEvents` event whose hour starts the phase.
	- TimeShare: This phase's relative share of the day's real-world duration. Only the
	  ratios between phases matter. If nil, the phase's length in game hours is used, so
	  the phase runs at the same speed as an unweighted day.
	- BlendHours: Game hours, from the start of the phase, over which the lighting blends from
	  the previous phase's look to this phase's look. Limited to the phase's length. If nil,
	  a default is used.
	- Look: How the lighting should look in this phase. If nil, the previous look is kept.
]]
export type PhaseConfig = {
	Name: string,
	StartEvent: string,
	TimeShare: number?,
	BlendHours: number?,
	Look: Look?,
}

--[[
	The source-editable configuration (see Config.luau).
	- DayLengthInMinutes: Real-world minutes for a full 24-hour game day.
	- StartTimeOfDay: Optional start time in hours (0-24). If nil, uses the current Lighting time.
	- StartDay: The value of `Day` when the cycle starts. Each game decides what a "day" means.
	- TimeEvents: A dictionary mapping event names to game hours (0-24).
	- Phases: The parts of the day. Their `TimeShare` values set how fast each part passes,
	  and their `Look` values set the lighting. Leave empty for a constant speed.
	- Lighting: Whether the module applies the phases' looks to `Lighting` on Clients.
]]
export type Config = {
	DayLengthInMinutes: number,
	StartTimeOfDay: number?,
	StartDay: number,
	TimeEvents: TimeEventMap,
	Phases: { PhaseConfig },
	Lighting: {
		Enabled: boolean,
	},
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
