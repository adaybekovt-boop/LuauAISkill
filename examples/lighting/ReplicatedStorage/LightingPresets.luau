--!strict
-- Scene lighting presets: Lighting + Atmosphere + ColorCorrection + Bloom (+ optional SunRays) values per mood.
-- Art-direction STARTING POINTS judged for LightingStyle = Realistic; tune by eye on target devices.
-- Keys are engine property names (validated by tests/test_tools.py against the API index).
-- Each scene recipe in recipes/graphics embeds its own region of this file.
-- Status: TYPECHECKED. Values not screenshot-verified in Studio.
export type Preset = {
	lighting: { [string]: any },
	atmosphere: { [string]: any },
	colorCorrection: { [string]: any },
	bloom: { [string]: any },
	sunRays: { [string]: any }?,
}

local rgb = Color3.fromRGB
local Presets: { [string]: Preset } = {}

-- region HorrorInterior
-- Dark house at night: moonlight through windows as the only sky light, practical lamps do the work.
Presets.HorrorInterior = {
	lighting = {
		ClockTime = 0,
		Brightness = 0.3, -- moon
		Ambient = rgb(6, 6, 8), -- near-black: light must come from sources
		OutdoorAmbient = rgb(24, 27, 36),
		EnvironmentDiffuseScale = 0.15,
		EnvironmentSpecularScale = 0.3,
		ExposureCompensation = 0,
		ShadowSoftness = 0.4,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.25, Offset = 0.1, Color = rgb(40, 44, 52), Decay = rgb(20, 22, 28), Glare = 0, Haze = 1 },
	colorCorrection = { Brightness = 0, Contrast = 0.15, Saturation = -0.3, TintColor = rgb(235, 240, 255) },
	bloom = { Intensity = 0.4, Size = 24, Threshold = 1.8 },
}
-- endregion

-- region BackroomsOffice
-- Sealed fluorescent office: the one mood where fairly flat, warm fill is correct (motivated by a ceiling full of
-- panels); slight overexposure and low contrast sell the camcorder look.
Presets.BackroomsOffice = {
	lighting = {
		ClockTime = 12,
		Brightness = 0, -- no sun reaches inside; also prevents leaks through gaps
		Ambient = rgb(66, 58, 38),
		OutdoorAmbient = rgb(66, 58, 38),
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = 0.1,
		ExposureCompensation = 0.3,
		ShadowSoftness = 0.7,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.25, Offset = 0, Color = rgb(200, 190, 150), Decay = rgb(160, 150, 110), Glare = 0, Haze = 1.5 },
	colorCorrection = { Brightness = 0, Contrast = -0.05, Saturation = -0.15, TintColor = rgb(255, 246, 214) },
	bloom = { Intensity = 0.6, Size = 30, Threshold = 1.2 },
}
-- endregion

-- region DarkCorridor
-- Realistic dark corridor: pools of practical light separated by true darkness.
Presets.DarkCorridor = {
	lighting = {
		ClockTime = 0,
		Brightness = 0,
		Ambient = rgb(3, 3, 4),
		OutdoorAmbient = rgb(0, 0, 0),
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = 0.2,
		ExposureCompensation = 0.3, -- lift the lit pools, keep the blacks
		ShadowSoftness = 0.3,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.35, Offset = 0, Color = rgb(30, 30, 34), Decay = rgb(10, 10, 12), Glare = 0, Haze = 0.8 },
	colorCorrection = { Brightness = 0, Contrast = 0.2, Saturation = -0.2, TintColor = rgb(230, 236, 255) },
	bloom = { Intensity = 0.3, Size = 20, Threshold = 2 },
}
-- endregion

-- region NightExterior
-- Moonlit exterior: one cool key (moon), dark ambient, warm practicals for contrast.
Presets.NightExterior = {
	lighting = {
		ClockTime = 1,
		GeographicLatitude = 35,
		Brightness = 0.35,
		Ambient = rgb(6, 7, 10),
		OutdoorAmbient = rgb(32, 38, 56),
		EnvironmentDiffuseScale = 0.35,
		EnvironmentSpecularScale = 0.6,
		ExposureCompensation = 0.4,
		ShadowSoftness = 0.25,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.33, Offset = 0.15, Color = rgb(60, 70, 95), Decay = rgb(25, 30, 45), Glare = 0, Haze = 1.4 },
	colorCorrection = { Brightness = 0, Contrast = 0.1, Saturation = -0.25, TintColor = rgb(225, 232, 255) },
	bloom = { Intensity = 0.4, Size = 24, Threshold = 1.8 },
}
-- endregion

