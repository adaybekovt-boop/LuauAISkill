# AI failure modes in Roblox/Luau work (BAD → WHY → CURRENT CORRECT → VERIFY USING)

Read before submitting any Roblox code or answer. Every "correct" item was checked against API 0.741.19 /
creator-docs (Sep 2026). "VERIFY" tells you how to prove it yourself: `python tools/api.py X`,
`python tools/check_api_refs.py file`, `python tools/check_code.py`, or a named doc.
Lines marked FAKE show names that do not exist — never use them.

## 1. Hallucinated APIs (they sound plausible, they don't exist)
| BAD (FAKE unless noted) | WHY | CORRECT | VERIFY |
|---|---|---|---|
| `Lighting.GlobalIllumination`, `Lighting.RayTracing`, `Lighting.SSAO`, `Lighting.ReflectionQuality` FAKE | no such properties; no user-controllable GI/RT/SSAO toggles | `LightingStyle = Realistic` (Studio), EnvironmentDiffuse/SpecularScale, local lights, post effects | `tools/api.py Lighting` |
| `game:GetService("PostProcessingService")`, `Camera.PostProcessing` FAKE | post effects are Instances | `BloomEffect`, `ColorCorrectionEffect`, `ColorGradingEffect`, `DepthOfFieldEffect`, `SunRaysEffect`, `BlurEffect` in Lighting/Camera | graphics/02 |
| `Instance.new("Shader")`, `material.Shader`, custom HLSL/GLSL FAKE | Roblox has no user shaders | materials/MaterialVariant/SurfaceAppearance, post effects, `EditableImage`/`EditableMesh` (CPU-side, budgeted) | `tools/api.py --search Shader` (none) |
| `InputService`, `game:GetService("Input")` FAKE | wrong service name | `UserInputService`, `ContextActionService`, InputAction instances | `tools/api.py UserInputService` |
| `Instance.new("UIFlexLayout")` FAKE | flex is a property set | `UIListLayout` (`HorizontalFlex`, `Wraps`) + `UIFlexItem` | ui chapter |
| `Humanoid.Speed`, `Sound.Loop`, `ScreenGui.Visible`, `ProximityPrompt.Text`, `Part.Colour` FAKE | invented names | `Humanoid.WalkSpeed`, `Sound.Looped`, `ScreenGui.Enabled`, `ProximityPrompt.ActionText`/`ObjectText`, `BasePart.Color` | `tools/api.py` each |
| `Model.CFrame`, `Model.Position` FAKE | Model has no transform properties | `model:GetPivot()`, `model:PivotTo(cf)`, `model.WorldPivot` | `tools/api.py Model` |
| `Enum.KeyCode.Shift`, `Enum.HumanoidStateType.Walking`, `Enum.EasingStyle.EaseInOut`, `Enum.Material.Steel` FAKE | nonexistent enum items | `Enum.KeyCode.LeftShift`, `Enum.HumanoidStateType.Running`, `Enum.EasingStyle.Sine` + `Enum.EasingDirection.InOut`, `Enum.Material.Metal`/`DiamondPlate`/`CorrodedMetal` | `tools/api.py Enum.KeyCode` |
| `RaycastFilterType.Blacklist/Whitelist` | removed items | `Exclude`/`Include`, or `RaycastParams.ExcludeInstances` | `tools/api.py Enum.RaycastFilterType` |
| `Vector3.magnitude` / `.unit` lowercase | undocumented legacy aliases | `.Magnitude`, `.Unit` | `tools/api.py Vector3` |
| `TweenService:Tween(part, 1, {...})` FAKE | wrong method/args | `TweenService:Create(inst, TweenInfo.new(1), goals):Play()` | `tools/api.py TweenService` |
| `PathfindingService:FindPath(a, b)` FAKE; `FindPathAsync` legacy | wrong/old | `CreatePath(params)` + `path:ComputeAsync(a, b)` | npc chapter |
| `Player:GetData()`, `PlayerDataService`, `PlayerDataRecord` (exist, undocumented in 0.740–0.741) | present in the engine dump without creator-docs pages → unreleased/in development; behaviour and availability unknown | DataStoreService + session-locked profiles ([save system](../recipes/gameplay/save-system.md)) | `tools/api.py PlayerDataService` prints UNDOCUMENTED |

