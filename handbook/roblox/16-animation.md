# Animation: Animator, tracks, priorities, blending, markers, IK, graphs

## TL;DR
- Load and manage tracks through the supported animation path.
- Understand which side owns and replicates each animation.
- Choose priorities and transitions explicitly.
- Disconnect marker and completion handlers on cleanup.
- Verify rig compatibility and permissions for real assets.

Read when: character/NPC/weapon animation, locomotion blending, aim/look, foot placement, procedural motion.
Related: [character controllers](13-character-controllers.md), [combat](15-combat.md), [NPC](20-npc-ai.md).

## Pipeline
`Animation` (holds `AnimationId`) → `Animator:LoadAnimation(animation)` → `AnimationTrack` → `Play/Stop/AdjustWeight/
AdjustSpeed`. The `Animator` lives under the rig's `Humanoid` or `AnimationController`.
- `Humanoid:LoadAnimation` and `AnimationController:LoadAnimation` are **deprecated** → always go through the
  `Animator` (`humanoid:FindFirstChildOfClass("Animator")` / `WaitForChild("Animator")`).
- Asset permission: the animation must be usable by the experience — created by the same user/group, or shared to
  the universe/collaborator via Creator Dashboard → Permissions. Otherwise it silently fails to load
  (Output warning). Most common "animation doesn't play" cause after wrong rig type (R6 vs R15).

## Replication rules
| Rig | Where to play | Replicates? |
|---|---|---|
| Player character | **owning client** (LocalScript), via its Animator | yes, to server & others (Animator on a client-owned character) |
| NPC | server | yes, to all clients (costs server CPU + bandwidth) |
| NPC, cosmetic-only / many NPCs | clients (each client creates/plays locally) | no (by design; cheaper) |
| Viewmodel / first-person arms | local client only | no |
Don't play the same animation from both server and client on the same rig (double playback/fighting).

## Track API essentials
- `track:Play(fadeTime = 0.1, weight = 1, speed = 1)`, `Stop(fadeTime)`, `AdjustWeight(w, fade)`,
  `AdjustSpeed(s)`, `Looped`, `Priority`, `TimePosition`, `Length` (0 until loaded — check before using),
  `IsPlaying`, `Ended`, `Stopped`, `DidLoop`.
- Load each animation **once per Animator** and reuse the track (cache by id); don't `LoadAnimation` every play
  (leaks tracks; there's a per-Animator track limit and warnings). Exception: server authority mode — query live
  tracks with `Animator:GetTrackByAnimationId` instead of caching ([05](05-server-authority.md)).
- Markers: `track:GetMarkerReachedSignal("Hit"):Connect(fn)` for footsteps, weapon trails, FX sync. `KeyframeReached`
  works for named keyframes. Markers on the client are cosmetic — never grant damage from a client marker alone.

## Priorities and blending
`Enum.AnimationPriority`: `Core` (lowest, default Animate idle/walk) < `Idle` < `Movement` < `Action` < `Action2` <
`Action3` < `Action4`. Higher priority overrides lower **per joint** for joints it animates; same priority blends by
weight. Design:
| Layer | Priority | Examples |
|---|---|---|
| Base locomotion | Core/Idle/Movement | idle, walk, run (default Animate script) |
| Stance overrides | Movement | crouch walk, aim walk |
| Upper-body actions | Action | reload, attack (animate only upper-body joints in the clip to leave legs to locomotion) |
| Hit reactions | Action2/3 | flinch, stagger |
| Emergency/overrides | Action4 | death pose, cutscene |
"Additive-like" layering: author clips that only key the joints you want (e.g. spine/arms) and play them above
locomotion; true additive blending exists in Animation Graphs (Add node).

## Locomotion
- Default `Animate` LocalScript (in the character) handles idle/walk/run/jump/fall/climb/swim. Replace animations by
  editing its `StringValue`/`Animation` children or copy the script and edit ids; or ship your own controller.
- Speed matching: adjust walk/run track speed by `horizontalSpeed / authoredSpeed` to prevent foot sliding; blend
  walk↔run weights by speed.
- Strafing (8-way): 4 directional clips weighted by `MoveDirection` in character space (dot with look/right vectors),
  or an Animation Graph blend space.

## Procedural animation
- Modify joints via `Motor6D.Transform` (applied after animation each frame; set in `PreSimulation`/after animation)
  — **not** `C0/C1` every frame (rebuilds clusters, expensive).
- Look-at/aim: rotate waist/neck `Motor6D.Transform` toward camera pitch with clamped angles; replicate aim pitch to
  others at a low rate (unreliable remote) and apply on their clients.
- `RunService.PreAnimation` runs before animations step — adjust weights/speeds there.

## Inverse kinematics (`IKControl`)
Put an `IKControl` under the Humanoid/AnimationController: `Type` (`Transform`, `Position`, `Rotation`, `LookAt`),
`ChainRoot` (e.g. UpperArm), `EndEffector` (e.g. RightHand or an Attachment), `Target` (Attachment/Part), optional
`Pole`, `Weight` (0–1), `SmoothTime`, `Priority`. Uses: hand on weapon grip, head look-at, foot placement on slopes
(raycast per foot → target attachment at hit position), reaching doors. IK respects `AnimationConstraint`s. Blend
`Weight` to 0 when not needed.

## Animation Graphs (2026 workflow)
- Built in Studio's Animation Graph Editor (Avatar tab) → publishes an `AnimationGraphDefinition` asset. Load it like
  an animation (`Animation.AnimationId = graph asset id`, `Animator:LoadAnimation`), then drive it with
  `track:SetParameter("Speed", v)`; read with `GetParameter`. Node types: `Enum.AnimationNodeType`. Marker events
  propagate up weighted by influence (zero-weight branches emit nothing).
- Replication: in `AuthorityMode.Automatic` the owning client drives player graphs and parameters replicate
  automatically (coalesced per frame); server drives NPC graphs. In `AuthorityMode.Server` the server drives the
  graph with client prediction.
- "Graph → Create Animate script" generates `Animate` (ModuleScript) + `RunClient`/`RunServer`; attributes
  `SourceAssetId`, `PreviewInStudio` (Studio loads the unpublished graph; set false to test the published asset —
  not supported under server authority). Publish before shipping.

## Pitfalls
| Symptom | Cause |
|---|---|
| Animation plays only for you | played on a client-created Animator on another player's rig, or on a non-owned NPC from the client |
| Doesn't play at all | wrong rig type (R6 clip on R15), asset permission, priority lower than locomotion, weight 0, track not loaded yet |
| Jitter/fighting | same joint driven by two same-priority tracks or by script `C0` + animation |
| Sliding feet | locomotion speed not matched to movement speed |
| Leaks / warnings about too many tracks | `LoadAnimation` called repeatedly; tracks never destroyed |

Sources: cd:animation/using, cd:animation/events, cd:animation/inverse-kinematics, cd:animation/graph-editor,
cd:reference/engine/classes/Animator, cd:reference/engine/classes/AnimationTrack, cd:reference/engine/classes/IKControl,
cd:reference/engine/enums/AnimationPriority, cd:projects/assets/privacy, cd:performance-optimization/improve,
cd:projects/server-authority/techniques.
