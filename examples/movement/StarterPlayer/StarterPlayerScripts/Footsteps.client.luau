--!strict
-- Stride-based footsteps for every nearby character (players + models tagged "Footsteps"), played locally with the
-- Audio API (AudioPlayer → Wire → AudioEmitter on the root). One loop for all characters.
-- Sound assets are YOUR uploads: ReplicatedStorage.Footsteps.<MaterialName>/<AudioPlayer templates with Asset set>,
-- plus a "Default" folder. No asset ids are hard-coded here.
-- Status: TYPECHECKED. Not run in Studio.
local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HEAR_DISTANCE = 90 -- studs; farther characters are skipped entirely
local VOICES = 3 -- round-robin AudioPlayers per character (overlapping steps don't cut each other)
local LANDING_MIN_FALL = 18 -- studs/s downward speed that triggers a landing thud

local library = ReplicatedStorage:WaitForChild("Footsteps", 15)
if not library then
	warn("[Footsteps] ReplicatedStorage.Footsteps not found; footsteps disabled")
	return
end

local templates: { [string]: { AudioPlayer } } = {}
local preload: { Instance } = {}
for _, folder in library:GetChildren() do
	local list = {}
	for _, t in folder:GetChildren() do
		if t:IsA("AudioPlayer") then
			table.insert(list, t)
			table.insert(preload, t)
		end
	end
	if #list > 0 then
		templates[folder.Name] = list
	end
end
task.spawn(function()
	ContentProvider:PreloadAsync(preload) -- first steps would otherwise be silent while assets load
end)

type Walker = {
	humanoid: Humanoid,
	root: BasePart,
	voices: { AudioPlayer },
	nextVoice: number,
	distance: number,
	cleanup: { Instance | RBXScriptConnection },
}
local walkers: { [Model]: Walker } = {}
local random = Random.new()

local function pick(material: Enum.Material): AudioPlayer?
	local list = templates[material.Name] or templates.Default
	return if list then list[random:NextInteger(1, #list)] else nil
end

local function play(w: Walker, material: Enum.Material, loudness: number)
	local template = pick(material)
	if not template then
		return
	end
	local voice = w.voices[w.nextVoice]
	w.nextVoice = w.nextVoice % #w.voices + 1
	voice.Asset = template.Asset
	voice.Volume = template.Volume * loudness
	voice.PlaybackSpeed = template.PlaybackSpeed * random:NextNumber(0.92, 1.08) -- avoid the "machine gun" repeat
	voice:Play()
end

local function remove(character: Model)
	local w = walkers[character]
	if not w then
		return
	end
	walkers[character] = nil
	for _, item in w.cleanup do
		if typeof(item) == "RBXScriptConnection" then
			item:Disconnect()
		else
			item:Destroy()
		end
	end
end

local function add(character: Model)
	if walkers[character] then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) or not character:IsDescendantOf(game) then
		return
	end
	local emitter = Instance.new("AudioEmitter")
	emitter:SetDistanceAttenuation({ [0] = 1, [10] = 0.7, [35] = 0.2, [HEAR_DISTANCE] = 0 })
	emitter.Parent = root
	local w: Walker = { humanoid = humanoid, root = root, voices = {}, nextVoice = 1, distance = 0, cleanup = { emitter } }
	for i = 1, VOICES do
		local voice = Instance.new("AudioPlayer")
		voice.Name = "Step" .. i
		voice.Parent = root
		local wire = Instance.new("Wire")
		wire.SourceInstance = voice
		wire.TargetInstance = emitter
		wire.Parent = voice
		table.insert(w.voices, voice)
		table.insert(w.cleanup, voice)
	end
	table.insert(w.cleanup, humanoid.StateChanged:Connect(function(_, new: Enum.HumanoidStateType)
		if new == Enum.HumanoidStateType.Landed and -root.AssemblyLinearVelocity.Y > LANDING_MIN_FALL then
			play(w, humanoid.FloorMaterial, 1.4)
		end
	end))
	table.insert(w.cleanup, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			remove(character)
		end
	end))
	walkers[character] = w
end

-- Stride length grows with speed (walk ≈ 5.3 studs, sprint ≈ 6.3, crouch ≈ 4.2).
local function strideFor(speed: number): number
	return 3.2 + speed * 0.13
end

RunService.PostSimulation:Connect(function(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local ear = camera.CFrame.Position
	for character, w in walkers do
		local material = w.humanoid.FloorMaterial
		if w.humanoid.Health <= 0 or material == Enum.Material.Air or (w.root.Position - ear).Magnitude > HEAR_DISTANCE then
			continue
		end
		local v = w.root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		if speed < 1 then
			w.distance = 0 -- standing still resets the phase so the first step is on time
			continue
		end
		w.distance += speed * dt
		local stride = strideFor(speed)
		if w.distance >= stride then
			w.distance -= stride
			local loudness = math.clamp(speed / 16, 0.35, 1.3)
			if character:GetAttribute("Crouching") == true then -- only known for the local character
				loudness *= 0.5
			end
			play(w, material, loudness)
		end
	end
end)

local function watchPlayer(p: Player)
	p.CharacterAdded:Connect(add)
	if p.Character then
		task.spawn(add, p.Character)
	end
end
Players.PlayerAdded:Connect(watchPlayer)
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end

-- NPCs opt in with a tag; streaming may add/remove them at any time.
local function onTagged(inst: Instance)
	if inst:IsA("Model") then
		add(inst)
	end
end
CollectionService:GetInstanceAddedSignal("Footsteps"):Connect(onTagged)
CollectionService:GetInstanceRemovedSignal("Footsteps"):Connect(function(inst: Instance)
	if inst:IsA("Model") then
		remove(inst)
	end
end)
for _, inst in CollectionService:GetTagged("Footsteps") do
	task.spawn(onTagged, inst)
end
