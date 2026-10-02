# Engine server authority mode (prediction + rollback)

## TL;DR
- Verify the current feature status and required Studio settings.
- Keep simulation callbacks deterministic and replay-safe.
- Use supported simulation bindings for authoritative movement.
- Separate simulation state from one-shot presentation effects.
- Test rollback and multiplayer behavior before choosing this mode.

Status: **full release 2026-07-09** (Roblox staff announcement:
https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993). The
server-authority docs pages carry no beta label; one stale line on the network-ownership page (creator-docs @
2026-10-01) still says "currently in beta" — trust the dated announcement. It is opt-in per place and still a big
architectural change: prototype in a branch place before converting a shipped game.
Read when: competitive/fast multiplayer (shooters, racing, sports, fighting) where client-owned movement is
unacceptable. Classic model: [01-runtime](01-runtime-architecture.md), [04-security](04-security.md).

## What it is
The server is the only source of truth for *all* simulated state, including characters. Clients send inputs
(Input Action System), predict locally a few frames ahead, and **roll back + resimulate** when the server's
authoritative state for a frame differs. Mispredictions are normal (other players' inputs are unknown).

## Required Workspace settings (set in Studio; `AuthorityMode = Server` sets the rest)
`Workspace.AuthorityMode = Server` (Studio-only; read/write RobloxScriptSecurity for scripts) →
`NextGenerationReplication` on, `PlayerScriptsUseInputActionSystem` on, `SignalBehavior = Deferred`,
`UseFixedSimulation` on, `StreamingEnabled` on.

## Programming model
| Concern | Rule |
|---|---|
| Core simulation | inside `RunService:BindToSimulation(fn, Enum.StepFrequency.Hz60 /* default Hz30 */, priority)` in a ModuleScript required by **both** server and client |
| What can be touched in `fn` | only members with **Simulation Access** (`python tools/api.py BasePart.CFrame` shows "Simulation Access"); others error. Notably `Players:GetPlayers()` and `Player.Character` are **not** simulation-accessible → cache references via events outside the callback |
| Custom state | **attributes** on predicted instances (mismatch → rollback); write them only inside bound functions |
| Attribute replication limits | first 64 attributes per Instance, name ≤ 50 chars, string values ≤ 50 chars |
| Inputs | `InputAction`s (`InputContext` must be a descendant of the `Player`, e.g. clone a folder into each player on join); read `action:GetState()` inside the simulation on both sides |
| Never in simulation | `UserInputService.InputBegan` etc., DataStore/HTTP/yields, UI, sounds, particles, purchases, `print` spam |
| Effects | render in `RunService.PreRender`/`RenderStepped` (client) by **reading** simulated state (e.g. an attribute state machine); be ready to undo effects that were mispredicted |
| Prediction scope | automatic near the local character; override with `RunService:SetPredictionMode(instance, Enum.PredictionMode.On/Off/Automatic)` (client only) |
| Creating instances predictively | `Instance.new`/`Clone`/`Instance.fromExisting` inside a bound callback → deterministic GUID "stitching" with the server copy; parent before the frame ends; set non-simulation props before parenting |
| Animations | don't cache `AnimationTrack`s across frames; query `Animator:GetTrackByAnimationId(id)` / `GetPlayingAnimationTracks()` each step; mirror animation logic on both sides |
| Remotes | still allowed for discrete events (score, pickups), but **not ordered** with property/attribute updates |
| Visual smoothing | render a separate visual-only clone that follows the simulated object with `TweenService:SmoothDamp` in `RenderStepped` |

## Minimal skeleton
```luau
--!strict
-- ReplicatedStorage/Simulation (ModuleScript), required by one server Script and one client script.
-- Players:GetPlayers() and Player.Character have NO Simulation Access, so references are gathered outside the
-- simulation (events) and the bound function only touches Simulation-Access members (GetState, SetAttribute).
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

type Entry = { character: Model, sprint: InputAction }
local tracked: { [Player]: Entry } = {}

local function track(player: Player, character: Model)
	local inputs = player:WaitForChild("Inputs", 10)
	local sprint = inputs and inputs:FindFirstChild("Sprint", true)
	if sprint and sprint:IsA("InputAction") then
		tracked[player] = { character = character, sprint = sprint }
	end
end

local Simulation = {}

function Simulation.start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(c) track(player, c) end)
		if player.Character then task.spawn(track, player, player.Character) end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do onPlayer(p) end
	Players.PlayerRemoving:Connect(function(p) tracked[p] = nil end)

	RunService:BindToSimulation(function(_dt: number)
		for _, entry in tracked do
			entry.character:SetAttribute("Sprinting", entry.sprint:GetState() == true)
		end
	end, Enum.StepFrequency.Hz60)
end

return Simulation
```
Verify every member you call inside the callback has Simulation Access (`python tools/api.py Class.Member`). The
example above is a shape illustration (TYPECHECKED only); not run under server authority.

## Decision: use it or not?
| Use server authority mode | Stay classic |
|---|---|
| PvP where movement/physics cheating ruins the game | Co-op, horror, social, tycoon, obby, story games |
| Physics-driven competitive objects (ball, cars) | Heavy use of legacy character scripts you can't port |
| You can restructure core gameplay into a deterministic simulation module | Team unfamiliar with deterministic simulation; deadline soon |
Classic + server validation ([04](04-security.md)) is enough for most games.

## Pitfalls
- Porting remote-per-action gameplay into the simulation loop → duplicated effects on every resimulation.
- Reading non-synchronized properties (e.g. `Humanoid.WalkSpeed` if not Simulation Access) inside `fn` → runtime
  error by design. Mirror them into attributes and apply in `PostSimulation`/`RenderStepped`.
- Holding references to instances you created speculatively and parenting them in a later frame (breaks stitching).
- Forgetting that `SetPredictionMode` is client-only.

Sources: cd:projects/server-authority/index, cd:projects/server-authority/techniques, cd:input/input-action-system,
cd:reference/engine/classes/RunService, cd:scripting/security/network-ownership, cd:scripting/events/deferred.
