#!/usr/bin/env node
// spur_mcp: an MCP server (stdio) for testing a spur_core game on this PC without taking the mouse or keyboard.
//
// RedM (spur_core, 24 Nov 2026): new. Part of spur_core (LGPL-3.0), the RedM port of whip_core by Whippy and WLVF,
// whose screen probe, screenshot and error log (made for their whip_devlink "AI link") this drives. Non-commercial.
// Node 18+, nothing to install.
//
// HOW IT WORKS. An MCP client (Claude Code) starts this and talks to it on stdin/stdout. This also serves
// http://127.0.0.1:<port>/link (this PC only), where spur_core's page in the game (html/js/mcp-link.js) asks for the
// next thing to do and posts the answer; client/mcp_link.lua does it. Things to do come only from stdin: nothing on
// the HTTP side can give the game an order, and only a game page is answered at all: spur_core's Origin, or Origin
// "null" (what RedM's NUI sends) from a browser that says CitizenFX in its user agent. Any page in that game browser
// (another resource's, on whatever server) could pose as spur_core while this runs; the most it can do is take a job or
// answer one wrongly, since nothing it sends is an order.
//
// ON WINDOWS, game_launch starts RedM through WMI, so the game is not this server's child and closing the session
// leaves it running, and game_screenshot reads the game window from Windows (PrintWindow), since RedM's pages are handed
// no game picture. Neither moves the mouse or takes the focus.
//
// THE GAME'S SIDE IS OFF until a developer turns it on, once per PC: /mcplink on in F8, or `spur_mcplink <id|all> on`
// in the server console. It stays on (KVP) and needs whip.devtools.
//
// REGISTER (user scope, so it is there in every project; the address is the server's, for game_launch):
//   claude mcp add --scope user spur-game --env SPUR_MCP_CONNECT=<ip:port> -- node "<path to>/spur_core/dev/mcp/spur_mcp.mjs"
//
// ENV: SPUR_MCP_PORT (47130; /mcplink on <port> to match), SPUR_MCP_CONNECT (ip:port, for game_launch),
// SPUR_REDM_EXE (%LOCALAPPDATA%\RedM\RedM.exe), SPUR_REDM_LOGS (%LOCALAPPDATA%\RedM\RedM.app\logs),
// SPUR_MCP_SHOTS (where screenshots are saved: <temp>\spur_mcp), SPUR_MCP_ORIGINS (more page origins, comma separated).
//
// STDOUT IS THE PROTOCOL: everything else goes to stderr.

import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import { spawn, execFile } from 'node:child_process';

const VERSION = '1.0.0';
const PORT = Number(process.env.SPUR_MCP_PORT) || 47130;
const LOCALAPPDATA = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
const REDM_EXE = process.env.SPUR_REDM_EXE || path.join(LOCALAPPDATA, 'RedM', 'RedM.exe');
const REDM_LOGS = process.env.SPUR_REDM_LOGS || path.join(LOCALAPPDATA, 'RedM', 'RedM.app', 'logs');
const SHOTS = process.env.SPUR_MCP_SHOTS || path.join(os.tmpdir(), 'spur_mcp');
const ORIGINS = new Set(['https://cfx-nui-spur_core', 'nui://spur_core',
    ...(process.env.SPUR_MCP_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean)]);
const POLL_HOLD_MS = 25000;
const LINKED_MS = 60000;

const log = (...a) => process.stderr.write('[spur_mcp] ' + a.join(' ') + '\n');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// What goes into the conversation: no 40-hex identifiers (licences), no lines that name a player.
const NAME_LINE = /knows \d+ vehicle models|Player connected|Player loaded|developer mode|\bnick(name)?\b|player ?name|social ?club|\bros ?id\b|\bsteam\b/i;
const mask = (s) => String(s).replace(/\b[0-9a-f]{40}\b/gi, '<hex>');

// ============================================================================================================
// The link: the game's page polls; things to do wait in a queue for it
// ============================================================================================================

