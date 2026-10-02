# Multiplayer regression fixture

Evidence: TYPECHECKED (old + new), CLI-EXECUTED pure protocol tests. Studio execution: NOT RUN.

Copy ReplicatedStorage, ServerScriptService and StarterPlayer folder contents into a disposable test place.
Leave PluginLauncher.lua.txt outside the DataModel mapping. Its exact contents are executable Luau for a Studio
plugin or Edit-mode command bar, where StudioTestService.ExecuteMultiplayerTestAsync has PluginSecurity.
Do not put that launcher in a game Script or LocalScript, and do not launch during an existing play session.

Run `python tools/check_recipe_contexts.py` from the repository root for the explicit context gate.
The launcher must pass PluginSecurity definitions and fail None definitions in the negative test. The runtime
fixture's method security and full signatures receive separate checks. Static typechecking does not start Studio.

The suite starts two clients, respawns one, adds a third, checks versioned replication/ignored malformed payloads,
then disconnects one and rechecks survivors. It returns named assertions through EndTest and prints JSON prefixed
REGRESSION_RESULT. Save that JSON and the launcher result with Studio build, place revision and mode before saying
STUDIO TESTED. See [the full recipe](../../recipes/gameplay/multiplayer-regression-harness.md) for test coverage,
timeouts, limits and the complete embedded source.
