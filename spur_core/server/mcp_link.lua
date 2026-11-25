-- ============================================
-- MCP link: the server console's switch for it (the link itself is client/mcp_link.lua)
-- ============================================
-- RedM (spur_core, 24 Nov 2026): new. Lets whoever runs the server turn a developer's MCP link on from the console
-- (the RocketNode panel), so it can be switched on without anyone at that game's keyboard. It only tells that
-- player's own game to start asking the MCP server on that PC (127.0.0.1); nothing here listens.
--
--   spur_mcplink <server id | all> on [port]   only players who hold whip.devtools
--   spur_mcplink <server id | all> off

RegisterCommand('spur_mcplink', function(source, args)
    if source ~= 0 then return end   -- the console only
    local who, what, port = args[1], args[2], tonumber(args[3])
    if not who or (what ~= 'on' and what ~= 'off') then
        print('usage: spur_mcplink <server id|all> on [port] | off')
        return
    end
    local targets = {}
    if who == 'all' then
        for _, id in ipairs(GetPlayers()) do targets[#targets + 1] = tonumber(id) end
    else
        targets[1] = tonumber(who)
    end
    local n = 0
    for _, id in ipairs(targets) do
        if id and GetPlayerName(id) and (what == 'off' or DevTools.isEligible(id)) then
            TriggerClientEvent('spur_core:client:mcpLink', id, what == 'on', port)
            n = n + 1
        end
    end
    print(('[spur_core:mcp] MCP link %s sent to %d player(s)%s'):format(what:upper(), n,
        what == 'on' and ' (only those with dev tools)' or ''))
end, true)
