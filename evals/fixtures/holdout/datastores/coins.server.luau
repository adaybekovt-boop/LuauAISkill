local store = game:GetService("DataStoreService"):GetDataStore("Coins")
local function addCoins(userId, amount)
    local old = store:GetAsync(tostring(userId)) or 0
    store:SetAsync(tostring(userId), old + amount)
end
return addCoins
