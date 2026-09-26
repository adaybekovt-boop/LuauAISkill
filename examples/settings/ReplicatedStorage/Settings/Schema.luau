--!strict
-- Player settings schema: the single definition used by the menu (rows), the client (apply) and the server
-- (sanitize before saving). Pure → CLI-tested (examples/tests/settings.spec.luau).
-- Status: TYPECHECKED + CLI-EXECUTED.
export type Def =
	{ id: string, label: string, kind: "range", default: number, min: number, max: number, step: number }
	| { id: string, label: string, kind: "toggle", default: boolean }
	| { id: string, label: string, kind: "choice", default: string, options: { string } }
export type Values = { [string]: number | boolean | string }

local Schema = {}

Schema.defs = {
	{ id = "MasterVolume", label = "Master volume", kind = "range", default = 0.8, min = 0, max = 1, step = 0.1 },
	{ id = "MusicVolume", label = "Music", kind = "range", default = 0.6, min = 0, max = 1, step = 0.1 },
	{ id = "FieldOfView", label = "Field of view", kind = "range", default = 70, min = 70, max = 100, step = 5 },
	{ id = "CameraShake", label = "Camera shake", kind = "range", default = 1, min = 0, max = 1, step = 0.25 },
	{ id = "ViewBobbing", label = "View bobbing", kind = "toggle", default = true },
	{ id = "Subtitles", label = "Subtitles", kind = "toggle", default = true },
	{ id = "GraphicsTier", label = "Graphics", kind = "choice", default = "Auto", options = { "Auto", "Low", "Medium", "High", "Ultra" } },
} :: { Def }

function Schema.defaults(): Values
	local out: Values = {}
	for _, def in Schema.defs do
		out[def.id] = def.default
	end
	return out
end

-- Untrusted input (client payload or old saved data) → complete, valid settings. Unknown keys are dropped.
function Schema.sanitize(raw: unknown): Values
	local out = Schema.defaults()
	if type(raw) ~= "table" then
		return out
	end
	local t = raw :: { [any]: any }
	for _, def in Schema.defs do
		local v = t[def.id]
		if def.kind == "range" then
			if type(v) == "number" and v == v then
				local snapped = def.min + math.floor((math.clamp(v, def.min, def.max) - def.min) / def.step + 0.5) * def.step
				out[def.id] = math.clamp(snapped, def.min, def.max)
			end
		elseif def.kind == "toggle" then
			if type(v) == "boolean" then
				out[def.id] = v
			end
		elseif def.kind == "choice" then
			if type(v) == "string" and table.find(def.options, v) then
				out[def.id] = v
			end
		end
	end
	return out
end

return Schema
