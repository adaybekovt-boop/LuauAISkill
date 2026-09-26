# Матрица модернизации

Не применять как поисково-заменяющий скрипт. Статусы различаются; все источники в registry.json.

## 01. Lua 5.4/5.5 syntax everywhere
**Подход:** Check Luau compatibility and host.

**Статус:** Language compatibility. Источник: L13.

**Ограничение:** Luau is not a full superset of later Lua; do not import filesystem/package APIs into Studio.

## 02. wait()
**Подход:** task.wait or an event driven design.

**Статус:** Migration with timing review. Источник: R07.

**Ограничение:** Do not preserve a polling loop unnecessarily; task.wait is not an exact timer.

## 03. spawn()
**Подход:** Choose task.defer or task.spawn by scheduling intent.

**Статус:** Migration with behavior review. Источник: R07.

**Ограничение:** Legacy delayed scheduling is not identical to immediate task.spawn.

## 04. delay()
**Подход:** task.delay with owner and cancellation policy.

**Статус:** Migration with lifecycle review. Источник: R07.

**Ограничение:** A scheduled callback can outlive character/UI; do not rely only on nominal delay.

## 05. a and b or c ternary
**Подход:** if a then b else c.

**Статус:** Supported modern syntax. Источник: L01.

**Ограничение:** False/nil b differs from desired true branch semantics.

## 06. hand written table iterator everywhere
**Подход:** Generalized iteration where appropriate.

**Статус:** Supported syntax, optional migration. Источник: L01.

**Ограничение:** Dictionary order remains unsuitable for deterministic algorithms.

## 07. assume all number values finite
**Подход:** Validate finite and domain range.

**Статус:** Correctness/security rule. Источник: R04.

**Ограничение:** Current math predicates have an isolated feature probe; portable predicate also provided.

## 08. const makes all data immutable
**Подход:** Binding immutability plus explicit ownership/freeze strategy.

**Статус:** Current documented language feature. Источник: L01.

**Ограничение:** Nested contents can still mutate; probe target parser.

## 09. type casts sanitize remotes
**Подход:** unknown + runtime validation.

**Статус:** Security rule. Источник: L02.

**Ограничение:** :: and --!strict do not perform runtime checks.

## 10. any as universal repair
**Подход:** Narrow unknown; local interfaces and tagged unions.

**Статус:** Engineering recommendation. Источник: L02.

**Ограничение:** Use escape hatches only with isolated rationale; do not mute entire modules.

## 11. table.clone for deep snapshot
**Подход:** Explicit copy depth and alias contract.

**Статус:** Library semantics. Источник: L10.

**Ограничение:** Clone is shallow; cyclic graphs need an explicit policy.

## 12. table.freeze recursively freezes game state
**Подход:** Freeze only documented boundary; preserve nested ownership.

**Статус:** Library semantics. Источник: L10.

**Ограничение:** Shallow table freeze does not freeze Instances or nested tables.

## 13. explicit generic syntax f<number>()
**Подход:** Current Luau f<<number>>() where supported.

**Статус:** Current documented syntax. Источник: L06.

**Ограничение:** Do not import TypeScript syntax; probe actual parser.

## 14. always --!native all files
**Подход:** Profile hot numeric code; file/function directive where supported.

**Статус:** Optional optimization. Источник: L12.

**Ограничение:** @native does not recursively mark inner functions; no universal speedup.

## 15. if local/exact tables as universal baseline
**Подход:** Treat current upstream experiments as gated.

**Статус:** Experimental in inspected 740. Источник: G05.

**Ограничение:** Merged/release source is not universal Studio support.

## 16. LocalScript in ReplicatedStorage runs
**Подход:** Script with RunContext Client or a valid LocalScript container.

**Статус:** Runtime placement. Источник: R01.

**Ограничение:** LocalScript remains supported; class and placement both matter.

## 17. Client Script copied into every starter root
**Подход:** One intentional entrypoint and correct host.

**Статус:** Duplicate-start risk. Источник: R01.

**Ограничение:** Avoid both original and clone startup where applicable.

## 18. ReplicatedStorage for private server secrets
**Подход:** Server-only storage/backend with appropriate rights.

**Статус:** Security boundary. Источник: R02.

**Ограничение:** Replicated containers are visible to clients.

## 19. RemoteFunction for every interaction
**Подход:** RemoteEvent request/ack where non-blocking semantics fit.

**Статус:** Architecture choice. Источник: R03.