let poller = null;           // { res, timer }: the page's request we are holding
const queue = [];            // jobs not handed out yet
const pending = new Map();   // id -> answer(fn)
let nextId = 1;
let lastSeen = 0;
let linkError = null;        // why the HTTP side could not start
const origins = new Map();   // origin -> times seen (game_status shows them)
const refused = new Set();   // origins (and "null" from a browser that is not the game's) turned away

const linked = () => Date.now() - lastSeen < LINKED_MS || pending.size > 0;

function send(res, code, body, type = 'application/json') {
    if (res.writableEnded || res.destroyed) return false;
    res.writeHead(code, body == null ? {} : { 'Content-Type': type });
    res.end(body == null ? undefined : (typeof body === 'string' ? body : JSON.stringify(body)));
    return true;
}

function handOut(job) {
    while (poller) {
        const p = poller;
        poller = null;
        clearTimeout(p.timer);
        if (send(p.res, 200, job)) return true;
    }
    queue.push(job);
    return false;
}

function readBody(req, max) {
    return new Promise((resolve, reject) => {
        const parts = [];
        let size = 0;
        req.on('data', (c) => {
            size += c.length;
            if (size > max) { reject(new Error('too big')); req.destroy(); return; }
            parts.push(c);
        });
        req.on('end', () => resolve(Buffer.concat(parts).toString('utf8')));
        req.on('error', reject);
    });
}

const httpServer = http.createServer(async (req, res) => {
    const origin = req.headers.origin || '(none)';
    origins.set(origin, (origins.get(origin) || 0) + 1);
    if (origins.get(origin) === 1) log(`first request from origin ${origin} (user agent: ${req.headers['user-agent'] || '-'}; referer: ${req.headers.referer || '-'}; fetch site: ${req.headers['sec-fetch-site'] || '-'})`);
    // RedM's NUI sends its fetches as Origin "null" (seen 24 Nov 2026, though the page is https://cfx-nui-spur_core),
    // so "null" counts only from CitizenFX's own browser: a web page cannot set its user agent, and a sandboxed page
    // in an ordinary browser, which is also "null", does not say CitizenFX.
    const ok = ORIGINS.has(origin) || (origin === 'null' && /\bCitizenFX\/\d/.test(req.headers['user-agent'] || ''));
    if (ok) {
        res.setHeader('Access-Control-Allow-Origin', origin);
        res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
        res.setHeader('Access-Control-Allow-Private-Network', 'true');
        res.setHeader('Vary', 'Origin');
    }
    if (req.method === 'OPTIONS') return send(res, ok ? 204 : 403, null);
    if (!ok) {
        if (!refused.has(origin)) { refused.add(origin); log(`refused origin ${origin}`); }
        return send(res, 403, 'origin not allowed', 'text/plain');
    }
    if (req.method !== 'POST') return send(res, 405, null);

    let body;
    try {
        body = JSON.parse((await readBody(req, 40 * 1024 * 1024)) || '{}');
    } catch (e) {
        return send(res, 400, 'bad body', 'text/plain');
    }
    lastSeen = Date.now();

    if (req.url === '/link/next') {
        if (poller) { const p = poller; poller = null; clearTimeout(p.timer); send(p.res, 204, null); }
        const job = queue.shift();
        if (job) return send(res, 200, job);
        const held = { res, timer: null };
        held.timer = setTimeout(() => { if (poller === held) poller = null; send(res, 204, null); }, POLL_HOLD_MS);
        res.on('close', () => { if (poller === held) { clearTimeout(held.timer); poller = null; } });
        poller = held;
        return;
    }
    if (req.url === '/link/result') {
        const answer = pending.get(body.id);
        if (answer) answer({ ok: body.ok === true, result: body.result, err: body.err });
        return send(res, 204, null);
    }
    return send(res, 404, null);
});

httpServer.on('error', (e) => {
    linkError = e.code === 'EADDRINUSE'
        ? `127.0.0.1:${PORT} is taken (another spur_mcp, from another session?). Close it, or set SPUR_MCP_PORT and /mcplink on <port>.`
        : `the link could not start: ${e.message}`;
    log(linkError);
});
httpServer.listen(PORT, '127.0.0.1', () => log(`link on http://127.0.0.1:${PORT}/link`));

