-- ============================================
-- EDITOR HUD — the in-world editor overlay, for any tool
-- ============================================
--
-- The box in the top-right corner while an admin works in the world: what the mode is, what it has
-- so far, which keys do what. The zone and door editors each have one written for them alone; this
-- is the same box built from a table, so a new mode is a few lines rather than new markup, a new
-- script and a new stylesheet. It is drawn by html/js/editor-hud.js in the Door Editor's look.
--
--   EditorHud.show(state)       replace everything and show it
--   EditorHud.update(patch)     change some of it; a patch identical to the last is not re-sent
--   EditorHud.status(text, kind)   a line under the box for three seconds: 'ok', 'err', 'warn'
--   EditorHud.hide()
--   EditorHud.isShown()
--
-- state = {
--     title    = 'Space',                          -- upper-cased by the page
--     sub      = 'Mega A 3-1 · step 2 of 7',       -- one dim line under it
--     rows     = { { label = 'Corners', value = '2 / 2', tone = 'ok' }, { 'Area', '41.2 m²' } },
--     hints    = { { key = 'E', text = 'Add corner' }, { key = 'Enter', text = 'Apply', off = true } },
--     progress = { done = 37, total = 195 },     -- a bar, for tours
-- }
--
-- A row's tone is 'ok', 'warn' or 'err'. A hint with `off` is drawn dimmed: the key does nothing
-- right now, and leaving it in place keeps the list from jumping about.
--
-- The HUD shows nothing about focus or keys; the mode that shows it owns the keyboard, exactly as
-- the zone and door editors do. And whoever shows it hides it, on every way out.

EditorHud = {}

local _shown = false
local _lastPatch = nil

function EditorHud.show(state)
    _shown = true
    _lastPatch = nil
    SendNUIMessage({ action = 'ehShow', state = state or {} })
end

--- Cheap to call every frame: the same patch twice in a row is sent once.
function EditorHud.update(patch)
    if not _shown or type(patch) ~= 'table' then return end
    local encoded = json.encode(patch)
    if encoded == _lastPatch then return end
    _lastPatch = encoded
    SendNUIMessage({ action = 'ehUpdate', patch = patch })
end

---@param text string
---@param kind string|nil  'ok' | 'err' | 'warn'
function EditorHud.status(text, kind)
    if not _shown then return end
    SendNUIMessage({ action = 'ehStatus', text = text, kind = kind })
end

function EditorHud.hide()
    if not _shown then return end
    _shown = false
    _lastPatch = nil
    SendNUIMessage({ action = 'ehHide' })
end

function EditorHud.isShown()
    return _shown
end
