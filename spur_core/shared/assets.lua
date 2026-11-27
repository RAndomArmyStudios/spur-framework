-- ============================================
-- WHIP ASSETS — which media pack holds a picture, a video or a map file
-- ============================================
--
-- whip's pictures and videos are in media packs (whip_media_*) of at most 256 MB each, by category (Josh, 30 Oct
-- 2026): a player downloads each once, and again only when something in that one changes. Which holds what is
-- shared/assets_index.lua, made by dev/assets_index.mjs from the packs. Ask here, never name a pack:
--
--     WhipAssets.resourceFor('img/props/p_bench03x.webp')   -> 'whip_media_props'
--     WhipAssets.url('img/props/p_bench03x.webp')           -> 'https://cfx-nui-whip_media_props/img/props/...'
--
-- The NUI asks html/js/assets.js the same (whipAssetUrl). Shared: both sides ask.

--- The resource whose folder has `path` (inside it, as 'img/props/<model>.webp'), or nil when no area holds it.
--- An area split over several resources goes by the name: the last whose run of names starts at or before it.
---@param path string
---@return string|nil
function WhipAssets.resourceFor(path)
    local p = (tostring(path or ''):gsub('^/+', '')):lower()
    local found, foundLen = nil, -1
    for _, c in ipairs(WhipAssets.chunks) do
        local d = c.dir
        if #d >= foundLen and p:sub(1, #d + 1) == d .. '/' then
            if #d > foundLen then found, foundLen = nil, #d end
            if not c.from or p:sub(#d + 2) >= c.from then found = c.resource end
        end
    end
    return found
end

--- The URL a page loads `path` from, or nil when no area holds it.
---@param path string
---@return string|nil
function WhipAssets.url(path)
    local res = WhipAssets.resourceFor(path)
    if not res then return nil end
    return ('https://cfx-nui-%s/%s'):format(res, (tostring(path):gsub('^/+', '')))
end

--- Every media pack, in the index's order (the order of the areas they hold).
---@return string[]
function WhipAssets.resources()
    local out, seen = {}, {}
    for _, c in ipairs(WhipAssets.chunks) do
        if not seen[c.resource] then
            seen[c.resource] = true
            out[#out + 1] = c.resource
        end
    end
    return out
end

--- Is `name` one of them? (Its restart brings new pictures: whatever was read from it is read again.)
---@param name string
---@return boolean
function WhipAssets.isAsset(name)
    for _, c in ipairs(WhipAssets.chunks) do
        if c.resource == name then return true end
    end
    return false
end