**Ограничение:** RemoteFunction is not deprecated universally; avoid server critical path waiting on client.

## 20. client sends final damage/reward
**Подход:** Client intent, server computes and validates.

**Статус:** Security rule. Источник: R04.

**Ограничение:** Validate state, identity, timing and target independently.

## 21. client cooldown only
**Подход:** Server rate limiting + bounded registries.

**Статус:** Security rule. Источник: R04.

**Ограничение:** Client UI feedback is not enforcement.

## 22. checking range means movement anti-cheat
**Подход:** Separate movement authority/validation.

**Статус:** Security rule. Источник: R05.

**Ограничение:** A replicated exploiter-controlled position can pass naive distance checks.

## 23. all remotes reliable cosmetic streams
**Подход:** Choose reliable transitions vs lossy samples.

**Статус:** Protocol design. Источник: R03.

**Ограничение:** Unreliable samples cannot carry sole economy or guaranteed state transitions.

## 24. replicated attributes arrive before remote
**Подход:** Versioned reconciliation and missing-instance handling.

**Статус:** Replication rule. Источник: R02.

**Ограничение:** Do not depend on an undocumented ordering guarantee.

## 25. WaitForChild once proves lifetime
**Подход:** Streaming-aware lookup/cleanup/rebind.

**Статус:** Streaming contract. Источник: R10.

**Ограничение:** Instance can stream out later; timeout is not permission to invent placeholder state.

## 26. GetDescendants every frame
**Подход:** One-time scan + events/registries where correct.

**Статус:** Performance recommendation. Источник: R20.

**Ограничение:** A bounded audit pass is not the same as hot-loop scanning.

## 27. Actors make all API writes thread-safe
**Подход:** Read thread safety per member; serial commit.

**Статус:** Parallel contract. Источник: R08.

**Ограничение:** ReadSafe is not parallel write permission.

## 28. task.spawn is multicore parallelism
**Подход:** Actor/parallel model only when justified.

**Статус:** Concurrency distinction. Источник: R08.

**Ограничение:** Coroutines and concurrent tasks are not proof of CPU parallel speedup.

## 29. old ray helpers for new code
**Подход:** Workspace:Raycast + RaycastParams.

**Статус:** Modern API choice. Источник: R27.

**Ограничение:** Direction includes range magnitude; check returned nil and filters.

## 30. body mover chosen by an old tutorial
**Подход:** Evaluate current mover constraints.

**Статус:** Physics migration. Источник: R28.

**Ограничение:** Do not substitute force/velocity/position constraints without matching physical intent.

## 31. load failure creates fresh profile
**Подход:** Explicit unavailable/failed state and retry.

**Статус:** Data safety. Источник: R21.

**Ограничение:** Do not overwrite a valid stored profile with defaults after a failed read.

## 32. last retry may write older state
**Подход:** Serialize key operations and version/fence.

**Статус:** Data safety. Источник: R22.

**Ограничение:** Independent retry loops can reorder writes.

## 33. UpdateAsync callback yields/sends rewards
**Подход:** Pure non-yielding repeatable transform.

**Статус:** Data contract. Источник: R21.

**Ограничение:** Callback can execute more than once; irreversible effects need a separate durable protocol.

## 34. purchase popup closed means grant
**Подход:** Reviewed receipt processing and idempotency.

**Статус:** Purchase safety. Источник: R22.

**Ограничение:** Client completion is not authoritative purchase fulfillment.

## 35. MemoryStore forever inventory
**Подход:** Ephemeral cache/coordination + durable source.

**Статус:** Service distinction. Источник: R34.

**Ограничение:** TTL/expiry must be tolerated; not a replacement for DataStore.

## 36. MessagingService equals durable transaction
**Подход:** Publish invalidation/events around durable state.

**Статус:** Architecture choice. Источник: R35.

**Ограничение:** Design for duplicates/late events; no invented exactly-once guarantee.

## 37. client Teleport() for new systems
**Подход:** Server TeleportAsync and access settings.

**Статус:** Current guide deprecation. Источник: R36.

**Ограничение:** Full test needs published Roblox client, not Studio alone.

## 38. raw user text fallback if filter fails
**Подход:** Safe pending/error UI; current filter API.

**Статус:** Safety requirement. Источник: R37.

**Ограничение:** Do not publish unfiltered text on service errors.

## 39. Lighting.Technology = Future in normal script
**Подход:** LightingStyle + PrioritizeLightingQuality after exact permission check.

