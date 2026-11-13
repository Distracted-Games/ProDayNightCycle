--!strict

--[[
	LookTargets
	@author DistractedGames

	The things a phase's `Look` can change, and which of their properties it may set.
	Keeping this as data lets typos in the Config be caught with a clear message, and lets
	the look code stay generic. Free of Roblox services so it can be tested outside of Studio.
]]

--[[
	- ClassName: The effect class to find in `Lighting` (or create). Nil for `Lighting` itself.
	- Properties: The properties a look may set, as a set. Every one is a number or a Color3.
]]
export type Target = {
	ClassName: string?,
	Properties: { [string]: boolean },
}

const LookTargets: { [string]: Target } = {
	Lighting = {
		Properties = {
			Ambient = true,
			Brightness = true,
			ColorShift_Bottom = true,
			ColorShift_Top = true,
			EnvironmentDiffuseScale = true,
			EnvironmentSpecularScale = true,
			ExposureCompensation = true,
			FogColor = true,
			FogEnd = true,
			FogStart = true,
			OutdoorAmbient = true,
			ShadowSoftness = true,
		},
	},
	Atmosphere = {
		ClassName = "Atmosphere",
		Properties = {
			Color = true,
			Decay = true,
			Density = true,
			Glare = true,
			Haze = true,
			Offset = true,
		},
	},
	Bloom = {
		ClassName = "BloomEffect",
		Properties = {
			Intensity = true,
			Size = true,
			Threshold = true,
		},
	},
	SunRays = {
		ClassName = "SunRaysEffect",
		Properties = {
			Intensity = true,
			Spread = true,
		},
	},
	ColorCorrection = {
		ClassName = "ColorCorrectionEffect",
		Properties = {
			Brightness = true,
			Contrast = true,
			Saturation = true,
			TintColor = true,
		},
	},
}

return table.freeze(LookTargets)
