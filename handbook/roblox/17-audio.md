# Audio: the Audio API graph, spatial sound, soundscapes, horror ambience

Read when: any sound work. Related: [character footsteps](13-character-controllers.md#stride-based-footsteps-client-for-every-visible-character),
recipe [footsteps](../../recipes/gameplay/footsteps.md), [horror soundscape](../../recipes/graphics/cinematic-horror-interior.md#sound).

## Two systems (2026 status)
| System | Objects | Status |
|---|---|---|
| **Audio API (modular graph)** | `AudioPlayer`, `AudioEmitter`, `AudioListener`, `AudioDeviceOutput`, `AudioDeviceInput`, `Wire`, effects (`AudioEqualizer`, `AudioCompressor`, `AudioReverb`, `AudioChorus`, `AudioDistortion`, `AudioEcho`, `AudioFlanger`, `AudioPitchShifter`, `AudioTremolo`, `AudioFilter`, `AudioLimiter`, `AudioGate`), mixing (`AudioFader`, `AudioChannelMixer/Splitter`), `AudioAnalyzer`, `AudioTextToSpeech`, `AudioSpeechToText` | **current, recommended**; the audio docs say Sound/SoundGroup/SoundEffect are "now discouraged" in favor of it |
| Legacy | `Sound`, `SoundGroup`, `*SoundEffect` | still works everywhere; fine for existing projects and quick one-shots |
Don't rewrite a working Sound-based project just to migrate; do use the Audio API for new systems that need routing,
voice, occlusion or analysis.

## Audio API mental model
Producers (`AudioPlayer`, `AudioTextToSpeech`, `AudioDeviceInput` for voice) → **Wire** → modifiers (effects/fader)
→ Wire → consumers (`AudioEmitter` in the world, or `AudioDeviceOutput` = the player's speakers). The world is heard
by an `AudioListener` (usually on camera or character) → Wire → `AudioDeviceOutput`.
- `Wire.SourceInstance` / `Wire.TargetInstance` (optionally pin names). Nothing plays without a complete chain.
- 2D (UI, music): `AudioPlayer` → Wire → `AudioDeviceOutput`.
- 3D: `AudioPlayer` → Wire → `AudioEmitter` (parented to a part/attachment = position); listener chain created
  automatically when `SoundService.DefaultListenerLocation` (Studio setting) is `Character` or `Camera`
  (engine also creates an `AudioDeviceOutput`); `None` = you create the listener; `Default` = camera listener in
  voice-enabled experiences.
- `AudioPlayer`: `Asset` (content id; `AssetId` deprecated), `Looping`, `Volume`, `PlaybackSpeed`, `TimePosition`,
  `IsReady`, `Play(atTime?)`, `Stop()`, `Ended`, `LoopRegion`, `PlaybackRegion`.
- `AudioEmitter`: `SetDistanceAttenuation({[distance] = volume, ...})` volume-over-distance curve,
  `SetAngleAttenuation`, `AudioInteractionGroup` (only listeners in the same group hear it — separate "radio"
  channels, per-team audio), `GetAudibilityFor(listener)`.
- Acoustic simulation: `SoundService.AcousticSimulationEnabled` (global, documented) makes emitters/listeners
  simulate **occlusion** (muffled through walls), **diffraction** (around corners) and **reverb**; per-emitter
  `AcousticSimulationEnabled`, `OcclusionEnabled`/`DiffractionEnabled`/`ReverbEnabled` (`Enum.SimulationMode`) exist
  in the API dump but are thinly documented — test on target devices and budget CPU.

```luau
--!strict
-- 3D looping hum on a lamp using the Audio API (client or server; server-created instances replicate).
local function attachHum(lamp: BasePart, assetId: string): AudioPlayer
	local player = Instance.new("AudioPlayer")
	player.Asset = assetId
	player.Looping = true
	player.Volume = 0.6
	player.Parent = lamp
	local emitter = Instance.new("AudioEmitter")
	emitter:SetDistanceAttenuation({ [0] = 1, [8] = 0.6, [24] = 0.15, [40] = 0 })
	emitter.Parent = lamp
	local wire = Instance.new("Wire")
	wire.SourceInstance = player
	wire.TargetInstance = emitter
	wire.Parent = lamp
	player:Play()
	return player
end
print(attachHum)
```

## Legacy `Sound` quick reference (still valid)
`Sound.SoundId`, `Volume`, `PlaybackSpeed` (not `Pitch`, deprecated), `Looped`, `RollOffMode` (`InverseTapered`
recommended for realism), `RollOffMinDistance`/`RollOffMaxDistance` (not `MinDistance`/`MaxDistance`,
deprecated), `SoundGroup` for mixing, `TimePosition`, `IsLoaded`/`Loaded`. Parented to a part/attachment = 3D;
parented elsewhere (SoundService/PlayerGui) = 2D. `SoundService:PlayLocalSound(sound)` for UI clicks.
`SoundService.AmbientReverb`, `DistanceFactor`, `DopplerScale`, `RolloffScale` are global (affect `Sound`s).

## Who plays what (replication)
- Sounds/audio objects created or played **on the server** replicate to everyone (useful for world events).
- Client-created/played audio is local only — correct for UI, footsteps computed per client, music, ambience.
- For gameplay sounds from other players (gunshots), the server tells clients "shot at P" (remote) and each client
  plays locally (lower latency than server-played sounds, no duplicate for the shooter who already played it).

## Soundscape design (horror / immersive)
Layers, each with its own bus (AudioFader or SoundGroup) and volume setting:
1. **Room tone / ambience bed** (quiet looping, per zone): HVAC hum, fluorescent buzz (Backrooms ~120 Hz-ish buzz
   + slight high-freq hiss), wind, distant traffic. Crossfade between zones over 1–2 s when the player changes rooms
   (zones via tagged volumes checked a few times per second, or `GetPartsInPart` on the camera position).
2. **Spot emitters**: lamps, vents, machinery — 3D, short attenuation curves, randomized start offset so identical
   loops don't phase.
3. **Stingers / one-shots**: distant slams, creaks, metal groans — random interval (e.g. 20–60 s) with a cooldown and
   spatial placement behind/around the player; never too frequent (fatigue).
4. **Footsteps & foley**: material-based, stride-driven, pitch ±5–10 %, 3–6 variations per material.
5. **Threat audio**: monster breathing/footsteps with clear directionality — the player should be able to locate
   danger; this is gameplay, keep it readable.
6. **Music**: sparse; silence is a tool. Duck ambience under dialogue/stingers (fader automation).
Indoor vs outdoor: switch reverb (AudioReverb params or `SoundService.AmbientReverb` for legacy), low-pass outdoor
sounds when indoors, or rely on acoustic simulation occlusion.

## Performance and limits
- Hundreds of simultaneously playing 3D sounds cost CPU; cap concurrent one-shots per category (voice stealing:
  drop the quietest/farthest).
- Audio files are memory; don't preload every sound; stream long music.
- Distance-cull loops that are far from all listeners (stop/pause them).

## Accessibility
Master/music/SFX/voice sliders; subtitles/captions for important sounds; visual cues for critical audio (threat
indicators) for deaf/hard-of-hearing players.

Sources: cd:audio/index, cd:audio/objects, cd:audio/effects, cd:audio/assets, cd:sound/index, cd:sound/objects,
cd:sound/groups, cd:sound/dynamic-effects, cd:reference/engine/classes/SoundService,
cd:reference/engine/classes/AudioPlayer, cd:reference/engine/classes/AudioEmitter, cd:reference/engine/classes/Wire,
cd:reference/engine/classes/Sound.
