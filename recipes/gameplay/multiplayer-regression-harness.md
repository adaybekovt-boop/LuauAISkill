# StudioTestService multiplayer regression harness

An opt-in, bounded Studio regression fixture with an executable plugin/command-bar launcher, initial client
barrier, versioned replication checks, respawn, late join, forged input rejection, disconnect and survivor checks.

Evidence: **TYPECHECKED** (strict, old + new solver, pinned Roblox definitions); pure logic **CLI-EXECUTED**.
**Studio / live: NOT RUN.**

## Architecture
- The launcher runs in Edit mode with PluginSecurity and calls ExecuteMultiplayerTestAsync for two clients.
  It passes a unique suite argument and asserts the structured server result. A single Play client is insufficient.
- The server checks IsStudio and GetTestArgs before creating any fixture objects; no production DataStore,
  external request, asset insertion, purchase, or published-place mutation is made.
- Clients announce readiness after installing their listener. Each phase has its own acknowledgement label;
  the server waits for every expected user ID, not just one response or a clean console.
- Remote/property arrival is not ordered: clients wait for an explicit replicated revision, then acknowledge.
  Fifteen-second stage deadlines and a 120-second server watchdog convert hangs into failed assertions.
- The server owns the fixture revision. Clients send deliberately malformed score-like payloads; they are ignored,
  and the server asserts the revision remained unchanged. This tests the fixture boundary, not your game's remotes.
- AddPlayers adds a late third peer; LoadCharacterAsync changes one character; LeaveTest disconnects the selected
  peer after CanLeaveTest. EndTest returns counts and every named assertion; logs carry a machine-readable prefix.

## When NOT to use

not an engine test result by itself, not a production test runner, not an adversarial exploit
suite, not evidence that unrelated game systems are safe. Adapt the fixture assertions to actual gameplay state
and preserve the same reproducer before/after a fix. Studio clients aren't real device/network coverage.

## Setup and integration
1. Copy `examples/regression` service folders into a disposable test place or an authorized saved copy of your place.
   Do not map PluginLauncher.lua.txt into a game Script; its exact text belongs in a Studio plugin or the Edit-mode
   command bar. Save/version the place before editing it.
2. Stop existing play sessions. Execute [the launcher](../../examples/regression/PluginLauncher.lua.txt) from the
   plugin/command-bar context. It yields until EndTest; a plugin UI may wrap the invocation in task.spawn to stay responsive.
3. One test session per Studio is supported; this fixture uses two initial clients and a third late join, within
   the documented maximum of eight. The server's suite argument is required for it to activate.
4. Save the REGRESSION_RESULT and REGRESSION_LAUNCH_RESULT JSON plus Studio build, place revision and console output.
   A timed-out/failed launcher is a failed or inconclusive test, never a pass.
5. To launch through an MCP execute_luau tool, first verify its live schema/context and whether it tolerates the
   yielding test lifecycle. If it cannot, use the plugin/command bar. Do not call start_stop_play and label it multiplayer.

Plugin launcher is checked separately by `python tools/check_recipe_contexts.py` with pinned PluginSecurity
signatures, strict old and new solvers. The runtime methods' security is independently checked against the API index.
The ordinary service-folder files still pass the game-script checker. Negative tests require the launcher to fail
under None definitions; no any-cast suppresses the plugin boundary.

## Implementation

### `examples/regression/ReplicatedStorage/Regression/Protocol.luau`

<!-- code: examples/regression/ReplicatedStorage/Regression/Protocol.luau -->
```luau
-- file: examples/regression/ReplicatedStorage/Regression/Protocol.luau
--!strict
export type Receipt = { name: string, ok: boolean, detail: string }
local Protocol = {}
function Protocol.complete(expected: { number }, acknowledgments: { [number]: string }, phase: string): boolean
    for _, userId in expected do if acknowledgments[userId] ~= phase then return false end end
    return true
end
function Protocol.result(rows: { Receipt }): { passed: number, failed: number, assertions: { Receipt } }
    local passed, failed = 0, 0
    for _, row in rows do if row.ok then passed += 1 else failed += 1 end end
    return { passed = passed, failed = failed, assertions = rows }
end
return Protocol
```
<!-- /code -->

### `examples/regression/ServerScriptService/RegressionServer.server.luau`

