-- World voices and the radio: what spur_core's Director asks of a voice system that has a voice bot.
--
-- RedM (spur_voice, 24 Nov 2026): whip_voice's voice bot played recordings from a place in the world (a lore
-- character's lines, the Director's speakers), and its radio carried frequencies. Mumble has no voice bot, and 1899 has
-- no radio. These exports answer false and why, as whip_voice answers when its voice bot is not set up, so spur_core
-- says it once in the console and goes on (a lore line's subtitle still shows).

local NO_BOT = 'spur_voice (Mumble) has no voice bot: recordings in the world need whip_voice'

exports('CreateWorldVoice', function() return false, NO_BOT end)
exports('PlayWorldVoice', function() return false, NO_BOT end)
exports('StopWorldVoice', function() return true end)     -- nothing playing: nothing to stop
exports('RemoveWorldVoice', function() return true end)   -- nothing made: nothing to remove
exports('SetWorldVoiceRange', function() return false, NO_BOT end)
exports('SetWorldVoiceSound', function() return false, NO_BOT end)
exports('SetWorldVoiceMegaphone', function() return false, NO_BOT end)
exports('SetWorldVoiceRadio', function() return false, 'there is no radio in 1899' end)
exports('GetPlayerRadio', function() return false end)   -- nobody is on a frequency
