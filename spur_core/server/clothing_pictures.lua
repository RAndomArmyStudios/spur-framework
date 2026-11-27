-- ========================================
-- Clothing pictures — which apparel and accessories have one
-- ========================================
--
-- The character editor shows apparel and accessories only where there is a picture: the game's lists carry items
-- that do not exist, only their data, and those are the ones with none. Numbers are kept — a card's
-- number is the game's own — so a list runs 454, 455, 461 when 456 to 460 are not real. The editor
-- decides card by card (html/js/creator.js hasPicture); this side says which pictures there are.
--
-- The list is data/clothing-pictures.json HERE in spur_core (not beside the pictures, so the editor shows
-- only real items even when their media pack is not running; players never download it), written by
-- dev/clothing_pictures.js from the media packs' folders ("Rebuild clothing picture list.bat" in
-- whip_media_clothing_male): FXServer's Lua cannot list a folder, and a JavaScript file listing it here made FXServer
-- enter spur_core every server frame for good. It is read when spur_core starts and whenever a
-- media pack does (new pictures reach players at that restart, so that is when the list changes). A
-- player's game asks for its body's part once, the first time its editor opens.
--
-- No list, nothing hidden: without it, every card shows as it did before pictures.
--
-- RedM (spur_core, 23 Nov 2026): data/clothing-pictures.json is gone. It listed the original game's clothing, and the editor
-- would have hidden RDR2 outfit presets by whether the original game's item of the same number had a picture. Without it nothing
-- is hidden, and noList says nothing (there is no media pack to rebuild it from).

local RES = GetCurrentResourceName()
local LIST = 'data/clothing-pictures.json'

local pictures = nil   -- the list's `found`: { male = {...}, female = {...} }

local function noList(why)
    pictures = nil
    if RdrCompat then return end   -- RedM: no list is the normal case
    print(('[spur_core:clothing] WARNING: no clothing picture list (%s), so the character editor shows every'
        .. ' apparel and accessory item, pictured or not. Double-click "Rebuild clothing picture list.bat" in'
        .. ' whip_media_clothing_male, then restart spur_core.'):format(why))
end

local function readList()
    local raw = LoadResourceFile(RES, LIST)
    if not raw or raw == '' then return noList(('%s/%s is missing'):format(RES, LIST)) end
    local ok, list = pcall(json.decode, raw)
    if not ok or type(list) ~= 'table' or type(list.found) ~= 'table' then
        return noList(('%s/%s could not be read'):format(RES, LIST))
    end
    pictures = list.found
    print(('[spur_core:clothing] %d clothing pictures (list made %s): apparel and accessories without one are left'
        .. ' out of the character editor.'):format(tonumber(list.files) or 0, tostring(list.made or '?')))
end

AddEventHandler('onResourceStart', function(res)
    if res == RES or WhipAssets.isAsset(res) then readList() end
end)

--- The picture list for one body, for the editor: { components = { ['11'] = { base = '0-15,...' } },
--- props = { ... } }, or false when there is none. Before the player's character is loaded too: the
--- editor of a character just made can open first, and the list is the same for everyone.
SecureCallback('spur_core:appearance:clothingPictures', {
    requirePlayer = false,
    params = { { 'body', 'enum', { 'male', 'female' } } },
}, function(_, _, body)
    local mine = pictures and pictures[body]
    if type(mine) ~= 'table' then return false, 'No clothing pictures' end
    return mine
end)
