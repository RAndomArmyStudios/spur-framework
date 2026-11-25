-- ============================================
-- CLOCK — the server's time, for games that play something in step
-- ============================================
--
-- A prop's tasks play on every player's game at once (each game makes its own copy), and so does a
-- recorded take on the game that drives it: from a start the server names in ITS milliseconds
-- (GetGameTimer). Each game asks this a few times (client/clock.lua) and keeps the answer with the
-- shortest round trip, so it can tell the server's time to within half of that trip.

-- (No player session needed: the time is no secret, and a game asks as it loads, before its session may be there.
-- Refused then, it read its own time as the server's for five minutes, and a take played minutes off on it.)
SecureCallback('spur_core:clock:now', {
    rateLimit = 50, burst = 12, whileDead = true, requirePlayer = false,
}, function()
    return GetGameTimer()
end)
