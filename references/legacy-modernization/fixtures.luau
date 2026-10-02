-- LEGACY: generated detecting fixtures; intentionally incorrect/obsolete examples.
-- These are scanner fixtures, not a runnable Studio script or migration code.
-- Edit catalog.json fixture fields, then run tools/check_legacy.py.

-- rule: sched-wait
wait(1)

-- rule: sched-spawn
spawn(function() work() end)

-- rule: sched-delay
delay(1, callback)

-- rule: sched-tick
local now = tick()

-- rule: sched-while-wait
while wait(0.1) do poll() end

-- rule: sched-stepped
RunService.Stepped:Connect(step)

-- rule: sched-renderstepped
RunService.RenderStepped:Connect(render)

-- rule: sched-coroutine-wrap
coroutine.wrap(function() work() end)()

-- rule: lang-ypcall
ypcall(work)

-- rule: lang-getfenv
local env = getfenv(1)

-- rule: lang-table-getn
local n = table.getn(values)

-- rule: lang-g-shared
_G.Money = 5

-- rule: lang-ternary
local value = condition and first or fallback

-- rule: lang-cframe-new-lookat
local cf = CFrame.new(position, target)

-- rule: inst-new-parent
local p = Instance.new("Part", workspace)

-- rule: inst-lowercase
signal:connect(callback)

-- rule: inst-remove
part:Remove()

-- rule: inst-getservice
local players = game.Players

-- rule: inst-setprimarypartcframe
model:SetPrimaryPartCFrame(cf)

-- rule: inst-makejoints
model:MakeJoints()

-- rule: inst-message-hint
local hint = Instance.new("Hint")

-- rule: inst-hopperbin
local bin = Instance.new("HopperBin")

-- rule: inst-status
humanoid:AddCustomStatus("Slow")

-- rule: phys-bodymovers
local velocity = Instance.new("BodyVelocity")

-- rule: phys-velocity
part.Velocity = direction

-- rule: phys-collision-groups
PhysicsService:CreateCollisionGroup("Players")

-- rule: phys-light-range-60
Lighting.ExtendLightRangeTo120 = false

-- rule: query-findpartonray
workspace:FindPartOnRay(ray)

-- rule: query-filter-blacklist
params.FilterType = Enum.RaycastFilterType.Blacklist -- removed enum item, intentional fixture

-- rule: query-filterdescendants
params.FilterDescendantsInstances = {character}

-- rule: query-region3
workspace:FindPartsInRegion3(region)

-- rule: anim-humanoid-load
humanoid:LoadAnimation(animation)

-- rule: anim-keyframereached
track.KeyframeReached:Connect(onKeyframe)

-- rule: sec-filteringenabled
workspace.FilteringEnabled = false

-- rule: sec-client-currency
player.leaderstats.Coins.Value += 10

-- rule: sec-remote-damage
damageRemote.OnServerEvent:Connect(function(player, target, damage) target.Humanoid:TakeDamage(damage) end)

-- rule: sec-invokeclient
remote:InvokeClient(player)

-- rule: sec-require-assetid
local admin = require(123456789)

-- rule: sec-secrets-replicated
local api_key = "example-placeholder"

-- rule: async-loadcharacter
player:LoadCharacter()

-- rule: async-group
player:IsInGroup(groupId)

-- rule: async-friends
player:IsFriendsWith(userId)

-- rule: async-humanoiddesc
humanoid:ApplyDescription(description)

-- rule: async-preload
ContentProvider:Preload(id)

-- rule: money-productinfo
MarketplaceService:GetProductInfo(id)

-- rule: money-gamepass
GamePassService:PlayerHasPass(player, id)

-- rule: money-receipt
return Enum.ProductPurchaseDecision.PurchaseGranted

-- rule: money-badge
BadgeService:AwardBadge(userId, badgeId)

-- rule: tp-client-teleport
TeleportService:Teleport(placeId, player)

-- rule: tp-reserve
TeleportService:ReserveServer(placeId)

-- rule: data-player-save
player:SaveNumber("Coins", amount)

-- rule: data-setasync-profile
store:SetAsync(key, profile)

