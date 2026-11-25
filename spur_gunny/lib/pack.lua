-- spur_gunny's helper for a weapon pack: `shared_script '@spur_gunny/lib/pack.lua'` in the pack's fxmanifest.
--
-- Gunny.register(fn): fn runs once spur_gunny is up, and again every time it starts (it forgets packs when it stops).
-- Put the pack's RegisterAmmo and RegisterWeapon calls in it, in a file both sides load. See spur_gunny's README,
-- "Weapon packs".
--
-- RedM (spur_gunny, 24 Nov 2026): whip_gunny -> spur_gunny; RegisterMagazine -> RegisterAmmo.

Gunny = Gunny or {}

local fns = {}

local function run(fn)
    local ok, err = pcall(fn)
    if not ok then print(('[%s] Gunny.register errored: %s'):format(GetCurrentResourceName(), tostring(err))) end
end

---@param fn function
function Gunny.register(fn)
    fns[#fns + 1] = fn
    if GetResourceState('spur_gunny') == 'started' then run(fn) end
end

AddEventHandler('spur_gunny:packs:ready', function()
    for _, fn in ipairs(fns) do run(fn) end
end)
