--!strict
-- Disabled by default via Workspace attribute; configure in Edit before starting the disposable place.
local Workspace = game:GetService("Workspace")
if Workspace:GetAttribute("ReleaseSmokeEnabled") ~= true then
	warn("[ReleaseSmoke] NOT RUN: ReleaseSmokeEnabled is not true")
	return
end
local Run = require(script.Parent.ReleaseSmoke.Run)
Run.run()
