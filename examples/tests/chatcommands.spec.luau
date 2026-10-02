--!strict
local Parser = require("../chatcommands/ServerScriptService/Commands/Parser")
assert(Parser.parse("/respawn"))
local kick = Parser.parse("/kick 12345")
assert(kick and kick.targetId == 12345)
for _, value in { "/kick DisplayName", "/kick 123 reason", "/kick -1", "/kick 1.2", "/kick 0", string.rep("x", 100) } do
    assert(Parser.parse(value) == nil, value)
end
assert(Parser.allowed(1, 1, {}))
assert(Parser.allowed(2, 1, { [2] = true }))
assert(not Parser.allowed(3, 1, { [2] = true }))
assert(not Parser.allowed(0, 0, {}))
print("chatcommands.spec: exact grammar, numeric identity, authorization and malformed payloads passed")