<!-- code: examples/regression/ServerScriptService/RegressionServer.server.luau -->
```luau
-- file: examples/regression/ServerScriptService/RegressionServer.server.luau
--!strict
-- Opt-in Studio-only fixture: no production DataStores, purchases or third-party assets.
local RunService = game:GetService("RunService")
local StudioTestService = game:GetService("StudioTestService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Protocol = require(ReplicatedStorage.Regression.Protocol)
if not RunService:IsStudio() then return end
local ok, args = pcall(function() return StudioTestService:GetTestArgs() end)
if not ok or type(args) ~= "table" or args.suite ~= "recipe-regression-v1" then return end
local rows: { Protocol.Receipt } = {}
local connections: { RBXScriptConnection } = {}
local remote = Instance.new("RemoteEvent")
remote.Name = "RegressionPeer"; remote.Parent = ReplicatedStorage
local fixture = Instance.new("Folder")
fixture.Name = "RegressionState"; fixture:SetAttribute("Revision", 0); fixture.Parent = ReplicatedStorage
local acknowledgments: { [number]: string } = {}
local ready: { [number]: boolean } = {}
local left: { [number]: boolean } = {}
local phase = "boot"
local revision = 0
local function check(name: string, condition: boolean, detail: string)
    table.insert(rows, { name = name, ok = condition, detail = detail })
end
local function waitFor(label: string, predicate: () -> boolean): boolean
    local deadline = os.clock() + 15
    while not predicate() and os.clock() < deadline do task.wait(0.05) end
    local success = predicate(); check(label, success, if success then "condition observed" else "15-second timeout")
    return success
end
table.insert(connections, remote.OnServerEvent:Connect(function(player: Player, verb: any, value: any)
    if verb == "ready" then ready[player.UserId] = true
    elseif verb == "ack" and value == phase then acknowledgments[player.UserId] = value
    elseif verb == "forge" then
        -- Deliberately ignored. Fixture state has one server writer, irrespective of client payload.
    end
end))
table.insert(connections, Players.PlayerRemoving:Connect(function(player) left[player.UserId] = true end))
local function ids(players: { Player }): { number }
    local result: { number } = {}
    for _, player in players do table.insert(result, player.UserId) end
    return result
end
local function stage(name: string, peers: { Player })
    phase = name; acknowledgments = {}; revision += 1
    fixture:SetAttribute("Revision", revision)
    for _, player in peers do remote:FireClient(player, "observe", name, revision) end
    waitFor("all peers observed " .. name, function()
        return Protocol.complete(ids(peers), acknowledgments, name)
    end)
end
local function scenario()
    local function initialReady(): boolean
        local list = Players:GetPlayers()
        return #list == 2 and ready[list[1].UserId] == true and ready[list[2].UserId] == true
    end
    local initiallyReady = waitFor("two initial clients ready", initialReady)
    if not initiallyReady then return end
    local initial = Players:GetPlayers()
    table.sort(initial, function(a: Player, b: Player) return a.UserId < b.UserId end)
    stage("initial-replication", initial)
    local oldCharacter = initial[1].Character
    initial[1]:LoadCharacterAsync()
    waitFor("respawn replaced character", function()
        return initial[1].Character ~= nil and initial[1].Character ~= oldCharacter
    end)
    stage("after-respawn", initial)
    StudioTestService:AddPlayers(1)
    local function allReady(): boolean
        local list = Players:GetPlayers()
        if #list ~= 3 then return false end
        for _, player in list do if not ready[player.UserId] then return false end end
        return true
    end
    local lateReady = waitFor("late join ready", allReady)
    if not lateReady then return end
    stage("late-join-replication", Players:GetPlayers())
    local expected = fixture:GetAttribute("Revision")
    phase = "reject-forgery"; acknowledgments = {}
    for _, player in initial do remote:FireClient(player, "forge", phase, revision) end
    waitFor("forgery attempted by both clients", function()
        return Protocol.complete(ids(initial), acknowledgments, phase)
    end)
    check("client payload did not change server state", fixture:GetAttribute("Revision") == expected,
        "server revision remains authoritative")
    remote:FireClient(initial[2], "leave", "disconnect", 0)
    waitFor("selected client disconnected", function() return left[initial[2].UserId] == true end)
    stage("survivor-replication", Players:GetPlayers())
end
local complete = false
local function finish()
    if complete then return end
    complete = true
    for _, connection in connections do connection:Disconnect() end
    remote:Destroy(); fixture:Destroy()
    local result = Protocol.result(rows)
    print("REGRESSION_RESULT " .. HttpService:JSONEncode(result))
    StudioTestService:EndTest(result)
end
task.delay(120, function()
    if not complete then check("suite deadline", false, "120-second watchdog"); finish() end
end)
local failure: string? = nil
local success = xpcall(scenario, function(err: any) failure = debug.traceback(tostring(err)) end)
if not success then check("unexpected server error", false, failure or "unknown error") end
finish()
```
<!-- /code -->

