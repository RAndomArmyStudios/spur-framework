-- ============================================
-- WHAT A CALL COSTS — /nativecost
-- ============================================
--
-- Prices each call the controls loop's hooks (client/controls.lua) make, so a fix goes to the expensive one
-- instead of a guess.
--
-- HOW: every frame for FRAMES frames, each call runs a batch of times and the batch is timed. THE CLOCK IS
-- GetNetworkTimeAccurate: the client's Lua has no os library (os.clock is the server's only), GetGameTimer is read
-- once a frame, and this one is read fresh on every call (FiveM's docs suggest it for
-- benchmarking). It moves in whole milliseconds, so it is the SUM over many frames that is read: a batch starts
-- anywhere inside a millisecond, so the steps average out. A batch grows while it takes under 2 ms and halves over
-- 20 ms. The game stutters for a few seconds while it runs. Ungated like /mousedebug: it times this client's own
-- calls, nothing else.

local FRAMES = 60
local MAX_BATCH = 4000
local running = false

--- Draws GTA keeps a frame are limited, and a draw past the limit may be dropped on a cheaper path: kept well under it.
local MAX_DRAWS = 250

local function cases(dict, tex)
    local ped = PlayerPedId()
    local empty = function() end
    return {
        { name = 'nothing (the timing itself)', fn = empty },
        { name = 'pcall of an empty function', fn = function() pcall(empty) end },
        { name = 'GetGameTimer', fn = function() GetGameTimer() end },
        { name = 'PlayerPedId', fn = function() PlayerPedId() end },
        { name = 'DoesEntityExist', fn = function() DoesEntityExist(ped) end },
        { name = 'IsPauseMenuActive', fn = function() IsPauseMenuActive() end },
        { name = 'IsMinimapRendering', fn = function() IsMinimapRendering() end },
        { name = 'IsBigmapActive', fn = function() IsBigmapActive() end },
        { name = 'SetScriptGfxDrawOrder', fn = function() SetScriptGfxDrawOrder(4) end },
        -- A speck in the top-left corner: the call is what is priced, not the drawing.
        { name = 'DrawSprite (' .. dict .. ')', max = MAX_DRAWS,
          fn = function() DrawSprite(dict, tex, 0.0, 0.0, 0.0001, 0.0001, 0.0, 255, 255, 255, 255) end },
        { name = 'DisableControlAction', fn = function() DisableControlAction(0, 36, true) end },
        { name = 'IsDisabledControlJustPressed', fn = function() IsDisabledControlJustPressed(0, 200) end },
        { name = 'IsDisabledControlPressed', fn = function() IsDisabledControlPressed(0, 205) end },
        { name = 'HideHudComponentThisFrame', fn = function() HideHudComponentThisFrame(6) end },
        -- The black skin's once-a-second checks (hud_skin.lua buildLayers).
        { name = 'GetActiveScreenResolution', fn = function() GetActiveScreenResolution() end },
        { name = 'GetSafeZoneSize', fn = function() GetSafeZoneSize() end },
        { name = 'HasStreamedTextureDictLoaded', fn = function() HasStreamedTextureDictLoaded(dict) end },
    }
end

local function measure(clock)
    -- The black skin's own frame when it is loaded, as the hook draws it; whip's disc otherwise.
    local shape = ({ rounded = true, square = true, circle = true })[Config.MinimapMask] and Config.MinimapMask or 'rounded'
    local dict, tex = 'whipframe_' .. shape, 'frame'
    if not HasStreamedTextureDictLoaded(dict) then
        dict, tex = 'whiphud', 'disc'
        if not LoadTextureDict(dict, 3000) then return nil, 'whiphud.ytd did not load' end
    end

    local list = cases(dict, tex)
    for _, c in ipairs(list) do c.batch, c.sec, c.calls = 10, 0.0, 0 end
    for frame = 1, FRAMES do
        -- A different one first each frame, so none is always the one that pays for a cold start.
        for k = 0, #list - 1 do
            local c = list[(frame + k) % #list + 1]
            local fn, n = c.fn, c.batch
            local t0 = clock()
            for _ = 1, n do fn() end
            local dt = clock() - t0
            -- The network clock can be nudged by its sync: a batch it jumped in is not counted.
            if dt >= 0 and dt < 1 then c.sec, c.calls = c.sec + dt, c.calls + n end
            if dt < 0.002 and n < (c.max or MAX_BATCH) then
                c.batch = math.min(n * 2, c.max or MAX_BATCH)
            elseif dt > 0.02 and n > 1 then
                c.batch = n // 2
            end
        end
        Wait(0)
    end
    return list
end

local function report(list)
    local p = function(...) print('[spur_core:nativecost] ' .. string.format(...)) end
    local base = list[1].calls > 0 and list[1].sec / list[1].calls or 0
    table.sort(list, function(a, b) return a.sec / math.max(a.calls, 1) > b.sec / math.max(b.calls, 1) end)
    p('microseconds a call, over %d frames (the timing itself, %.3f us, taken off each):', FRAMES, base * 1e6)
    for _, c in ipairs(list) do
        local each = c.calls > 0 and (c.sec / c.calls - base) or 0
        p('%-44s %8.3f us   (%d calls)', c.name, math.max(each, 0) * 1e6, c.calls)
    end
    -- What the controls loop holds right now: each block's controls are one DisableControlAction a frame.
    for _, line in ipairs(ControlBlocks.describe()) do p('held: %s', line) end
end

DevCommand('nativecost', function()
    if running then return end
    local clock = function() return GetNetworkTimeAccurate() / 1000 end   -- seconds
    running = true
    CreateThread(function()
        UI.Notify('Timing calls: the game will stutter for a few seconds', 'info', 3000)
        local before = GetNetworkTimeAccurate()
        Wait(500)
        if GetNetworkTimeAccurate() - before < 100 then
            print('[spur_core:nativecost] the network clock is not moving (no session yet?): nothing to time with')
            running = false
            return
        end
        local ok, list, why = pcall(measure, clock)
        if ok and list then
            report(list)
            UI.Notify('Call costs are in F8', 'success', 4000)
        else
            print('[spur_core:nativecost] the probe failed: ' .. tostring(ok and why or list))
        end
        running = false
    end)
end)
