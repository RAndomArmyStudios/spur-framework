-- Developer-mode commands: run only while developer mode is on (/w); anyone else is told so. The client twin of
-- server/commands.lua's devCommand; the server re-checks anything it does behind one.
-- Satellites can't register a command through spur_core (it would outlive them), so they ask HasDevTools() in their own handler.

--- Register a client command that works only with developer mode on.
---@param name string
---@param fn fun(source: number, args: table, raw: string)
function DevCommand(name, fn)
    RegisterCommand(name, function(source, args, raw)
        if not (DevToolsOn and DevToolsOn()) then
            UI.Notify('/' .. name .. ' is a developer tool: turn developer mode on in /w', 'error')
            return
        end
        return fn(source, args, raw)
    end, false)
end

--- For satellites: is developer mode on for this player? Only for what a client tool shows; the server's HasDevTools(source) is authoritative.
exports('HasDevTools', function()
    return (DevToolsOn and DevToolsOn()) == true
end)

-- /spurerrors [resource]: this game's error log, grouped by resource, in F8 (the server console's is spurerrors there).
DevCommand('spurerrors', function(_, args)
    local only = args[1]
    local logged = ErrorTap.read({ max = 200 })
    local by, order = {}, {}
    for _, e in ipairs(logged and logged.entries or {}) do
        local res = tostring(e.resource or '?')
        if not only or res == only then
            if not by[res] then by[res] = {}; order[#order + 1] = res end
            table.insert(by[res], e)
        end
    end
    if #order == 0 then print(only and ('[spur] no errors from %s in this game'):format(only) or '[spur] no errors in this game') return end
    table.sort(order, function(a, b) return #by[a] > #by[b] end)
    for _, res in ipairs(order) do
        local list = by[res]
        print(('[spur] ^1%s^0: %d'):format(res, #list))
        for i = math.max(1, #list - 4), #list do
            local text = tostring(list[i].text):gsub('\n.*', '')
            print('[spur]     ' .. text:sub(1, 300))
        end
    end
    UI.Notify('Errors printed in F8', 'info')
end)