function notLinkedWhy() {
    if (linkError) return linkError;
    const seen = [...refused];
    return 'The game is not linked. Is RedM running and in the server (game_launch; about 3 minutes to load)? '
        + 'Is the link on for this PC (once: /mcplink on in F8, or spur_mcplink <id|all> on in the server console)? '
        + 'The account needs whip.devtools.'
        + (seen.length ? ` Refused origins seen: ${seen.join(', ')}.` : '');
}

/** One thing for the game to do. Resolves { ok, result, err }. */
function call(cmd, args = {}, ms = 30000) {
    if (!linked()) return Promise.resolve({ ok: false, err: notLinkedWhy() });
    const id = nextId++;
    return new Promise((resolve) => {
        const timer = setTimeout(() => {
            pending.delete(id);
            const i = queue.findIndex((j) => j.id === id);
            if (i >= 0) queue.splice(i, 1);
            resolve({ ok: false, err: `the game did not answer in ${Math.round(ms / 1000)} s` });
        }, ms);
        pending.set(id, (r) => { clearTimeout(timer); pending.delete(id); resolve(r); });
        handOut({ id, cmd, args });
    });
}

// ============================================================================================================
// Tools
// ============================================================================================================

const text = (s, isError = false) => ({ content: [{ type: 'text', text: mask(s) }], ...(isError ? { isError: true } : {}) });
const json = (v) => JSON.stringify(v, null, 1);
const clip = (s, n = 40000) => (s.length > n ? s.slice(0, n) + `\n... (${s.length - n} more characters)` : s);

async function game(cmd, args, ms, format = (r) => json(r)) {
    const r = await call(cmd, args, ms);
    if (!r.ok) return text(r.err || 'refused', true);
    return text(clip(format(r.result)));
}

function run(file, args) {
    return new Promise((resolve) => execFile(file, args, { windowsHide: true }, (err, out, errOut) =>
        resolve({ err, out: String(out || ''), errOut: String(errOut || '') })));
}

async function quitGame() {
    if (process.platform !== 'win32') return 'not Windows: nothing to close';
    const r = await run('taskkill', ['/F', '/IM', 'RedM*']);
    await sleep(1500);
    return /SUCCESS/i.test(r.out) ? 'RedM closed.' : 'RedM was not running.';
}

/**
 * Start the game so that it is not ours. Anything spawned from here, detached or not, stays in the process group
 * (Windows job) of whoever started this MCP server, and closing that session, or restarting this server, would close
 * the game too. Windows' own process service (WMI) starts it as a process of the desktop instead; the command line
 * goes in through an environment variable, so nothing in it is read as PowerShell.
 */
async function startApart(exe, arg) {
    if (process.platform === 'win32') {
        const r = await new Promise((resolve) => execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
            '$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $env:SPUR_CMDLINE; CurrentDirectory = $env:SPUR_CWD }; $r.ReturnValue'],
        { windowsHide: true, env: { ...process.env, SPUR_CMDLINE: `"${exe}" "${arg}"`, SPUR_CWD: path.dirname(exe) } },
        (err, out) => resolve({ err, out: String(out || '').trim() })));
        if (!r.err && r.out === '0') return ' (apart from this session: closing it leaves the game running)';
        log(`starting RedM through WMI did not work (${r.err ? r.err.message : 'code ' + r.out}); starting it directly`);
    }
    const child = spawn(exe, [arg], { detached: true, stdio: 'ignore' });
    child.on('error', (e) => log(`RedM did not start: ${e.message}`));
    child.unref();
    return ' (from this session: closing the session or this server may close the game)';
}