## 2. Other engines / other languages leaking in
| BAD | WHY | CORRECT | VERIFY |
|---|---|---|---|
| Unity (not Roblox): `Instantiate(prefab)`, `GetComponent<T>()`, `transform.position`, `Time.deltaTime`, `Update()`, `Rigidbody.AddForce`, `Mathf.Lerp`, `Debug.Log`, `Vector3.Distance(a,b)` | not Roblox | `template:Clone()`, `inst:FindFirstChildOfClass("Humanoid")`, `part.Position`/`CFrame`, `dt` from RunService events, `RunService.Heartbeat`, `part:ApplyImpulse`/`VectorForce`, `math.lerp` or `a:Lerp(b, t)`, `print/warn`, `(a - b).Magnitude` | luau chapters |
| Unreal: "enable Lumen / Nanite / post-process volume" | not Roblox | Realistic lighting, SLIM/LOD, post effects in Lighting | graphics |
| JS/Python: `array.length`, `.push()`, `!=`, `&&`, `null`, `x ?? y`, `obj?.a`, `for i in range()` | not Luau | `#t`, `table.insert`, `~=`, `and`, `nil`, `if x == nil then y else x`, explicit nil checks, numeric for | luau/01 |
| Lua 5.4: `goto`, `<const>`, integer subtype, `utf8.charpattern` assumptions, `io.*`, `os.execute`, `require("path.to.file")` on disk | not available / different | `continue`, `const x =`, one number type, Roblox `require(ModuleScript)` or require-by-string relative to the script | luau/01, luau/03 |

## 3. Client/server confusion
| BAD | WHY | CORRECT | VERIFY |
|---|---|---|---|
| `Players.LocalPlayer` in a server Script | nil on server | player from events (`PlayerAdded`, remote first arg) | runtime chapter |
| Server: `remote.OnServerEvent:Connect(function(data) ...)` | first arg is always the Player | `function(player, data)` | networking |
| Client: `remote:FireServer(player, data)` | engine adds player; server receives (player, player, data) | `remote:FireServer(data)` | networking |
| Server: `remote:FireClient(data)` | first arg must be the target Player | `remote:FireClient(player, data)` / `FireAllClients(data)` | networking |
| Client handler `OnClientEvent:Connect(function(player, data)` | no player arg on client | `function(data)` | networking |
| DataStore/HttpService/MessagingService/MemoryStore/`BanAsync`/TeleportAsync from a LocalScript | server-only | server Script + remote intent | api security column |
| `workspace.CurrentCamera`, `UserInputService`, `Player:GetMouse()` on server | client concepts | client scripts | runtime chapter |
| LocalScript in `Workspace`/`ReplicatedStorage` expecting it to run | doesn't run there | client `Script` (RunContext Client) in ReplicatedStorage or LocalScript in StarterPlayerScripts | `cd:scripting/locations` |
| Client changes a part/leaderstat and expects others to see it | no replication from client | server changes it | security |
| Client-side `humanoid.Health = 0` on another player | doesn't replicate; can't kill others | server-side damage via validated remote | security |

## 4. Permissions and security levels
| BAD | WHY | CORRECT | VERIFY |
|---|---|---|---|
| `Lighting.Technology = ...`, `Lighting.LightingStyle = ...` in a game script | RobloxScriptSecurity / PluginOrOpenCloud-only write | set in Studio Properties; runtime changes other properties | `tools/api.py Lighting.LightingStyle` |
| `workspace.StreamingEnabled = true`, `SignalBehavior`, `StreamingIntegrityMode` at runtime | Studio settings (PluginSecurity/NotScriptable) | set in Studio | `tools/api.py Workspace.StreamingEnabled` |
| `script.Source = "..."`, `Instance.new("Script")` + Source | Source is plugin-only | ModuleScripts written in Studio | `tools/api.py Script.Source` |
| `meshPart.MeshId = ...`, `surfaceAppearance.ColorMap = ...` at runtime | NotAccessible/PluginSecurity | clone prebuilt variants; `AssetService:CreateMeshPartAsync`; tint via `SurfaceAppearance.Color` | api tool |
| `meshPart.CollisionFidelity = ...` at runtime | plugin-only write | set in Studio | api tool |
| `pcall(function() Lighting.Technology = ... end)` "to be safe" | pcall doesn't grant permission; hides the failure | don't write it | — |
| `loadstring(code)()` on client / enabling it for "mods" | client never has it; server flag off; security hole | data-driven configs | — |
| "It worked in `execute_luau` / the command bar" → same call in a game Script | MCP `execute_luau` and the command bar run with plugin security | check the game-script verdict before shipping | `tools/api.py Class.Member` |

