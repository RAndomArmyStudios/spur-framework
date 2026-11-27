-- ============================================
-- MOUSE SPEED PROBE — /mousedebug
-- ============================================
--
-- The skill check's dot can be fast for some players and slow for others. It reads GTA's
-- mouse look (1/2), which carries each player's own GTA sensitivity, and FiveM players set that
-- anywhere from -60 to 100 (profile_mouseOnFootScale). This measures one five-second sweep three ways,
-- so the fix is picked from numbers, not a guess:
--   look     GetDisabledControlNormal 1/2, what the skill check reads now (clamped to -1..1 a frame)
--   unbound  the same without the clamp
--   cursor   the Windows cursor (239/240), put back in the middle near the edges; GTA's sensitivity
--            does not touch it, if it moves at all with no menu open
-- Run it twice with very different GTA sensitivities. look / cursor is the multiplier the check
-- inherits, whatever the hand did. Ungated like /paddebug: it reads this client's own input, so any
-- player with the problem can run it and send the F8 lines.

local SECONDS = 5
local running = false

--- Profile setting ids, from docs.fivem.net/docs/game-references/profile-settings.
local PROFILE = { inputMethod = 750, lookSensitivity = 754, smoothing = 761 }

local function measure()
    -- pairLook: the unbound look on the frames the cursor was counted too, so the ratio compares like with like.
    local t = { lookX = 0, lookY = 0, freeX = 0, freeY = 0, curX = 0, curY = 0, pairLook = 0,
                frames = 0, clamped = 0, curMoved = 0, recentred = 0 }
    local lastX, lastY, skip = nil, nil, 2
    SetCursorLocation(0.5, 0.5)

    ControlBlocks.hold('mouseDebug', { all = true }, function()
        local lx, ly = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
        local ux, uy = GetDisabledControlUnboundNormal(0, 1), GetDisabledControlUnboundNormal(0, 2)
        t.lookX, t.lookY = t.lookX + math.abs(lx), t.lookY + math.abs(ly)
        t.freeX, t.freeY = t.freeX + math.abs(ux), t.freeY + math.abs(uy)
        if math.abs(ux) > 1 or math.abs(uy) > 1 then t.clamped = t.clamped + 1 end

        -- The cursor, as a position 0-1. Two frames are skipped after it is put back in the middle:
        -- the first may still read where it was, and that would count as a leap.
        local cx, cy = GetDisabledControlNormal(0, 239), GetDisabledControlNormal(0, 240)
        if skip > 0 then
            skip = skip - 1
        elseif lastX then
            local dx, dy = cx - lastX, cy - lastY
            if dx ~= 0 or dy ~= 0 then t.curMoved = t.curMoved + 1 end
            t.curX, t.curY = t.curX + math.abs(dx), t.curY + math.abs(dy)
            t.pairLook = t.pairLook + math.abs(ux) + math.abs(uy)
        end
        lastX, lastY = cx, cy
        if cx < 0.2 or cx > 0.8 or cy < 0.2 or cy > 0.8 then
            SetCursorLocation(0.5, 0.5)
            t.recentred = t.recentred + 1
            lastX, lastY, skip = nil, nil, 2
        end
        t.frames = t.frames + 1
    end)

    Wait(SECONDS * 1000)
    ControlBlocks.release('mouseDebug')
    return t
end

local function report(t)
    local p = function(...) print('[spur_core:mouse] ' .. string.format(...)) end
    p('%d s, %d frames (~%d fps)', SECONDS, t.frames, math.floor(t.frames / SECONDS + 0.5))
    p('Game settings: look sensitivity (754) = %s, smoothing (761) = %s, input method (750) = %s, profile_mouseOnFootScale = %s',
        tostring(GetProfileSetting(PROFILE.lookSensitivity)), tostring(GetProfileSetting(PROFILE.smoothing)),
        tostring(GetProfileSetting(PROFILE.inputMethod)), GetConvar('profile_mouseOnFootScale', 'n/a'))
    p('look     X %.3f  Y %.3f   (what the skill check reads now)', t.lookX, t.lookY)
    p('unbound  X %.3f  Y %.3f   (over 1 on %d frames: the check loses those)', t.freeX, t.freeY, t.clamped)
    if t.curMoved == 0 then
        p('cursor   never moved: with no menu open the cursor does not follow the mouse here')
    else
        p('cursor   X %.4f  Y %.4f   (moved on %d frames, put back %d times)', t.curX, t.curY, t.curMoved, t.recentred)
        local cur = t.curX + t.curY
        if cur > 0 then p('look / cursor = %.2f   <- compare this between runs', t.pairLook / cur) end
    end
end

DevCommand('mousedebug', function()
    if running then return end
    running = true
    CreateThread(function()
        UI.Notify(('Move the mouse left and right for %d seconds'):format(SECONDS), 'info', 3000)
        Wait(1000)
        local ok, t = pcall(measure)
        ControlBlocks.release('mouseDebug')
        if ok then
            report(t)
            UI.Notify('Mouse readings are in F8', 'success', 4000)
        else
            print('[spur_core:mouse] the probe failed: ' .. tostring(t))
        end
        running = false
    end)
end)
