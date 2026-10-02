local function cast(origin, direction, character)
    local ray = Ray.new(origin, direction.Unit * 200)
    local part, position = workspace:FindPartOnRayWithIgnoreList(ray, {character})
    return part, position
end
return cast
