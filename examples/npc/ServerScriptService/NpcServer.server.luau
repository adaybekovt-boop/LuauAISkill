--!strict
-- Starts the NPC manager. Other systems report loud events with NpcService.noise(position, loudness).
-- Status: TYPECHECKED. Not run in Studio.
local ServerScriptService = game:GetService("ServerScriptService")

local NpcService = require(ServerScriptService.Npc.NpcService)

NpcService.start()