// The game window's picture, from Windows: PrintWindow with PW_RENDERFULLCONTENT (2) has the window's compositor copy
// drawn, so it is the game even with other windows over it (not when minimized). Nothing moves or takes focus. The
// script goes in encoded (no quoting), and the file, width and quality through the environment.
const WINDOW_SHOT_PS = `
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SpurShot {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
$p = Get-Process | Where-Object { $_.Name -like 'RedM_*GTAProcess' -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { 'NOWINDOW'; exit }
$h = $p.MainWindowHandle
if ([SpurShot]::IsIconic($h)) { 'MINIMIZED'; exit }
$r = New-Object SpurShot+RECT
[void][SpurShot]::GetWindowRect($h, [ref]$r)
$w = $r.R - $r.L; $ht = $r.B - $r.T
if ($w -lt 16 -or $ht -lt 16) { 'NOWINDOW'; exit }
$full = New-Object System.Drawing.Bitmap $w, $ht
$g = [System.Drawing.Graphics]::FromImage($full)
$dc = $g.GetHdc()
$ok = [SpurShot]::PrintWindow($h, $dc, 2)
$g.ReleaseHdc($dc); $g.Dispose()
if (-not $ok) { 'FAILED'; exit }
$ow = [Math]::Min([int]$env:SPUR_SHOT_W, $w); $oh = [int][Math]::Round($ht * $ow / $w)
$out = New-Object System.Drawing.Bitmap $ow, $oh
$g2 = [System.Drawing.Graphics]::FromImage($out)
$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g2.DrawImage($full, 0, 0, $ow, $oh); $g2.Dispose(); $full.Dispose()
$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ps = New-Object System.Drawing.Imaging.EncoderParameters 1
$ps.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([long]$env:SPUR_SHOT_Q)
$out.Save($env:SPUR_SHOT_FILE, $enc, $ps); $out.Dispose()
'OK'
`;

/** The game window into `file` (JPEG). Answers why not, or null. */
async function windowShot(file, width, quality) {
    if (process.platform !== 'win32') return "source 'window' is for Windows";
    const r = await new Promise((resolve) => execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-EncodedCommand', Buffer.from(WINDOW_SHOT_PS, 'utf16le').toString('base64')],
    { windowsHide: true, timeout: 30000, env: { ...process.env, SPUR_SHOT_FILE: file, SPUR_SHOT_W: String(width), SPUR_SHOT_Q: String(Math.round(quality * 100)) } },
    (err, out, errOut) => resolve({ err, out: String(out || '').trim(), errOut: String(errOut || '').trim() })));
    const said = r.out.split(/\r?\n/).pop();
    if (said === 'OK' && fs.existsSync(file)) return null;
    if (said === 'NOWINDOW') return 'RedM has no game window open (game_launch).';
    if (said === 'MINIMIZED') return 'The game window is minimized: restore it (it can stay behind other windows).';
    if (said === 'FAILED') return 'Windows would not draw the game window (PrintWindow failed).';
    return `The window could not be read: ${(r.errOut || (r.err && r.err.message) || said || 'no answer').slice(0, 400)}`;
}

function newestLog() {
    let files;
    try { files = fs.readdirSync(REDM_LOGS).filter((f) => /^CitizenFX_log.*\.log$/i.test(f)); } catch (e) { return null; }
    if (!files.length) return null;
    return files.map((f) => path.join(REDM_LOGS, f)).sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)[0];
}

