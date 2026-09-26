--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: Roblox shared ModuleScript
-- Idempotent attach/detach for CollectionService tags. Attach must be fast and non-yielding.
local CollectionService = game:GetService("CollectionService")
export type Release = () -> ()
local TaggedBinder = {}
function TaggedBinder.bind(tag: string, attach: (Instance) -> Release): Release
    local active = true
    local records: {[Instance]: {release: Release?}} = {}
    local function safeRelease(release: Release): ()
        local ok, err = pcall(release)
        if not ok then warn("TaggedBinder cleanup:", err) end
    end
    local function added(instance: Instance): ()
        if not active or records[instance] ~= nil then return end
        local record: {release: Release?} = {release = nil}
        records[instance] = record
        local ok, result = pcall(attach, instance)
        if not ok then
            if records[instance] == record then records[instance] = nil end
            warn("TaggedBinder attach failed:", result)
            return
        end
        local release = result :: Release -- trusted internal attach contract, not a remote payload
        if not active or records[instance] ~= record then
            safeRelease(release)
        else
            record.release = release
        end
    end
    local function removed(instance: Instance): ()
        local record = records[instance]
        if record == nil then return end
        records[instance] = nil
        if record.release then safeRelease(record.release) end
    end
    local addedConnection = CollectionService:GetInstanceAddedSignal(tag):Connect(added)
    local removedConnection = CollectionService:GetInstanceRemovedSignal(tag):Connect(removed)
    for _, instance in CollectionService:GetTagged(tag) do added(instance) end
    return function(): ()
        if not active then return end
        active = false
        addedConnection:Disconnect()
        removedConnection:Disconnect()
        -- Snapshot: cleanup callbacks may reenter this code.
        local owned = records
        records = {}
        for _, record in owned do
            if record.release then safeRelease(record.release) end
        end
    end
end
return table.freeze(TaggedBinder)
