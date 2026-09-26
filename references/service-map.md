# Service map (what each service is for, which side uses it)

S = server, C = client, both = S+C. Always `game:GetService(ServiceName)`. Details: `python tools/api.py <Service>`.

| Service | Side | Use for | Key APIs / notes |
|---|---|---|---|
| `Players` | both | players, characters, respawn | `PlayerAdded/PlayerRemoving`, `GetPlayers`, `LocalPlayer` (C), `GetPlayerFromCharacter`, `BanAsync` (S), `RespawnTime`, `CharacterAutoLoads` |
| `Workspace` (`workspace`) | both | 3D world, physics, queries | `Raycast/Blockcast/Spherecast/Shapecast`, `GetPartBoundsInBox/Radius`, `GetPartsInPart`, `BulkMoveTo`, `CurrentCamera` (C), `Gravity`, `GetServerTimeNow`, streaming settings (Studio) |
| `ReplicatedStorage` | both | shared modules, remotes, assets both sides need | not streamed; visible to clients |
| `ReplicatedFirst` | C first | loading screen | `RemoveDefaultLoadingScreen` |
| `ServerScriptService` | S | server scripts/modules | invisible to clients |
| `ServerStorage` | S | server-only assets/modules | clone into Workspace when needed |
| `StarterPlayer` (+ `StarterPlayerScripts`, `StarterCharacterScripts`) | template | client/character scripts, character defaults | `CharacterWalkSpeed`, `CharacterJumpHeight`, `CameraMaxZoomDistance`… |
| `StarterGui` | template | ScreenGuis | `SetCore`/`GetCore` (C) for core UI (e.g. reset button), `SetCoreGuiEnabled` |
| `StarterPack` | template | default tools | |
| `Lighting` | both (server changes replicate) | global lighting, post effects, Atmosphere, Sky | style settings Studio-only |
| `SoundService` | both | global audio settings, 2D sound playback | `PlayLocalSound`, `AcousticSimulationEnabled`, listener settings (Studio) |
| `RunService` | both | frame events, environment checks | `Heartbeat`, `PreSimulation`, `PostSimulation`, `PreRender` (C), `PreAnimation`, `BindToRenderStep` (C), `BindToSimulation`, `IsServer/IsClient/IsStudio` |
| `TweenService` | both (prefer C for visuals) | property tweens | `Create`, `GetValue`, `SmoothDamp` |
| `UserInputService` | C | raw input, devices, mouse | `InputBegan`, `GetMouseDelta`, `MouseBehavior`, `TouchEnabled`, `PreferredInput` |
| `ContextActionService` | C | action bindings + touch buttons | `BindAction`, `BindActionAtPriority`, `UnbindAction` |
| `GuiService` | C | UI selection, insets, accessibility flags | `SelectedObject`, `ReducedMotionEnabled`, `PreferredTextSize`, `TouchControlsEnabled` |
| `CollectionService` | both | tags | `GetTagged`, `GetInstanceAddedSignal/RemovedSignal`, `AddTag/HasTag` (also on Instance) |
| `PhysicsService` | S (setup) | collision groups | `RegisterCollisionGroup`, `CollisionGroupSetCollidable` |
| `PathfindingService` | S (usually) | navigation | `CreatePath` → `ComputeAsync` |
| `DataStoreService` | S | persistence | `GetDataStore`, `GetOrderedDataStore`, rate-limit APIs |
| `MemoryStoreService` | S | temporary shared data | `GetHashMap`, `GetSortedMap`, `GetQueue` |
| `MessagingService` | S | cross-server pub/sub | `PublishAsync`, `SubscribeAsync` |
| `TeleportService` | S (C for teleport GUI) | move players between places/servers | `TeleportAsync`, `ReserveServerAsync`, `SetTeleportGui` (C) |
| `MarketplaceService` | both (grant on S) | purchases | `ProcessReceipt` (S callback), `PromptProductPurchase` (C/S), `UserOwnsGamePassAsync`, `GetProductInfoAsync` |
| `BadgeService` | S | badges | `AwardBadgeAsync`, `UserHasBadgeAsync` |
| `GroupService` | S | group roles | `GetRolesInGroupAsync`, `GetGroupInfoAsync` |
| `HttpService` | S (requests) | web requests, JSON, GUIDs, secrets | `RequestAsync/GetAsync/PostAsync` (needs HTTP enabled), `JSONEncode/Decode`, `GenerateGUID`, `GetSecret` |
| `TextService` | S (filtering) / both (bounds) | text filtering, measurement | `FilterStringAsync`, `GetTextBoundsAsync` |
| `TextChatService` | both | modern chat | `TextChannels`, `TextChatCommand`, `OnIncomingMessage` |
| `LocalizationService` | both | translations | `GetTranslatorForPlayerAsync`, `RobloxLocaleId` |
| `PolicyService` | S/C | region/age policy checks (ads, paid random items, etc.) | `GetPolicyInfoForPlayerAsync` |
| `SocialService` | both | invites, parties | `PromptGameInvite`, `GetPlayersByPartyId` |
| `ProximityPromptService` | both | prompt global settings/events | `PromptTriggered`, `Enabled` |
| `AnalyticsService` | S | custom analytics events | `LogCustomEvent`, `LogEconomyEvent`, `LogProgressionEvent`, `LogOnboardingFunnelStepEvent` |
| `AssetService` | both (varies) | dynamic assets, place info | `CreateEditableImage/Mesh`, `CreateMeshPartAsync`, `GetGamePlacesAsync` |
| `ContentProvider` | C | preloading | `PreloadAsync` (sparingly) |
| `Debris` | both | timed destroy | `AddItem` (uncancellable) |
| `Teams` | both | teams | `Team` objects, `Player.Team` |
| `VoiceChatService` | both | voice settings | check docs for current API |
| `HapticService` | C | vibration | support checks |
| `MatchmakingService` | S | custom matchmaking attributes | `SetServerAttribute` |
| `SceneAnalysisService` | Studio/MCP diagnostics | scene composition analysis | not for runtime gameplay |

Verify any service quickly: `python tools/api.py <Service>` (members, security, deprecated flags).
Sources: cd:scripting/services, cd:projects/data-model, api:Players, api:RunService, api:AnalyticsService.