-- rule: data-default-on-fail
if not success then data = DEFAULT end

-- rule: data-onupdate
store:OnUpdate(key, callback)

-- rule: data-old-limits
local writeCooldownSeconds = 6

-- rule: data-datastore2
local profile = DataStore2("Coins", player)

-- rule: data-remove-version
store:RemoveVersionAsync(key, version)

-- rule: light-technology
Lighting.Technology = Enum.Technology.Future

-- rule: light-outlines
Lighting.Outlines = true

-- rule: light-fog-with-atmosphere
Lighting.FogEnd = 100

-- rule: light-compat-look
local technology = Enum.Technology.Compatibility

-- rule: render-highlight-31
local maxHighlights = 31

-- rule: render-surfaceappearance-swap
appearance.ColorMap = asset

-- rule: render-meshid-runtime
meshPart.MeshId = asset

-- rule: render-collisionfidelity-runtime
meshPart.CollisionFidelity = Enum.CollisionFidelity.Box

-- rule: render-streamingenabled-runtime
workspace.StreamingEnabled = true

-- rule: render-texture-realism
part.Material = Enum.Material.SmoothPlastic

-- rule: audio-sound-props
sound.Pitch = 0.5

-- rule: audio-legacy-sound
local sound = Instance.new("Sound")

-- rule: audio-assetid
audioPlayer.AssetId = asset

-- rule: ui-tween-methods
frame:TweenPosition(position)

-- rule: ui-text-props
label.FontSize = size

-- rule: ui-draggable
frame.Draggable = true

-- rule: ui-guiinset
local inset = GuiService:GetGuiInset()

-- rule: ui-resetplayergui
StarterGui.ResetPlayerGuiOnSpawn = false

-- rule: ui-mouseclick
button.MouseButton1Click:Connect(activate)

-- rule: input-mouse
mouse.KeyDown:Connect(onKey)

-- rule: input-modalenabled
UserInputService.ModalEnabled = true

-- rule: input-bindtypes
ContextActionService:BindActionToInputTypes("Jump", callback, false, input)

-- rule: chat-legacy
Chat:Chat(part, text)

-- rule: chat-filter-player
Chat:FilterStringForPlayerAsync(text, player)

-- rule: layout-localscript-rs
local script = Instance.new("LocalScript"); script.Parent = game:GetService("ReplicatedStorage")

-- rule: layout-scripts-in-parts
local script = Instance.new("Script"); script.Parent = workspace.Door

-- rule: layout-signalbehavior
workspace.SignalBehavior = Enum.SignalBehavior.Immediate

-- rule: stream-pausemode
workspace.StreamingPauseMode = mode

-- rule: terrain-legacy-cells
workspace.Terrain:SetCell(0, 0, 0, 1, 0, 0)

-- rule: path-old
PathfindingService:ComputeRawPathAsync(start, finish, distance)

-- rule: camera-old
camera.CoordinateFrame = cf

-- rule: server-authority-opt
character.HumanoidRootPart:SetNetworkOwner(player)

-- rule: badge-info-enabled
local disabled = BadgeService:IsDisabled(id)

-- rule: badge-islegal
if BadgeService:IsLegal(id) then grant(id) end

-- rule: money-premium-prompt
MarketplaceService:PromptPremiumPurchase(player)

-- rule: ui-transparency
frame.Transparency = 0.5

-- rule: phys-material-properties
part.Friction = 0.3

-- rule: phys-render-cframe
local cf = part:GetRenderCFrame()

-- rule: phys-touch-events
part.LocalSimulationTouched:Connect(onTouch)

-- rule: phys-outfit-changed
part.OutfitChanged:Connect(refresh)

-- rule: phys-lowercase-aliases
local mass = part:getMass()

-- rule: phys-bodymover-aliases
bodyVelocity.velocity = direction * speed

-- rule: anim-r6-body-parts
local leg = humanoid.LeftLeg

-- rule: anim-humanoid-aliases
humanoid:loadAnimation(animation)

-- rule: light-shadow-color
Lighting.ShadowColor = Color3.new(0, 0, 0)

