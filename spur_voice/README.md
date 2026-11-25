# spur_voice

Proximity voice for spur_core on RedM (Red Dead Redemption 2), on the Mumble voice built into RedM. You hear the
players near you. Press **Z** to whisper, talk or shout. The HUD mic lights blue while you talk. Other resources open
voice lines (a telephone call) through the same exports whip_voice has.

spur_voice is a port of whip_voice 1.0.0 to RedM, made with its author's permission on two conditions: no one makes
money from it, and it credits Whippy and WLVF. It isn't WHIP and doesn't come from WHIP's author. `NOTICE.md` lists what changed.

## On RedM

whip_voice ran its own voice server (LiveKit), which needs extra ports on the host and a download, and played voices
through a page in the game. spur_voice uses RedM's own voice instead, so there is nothing to set up but
`ensure spur_voice`.

- **Ranges.** Whisper 3 m, talk 8 m, shout 20 m (`Config.Ranges`). A voice fades out a little past its range.
- **Microphone.** Open mic or push to talk, the key and the microphone are each player's own RedM voice settings.
- **Voice lines.** Two or more players who hear each other wherever they are, at full volume. Lines open and close
  as whip_voice's do (`OpenLine`, `CloseLine` and the rest, below).
- **Not on Mumble.** Voices through walls and rooms, sound effects on a line (a telephone's tinny sound), a line on
  speaker for the people around, and the voice bot that played recordings in the world (lore characters' spoken
  lines, the Director's speakers). Those exports answer false and why. The radio, walkie-talkie and megaphone are
  left out for 1899.
- **The dead don't talk** (`Config.DeadCanTalk`).

When spur_voice starts it sets two of RedM's voice settings for every player, unless `server.cfg` already sets them:
`voice_use3dAudio` (voices come from where the speaker stands) and `voice_useSendingRangeOnly` (only players in range
get a voice). `Config.Convars = false` leaves them to `server.cfg`.

## Requirements

- `spur_core` (the RedM port of whip_core).

## Installation

Put `spur_voice` in your `resources` folder and add this line to `server.cfg`, after `ensure spur_core`:

```cfg
ensure spur_voice
```

Run only one voice resource: pma-voice and the like beside it are flagged in the setup report (`/spur`).

## For players

| To | Do |
| --- | --- |
| Talk | Talk (open mic) or hold your push-to-talk key, as your RedM voice settings say |
| Whisper, talk or shout | **Z** cycles them. The HUD's voice bar shows which. |

## Admin commands

| Command | Does |
| --- | --- |
| `/voicestatus` | Prints your voice in the F8 console: connected, your channel, your range, whether you're talking, RedM's voice settings, who hears you now and your lines. Needs developer mode on (`/w`). |

## For developers

Server side, through `exports.spur_voice`, or through spur_core's `Whip.voice('OpenLine', ...)`, which finds the voice
system that runs:

```lua
local lineId, why = exports.spur_voice:OpenLine({
    members = { callerSrc, calleeSrc },
    minMembers = 2,                           -- fewer and the line closes by itself (onEnd 'empty')
    sameWorld = false,                        -- true: only members in the same routing bucket hear each other
    onEnd = function(lineId, why) end,
    onLeave = function(lineId, src, why) end, -- 'left', 'logout', 'removed'
})
```

`CloseLine`, `AddLineMember`, `RemoveLineMember`, `SetLineMuted`, `GetLine`, `RegisterSound` and `IsVoiceReady` work
as in whip_voice. `SetLineSpeaker(lineId, src, true)` answers false: Mumble has no speaker. A recipe is checked for
its shape and kept, but a line sounds like the voice it carries. spur_core's voice system says so to other resources
(features: `lines` true; `speaker`, `pickup` and `quality` false; `sounds` 'basic').

## License

spur_voice is licensed under the GNU LGPL 3.0; see `COPYING.LESSER`, and `COPYING` for the GPL 3.0 it builds on.
`NOTICE.md` says what the licence doesn't cover and what this copy changed.
