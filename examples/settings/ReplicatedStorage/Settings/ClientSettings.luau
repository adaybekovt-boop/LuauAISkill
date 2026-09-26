--!strict
-- Client-side settings state other client scripts read (camera, audio, graphics tier). Client-only module.
-- Status: TYPECHECKED. Not run in Studio.
local Schema = require(script.Parent.Schema)
local Signal = require(script.Parent.Parent.Lib.Signal)

local ClientSettings = {}
ClientSettings.changed = Signal.new() :: Signal.Signal<string, any>

local values = Schema.defaults()

function ClientSettings.get(id: string): any
	return values[id]
end

function ClientSettings.all(): Schema.Values
	return table.clone(values)
end

-- Replace everything (e.g. when the server sends saved settings). Fires `changed` per changed key.
function ClientSettings.load(raw: unknown)
	local clean = Schema.sanitize(raw)
	for id, v in clean do
		if values[id] ~= v then
			values[id] = v
			ClientSettings.changed:fire(id, v)
		end
	end
end

function ClientSettings.set(id: string, value: any)
	local merged = table.clone(values)
	merged[id] = value
	ClientSettings.load(merged) -- goes through sanitize: the UI can't set invalid values either
end

return ClientSettings