-- rule: light-time-aliases
Lighting:setMinutesAfterMidnight(720)

-- rule: inst-model-bounds
local cf = model:GetModelCFrame()

-- rule: inst-model-identity
model:ResetOrientationToIdentity()

-- rule: inst-model-aliases
model:moveTo(position)

-- rule: query-addtofilter
params:AddToFilter(character)

-- rule: query-filtertype
params.FilterType = Enum.RaycastFilterType.Exclude

-- rule: path-waypoints
local points = path:GetPointCoordinates()

-- rule: path-emptycutoff
PathfindingService.EmptyCutoff = 0.2

-- rule: phys-collision-group-queries
local groups = PhysicsService:GetCollisionGroups()

-- rule: phys-unregister-group
PhysicsService:RemoveCollisionGroup("Old")

-- rule: terrain-legacy-water
workspace.Terrain:SetWaterCell(0, 0, 0, 0, 0)

-- rule: terrain-smooth-flags
if workspace.Terrain.IsSmooth then build() end

-- rule: stream-interpolation-throttling
workspace.InterpolationThrottling = mode

-- rule: lang-collectgarbage
local kb = collectgarbage("count")

-- rule: inst-lowercase-properties
if object:isA("Part") then inspect(object.className) end

-- rule: inst-value-changed-aliases
value.changed:Connect(onChanged)

-- rule: inst-collection-tags
local items = CollectionService:GetCollection("Coin")

-- rule: anim-playing-tracks
local tracks = humanoid:GetPlayingAnimationTracks()

-- rule: anim-played-signal
humanoid.AnimationPlayed:Connect(onTrack)

-- rule: anim-keyframe-provider-async
provider:GetKeyframeSequence(id)

-- rule: anim-clip-provider-async
provider:GetAnimationClip(id)

-- rule: avatar-editor-async
local pages = AvatarEditorService:SearchCatalog(params)

-- rule: async-character-description
player:LoadCharacterWithHumanoidDescription(description)

-- rule: async-avatar-model-description
local description = Players:GetHumanoidDescriptionFromOutfitId(id)

-- rule: async-description-reset
humanoid:ApplyDescriptionReset(description)

-- rule: async-group-all-roles
local rank = player:GetRankInGroupAsync(groupId)

-- rule: player-character-appearance
player:LoadCharacterAppearance(accessory)

-- rule: player-appearance-loaded
if player.AppearanceDidLoad then ready() end

-- rule: player-service-aliases
local count = Players.NumPlayers

-- rule: player-userid-alias
local key = tostring(player.userId)

-- rule: phys-attachment-axis
attachment:SetAxis(direction)

-- rule: phys-attachment-orientation
attachment.Rotation = angles

-- rule: render-particle-spread
emitter.VelocitySpread = 45

-- rule: ui-translator-async
local translator = LocalizationService:GetTranslatorForPlayer(player)

-- rule: ui-localization-table
local contents = localizationTable:GetContents()

-- rule: ui-localization-language
local locale = localizationTable.DevelopmentLanguage

-- rule: ui-auto-localize
label.Localize = true

-- rule: ui-selection-groups
GuiService:AddSelectionParent("Menu", frame)

-- rule: ui-layout-custom-sort
layout:SetCustomSortFunction(compare)

-- rule: input-vr-service
local pose = UserInputService:GetUserCFrame(Enum.UserCFrame.Head)

-- rule: input-touch-movement-enums
mode = Enum.DevTouchMovementMode.DPad

-- rule: phys-align-enums
align.AlignType = Enum.AlignType.Parallel

-- rule: audio-acoustic-simulation
emitter.SimulationFidelity = fidelity

-- rule: audio-search-subtype
params.AudioSubtype = subtype

-- rule: inst-service-aliases
local players = game:getService("Players")

-- rule: data-shutdown-callback
game.OnClose = saveAll

-- rule: server-private-fields
local id = game.VIPServerId

-- rule: audio-sound-aliases
sound:play()

-- rule: asset-free-search-async
local results = InsertService:GetFreeModels(query, page)

-- rule: asset-search-package-async
local pages = AssetService:SearchAudio(params)