## 5. Data & persistence semantics
| BAD | WHY | CORRECT | VERIFY |
|---|---|---|---|
| "GetAsync always returns the latest value" | 4 s local cache | `DataStoreGetOptions.UseCache = false` for verification reads | data chapter |
| "SetAsync is safe across servers" | last write wins, no read | `UpdateAsync` + session lock | data chapter |
| `task.wait` / remote calls inside `UpdateAsync` transform | transform must not yield; may rerun | pure transform | api: GlobalDataStore.UpdateAsync |
| "BindToClose gives unlimited time" | ~30 s total | parallel saves, skip stale queue entries | data chapter |
| "DataStores work in Studio by default" | need API access enabled; separate lower limits; writes hit real data | test universe | data chapter |
| Storing `Vector3`/`CFrame`/Instances in DataStores | not serializable | numbers/arrays | data chapter |
| Granting dev products on `PromptProductPurchaseFinished` | not a receipt; can fire without durable purchase | `ProcessReceipt` only | `api:MarketplaceService.ProcessReceipt` |
| `OrderedDataStore` for tables | integers only | standard DataStore + separate ordered score | data chapter |
| Returning `Enum.ProductPurchaseDecision` from a `BindReceiptHandler` handler (or `ReceiptDecision` from `ProcessReceipt`) | two receipt APIs, two enums | `BindReceiptHandler` → `Enum.ReceiptDecision.Processed`/`NotProcessedYet` | monetization chapter |
| Copying the docs' minimal `ProcessReceipt` sample into production | grants into leaderstats with no `PurchaseId` dedupe/durable save | session-locked profile + recorded `PurchaseId` ([save system](../recipes/gameplay/save-system.md)) | monetization chapter |
| `dataStore:BatchGetAsync(keys)` on a standard DataStore | ordered stores only; throws | `GetAsync` per key (or ordered store for scores) | `tools/api.py GlobalDataStore.BatchGetAsync` |

## 6. Outdated facts (confidently stated by models trained on older data)
See [legacy-modernization/CATALOG.md](legacy-modernization/CATALOG.md) (`outdated-fact` entries): light range 120 (not
60), Highlight cap 255 (not 31), DataStore limits changed, `*Async` renames (`LoadCharacterAsync`, `IsInGroupAsync`,
`GetProductInfoAsync`, `AwardBadgeAsync`, `ReserveServerAsync`, `PreloadAsync`), `PreRender`/`PreSimulation`
superseding `RenderStepped`/`Stepped`, Audio API superseding `Sound` for new work, Input Action System, server
authority mode (full release 2026-07, older models say beta or don't know it), `ExcludeInstances`.

## 7. Behavioural/semantic errors that typecheck fine
| BAD | WHY | CORRECT |
|---|---|---|
| `Color3.new(255, 0, 0)` | components are 0–1 → clamps to white-ish | `Color3.fromRGB(255, 0, 0)` |
| `CFrame.Angles(90, 0, 0)` | radians expected | `CFrame.Angles(math.rad(90), 0, 0)` |
| `UDim2.new(0.5, 0.5)` | 4 args (xScale, xOffset, yScale, yOffset) | `UDim2.fromScale(0.5, 0.5)` |
| `workspace:Raycast(origin, direction.Unit)` | 1-stud ray | `direction.Unit * range` |
| `character:Clone()` returns nil | characters have `Archivable = false` | set `Archivable = true` first or use `Players:CreateHumanoidModelFromDescriptionAsync` |
| `humanoid:MoveTo(target)` for a long chase | gives up after ~8 s | re-issue on `MoveToFinished`, pathfinding |
| Server sets another player's `AssemblyLinearVelocity` | the owning client overrides it | constraint on the victim or client-applied impulse |
| `TeleportService:TeleportAsync` "works" in Studio | Studio playtests don't support teleports | publish and test |
| `Touched` with no debounce | fires many times per contact | per-target cooldown set |
| `string.format("%s", nil)` | errors in Luau | `tostring(x)` |
| Echoing `TextChatCommand.Triggered` text to other players | it is the **unfiltered** message | filter with `TextService:FilterStringAsync` or don't echo |
| Verifying replication with MCP `start_stop_play` | it starts one client | `StudioTestService:ExecuteMultiplayerTestAsync` or Server & Clients |
| Fixing a bug by editing instances during Play (MCP or by hand) | play-mode changes are discarded; Rojo overwrites synced scripts | patch the source of truth, then re-run the reproducer |

## 8. Honesty failures
| BAD | CORRECT |
|---|---|
| "Tested in Studio, works perfectly" without Studio access | state evidence level: TYPECHECKED / CLI-EXECUTED / NOT RUN |
| Inventing profiler numbers or FPS gains | only report measured values with conditions |
| Claiming an API exists because it "should" | `python tools/api.py X` → NOT FOUND means don't use |
| "STUDIO TESTED" because a playtest subagent said "passed" | quote the concrete assertions/console lines/screenshot it produced, with mode |
| "Tested" after an Open Cloud task | CLOUD EXECUTED: server DataModel only, no physics, no clients |
| Silently changing public behaviour while "modernizing" | list behavioural changes explicitly |

Sources: api:Lighting.LightingStyle, api:Script.Source, api:MeshPart.MeshId, api:Enum.RaycastFilterType,
cd:scripting/events/remote, cd:scripting/locations, cd:cloud-services/data-stores/versioning-listing-and-caching,
cd:reference/engine/classes/MarketplaceService, cd:projects/teleport, cd:studio/mcp,
cd:reference/engine/classes/StudioTestService, cd:reference/engine/classes/TextChatCommand, cd:art/modeling/surface-appearance.

## Case-sensitive orientation members
Use the documented `CFrame.LookVector` spelling for the forward direction; do not preserve undocumented
`lookVector` casing when modernizing code. Verify the current datatype member with `python tools/api.py CFrame.LookVector`.
