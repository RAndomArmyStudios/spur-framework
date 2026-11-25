# spur_chat

Chat for [spur_core](../spur_core) on RedM, ported from whip_chat by Whippy. It stands in for FXServer's stock `chat`
resource: its events, exports, modes, templates and `^1` colour codes work the same, so resources written for stock
chat work with it. Non-commercial and credited: Whippy allowed the port on the condition that no one makes money from it and that it
credits Whippy and WLVF.

## Features

- **Local chat.** A message reaches the players near the speaker, under their character's name. `/global` reaches
  everyone.
- **Typing in the HUD.** **T** turns spur_core's player capsule into the text field, with command suggestions as you
  type. You can still look around while you type.
- **Controller support.** With a controller, **Chat** on the F1 wheel opens spur_core's on-screen keyboard.
- **Your choice of visibility.** Messages fade away, stay on screen or stay hidden. Each player picks, and the choice
  is saved.
- **Spam limits.** A message is at most 256 characters, and the server limits how fast a player can send them.

## Requirements

- RedM FXServer with `spur_core`.
- No other chat resource. If another chat runs beside it, spur_chat says so in the server console, with the fix.

## Installation

Put `spur_chat` in your `resources` folder and add this line to `server.cfg`, after `ensure spur_core`:

```cfg
ensure spur_chat
```

Then remove `ensure chat`. If stock chat still starts, add `stop chat` after `ensure spur_chat`. With two chats
running, every message shows twice and typing can get stuck.

## For players

| Key or command | Does |
| --- | --- |
| **T** | Open chat. Start with `/` for a command; **Tab** and the arrow keys pick a suggestion. |
| **/** | Open chat with `/` already typed, for a command |
| **Page Up** / **Page Down** | Scroll the messages while typing |
| **F6** | Switch between messages that fade away, stay on screen, or stay hidden |
| `/global <message>` | Send a message to every player on the server, under your character's name. It needs a character: it doesn't work from the character screen. |
| `/clearchat` | Clear your own chat. Nobody else's changes. |
| `/resetchat` | Get the keyboard back if chat seems stuck |

Players can rebind **T**, **/** and **F6** in the game's key binding settings. The visibility choice is also in the
pause menu, under **Server Settings > Chat & voice**.

Admins can send a server notice to everyone with `/say <message>`, from the server console or in game with developer
mode on (`/w`).

## Configuration

spur_chat has no `config.lua`.

| Setting | Where | Does |
| --- | --- | --- |
| `Config.NetworkRange` | spur_core's `config.lua` | How far a message reaches, 424 m by default |
| `set chat_showJoins 0` | `server.cfg` | Hides the "joined" lines |
| `set chat_showQuits 0` | `server.cfg` | Hides the "left" lines |

## For developers

spur_chat answers stock chat's API:

| Side | Events and exports |
| --- | --- |
| Client events | `chat:addMessage`, `chat:addSuggestion`, `chat:addSuggestions`, `chat:removeSuggestion`, `chat:addTemplate`, `chat:addMode`, `chat:removeMode`, `chat:clear`, `chatMessage` |
| Client exports | `addMessage`, `addSuggestion`, `SetChatScale` (the chat's size relative to spur_core's other panels) |
| Server exports | `addMessage`, `registerMessageHook`, `registerMode`, `routeMessage` |
| Server event | `chatMessage`: cancel it to stop a message |

A resource that triggers these events needs no change. spur_chat says `provide 'chat'` in its `fxmanifest.lua`, so one
that has `dependency 'chat'` starts with it. Stock chat's exports (`addMessage` and `addSuggestion` on the client;
`addMessage`, `registerMessageHook` and `registerMode` on the server) also answer as `exports.chat:<name>(...)`
(`shared/stock_exports.lua`: `provide` alone does not carry exports), so those calls need no change either.

## License

spur_chat is licensed under the GNU LGPL 3.0; see `COPYING.LESSER`, and `COPYING` for the GPL 3.0 it builds on.
`NOTICE.md` is whip_chat's notice with what this copy changed; it says what the licence doesn't cover, including the
Barlow font (SIL Open Font License 1.1).
