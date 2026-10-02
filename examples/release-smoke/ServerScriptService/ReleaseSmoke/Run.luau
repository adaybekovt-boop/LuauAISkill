--!strict
-- Call from a game Script, or explicitly require/run in an Open Cloud execution task (save-system only).
-- Prints one machine-readable result, including failures. NOT RUN in Roblox.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Context = require(script.Parent.Context)
local Cases = require(script.Parent.Cases)
local Fixtures = require(script.Parent.Fixtures)
local started = false
local Run = {}

function Run.run(): any
	assert(not started, "smoke already started in this DataModel; use a fresh place session")
	started = true
	local caseId = Workspace:GetAttribute("ReleaseSmokeCase")
	assert(type(caseId) == "string" and Cases[caseId], "unknown ReleaseSmokeCase")
	local result: any = {
		schema_version = 1,
		case = caseId,
		run_id = HttpService:GenerateGUID(false),
		source_digest = Workspace:GetAttribute("ReleaseSmokeSourceDigest"),
		started_at = DateTime.now():ToIsoDate(),
		environment = if RunService:IsStudio() then "studio-server-clients" else "open-cloud",
		engine_version = Workspace:GetAttribute("ReleaseSmokeEngineVersion"),
		universe_id = game.GameId,
		place_id = game.PlaceId,
		place_version = game.PlaceVersion,
		client_count = 0,
		assertions = {},
		status = "FAIL",
	}
	Workspace:SetAttribute("ReleaseSmokeRunId", result.run_id)
	local ctx: Context.Context? = nil
	local finished = false
	local function finish(ok: boolean, err: any)
		if finished then return end
		finished = true
		result.status = if ok then "PASS" else "FAIL"
		result.error = if ok then nil else tostring(err)
		result.finished_at = DateTime.now():ToIsoDate()
		print("LUAU_RELEASE_SMOKE_RESULT " .. HttpService:JSONEncode(result))
		Workspace:SetAttribute("ReleaseSmokeFinished", true)
		Workspace:SetAttribute("ReleaseSmokePassed", ok)
		if ctx then ctx.close() end
	end
	-- Engine API calls can yield; even a stalled DataStore/client produces a failed receipt by this deadline.
	-- Once timed out, stop the Studio/Cloud session; continuing async work must never be interpreted as a pass.
	local timeout = if caseId == "lighting-presets" and Workspace:GetAttribute("ReleaseSmokePauseForScreenshots") == true
		then 1200 else 180
	task.delay(timeout, function() finish(false, "overall smoke deadline exceeded") end)
	local ok, err = xpcall(function()
		assert(Workspace:GetAttribute("ReleaseSmokeEnabled") == true, "smoke is not enabled")
		assert(RunService:IsServer(), "server DataModel required")
		assert(type(result.source_digest) == "string" and #result.source_digest == 64, "set current source digest")
		assert(type(result.engine_version) == "string" and #result.engine_version > 0, "record actual engine version")
		assert(RunService:IsStudio() or (caseId == "save-system" and Workspace:GetAttribute("ReleaseSmokeOpenCloud") == true),
			"only save-system supports explicitly opted-in Open Cloud; never run this on live servers")
		Fixtures.prepare(caseId)
		local clients = if caseId == "save-system" then 0
			elseif caseId == "inventory" or caseId == "network-rate-limiter" or caseId == "round-manager" then 2 else 1
		local context = Context.new(clients)
		ctx = context
		result.client_count = #Players:GetPlayers()
		result.assertions = context.assertions
		Cases[caseId](context)
		return true
	end, function(message: any): string return debug.traceback(tostring(message)) end)
	finish(ok, err)
	return result
end

return Run
