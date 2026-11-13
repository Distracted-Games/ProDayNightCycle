--!strict

--[[
	Config
	@author DistractedGames

	The one file meant to be edited by the developer. These values are read by the server
	when the cycle starts and are not changeable by editing this file at runtime.
	Runtime changes go through the DayNightCycle API (SetDayLength, SetTime, ...).
]]

const Types = require("./Types")

-- The ambient light the original looks used in every phase.
const NORMAL_AMBIENT = Color3.fromRGB(140, 140, 140)

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
		the next phase starts.
		- TimeShare: The phase's relative share of the real-world day length (only the ratios
		  matter), so it sets how fast the phase passes. These defaults make dusk and dawn
		  linger briefly and the night pass faster than the day.
		- BlendHours: Game hours, from the start of the phase, spent blending from the previous
		  phase's look to this one (limited to the phase's length).
		- Look: How the lighting looks in the phase. Every target (Lighting, Atmosphere, Bloom,
		  SunRays, ColorCorrection) and every property is optional; anything left out keeps the
		  value from the closest earlier phase that sets it.

		Phase start events are owned by the phases: AddTimeEvent and RemoveTimeEvent refuse
		to change them. Set `Phases = {}` for a constant speed and no looks.
	]]
	Phases = {
		{
			Name = "Night",
			StartEvent = "Dusk",
			TimeShare = 28,
			BlendHours = 0.75,
			Look = {
				Lighting = {
					Ambient = NORMAL_AMBIENT,
					OutdoorAmbient = NORMAL_AMBIENT,
					Brightness = 1.35,
					ExposureCompensation = -0.15,
					ColorShift_Top = Color3.fromRGB(55, 75, 135),
					ColorShift_Bottom = Color3.fromRGB(25, 35, 75),
					ShadowSoftness = 0.3,
				},
				Atmosphere = {
					Color = Color3.fromRGB(75, 95, 150),
					Decay = Color3.fromRGB(25, 35, 65),
					Density = 0.5,
					Haze = 3.2,
					Glare = 0,
				},
				Bloom = { Intensity = 0.08, Size = 34, Threshold = 1.1 },
				SunRays = { Intensity = 0.02, Spread = 1 },
				ColorCorrection = { Brightness = -0.02, Contrast = 0.1, Saturation = -0.05 },
			},
		},
		{
			Name = "Dawn",
			StartEvent = "Dawn",
			TimeShare = 4,
			BlendHours = 0.5,
			Look = {
				Lighting = {
					Ambient = NORMAL_AMBIENT,
					OutdoorAmbient = NORMAL_AMBIENT,
					Brightness = 1.8,
					ExposureCompensation = 0,
					ColorShift_Top = Color3.fromRGB(255, 200, 150),
					ColorShift_Bottom = Color3.fromRGB(255, 160, 120),
					ShadowSoftness = 0.3,
				},
				Atmosphere = {
					Color = Color3.fromRGB(255, 205, 170),
					Decay = Color3.fromRGB(255, 150, 110),
					Density = 0.32,
					Haze = 2.2,
					Glare = 0.25,
				},
				Bloom = { Intensity = 0.13, Size = 42, Threshold = 1 },
				SunRays = { Intensity = 0.1, Spread = 0.95 },
				ColorCorrection = { Brightness = 0, Contrast = 0.09, Saturation = 0.15 },
			},
		},
		{
			Name = "Day",
			StartEvent = "Sunrise",
			TimeShare = 65,
			BlendHours = 0.75,
			Look = {
				Lighting = {
					Ambient = NORMAL_AMBIENT,
					OutdoorAmbient = NORMAL_AMBIENT,
					Brightness = 2.4,
					ExposureCompensation = 0.05,
					ColorShift_Top = Color3.fromRGB(255, 245, 230),
					ColorShift_Bottom = Color3.fromRGB(255, 250, 240),
					ShadowSoftness = 0.3,
				},
				Atmosphere = {
					Color = Color3.fromRGB(220, 235, 255),
					Decay = Color3.fromRGB(120, 170, 255),
					Density = 0.22,
					Haze = 1.15,
					Glare = 0.2,
				},
				Bloom = { Intensity = 0.12, Size = 38, Threshold = 1 },
				SunRays = { Intensity = 0.08, Spread = 0.9 },
				ColorCorrection = { Brightness = 0, Contrast = 0.07, Saturation = 0.1 },
			},
		},
		{
			Name = "Dusk",
			StartEvent = "Sunset",
			TimeShare = 3,
			BlendHours = 0.35,
			Look = {
				Lighting = {
					Ambient = NORMAL_AMBIENT,
					OutdoorAmbient = NORMAL_AMBIENT,
					Brightness = 2,
					ExposureCompensation = 0,
					ColorShift_Top = Color3.fromRGB(255, 190, 125),
					ColorShift_Bottom = Color3.fromRGB(255, 135, 90),
					ShadowSoftness = 0.3,
				},
				Atmosphere = {
					Color = Color3.fromRGB(255, 180, 140),
					Decay = Color3.fromRGB(255, 130, 95),
					Density = 0.3,
					Haze = 2,
					Glare = 0.35,
				},
				Bloom = { Intensity = 0.15, Size = 45, Threshold = 0.95 },
				SunRays = { Intensity = 0.12, Spread = 0.9 },
				ColorCorrection = { Brightness = 0, Contrast = 0.1, Saturation = 0.18 },
			},
		},
	},

	-- Applies the phases' looks to `Lighting` on each Client. Set `Enabled = false` to
	-- keep control of the lighting yourself (phases still set the speed of time).
	Lighting = {
		Enabled = true,
	},
}

return Config
