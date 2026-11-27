---@meta
-- The few Cfx.re runtime names spur_core/types leans on, for the CI type check only.
-- In an editor they come from a natives extension (spur_core/types/_README.lua, step 4); CI has none, so without
-- these every vector3 in the stubs would read as an unknown type and hide a real one.

---@class vector2
---@field x number
---@field y number

---@class vector3: vector2
---@field z number

---@class vector4: vector3
---@field w number

Citizen = {}
