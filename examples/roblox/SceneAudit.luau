--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: Roblox Studio read-only ModuleScript
-- Counts instances; not draw calls, triangle counts, performance proof, or full security audit.
export type Report = {
    total: number,
    byClass: {[string]: number},
    unanchoredParts: number,
    transparentParts: number,
    shadowLights: number,
    codeObjects: {string},
}
local SceneAudit = {}
function SceneAudit.inspect(root: Instance): Report
    local report: Report = {total = 0, byClass = {}, unanchoredParts = 0, transparentParts = 0, shadowLights = 0, codeObjects = {}}
    for _, instance in root:GetDescendants() do
        report.total += 1
        report.byClass[instance.ClassName] = (report.byClass[instance.ClassName] or 0) + 1
        if instance:IsA("BasePart") then
            if not instance.Anchored then report.unanchoredParts += 1 end
            if instance.Transparency > 0 and instance.Transparency < 1 then report.transparentParts += 1 end
        end
        if instance:IsA("Light") and instance.Enabled and instance.Shadows then
            report.shadowLights += 1
        end
        if instance:IsA("LuaSourceContainer") then
            table.insert(report.codeObjects, instance:GetFullName())
        end
    end
    table.sort(report.codeObjects)
    return report
end
return table.freeze(SceneAudit)