-- region Sunset
-- Low warm sun, long shadows, glowing horizon.
Presets.Sunset = {
	lighting = {
		ClockTime = 18.1,
		GeographicLatitude = 30,
		Brightness = 2.2,
		Ambient = rgb(20, 16, 18),
		OutdoorAmbient = rgb(110, 90, 90),
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 1,
		ExposureCompensation = 0,
		ShadowSoftness = 0.15,
		ColorShift_Top = rgb(60, 30, 10), -- subtle warm tint on sun-facing surfaces
		ColorShift_Bottom = rgb(0, 0, 0),
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.3, Offset = 0.25, Color = rgb(255, 190, 150), Decay = rgb(130, 90, 110), Glare = 0.6, Haze = 1.8 },
	colorCorrection = { Brightness = 0, Contrast = 0.08, Saturation = 0.05, TintColor = rgb(255, 244, 235) },
	bloom = { Intensity = 0.5, Size = 28, Threshold = 1.6 },
	sunRays = { Intensity = 0.08, Spread = 0.8 },
}
-- endregion

-- region FogDay
-- Overcast, thick fog: soft shadows, grey-white distance, silhouettes.
Presets.FogDay = {
	lighting = {
		ClockTime = 10,
		Brightness = 1.2,
		Ambient = rgb(40, 42, 45),
		OutdoorAmbient = rgb(120, 124, 128),
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 0.6,
		ExposureCompensation = 0.1,
		ShadowSoftness = 0.8,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.55, Offset = 0, Color = rgb(185, 190, 195), Decay = rgb(150, 155, 160), Glare = 0, Haze = 3 },
	colorCorrection = { Brightness = 0, Contrast = 0.02, Saturation = -0.2, TintColor = rgb(245, 248, 255) },
	bloom = { Intensity = 0.25, Size = 24, Threshold = 2 },
}
-- endregion

-- region IndustrialWarehouse
-- Afternoon sun through high windows/skylights, dust, cool metal and concrete.
Presets.IndustrialWarehouse = {
	lighting = {
		ClockTime = 15,
		GeographicLatitude = 40,
		Brightness = 2.5,
		Ambient = rgb(10, 10, 12),
		OutdoorAmbient = rgb(90, 95, 105),
		EnvironmentDiffuseScale = 0.5,
		EnvironmentSpecularScale = 0.6,
		ExposureCompensation = -0.1,
		ShadowSoftness = 0.2,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.3, Offset = 0.05, Color = rgb(170, 165, 150), Decay = rgb(90, 88, 80), Glare = 0.2, Haze = 1 },
	colorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = -0.15, TintColor = rgb(250, 245, 235) },
	bloom = { Intensity = 0.35, Size = 24, Threshold = 1.8 },
	sunRays = { Intensity = 0.06, Spread = 0.5 },
}
-- endregion

-- region Poolrooms
-- Tiled, humid, bright and soft: skylight-lit, strong reflections, pale cyan haze.
Presets.Poolrooms = {
	lighting = {
		ClockTime = 13,
		Brightness = 1.5,
		Ambient = rgb(60, 70, 75),
		OutdoorAmbient = rgb(140, 160, 170),
		EnvironmentDiffuseScale = 0.8,
		EnvironmentSpecularScale = 1, -- wet tiles must reflect
		ExposureCompensation = 0.35,
		ShadowSoftness = 0.6,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.35, Offset = 0, Color = rgb(200, 230, 235), Decay = rgb(160, 200, 205), Glare = 0, Haze = 2 },
	colorCorrection = { Brightness = 0, Contrast = -0.05, Saturation = -0.05, TintColor = rgb(240, 252, 255) },
	bloom = { Intensity = 0.7, Size = 32, Threshold = 1.2 },
}
-- endregion

-- region EmergencyRed
-- Power failure: main lights off, red emergency lights (local lights do the colouring; the grade only supports it).
Presets.EmergencyRed = {
	lighting = {
		ClockTime = 0,
		Brightness = 0,
		Ambient = rgb(6, 1, 1),
		OutdoorAmbient = rgb(0, 0, 0),
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = 0.2,
		ExposureCompensation = 0.2,
		ShadowSoftness = 0.3,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.35, Offset = 0, Color = rgb(40, 12, 12), Decay = rgb(15, 4, 4), Glare = 0, Haze = 0.8 },
	colorCorrection = { Brightness = 0, Contrast = 0.2, Saturation = 0.1, TintColor = rgb(255, 235, 235) },
	bloom = { Intensity = 0.5, Size = 24, Threshold = 1.4 },
}
-- endregion

return Presets
