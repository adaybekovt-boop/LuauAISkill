# Track: audio

Use for: sound effects, footsteps, ambience, music, horror soundscapes, voice.
Load: [audio](../handbook/roblox/17-audio.md).

Non-negotiables
- Audio API (AudioPlayer → Wire → AudioEmitter/AudioDeviceOutput) for new systems; legacy `Sound` still works.
- Cosmetic sounds play on clients (no replication); server-played sounds replicate to everyone.
- No hard-coded asset ids you haven't verified; preload what plays first.
- Layered soundscapes with buses/volume settings; captions for important sounds.

Recipes: [footsteps](../recipes/gameplay/footsteps.md), [horror interior § sound](../recipes/graphics/cinematic-horror-interior.md#sound).
