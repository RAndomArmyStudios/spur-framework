# The MCP link: let an AI client test your game

`spur_mcp.mjs` is an MCP server that lets an AI client (Claude Code, or any client that speaks MCP) drive a
spur_core game running on the same PC. It reads the screen, presses spur_core's buttons, runs commands and Lua,
takes screenshots and reads the error log. It never moves your mouse, types on your keyboard or takes the focus, so
the game can sit behind your other windows (not minimized) while it works.

It is a developer tool. A server runs fine without it, and players never need it.

RedM (spur_core, 24 Nov 2026): new. It drives the screen probe, screenshot and error log that Whippy and WLVF made
for whip_devlink, WHIP's "AI link". Non-commercial, LGPL-3.0, like the rest of spur_core.

## What you need

- Windows, with RedM installed. (`game_launch` and the default `game_screenshot` are Windows only. The other tools
  work wherever the game and the MCP server share a PC.)
- [Node.js](https://nodejs.org) 18 or newer. There is nothing to `npm install`.
- A server running spur_core, where your account holds the `whip.devtools` ACE
  (`add_ace group.admin whip.devtools allow` and you in `group.admin`).
- An MCP client.

## Set it up

There are two halves: the MCP server on your PC, and a switch in the game. Both are needed.

### 1. Register the MCP server with your client

**Claude Code**, in a terminal. Put your own path and your server's address in:

```
claude mcp add --scope user spur-game --env SPUR_MCP_CONNECT=<ip:port> -- node "<path to>\spur_core\dev\mcp\spur_mcp.mjs"
```

Use `--scope user`, not project scope. User scope keeps your server's address in your own settings and out of any
repository.

**Any other MCP client** that takes a JSON config:

```json
{
  "mcpServers": {
    "spur-game": {
      "command": "node",
      "args": ["<path to>/spur_core/dev/mcp/spur_mcp.mjs"],
      "env": { "SPUR_MCP_CONNECT": "<ip:port>" }
    }
  }
}
```

Restart the client. It should now list twelve tools whose names start with `game_`.

### 2. Turn the link on in the game

The game's side does nothing until a developer turns it on. Do this once per PC; it stays on after that.

- In the game, press F8 and type `mcplink on`.
- Or, from the server console: `spur_mcplink <server id> on` (or `all` instead of an id). It only reaches players
  who hold `whip.devtools`.

`mcplink off` turns it off again. `mcplink` on its own says which it is.

### 3. Check it

Ask the client to call `game_status`. With the game running it answers `linked: true`, with your server id and
coordinates. Reading and pressing the screen, commands and Lua also need developer mode: the client can switch it on
with `game_dev_mode`, the same switch as `/w`.

## The tools

| Tool | What it does |
| --- | --- |
| `game_launch` | Closes RedM if it's running, starts it and connects to `SPUR_MCP_CONNECT`. Loading takes about 3 minutes |
| `game_quit` | Closes RedM |
| `game_status` | The link, server id, coords, health, developer mode, whether a character is loaded. Never the player's name |
| `game_dev_mode` | Developer mode on or off |
| `game_read_screen` | The words and controls spur_core's interface shows, each control with an id |
| `game_press` | Presses a control by `id` or by its `label`. `text` with an `id` types into that field |
| `game_wait_for_text` | Waits until the interface shows some words (up to 600 s). Works straight after `game_launch` |
| `game_command` | Runs a command as if typed in F8 |
| `game_lua` | Runs Lua in spur_core's client, with 30 s to finish |
| `game_screenshot` | The game's picture as a JPEG, also saved to a file |
| `game_errors` | Errors spur_core caught: its page's JavaScript and its client Lua |
| `game_log` | The end of RedM's client log, with licences masked and lines that name players left out |

## Settings

Environment variables, set where you registered the server:

| Variable | Default | What it is |
| --- | --- | --- |
| `SPUR_MCP_CONNECT` | none | Your server's `ip:port`, for `game_launch` |
| `SPUR_MCP_PORT` | `47130` | The local port the game talks to. If you change it, use `mcplink on <port>` to match |
| `SPUR_REDM_EXE` | `%LOCALAPPDATA%\RedM\RedM.exe` | Where RedM is |
| `SPUR_REDM_LOGS` | `%LOCALAPPDATA%\RedM\RedM.app\logs` | Where RedM's logs are |
| `SPUR_MCP_SHOTS` | `<temp>\spur_mcp` | Where screenshots are saved |
| `SPUR_MCP_ORIGINS` | none | More page origins to answer, comma separated |

## Safety

- **It is as powerful as F8.** `game_lua` and `game_command` run whatever the AI client sends, as you, on whatever
  server the game is connected to. Use it on your own test server, with a client you trust.
- **It only listens on this PC.** The HTTP side is `127.0.0.1` only, and orders come only from the MCP client on
  stdin. Nothing that reaches the HTTP port can give the game an order.
- **It only answers the game.** RedM's pages send `Origin: null`, so the server answers spur_core's origin, or `null`
  from a browser whose user agent says `CitizenFX/`. Another resource's page in the same game could pose as
  spur_core while the server runs; the most it can do is take a job or answer one wrongly.
- **Screenshots show the whole game window**, chat and player names included. Look before you share one.
- **Keep your server's address out of the repository.** That is what `--scope user` is for.

## Things that trip people up

- **`linked: false`.** The game isn't running or is still loading (about 3 minutes after `game_launch`), the link
  is off (`mcplink on`), or the ports don't match.
- **Never reconnect from inside the game.** RedM crashes. Use `game_quit`, restart the server, then `game_launch`.
- **"Press any button to continue"** has no control to press. Use `game_lua` with `Landing.Continue()`.
- **Screenshots come from Windows.** RedM hands its pages no game picture, so `game_screenshot` reads the window
  with PrintWindow. The window can be behind others, but not minimized. `source: 'page'` is the in-game way and works on FiveM only.
- **World prompts are hidden while Dev Tools (`w`) is open.** Close it before walking up to a shop counter or a door.
- **A world prompt can't be pressed with `game_press`.** Call it instead: `Interactions.getAll()[id]` gives each
  prompt, and its `callback` or `options[1].callback` does what E does.
- **The mouse and held keys can't be faked.** Anything that needs a real mouse wheel, a held key or a second player
  is listed under "Not yet tried in game" in [CONVERSION.md](../../CONVERSION.md).

Handy calls while testing: `whip_reviveme` (`game_command`) revives you, `Inventory.close()` shuts the inventory or
shop screen, and `TriggerEvent('spur_core:client:fadeTeleport', x, y, z, h)` moves you with a fade.

How the link works inside is described in the header of `spur_mcp.mjs` and in CONVERSION.md, "The MCP link".