**Статус:** Current API supersession. Источник: R16.

**Ограничение:** Current YAML says new members write None; Technology RobloxScriptSecurity.

## 40. pcall makes restricted property work
**Подход:** Check security and required Studio setup.

**Статус:** API rule. Источник: R16.

**Ограничение:** pcall catches denial; it does not grant rights.

## 41. PBR has only four relevant maps
**Подход:** Read current five-map SurfaceAppearance guide.

**Статус:** Current graphics guide. Источник: R18.

**Ограничение:** Emissive is included; supported behavior and mutability still need checking.

## 42. every texture map freely mutable at runtime
**Подход:** Read pre-processing/mutation restrictions.

**Статус:** Material API contract. Источник: R18.

**Ограничение:** Color tint support is different from replacing texture maps.

## 43. higher roughness = more mirror-like
**Подход:** Use material reference and compare real response.

**Статус:** PBR review. Источник: R18.

**Ограничение:** Do not compensate wrong roughness with fake Bloom.

## 44. all instances unique imported meshes
**Подход:** Reuse supported content where appropriate.

**Статус:** Rendering recommendation. Источник: R20.

**Ограничение:** Separate asset IDs can prevent intended batching; verify actual render statistics.

## 45. SLIM works in any unsaved local file
**Подход:** Follow published/Team Create prerequisites.

**Статус:** Feature-specific setup. Источник: R24.

**Ограничение:** No claim of successful cloud transcoding without a real result.

## 46. realism is maximum Bloom/DOF/noise
**Подход:** Geometry→material→lighting→camera→effects.

**Статус:** Art-direction method. Источник: R19.

**Ограничение:** Readability and low-tier performance are acceptance criteria.

## 47. Sound is the only audio architecture
**Подход:** Evaluate modern AudioPlayer/Wire graph.

**Статус:** Modern option, not blanket deletion. Источник: R13.

**Ограничение:** Legacy working audio need not be rewritten without a reason.

## 48. keyboard callback equals cross-platform input
**Подход:** InputAction and device bindings where appropriate.

**Статус:** Current input system. Источник: R12.

**Ограничение:** Touch UI and modal priorities still require implementation.

## 49. Roblox styling is full CSS
**Подход:** StyleSheet/StyleRule contract and compatibility.

**Статус:** Current UI system. Источник: R14.

**Ограничение:** Do not generate unsupported CSS properties/selectors.

## 50. all movement requires hardcoded Humanoid state overrides
**Подход:** Evaluate opt-in CCL abilities.

**Статус:** Current beta option. Источник: R40.

**Ограничение:** Do not enable CCL blindly on an existing game.

## 51. animation graph is just a local table
**Подход:** Published graph asset + Animator + parameters.

**Статус:** Current animation workflow. Источник: R41.

**Ограничение:** Preview and published support/authority mode differ.

## 52. script sync backs up every scene property
**Подход:** Sync supported code roots; preserve separate metadata/place.

**Статус:** Current sync limitation. Источник: R30.

**Ограничение:** Tags/attributes and arbitrary instances are not a complete disk backup.

## 53. generated model can mutate any Workspace child
**Подход:** OnGenerate writes only its targetContainer.

**Статус:** Current procedural API. Источник: R33.

**Ограничение:** Avoid irreversible side effects during cancellable generation.

## 54. toolbox generator harmless until Play
**Подход:** Audit edit-time generators and capabilities.

**Статус:** Asset safety. Источник: R33.

**Ограничение:** Procedural assets can modify a place while editing.

## 55. all supported API is automatically available in a sandbox
**Подход:** Inspect exact capability and nesting contract.

**Статус:** Experimental security system. Источник: R32.

**Ограничение:** Nested capability sets do not grant extra parent rights.

## 56. instance count proves GPU budget
**Подход:** Real MicroProfiler / Scene Analysis / device evidence.

**Статус:** Measurement distinction. Источник: R39.

**Ограничение:** SceneAudit helper explicitly does not measure draw calls.

## 57. 60 FPS average proves smoothness
**Подход:** Frame-time distribution and repeatable scenarios.

**Статус:** Measurement method. Источник: R38.

**Ограничение:** Track spikes and separate CPU/GPU/bottleneck evidence.

## 58. all docs into one prompt
**Подход:** Progressive local retrieval + full relevant subsection.

**Статус:** Agent workflow. Источник: R00.

**Ограничение:** Index count is not file download count or measured model improvement.
