-- ============================================
-- THE CURTAIN — client/curtain.lua
-- ============================================
--
-- whip's own blackout, as opposed to the game's DoScreenFadeOut. Two things make it worth having
-- rather than just calling the native:
--
--   IT REPORTS BACK. Cover() does not return until the browser has confirmed the screen is
--   genuinely black. The game's fade gives you nothing to wait on, so hiding work behind it means
--   sleeping for a guessed duration — and a guess that is too short shows the player the
--   machinery. The character screen teleports people across the map, streams a corner of the
--   world and builds a ped behind this; none of that takes a predictable length of time.
--
--   IT IS OURS TO STYLE. The effect is a CSS transition in html/css/curtain.css. A different
--   look is a stylesheet edit, and nothing in Lua changes.
--
-- It knows nothing about any screen.
--
-- The two blackouts have to hand over cleanly (GiveToGame/TakeFromGame): the curtain is a NUI
-- element, so hiding the page takes it with it. Whenever the blackout has to outlive the browser
-- being hidden, one black is put up underneath the other BEFORE the first comes down.

Curtain = {}

-- Every cover carries a token and the browser hands it back once the screen is actually black.
-- An ack from an abandoned cover can then be told apart from the one being waited on, which is
-- what stops somebody clicking faster than a scene can be built from releasing the wrong wait.
--
-- ONE CURTAIN, SO ONE COUNTER. Two Cover() calls in flight at once means the second takes the
-- token and the first waits out its deadline and gives up — noisy, but it recovers, and it is
-- the honest behaviour: there is only one screen and they were both trying to own it. Callers
-- keep their own "am I already doing this" guards (CharSelect._switching, ._loading) so it does
-- not come up; this is what happens if one is ever missing, not a thing to design around.
local _token = 0
local _ack   = -1

-- How long past the transition itself we will wait for the browser to answer, and how often the
-- request is repeated while waiting. See the note on repeating in Cover.
local COVER_GRACE_MS = 5000
local COVER_RESEND_MS = 400

