-- ============================================
-- INTERACT RENDERER — NUI
-- ============================================
--
-- The original way whip drew world prompts, extracted from client/interact.lua unchanged so it
-- can keep being the fallback. Lua projects each point to screen coordinates and posts them to
-- the browser, which moves a div.
--
-- ITS ONE FLAW IS STRUCTURAL AND CANNOT BE FIXED HERE. NUI is asynchronous: the browser renders
-- into a texture the game composites some frames later, so the marker on screen is always showing
-- where the point was two or more frames ago. It tracks perfectly and arrives late. Sending
-- positions more often, projecting in JS, using transform instead of left/top — none of it helps,
-- because the problem is the compositing, not the freshness of the input.
--
-- client/interact_world.lua is the answer to that. This file is what you switch back to if the
-- answer turns out to have a problem of its own.
--
-- Drawing aside, this owes its speed to two things worth keeping: positions are only SENT when
-- they actually moved on screen, and nothing is sent at all on a frame where nothing moved.
--
-- MULTI-CHOICE COSTS THIS FILE NOTHING, and that is by design rather than by luck. interact.lua
-- resolves `icon` and `label` on the entry to whichever option is SELECTED, so scrolling changes
-- what arrives here without this file knowing options exist at all. What it does not do is draw
-- the rest of the stack — the unselected circles are world-renderer only. That is the right trade
-- for a fallback: the player can still see and fire the selected option, which is the part that
-- matters, and the stack is a thing you look at rather than a thing you need.

local abs = math.abs

local R = {}

-- Screen position of each indicator as last SENT ([id] = {sx, sy}): a stationary player looking at
-- a stationary prompt costs no NUI traffic. The epsilon is under a pixel at 1080p (coords are 0..1).
local lastSentPos = {}
local layerOpen = false

function R.attach()
    lastSentPos = {}
    layerOpen = false
end

function R.detach()
    R.clear()
end

--- Everything off screen.
function R.clear()
    if layerOpen then
        SendNUIMessage({ action = 'interactHide' })
        layerOpen = false
    end
    lastSentPos = {}
end

--- Called every frame while anything is visible.
---
--- `changed` and `removed` are only present on a score frame; on every other frame this is a
--- reposition pass and nothing else, which is exactly what the old position-only branch was.
---@param visible table   [id] = entry
---@param changed table|nil  list of state changes
---@param removed table|nil  list of ids that left
function R.frame(visible, changed, removed)
    local positions = {}

    for id, e in pairs(visible) do
        local onScreen, sx, sy = World3dToScreen2d(e.x, e.y, e.z)
        if onScreen then
            local lp = lastSentPos[id]
            if not lp
                or abs(sx - lp[1]) > 0.0005
                or abs(sy - lp[2]) > 0.0005 then
                positions[#positions + 1] = id
                positions[#positions + 1] = sx
                positions[#positions + 1] = sy
                if lp then lp[1] = sx; lp[2] = sy
                else lastSentPos[id] = { sx, sy } end
            end
        end
    end

    -- Anything that left takes its remembered position with it, or an id reused later would be
    -- diffed against where a different prompt used to be and skip its first update.
    if removed then
        for i = 1, #removed do
            lastSentPos[removed[i]] = nil
        end
    end

    local hasChanged = changed and #changed > 0
    local hasRemoved = removed and #removed > 0

    if #positions > 0 or hasChanged or hasRemoved then
        layerOpen = true
        local msg = {
            action    = 'interactFrame',
            positions = positions,
        }
        if hasChanged then msg.state = changed end
        if hasRemoved then msg.removed = removed end
        SendNUIMessage(msg)
    end
end

-- Sign in. The registry is client/interact.lua's, which loads before this file.
InteractRenderers.nui = R
