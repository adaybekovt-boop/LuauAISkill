--!strict
local Service = {}
local dependency: any = nil
task.spawn(function()
	dependency:Start()
end)
function Service.init(other: any)
	dependency = other
end
return Service
