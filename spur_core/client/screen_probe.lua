-- ============================================
-- Screen probe: what whip's screens show, and pressing them by their words
-- ============================================
-- For tests and tools (whip_devlink, whip_test). ReadScreen answers the words and the controls on spur_core's page
-- right now, and on every other resource's page that loads js/page-tools.js (the phone, Whiplash, the dealership:
-- `pages`, by resource); PressScreen presses one the way a mouse would, so the page's own handlers run (`page` names
-- another resource's). The page half is html/js/page-tools.js; another resource's asks go through its
-- lib/satellite.lua. Developer mode only: pressing a player's screen from code is a tool, never a feature.

local TIMEOUT_MS = 4000
local PAGES_MS = 400      -- for the other pages to answer a read: those that have not by then have nothing for it

local waiting = {}   -- [token] = promise
local seq = 0

local function ask(kind, opts)
    if not DevToolsOn() then return false, 'developer mode is off' end
    seq = seq + 1
    local token = 'sp' .. seq
    local p = promise.new()
    waiting[token] = p
    SendNUIMessage({ action = 'screenProbe', kind = kind, token = token, opts = opts })
    SetTimeout(TIMEOUT_MS, function()
        if waiting[token] then
            waiting[token] = nil
            p:resolve({ ok = false, err = 'the page did not answer' })
        end
    end)
    local r = Citizen.Await(p)
    if not r.ok then return false, r.err or 'refused' end
    return r.result
end

RegisterNUICallback('screenProbe', function(data, cb)
    cb('ok')
    local p = type(data) == 'table' and waiting[data.token]
    if p then
        waiting[data.token] = nil
        p:resolve(data)
    end
end)

-- ---- Other resources' pages ----
local pageAnswers = {}   -- [token] = { [resource] = { ok, result, err } }

AddEventHandler('spur_core:probe:answer', function(res, token, ok, result, err)
    local into = type(token) == 'string' and pageAnswers[token]
    if into and type(res) == 'string' then into[res] = { ok = ok == true, result = result, err = err } end
end)

--- Ask every other page (or one: `page`), and wait `ms` for their answers. Answers [resource] = { ok, result, err }.
local function askPages(kind, opts, page, ms)
    seq = seq + 1
    local token = 'pp' .. seq
    local got = {}
    pageAnswers[token] = got
    TriggerEvent('spur_core:probe:ask', token, kind, opts, page)
    local by = GetGameTimer() + ms
    while GetGameTimer() < by and not (page and got[page]) do Wait(0) end
    pageAnswers[token] = nil
    return got
end

exports('ReadScreen', function(opts)
    opts = type(opts) == 'table' and opts or {}
    local mine, why = ask('read', opts)
    if not mine then return false, why end
    if opts.pages ~= false then
        local pages = {}
        for res, a in pairs(askPages('read', opts, nil, PAGES_MS)) do
            local r = a.ok and type(a.result) == 'table' and a.result or nil
            if r and ((r.text and #r.text > 0) or (r.controls and #r.controls > 0)) then pages[res] = r end
        end
        if next(pages) then mine.pages = pages end
    end
    return mine
end)

exports('PressScreen', function(target, opts)
    if type(target) == 'number' then target = { id = target }
    elseif type(target) == 'string' then target = { label = target } end
    if type(target) ~= 'table' then return false, 'target: an id from ReadScreen, a label, or { label, near, kind, index, page }' end
    opts = type(opts) == 'table' and opts or {}
    local o = {
        target = { id = tonumber(target.id), label = target.label, near = target.near, kind = target.kind, index = tonumber(target.index) },
        button = opts.button, text = opts.text, enter = opts.enter == true, choose = opts.choose,
    }
    if type(target.page) == 'string' and target.page ~= GetCurrentResourceName() then
        if not DevToolsOn() then return false, 'developer mode is off' end
        local a = askPages('press', o, target.page, TIMEOUT_MS)[target.page]
        if not a then return false, ('%s\'s page did not answer (does it load js/page-tools.js?)'):format(target.page) end
        if not a.ok then return false, a.err or 'refused' end
        return a.result
    end
    return ask('press', o)
end)
