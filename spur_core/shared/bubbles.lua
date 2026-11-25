-- ============================================
-- Bubble text — the one cleaning rule for /me
-- ============================================
-- The client uses it to warn before sending; the server uses it to decide what everyone sees.

BubbleText = {}

--- Cleans bubble text: colour codes (^1) and control characters out, whitespace collapsed to single
--- spaces, cut to `max` characters. Returns the text ('' when nothing is left) and whether it was cut.
---@param text any
---@param max number|nil
---@return string text, boolean cut
function BubbleText.clean(text, max)
    if type(text) ~= 'string' then return '', false end
    text = text:gsub('%^%d', '')
    text = text:gsub('[\0-\31\127]', ' ')
    if not utf8.len(text) then text = text:gsub('[\128-\255]', '') end   -- broken UTF-8: keep plain letters
    text = text:gsub('%s+', ' '):match('^%s*(.-)%s*$')

    local cut = false
    if max and utf8.len(text) > max then
        text = text:sub(1, utf8.offset(text, max + 1) - 1):gsub('%s+$', '')
        cut = true
    end
    return text, cut
end
