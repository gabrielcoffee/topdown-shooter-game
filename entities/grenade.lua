local Entity = require('entity')

local Grenade = {}
Grenade.__index = Grenade
setmetatable(Grenade, Entity)

return Grenade