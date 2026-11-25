-- ============================================
-- Copy Outfit for Menyoo — your clothes, face and tattoos as one line on the clipboard
-- ============================================
--
-- For story mode (Josh, 22 Oct 2026): pasted to the session that turns it into a Menyoo outfit
-- (menyooStuff\Outfit\*.xml). This only dumps what is on the character; the converting is done there.
-- One line of JSON, no newlines (it is pasted into a terminal), tagged "whipOutfit".
--
-- WHAT COMES FROM WHERE
--   clothes and props  the ped as it stands: what you see. Each with its global number AND, the part that
--                      matters, its COLLECTION name and LOCAL index (build 2699+): a global number is a
--                      different item on another build or with other add-on clothes; a collection and local
--                      index are not
--   the face           the saved appearance: the head blend, all 20 sliders, eye colour, hair colour and
--                      highlight, and the 11 overlays whip keeps. That is exactly what whip put on the ped
--                      (ApplyAppearance). The ped's own getters read GTA's memory at fixed places and are
--                      not exact (Dazza Doolan, 4 Nov: the last two sliders came back 0 and 0 instead of
--                      -0.17 and -1), so they are only asked for a ped with no saved look, and for overlays
--                      11 and 12 (body blemishes), which whip never sets. Whip blends one set of parents for
--                      shape and skin
--   tattoos            the saved appearance: GTA cannot list the decorations on a ped by name. The hair fade
--                      is a decoration too, so it comes first in the same list (a head tattoo draws over it)
--
-- /w Copy Outfit for Menyoo, or /copyoutfit (developer mode). If the clipboard refuses, the line comes up in
-- a box to copy by hand (/copyoutfit show opens that box straight away).

local FREEMODE = { [GetHashKey('mp_male')] = 'mp_male', [GetHashKey('mp_female')] = 'mp_female' }

-- The overlays whip's appearance keeps, by GTA's overlay number (client/appearance.lua OVERLAY_IDS).
local SAVED_OVERLAY = { [0] = 'blemishes', 'beard', 'eyebrows', 'ageing', 'makeup', 'blush', 'complexion', 'sunDamage',
    'lipstick', 'moles', 'chestHair' }

--- A native's answer, or nil when this build has no such native or it fails.
local function ask(native, ...)
    if type(native) ~= 'function' then return nil end
    local ok, a, b, c, d, e, f = pcall(native, ...)
    if not ok then return nil end
    return a, b, c, d, e, f
end

local function round(n, places)
    local m = 10 ^ (places or 3)
    return math.floor((tonumber(n) or 0) * m + 0.5) / m
end

--- The whole outfit, as the table that becomes the line.
local function outfitOf(ped)
    local saved = PlayerData and PlayerData.metadata and PlayerData.metadata.appearance or {}
    local hash = GetEntityModel(ped)
    local out = {
        whipOutfit = 1,
        build = GetGameBuildNumber(),
        model = FREEMODE[hash] or saved.model or tostring(hash),
        modelHash = hash,
        comps = {}, props = {},
    }

    for c = 0, 11 do
        out.comps[#out.comps + 1] = {
            c = c,
            d = GetPedDrawableVariation(ped, c),
            t = GetPedTextureVariation(ped, c),
            col = ask(GetPedDrawableVariationCollectionName, ped, c),
            loc = ask(GetPedDrawableVariationCollectionLocalIndex, ped, c),
        }
    end
    for a = 0, 9 do
        local d = GetPedPropIndex(ped, a)
        if d and d ~= -1 then
            out.props[#out.props + 1] = {
                a = a, d = d, t = GetPedPropTextureIndex(ped, a),
                col = ask(GetPedPropCollectionName, ped, a),
                loc = ask(GetPedPropCollectionLocalIndex, ped, a),
            }
        end
    end

    -- One set of parents for shape and skin, as whip blends them (ApplyAppearance).
    local hb = saved.headBlend or {}
    out.blend = {
        s1 = hb.mom or 0, s2 = hb.dad or 0, s3 = hb.grandparent or 0,
        k1 = hb.mom or 0, k2 = hb.dad or 0, k3 = hb.grandparent or 0,
        sm = round(hb.faceWeight or 0.5), km = round(hb.skinWeight or 0.5), tm = round(hb.thirdWeight or 0.0),
    }

    local savedFace = type(saved.faceFeatures) == 'table' and #saved.faceFeatures == 20 and saved.faceFeatures
    out.face = {}
    for i = 0, 19 do
        local v = savedFace and tonumber(savedFace[i + 1]) or nil
        if v == nil then v = ask(GetPedFaceFeature, ped, i) or 0.0 end
        out.face[#out.face + 1] = round(v)
    end

    out.overlays = {}
    for i = 0, 12 do
        local name = SAVED_OVERLAY[i]
        local ov = name and saved.overlays and saved.overlays[name]
        local e
        if ov then
            local off = (ov.type or 0) == 0 and (ov.opacity or 0.0) == 0.0
            e = { i = off and 255 or (ov.type or 0), o = round(ov.opacity or 0.0), c1 = ov.color or 0, c2 = ov.color2 or 0 }
        else
            local okData, value, _, c1, c2, opacity = ask(GetPedHeadOverlayData, ped, i)
            e = { i = (okData and value) or 255, o = round(opacity or 0.0), c1 = c1 or 0, c2 = c2 or 0 }
        end
        e.n = i
        out.overlays[#out.overlays + 1] = e
    end

    local hair = type(saved.hair) == 'table' and saved.hair or {}
    out.hair = { hair.color or ask(GetPedHairColor, ped) or 0, hair.highlight or ask(GetPedHairHighlightColor, ped) or 0 }
    out.eye = saved.eyeColor or ask(GetPedEyeColor, ped) or 0

    out.tattoos = {}
    local fade = saved.hairFade
    if type(fade) == 'table' and fade.collection and fade.overlay then
        out.tattoos[1] = { col = fade.collection, name = fade.overlay }
    end
    for _, t in ipairs(saved.tattoos or {}) do
        if type(t) == 'table' then out.tattoos[#out.tattoos + 1] = { col = t.collection, name = t.overlay } end
    end
    return out
end

--- The line, for the clipboard.
local function outfitLine()
    return json.encode(outfitOf(PlayerPedId()))
end

--- The box to copy it from by hand.
local function showBox(line)
    CreateThread(function()
        UI.Input('Copy this line (Ctrl+A, Ctrl+C)', { { label = 'Outfit for Menyoo', type = 'text', default = line } })
    end)
end

local function copyOutfit()
    local line = outfitLine()
    CopyToClipboard(line, function(ok)
        if ok then UI.Notify('Outfit copied', 'success') else showBox(line) end
    end)
end

--- A one-off: copies and is done (never stays lit).
ToolHandlers['Copy Outfit for Menyoo'] = {
    enter = copyOutfit,
    exit = function() end,
    isActive = function() return false end,
}

RegisterCommand('copyoutfit', function(_, args)
    if not DevToolsOn() then
        UI.Notify('Copy Outfit for Menyoo is a developer tool: turn developer mode on in /w', 'error')
        return
    end
    if args[1] == 'show' then showBox(outfitLine()) else copyOutfit() end
end, false)
