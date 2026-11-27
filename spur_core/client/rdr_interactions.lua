-- ============================================
-- RDR2'S OWN INTERACTIONS, OFF — client/rdr_interactions.lua
-- ============================================
--
-- RedM (spur_core, 25 Nov 2026). New with the port: whip_core (by Whippy and WLVF) has no such file, because the original game has
-- no such thing. RDR2 lets a player lock on to anyone with the right mouse button (Greet, Antagonize, Rob), search
-- drawers and bodies, and pick up hats and whatever lies about, each with a prompt of its own at the bottom right.
-- On a whip server those are whip's to offer, on E (client/interact.lua), so RDR2's are switched off here.
-- Config.RdrInteractions (config.lua) keeps either.
--
-- Found by trying each in game:
--   * the lock-on: its control disabled every frame. SET_PLAYER_LOCKON(false) removes it too but takes gun aiming
--     with it.
--   * the prompts: NOT _UI_PROMPT_DISABLE_PROMPTS_THIS_FRAME (all of them). It hides everything, and blocks the
--     actions behind the prompts too: a player could no longer get on a horse. Instead, what the player may do is
--     switched off at its source: picking things up (hats too), and looting or searching (the player ped's looting
--     flags, femga's and Halen84's lists), with prompt type 5 (Pick Up on a carcass) hidden every frame. Never pass
--     a prompt type above 40: 41 and up crashed the game.
--   whip's prompts are NUI and its E a key mapping; neither is an RDR2 prompt, so both carry on.
--
-- And RDR2's idle cinematic camera, which client/idle_cam.lua cannot reach (Cfx.re's DisableIdleCamera is not in
-- RedM): the letterboxed pan after a while with no input. Off every frame while Config.IdleCam.Disable is not false.

local INPUT_INTERACT_LOCKON = 0xF8982F00

local function allowed(what)
    local c = Config.RdrInteractions
    return type(c) == 'table' and c[what] == true
end

local SET_LOOTING_FLAG = 0x6569F31A01B4C097
local LOOT_CAN_LONG_LOOT, LOOT_CAN_QUICK_LOOT, LOOT_NO_AMBIENT_PEDS = 2, 3, 18

--- The lasting switches, set again every second (a new ped starts with the game's own).
---@param on boolean  RDR2's own picking up and looting allowed
local function setLooting(on)
    local ped, player = PlayerPedId(), PlayerId()
    Citizen.InvokeNative(0xD1A70C1E8D1031FE, player, on)   -- _SET_PLAYER_CAN_PICKUP_ABILITY: every Pick Up
    Citizen.InvokeNative(0xACA45DDCEF6071C4, player, on)   -- _SET_PLAYER_CAN_PICKUP_HAT
    Citizen.InvokeNative(SET_LOOTING_FLAG, ped, LOOT_CAN_LONG_LOOT, on)
    Citizen.InvokeNative(SET_LOOTING_FLAG, ped, LOOT_CAN_QUICK_LOOT, on)
    Citizen.InvokeNative(SET_LOOTING_FLAG, ped, LOOT_NO_AMBIENT_PEDS, not on)
end

CreateThread(function()
    local was, wasCarrying = nil, false
    while true do
        local on = allowed('prompts')
        -- client/rdr_world.lua: while the player carries something, RDR2's own Drop and Stow are the way to put it
        -- down, so its pick-up switches are given back; and a search under way has the looting flags to itself.
        local carrying = RdrWorld and RdrWorld.carrying() or false
        if RdrWorld and RdrWorld.looting then
            -- (left alone)
        elseif carrying then
            setLooting(true)
        elseif not on or was == false or wasCarrying then
            setLooting(on)   -- off: kept off; back on: given back once
        end
        wasCarrying = carrying
        was = on
        Wait(1000)
    end
end)

local carryAskedAt, carryingNow = 0, false

CreateThread(function()
    while true do
        local lockOn, prompts = allowed('lockOn'), allowed('prompts')
        local idleCam = Config.IdleCam and Config.IdleCam.Disable == false
        local now = GetGameTimer()
        if now - carryAskedAt > 250 then
            carryAskedAt, carryingNow = now, (RdrWorld and RdrWorld.carrying() or false)
        end
        if lockOn and prompts and idleCam then
            Wait(1000)   -- nothing to switch off: ask again in a second (the settings can change)
        else
            if not lockOn then DisableControlAction(0, INPUT_INTERACT_LOCKON, true) end
            -- _UI_PROMPT_DISABLE_PROMPT_TYPE_THIS_FRAME; not while carrying (type 5 is Drop then)
            if not prompts and not carryingNow then Citizen.InvokeNative(0xFC094EF26DD153FA, 5) end
            if not idleCam then Citizen.InvokeNative(0x8910C24B7E0046EC) end      -- _DISABLE_CINEMATIC_MODE_THIS_FRAME
            Wait(0)
        end
    end
end)