const TOOLS = [
    {
        name: 'game_status',
        description: 'Is the game linked, and where is the player: server id, coords, heading, health, ped model, developer mode, whether a character is loaded, NUI focus. Never names the player.',
        inputSchema: { type: 'object', properties: {} },
        run: async () => {
            const head = { linked: linked(), lastSeenSecondsAgo: lastSeen ? Math.round((Date.now() - lastSeen) / 1000) : null,
                port: PORT, origins: Object.fromEntries(origins), linkError };
            if (!linked()) return text(json(head) + '\n' + notLinkedWhy());
            const r = await call('status', {}, 15000);
            return text(json({ ...head, game: r.ok ? r.result : { error: r.err } }));
        },
    },
    {
        name: 'game_launch',
        description: 'Close RedM if it is running, then start it and connect to the server (SPUR_MCP_CONNECT, or `connect` ip:port). Loading takes about 3 minutes; then game_status shows the link. The game window comes to the front once: it keeps running behind other windows (do not minimize it).',
        inputSchema: { type: 'object', properties: { connect: { type: 'string', description: 'ip:port; default SPUR_MCP_CONNECT' } } },
        run: async (a) => {
            const addr = a.connect || process.env.SPUR_MCP_CONNECT;
            if (!addr || !/^[A-Za-z0-9.-]+:\d{2,5}$/.test(addr)) return text('No server address: set SPUR_MCP_CONNECT (ip:port) where this MCP server is registered, or pass `connect`.', true);
            if (!fs.existsSync(REDM_EXE)) return text(`RedM is not at ${REDM_EXE} (set SPUR_REDM_EXE).`, true);
            const closed = await quitGame();
            lastSeen = 0;
            const how = await startApart(REDM_EXE, `redm://connect/${addr}`);
            return text(`${closed} RedM started${how} and is connecting. Give it about 3 minutes, then game_status or game_wait_for_text.`);
        },
    },
    {
        name: 'game_quit',
        description: 'Close RedM (all its processes). Do this before restarting the server: a reconnect in game does not work.',
        inputSchema: { type: 'object', properties: {} },
        run: async () => { lastSeen = 0; return text(await quitGame()); },
    },
    {
        name: 'game_dev_mode',
        description: 'Turn developer mode on or off (as the /w switch does). Reading and pressing the screen, commands and Lua need it on.',
        inputSchema: { type: 'object', properties: { on: { type: 'boolean' } }, required: ['on'] },
        run: (a) => game('devmode', { on: a.on === true }, 15000),
    },
    {
        name: 'game_read_screen',
        description: "What spur_core's interface shows now: its words, and its controls (buttons, inputs, tabs, switches, rows) each with an id for game_press. Other resources' pages that load page-tools.js (the phone) come under `pages`. `under`: only what is under a heading or section with these words. Needs developer mode. Character names may appear: read them, never repeat them.",
        inputSchema: { type: 'object', properties: { under: { type: 'string' }, pages: { type: 'boolean', description: 'false: spur_core\'s page only' } } },
        run: (a) => game('screen', { opts: { ...(a.under ? { under: a.under } : {}), ...(a.pages === false ? { pages: false } : {}) } }, 20000),
    },
    {
        name: 'game_press',
        description: "Press a control on spur_core's interface the way a mouse would (its own handlers run): by `id` from the last game_read_screen, or by its words (`label`, exact first, then contained; `near` picks the one near other words). Text that is no control (the landing's \"Press any button to continue\") cannot be pressed: game_lua `Landing.Continue()` goes on from there. `text` types into an input first; `enter` presses Enter after; `choose` picks an option of a select. `page` presses another resource's page (e.g. a phone). Needs developer mode.",
        inputSchema: {
            type: 'object',
            properties: {
                id: { type: 'number' }, label: { type: 'string' }, near: { type: 'string' }, kind: { type: 'string' },
                index: { type: 'number' }, page: { type: 'string' }, text: { type: 'string' }, enter: { type: 'boolean' },
                choose: { type: 'string' }, button: { type: 'string', description: 'mouse button: left (default) or right' },
            },
        },
        run: (a) => {
            const target = {};
            for (const k of ['id', 'label', 'near', 'kind', 'index', 'page']) if (a[k] != null) target[k] = a[k];
            if (target.id == null && !target.label) return text('give an id (from game_read_screen) or a label', true);
            const opts = {};
            for (const k of ['text', 'enter', 'choose', 'button']) if (a[k] != null) opts[k] = a[k];
            return game('press', { target, opts }, 20000);
        },
    },
    {
        name: 'game_command',
        description: 'Run a command in the game as if typed in F8 (e.g. "w" for the dev tools menu, "propcheck", "mcplink"). Client commands run here; others go to the server as F8 would send them. Needs developer mode.',
        inputSchema: { type: 'object', properties: { command: { type: 'string' } }, required: ['command'] },
        run: (a) => game('command', { command: a.command }, 15000),
    },
    {
        name: 'game_lua',
        description: "Run Lua in spur_core's client (its globals: Screenshot, Landing, Interactions, DevToolsOn, natives...). An expression is returned (`GetEntityCoords(PlayerPedId())`); statements run as a chunk and may `return`. print() lines come back. Globals it sets persist. Needs developer mode. For testing only.",
        inputSchema: { type: 'object', properties: { code: { type: 'string' } }, required: ['code'] },
        run: (a) => game('lua', { code: a.code }, 30000),
    },
    {
        name: 'game_screenshot',
        description: "The game's picture now (JPEG), saved to a file too (the path comes back). source 'window' (the default on Windows): "
            + 'the game window as it looks, every interface in it, read from Windows, so it works with the window behind others (not '
            + "minimized) and needs no link. source 'page': spur_core's own shot from inside the game, `ui` to add its interface; "
            + "RedM's pages are handed no game picture (it comes out blue), so on RedM use 'window'.",
        inputSchema: { type: 'object', properties: {
            source: { type: 'string', enum: ['window', 'page'] }, ui: { type: 'boolean', description: "source 'page' only" },
            width: { type: 'number', description: 'pixels wide, default 1280' }, quality: { type: 'number', description: '0-1, default 0.8' } } },
        run: async (a) => {
            const width = Math.min(Math.max(Math.round(Number(a.width) || 1280), 160), 3840);
            const quality = Math.min(Math.max(Number(a.quality) || 0.8, 0.1), 1);
            const stamp = new Date().toISOString().replace(/[:.]/g, '-');
            fs.mkdirSync(SHOTS, { recursive: true });
            if ((a.source || (process.platform === 'win32' ? 'window' : 'page')) === 'window') {
                const file = path.join(SHOTS, `shot-${stamp}.jpg`);
                const why = await windowShot(file, width, quality);
                if (why) return text(why, true);
                return { content: [{ type: 'image', data: fs.readFileSync(file).toString('base64'), mimeType: 'image/jpeg' },
                    { type: 'text', text: `saved: ${file}` }] };
            }
            const r = await call('shot', { ui: a.ui === true, width, quality }, 30000);
            if (!r.ok) return text((r.err || 'no picture') + (process.platform === 'win32' ? " (try source 'window')" : ''), true);
            const m = /^data:(image\/[a-z]+);base64,(.+)$/s.exec(String(r.result || ''));
            if (!m) return text('the game sent something that is not a picture', true);
            const file = path.join(SHOTS, `shot-${stamp}.${m[1] === 'image/png' ? 'png' : 'jpg'}`);
            fs.writeFileSync(file, Buffer.from(m[2], 'base64'));
            return { content: [{ type: 'image', data: m[2], mimeType: m[1] }, { type: 'text', text: `saved: ${file}` }] };
        },
    },
    {
        name: 'game_errors',
        description: "Errors spur_core caught in the game: its page's (JS) and its client Lua's, newest last. `since`: the `last` number from an earlier call, for only the new ones.",
        inputSchema: { type: 'object', properties: { since: { type: 'number' }, max: { type: 'number' } } },
        run: (a) => game('errors', { since: a.since, max: a.max || 50 }, 15000),
    },
    {
        name: 'game_wait_for_text',
        description: "Wait until spur_core's interface shows these words (game_read_screen, once a second), up to timeout_s (default 60, max 600). Waits for the link too, so it works right after game_launch: for the first screen after loading use timeout_s 300. Turns developer mode on when the link comes up, since reading needs it.",
        inputSchema: { type: 'object', properties: { text: { type: 'string' }, timeout_s: { type: 'number' }, under: { type: 'string' } }, required: ['text'] },
        run: async (a) => {
            const want = String(a.text || '').toLowerCase();
            if (!want) return text('text: the words to wait for', true);
            const until = Date.now() + Math.min(Math.max(Number(a.timeout_s) || 60, 1), 600) * 1000;
            let last = 'not linked yet', devTried = false;
            while (Date.now() < until) {
                if (linked()) {
                    let r = await call('screen', { opts: { ...(a.under ? { under: a.under } : {}) } }, 20000);
                    if (!r.ok && /developer mode is off/.test(r.err || '') && !devTried) {
                        devTried = true;
                        await call('devmode', { on: true }, 15000);
                        r = await call('screen', { opts: {} }, 20000);
                    }
                    if (r.ok) {
                        const s = JSON.stringify(r.result);
                        if (s.toLowerCase().includes(want)) return text(`found "${a.text}"\n` + clip(json(r.result), 20000));
                        last = 'not shown yet';
                    } else last = r.err || 'refused';
                }
                await sleep(1000);
            }
            return text(`"${a.text}" did not show in time (${last})`, true);
        },
    },
    {
        name: 'game_log',
        description: "The end of RedM's own client log (CitizenFX_log, what F8 shows and more), newest file. `grep`: only lines matching this regular expression (case-insensitive). Identifiers are masked and lines that name a player are left out.",
        inputSchema: { type: 'object', properties: { lines: { type: 'number', description: 'default 60, max 400' }, grep: { type: 'string' } } },
        run: async (a) => {
            const file = newestLog();
            if (!file) return text(`no CitizenFX log in ${REDM_LOGS}`, true);
            const size = fs.statSync(file).size;
            const from = Math.max(0, size - 4 * 1024 * 1024);
            const fd = fs.openSync(file, 'r');
            const buf = Buffer.alloc(size - from);
            fs.readSync(fd, buf, 0, buf.length, from);
            fs.closeSync(fd);
            let rx = null;
            if (a.grep) { try { rx = new RegExp(a.grep, 'i'); } catch (e) { return text('grep: not a regular expression', true); } }
            const n = Math.min(Math.max(Number(a.lines) || 60, 1), 400);
            const out = buf.toString('utf8').split(/\r?\n/)
                .map((l) => l.replace(/\x1b\[[0-9;]*m/g, '').replace(/\^\d/g, ''))
                .filter((l) => l.trim() && !NAME_LINE.test(l) && (!rx || rx.test(l)))
                .slice(-n);
            return text(`${path.basename(file)} (last ${out.length} lines${rx ? ' matching' : ''})\n` + out.join('\n'));
        },
    },
];

const BY_NAME = new Map(TOOLS.map((t) => [t.name, t]));

// ============================================================================================================
// MCP over stdio (JSON-RPC 2.0, one message a line)
// ============================================================================================================

const out = (msg) => process.stdout.write(JSON.stringify(msg) + '\n');
const reply = (id, result) => out({ jsonrpc: '2.0', id, result });
const fail = (id, code, message) => out({ jsonrpc: '2.0', id, error: { code, message } });

const INSTRUCTIONS = 'Tests a spur_core RedM game on this PC without the mouse. game_launch starts RedM and connects; '
    + 'game_wait_for_text waits for a screen (300 s for the first after loading); game_dev_mode on before reading or '
    + 'pressing; game_read_screen then game_press by id or label. The landing ("Press any button to continue") has no '
    + 'control to press: game_lua `Landing.Continue()`. game_screenshot to see (the game window, behind other windows '
    + 'is fine); game_command and game_lua for anything else (a chunk gets 30 s); game_errors and game_log for what '
    + 'broke. game_quit before restarting the server.';

async function handle(msg) {
    const { id, method, params } = msg;
    const isRequest = id !== undefined && id !== null;
    switch (method) {
        case 'initialize':
            return reply(id, {
                protocolVersion: (params && params.protocolVersion) || '2025-06-18',
                capabilities: { tools: { listChanged: false } },
                serverInfo: { name: 'spur_mcp', version: VERSION },
                instructions: INSTRUCTIONS,
            });
        case 'ping':
            return isRequest && reply(id, {});
        case 'tools/list':
            return reply(id, { tools: TOOLS.map(({ name, description, inputSchema }) => ({ name, description, inputSchema })) });
        case 'tools/call': {
            const tool = BY_NAME.get(params && params.name);
            if (!tool) return fail(id, -32602, `no tool ${params && params.name}`);
            try {
                return reply(id, await tool.run((params && params.arguments) || {}));
            } catch (e) {
                return reply(id, text(`${tool.name} failed: ${e && e.message || e}`, true));
            }
        }
        default:
            if (isRequest) return fail(id, -32601, `no method ${method}`);
    }
}

const rl = readline.createInterface({ input: process.stdin });
rl.on('line', (line) => {
    if (!line.trim()) return;
    let msg;
    try { msg = JSON.parse(line); } catch (e) { return fail(null, -32700, 'parse error'); }
    handle(msg).catch((e) => log(`handler failed: ${e && e.stack || e}`));
});
rl.on('close', () => process.exit(0));