-- ---- The loading logo ------------------------------------------------------------------------
--
-- While the screen is black for a load, whip's logo shows in full at the bottom right, its I's
-- light running (html/js/curtain.js, NUI message `loadingLogo`). This file says when, because only
-- this file knows when a blackout starts and ends.
--
--   It follows the whole blackout, not the curtain element. The long loads — into the world, back
--   to the character screen, in and out of the creator — hand the black to the game's fade part way
--   (GiveToGame) and take it back at the end (TakeFromGame), with the curtain itself lifted in
--   between, and that stretch is exactly the loading. So the logo shows from the first Cover to
--   the Uncover that ends it. (NUI draws over the game's fade, so it stays on top the whole way.)
--
--   From the moment the curtain is called: the logo comes up as the black starts to fall (the
--   character screen's quick blinks between shots included).
--
--   It ends if the picture comes back some other way. Every flow here ends with Curtain.Uncover,
--   but a logo left on over a live picture would be a bug on screen: if neither the curtain nor
--   the game's fade is holding the black, the logo goes. Checked twice, LOADER_CHECK_MS apart, so an
--   instant handover between the two blackouts is never mistaken for it.
--
-- Only whip's curtain: the game's own fades (the death screen's, drama rather than loading) never show
-- the logo.
local LOADER_CHECK_MS = 500

local _blackout    = false   -- from the first Cover to the Uncover that ends it
local _blackGen    = 0       -- bumped at both ends: a timer or watcher from an earlier blackout stands down
local _curtainDown = false   -- the curtain element itself, as opposed to the game's fade, holding the black
local _logoOn      = false

local function screenIsBlack()
    return _curtainDown or IsScreenFadedOut()
end

local function endBlackout()
    if not _blackout then return end
    _blackout = false
    _blackGen = _blackGen + 1
    if _logoOn then
        _logoOn = false
        SendNUIMessage({ action = 'loadingLogo', on = false })
    end
end

local function beginBlackout()
    if _blackout then return end
    _blackout = true
    _blackGen = _blackGen + 1
    local gen = _blackGen

    _logoOn = true
    SendNUIMessage({ action = 'loadingLogo', on = true })

    -- The watch for a picture that comes back without Curtain.Uncover (see above).
    CreateThread(function()
        local open = 0
        while _logoOn and gen == _blackGen do
            Wait(LOADER_CHECK_MS)
            if gen ~= _blackGen then return end
            open = screenIsBlack() and 0 or open + 1
            if open >= 2 then
                print('[spur_core:curtain] the picture came back without Curtain.Uncover — loading logo off')
                endBlackout()
            end
        end
    end)
end

--- Cover the screen and WAIT until it is genuinely black.
---
--- Yields, so it must be called from a thread.
---
--- THE REQUEST IS REPEATED UNTIL IT IS ANSWERED, and that is not belt-and-braces — it is the fix
--- for a real failure. SendNUIMessage delivers to whatever is listening AT THAT MOMENT, and on a
--- fresh connect the page is often still loading when the character screen asks for its first
--- cover: nothing is listening, the message is simply dropped, and a single send would sit here
--- until the deadline and give up. Repeating means the request lands the instant the page is
--- ready. A repeat of a cover already running is ignored browser-side, so this cannot restart a
--- transition or report one finished early — see js/curtain.js.
---
--- The deadline exists only so a browser that never answers cannot strand somebody mid-journey.
--- It is a failsafe, not the normal path, it says so out loud when it fires, and — importantly —
--- callers must treat `false` as "the screen is NOT black" rather than pressing on regardless.
---@param ms number|nil  how long the curtain takes to fall; 0 for instant
---@return boolean covered  false only if the browser never answered
function Curtain.Cover(ms)
    ms = ms or 0
    _token = _token + 1
    local token = _token

    beginBlackout()
    _curtainDown = true
    SendNUIMessage({ action = 'curtainCover', ms = ms, token = token })

    local waited = 0
    local deadline = ms + COVER_GRACE_MS
    local nextResend = COVER_RESEND_MS

    while _ack ~= token and waited < deadline do
        Wait(16); waited = waited + 16
        if waited >= nextResend then
            nextResend = nextResend + COVER_RESEND_MS
            SendNUIMessage({ action = 'curtainCover', ms = ms, token = token })
        end
    end

    if _ack ~= token then
        print('[spur_core:curtain] the browser never reported the screen covered — continuing anyway')
        return false
    end
    return true
end

--- Send the browser away without touching the game's fade.
---
--- Private, because "lift the curtain" and "show the picture" are only the same thing when the
--- curtain is what is black. GiveToGame is the one case where it is not.
local function sendUncover(ms)
    _curtainDown = false
    SendNUIMessage({ action = 'curtainUncover', ms = ms or 0 })
end

--- Show the picture again, whatever happens to be hiding it.
---
--- Lifts the curtain AND clears the game's fade if that is still down. The second half is what
--- stops a failed handover becoming a permanently black screen: if Cover could not raise the
--- curtain, TakeFromGame will have left the game's fade in charge on purpose, and lifting a
--- curtain that was never lowered would do nothing at all. That was the fresh-connect hang —
--- black world with the character cards sitting on top of it, because NUI draws over the game's
--- fade and so the only thing that still worked was the part that was not black.
---
--- The rule this encodes: whoever is holding the blackout, this call ends it.
---@param ms number|nil
function Curtain.Uncover(ms)
    -- The blackout is over, whoever held it: the loading logo (if it came on) fades as the
    -- picture comes back.
    endBlackout()
    sendUncover(ms)
    if IsScreenFadedOut() then
        DoScreenFadeIn(ms or 0)
    end
end

--- Hand the blackout to the game's own fade, covering over `ms` on the way.
---
--- For the moment a screen is about to be hidden: the curtain falls where the player can see it,
--- the game's fade goes black INSTANTLY underneath while nothing is visible anyway, and only
--- then is the curtain lifted — invisibly, because there is already black behind it. Afterwards
--- the browser can be hidden freely and the screen stays black.
---
--- sendUncover rather than Uncover, deliberately: the game's fade is meant to be left holding
--- the black here, and the public Uncover would immediately clear it again.
---
--- Safe when the browser never answers — the fade below still goes black, just as a cut rather
--- than a transition. Black is black; there is nothing to strand.
---
--- THE CURTAIN IS NOT LIFTED UNTIL THE GAME'S FADE IS ON SCREEN. DoScreenFadeOut(0) is not black in
--- the frame it is called (the mirror of TakeFromGame's note below), and lifting the curtain in that
--- same frame put one frame of the picture between the two blackouts: the flash Josh saw at the end
--- of every fall to black (picking a character, the landing page going to the character screen).
--- So it waits for the fade to report black, and one frame more for that frame to be drawn. Bounded:
--- a fade that never reports lifts the curtain anyway, as before.
---
--- Yields.
---@param ms number|nil  how long the visible part of the transition takes
function Curtain.GiveToGame(ms)
    Curtain.Cover(ms)
    DoScreenFadeOut(0)
    local frames = 0
    while not IsScreenFadedOut() and frames < 10 do
        Wait(0); frames = frames + 1
    end
    Wait(0)
    sendUncover(0)
end

--- Take the blackout back from the game's fade, leaving the curtain holding it.
---
--- The mirror image: the curtain is put up instantly behind the game's fade — uncovering
--- nothing, because the fade is still black in front of it — and the fade is then cleared.
--- The screen never brightens. Follow with Curtain.Uncover(ms) to show the picture.
---
--- IF THE CURTAIN COULD NOT BE RAISED, THE FADE STAYS. Clearing it anyway is handing the
--- blackout from something that is holding it to something that is not, which puts a teleport,
--- a ped being built and a camera flying across the map on screen. Leaving the game's fade in
--- charge is worse-looking than intended and completely harmless, and Curtain.Uncover knows how
--- to end either kind of black — so the caller carries on as usual and the picture still comes
--- back at the right moment.
---
--- Yields.
--- IT DOES NOT RETURN UNTIL THE FADE HAS ACTUALLY GONE, and that is not tidiness. The game's
--- fade state does not update within the frame it is changed: IsScreenFadedOut still answers
--- "yes" immediately after DoScreenFadeIn(0). Curtain.Uncover uses exactly that test to decide
--- whether it also has to lift the game's fade, and every caller here runs the two back to back
--- — so the stale reading made Uncover start a SECOND fade-in underneath the curtain's own lift.
--- Two blackouts rising together is what the owner saw entering and leaving the creator: a
--- doubled transition instead of one motion.
---
--- Waiting costs nothing, because it happens with the curtain already black. The loop is bounded
--- so a fade that never clears cannot hang anybody — and if that happened, Uncover's fallback is
--- exactly the right thing to do anyway.
---@return boolean took  false if the game's fade is still the thing holding the screen black
function Curtain.TakeFromGame()
    if not Curtain.Cover(0) then return false end

    DoScreenFadeIn(0)
    local frames = 0
    while IsScreenFadedOut() and frames < 10 do
        Wait(0); frames = frames + 1
    end

    return true
end

--- The browser reporting that the screen is black.
RegisterNUICallback('curtainCovered', function(data, cb)
    _ack = tonumber(data and data.token) or -1
    cb({ ok = true })
end)

-- A resource restart leaves the browser's state behind with the old page, but a curtain stuck
-- down would not be: the NUI is rebuilt uncovered, so there is nothing to clean up here. What
-- DOES need saying is that a stop mid-cover leaves a Lua wait that never completes — harmless,
-- since the whole Lua state goes with it.
