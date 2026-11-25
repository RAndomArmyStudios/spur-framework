Config = {}

-- How far each voice level carries, in metres, by the name spur_core gives it (Z cycles them on the HUD).
Config.Ranges = {
    Whisper = 3.0,
    Normal  = 8.0,
    Shout   = 20.0,
}

-- A player is talked to this far past the range, so a voice fades out at its edge instead of cutting off there.
Config.Margin = 2.0

-- How often (ms) who is near is read again.
Config.RefreshMs = 250

-- Can the dead talk? Off: a dead player's voice goes nowhere until they are revived.
Config.DeadCanTalk = false

-- How loud a line's other members are (0.0-1.0): a call is heard at this volume wherever they are.
Config.LineVolume = 1.0

-- RedM's voice settings, set for every player when spur_voice starts. A setting already set in server.cfg (setr) is
-- left as it is there. false leaves them all to server.cfg.
--   voice_use3dAudio            voices come from where the speaker stands
--   voice_useSendingRangeOnly   only players inside the talker's range get the talker's audio
Config.Convars = {
    voice_use3dAudio = 'true',
    voice_useSendingRangeOnly = 'true',
}

-- Say in the server console who joins voice and what lines open and close.
Config.Debug = false
