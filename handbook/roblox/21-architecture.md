# Architecture: the simplest structure that fits the project

## TL;DR
- Start with the smallest architecture that fits the project.
- Give services and controllers explicit responsibilities.
- Use components for repeated world-object behavior.
- Keep dependencies and initialization order visible.
- Adopt frameworks or ECS only when their benefit is concrete.

Read when: starting a project, restructuring, adding a major system, choosing frameworks.
Related: [runtime](01-runtime-architecture.md), [code quality](22-code-quality.md), [patterns](../luau/04-patterns-data.md).

## Scale ladder — pick the lowest rung that works
| Project size | Structure |
|---|---|
| Prototype / jam (< 1–2k lines) | 1 server entry + 1 client entry + a handful of ModuleScripts; tags + binders for world objects |
| Small–medium game | **services (server) / controllers (client)** as plain ModuleScripts with `init()`/`start()`; shared `Types`, `Config`, `Net` modules; data-driven config tables |
| Large game / team | the same, plus: explicit dependency passing, component modules for tagged objects, strict typing everywhere, Rojo + Git + CI, test suites |
| Thousands of simulated entities | ECS-style data layout for the hot system only (e.g. projectiles, crowds), everything else stays services |
Do not start with a framework, DI container, event bus, and 40 folders for a 300-line game.

## Service / controller pattern (framework-free)
```luau
--!strict
-- ServerScriptService/ServerMain (Script): the only server entrypoint.
local ServerScriptService = game:GetService("ServerScriptService")

type Service = { name: string, init: ((any) -> ())?, start: (() -> ())? }
local services: { Service } = {}
for _, module in (ServerScriptService:WaitForChild("Services")):GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, svc = pcall(require, module)
		if ok and type(svc) == "table" then
			table.insert(services, svc :: Service)
		else
			warn("Service failed to load:", module.Name, svc)
		end
	end
end
table.sort(services, function(a: Service, b: Service) return a.name < b.name end) -- deterministic order
local registry = {}
for _, s in services do registry[s.name] = s end
for _, s in services do if s.init then s.init(registry) end end       -- wire dependencies, no side effects
for _, s in services do if s.start then task.spawn(s.start) end end   -- connect events, start loops
```
- `init` = resolve dependencies, build state; `start` = connect events, spawn loops. Nothing runs at require time.
- Explicit dependencies (`registry.DataService`) beat hidden requires of singletons in random places — but direct
  `require` of a stateless module is fine.
- Same shape on the client (controllers) from the client entry Script.

## Components for world objects
Tag instances (`Door`, `Lamp`, `Pickup`) in Studio; a component module binds behaviour per tagged instance with
setup/cleanup (see [lifecycle binder](02-lifecycle-events.md#tagged-objects-collectionservice-binder-replaces-scripts-inside-every-model)).
Server component = authoritative logic; client component = visuals/SFX. Config per instance via attributes.

## Data-driven design
```luau
--!strict
-- ReplicatedStorage/Shared/Items.luau — definitions are data; code reads them.
export type ItemDef = { id: string, name: string, maxStack: number, price: number?, kind: "Weapon" | "Consumable" | "Key" }
local Items: { [string]: ItemDef } = {
	medkit = { id = "medkit", name = "Medkit", maxStack = 3, price = 50, kind = "Consumable" },
	flashlight = { id = "flashlight", name = "Flashlight", maxStack = 1, kind = "Key" },
}
return table.freeze(Items)
```
Client-visible definitions are public; server-only secrets (drop tables, anti-cheat thresholds) go in
ServerStorage/ServerScriptService modules.

## Signals and event buses
- Within one side: a small typed signal module or `BindableEvent` for decoupling (e.g. `PlayerDataChanged`).
- Avoid a global string-keyed event bus for everything — untyped, hard to trace. Prefer explicit module APIs and a
  few well-named signals.
- Cross-side communication is **only** remotes/replication.

## State machines
Use explicit state machines for round flow, combat states, NPC AI, UI screens: a table of states with
`enter/exit/update` and a single `transition(to, reason)` function that logs. Replicate the current state to clients
via an attribute.

## When is ECS justified?
Many (≥ thousands) homogeneous entities updated every frame (bullets, particles-as-logic, crowd agents, voxel
sims) where cache-friendly arrays and batch processing matter. Otherwise ECS adds indirection with no benefit in
Luau. You can use arrays-of-structs-of-numbers in one hot system without converting the whole game.

## Third-party libraries (optional)
Common community packages (Wally-installed): signal implementations, Promise, cleanup helpers (Trove/Maid-like),
networking wrappers, profile/data libraries, state containers. Use only when they solve a real problem; pin versions;
review code (supply-chain risk); ensure the team understands the underlying engine behaviour. The skill's code works
without any of them.

## Folder conventions (Rojo-style, also fine in Studio)
```text
src/
  shared/      → ReplicatedStorage.Shared   (types, config, pure logic, net contract)
  client/      → ReplicatedStorage.Client   (+ ClientMain Script RunContext=Client)
  server/      → ServerScriptService.Server (+ ServerMain Script)
  assets/      → ServerStorage.Assets (models via .rbxm or built in Studio)
```

Sources: cd:scripting/locations, cd:scripting/module, cd:reference/engine/classes/CollectionService,
cd:resources/plant-reference-project, cd:projects/external-tools.