### `examples/regression/StarterPlayer/StarterPlayerScripts/RegressionClient.client.luau`

<!-- code: examples/regression/StarterPlayer/StarterPlayerScripts/RegressionClient.client.luau -->
```luau
-- file: examples/regression/StarterPlayer/StarterPlayerScripts/RegressionClient.client.luau
--!strict
local RunService = game:GetService("RunService")
local StudioTestService = game:GetService("StudioTestService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
if not RunService:IsStudio() then return end
-- GetTestArgs has a documented client issue; the server's opt-in remote is the gate.
local remote = ReplicatedStorage:WaitForChild("RegressionPeer", 20) :: RemoteEvent?
local fixture = ReplicatedStorage:WaitForChild("RegressionState", 20)
if not remote or not fixture then return end
local connection = remote.OnClientEvent:Connect(function(verb: string, phase: string, expected: number)
    if verb == "observe" then
        -- Remote/property ordering is not guaranteed. Wait for the explicit version with a deadline.
        local deadline = os.clock() + 10
        while fixture:GetAttribute("Revision") ~= expected and os.clock() < deadline do task.wait() end
        if fixture:GetAttribute("Revision") == expected then remote:FireServer("ack", phase) end
    elseif verb == "forge" then
        remote:FireServer("forge", 999999)
        remote:FireServer("forge", "invalid type")
        remote:FireServer("ack", phase)
    elseif verb == "leave" and StudioTestService:CanLeaveTest() then
        StudioTestService:LeaveTest()
    end
end)
remote:FireServer("ready", true)
script.Destroying:Connect(function() connection:Disconnect() end)
```
<!-- /code -->

### `examples/regression/PluginLauncher.lua.txt`

<!-- code: examples/regression/PluginLauncher.lua.txt -->
```luau
-- file: examples/regression/PluginLauncher.lua.txt
--!strict
-- Run from a Studio plugin/command bar in Edit mode, NEVER as a game Script.
local StudioTestService: StudioTestService = game:GetService("StudioTestService")
local HttpService = game:GetService("HttpService")
local result = StudioTestService:ExecuteMultiplayerTestAsync(2, { suite = "recipe-regression-v1" })
print("REGRESSION_LAUNCH_RESULT " .. HttpService:JSONEncode(result))
assert(type(result) == "table" and result.failed == 0 and result.passed >= 8, "Regression suite failed")
```
<!-- /code -->

## How to test

| Scenario | Required observation |
|---|---|
| CLI barrier / stale acknowledgement | One peer cannot satisfy all-peer barrier; old phase is rejected |
| Plugin-context static gate | Old/new PluginSecurity checks pass; None context intentionally rejects launcher |
| Two initial clients | Server receives readiness and both peers observe revision 1 |
| Respawn | Character instance changes; client script in PlayerScripts survives and acknowledges new revision |
| Late third client | Existing state replicates and all three peers observe the next revision |
| Forged payload | Both attempts acknowledged as attempted; authoritative revision unchanged |
| Selected peer disconnect | PlayerRemoving observed; survivors still acknowledge replication |
| Remove a client listener / force error | Deadline or exception appears as named failure and EndTest returns failure |
| Run fixture in a live server / ordinary Studio Play | Suite remains inactive without matching test args |

No test above has been run in Studio for this release. Retain actual artifacts before changing that evidence label.

## Failure paths and limits
The watchdog can return a failure but cannot recover a crashed Studio process; an external caller should also
have a deadline. Clients are cooperating assertion reporters, not trusted adversaries. EndTest ends the whole
Studio test session, so this fixture must never be installed into an unrelated ongoing test without authorization.
GetTestArgs has a documented client-side issue, which is why only the server reads it. Failed replication phases
retain explicit failures even if later phases happen to pass. The supplied test does not exercise receipts,
DataStores, physical vehicles or rollback; those have separate recipe test plans.

## Verification
From the skill directory, run `python tools/check_all.py`. Pure tests for this recipe:
`luau examples/tests/regression.spec.luau`. The checker runs both Luau solvers. Engine coverage remains NOT RUN until you retain
assertion output from the specified Studio scenario with Studio build, place revision, peers, and device.

Sources: cd:reference/engine/classes/StudioTestService, cd:studio/testing-modes, cd:studio/mcp, api:StudioTestService.ExecuteMultiplayerTestAsync, api:StudioTestService.AddPlayers, api:StudioTestService.EndTest, api:StudioTestService.GetTestArgs, api:StudioTestService.CanLeaveTest, api:StudioTestService.LeaveTest.
