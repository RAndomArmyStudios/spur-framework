-- The Director table, made before every other Director file; each file adds what it owns.
--   active    the scenarios switched on: [key] = the built scenario
--   isolated  builders in a world of their own: [src] = their routing bucket

Director = { active = {}, isolated = {} }

-- Listeners for catalogue changes (card type, task step, skill game or weapon added or gone).
local catalogueHooks = {}

--- Hear every change to the catalogue (fn()).
function Director.onCatalogueChanged(fn) catalogueHooks[#catalogueHooks + 1] = fn end

--- The catalogue changed: told to every listener.
function Director.catalogueChanged()
    for _, fn in ipairs(catalogueHooks) do
        local ok, err = pcall(fn)
        if not ok then print('^1[spur_core:director] a catalogue listener failed: ' .. tostring(err) .. '^0') end
    end
end
