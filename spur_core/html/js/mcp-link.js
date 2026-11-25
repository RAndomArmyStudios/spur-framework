// ========================================
// MCP LINK — the page half of client/mcp_link.lua
//
// RedM (spur_core, 24 Nov 2026): new. While Lua says so (/mcplink on, for a holder of whip.devtools), this page asks
// the MCP server on this PC (dev/mcp/spur_mcp.mjs, http://127.0.0.1 only) for the next thing to do, hands it to Lua
// on the mcpLink callback and posts Lua's answer back. Off, it does nothing at all. Nothing here listens: the page
// only goes out, to this PC, and only the MCP server's own client can give it anything to do.
//
// ONE MODULE GRAPH (main.js): an error here would take the whole page down, so nothing runs at import but the
// router registration, and every request is caught.
// ========================================

import { NuiRouter } from './router.js';

let on = false;
let port = 47130;
let gen = 0;   // a loop whose generation is not the current one stops

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const resource = () => (typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'spur_core');

/** To the MCP server. text/plain keeps it a simple request (no CORS preflight); the server reads it as JSON. */
function toServer(path, body, ms) {
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), ms);
    return fetch(`http://127.0.0.1:${port}/link/${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'text/plain' },
        body: JSON.stringify(body || {}),
        signal: ctl.signal,
    }).finally(() => clearTimeout(t));
}

/** One thing to do, done by Lua (which decides whether it may be). */
async function toLua(job) {
    try {
        const r = await fetch(`https://${resource()}/mcpLink`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ cmd: job.cmd, args: job.args || {} }),
        });
        const a = await r.json();
        return a && typeof a === 'object' ? a : { ok: false, err: 'Lua gave no answer' };
    } catch (e) {
        return { ok: false, err: 'Lua did not answer: ' + String(e && e.message || e) };
    }
}

async function loop(g) {
    let wait = 1000;
    while (on && g === gen) {
        let r;
        try {
            r = await toServer('next', { v: 1 }, 35000);   // held up to 25 s by the server when there is nothing
        } catch (e) {
            // No MCP server on this PC now (or it went): ask again, less often the longer it stays away.
            await sleep(wait);
            wait = Math.min(wait * 2, 30000);
            continue;
        }
        wait = 1000;
        if (r.status !== 200) {
            if (r.status !== 204) await sleep(r.status === 403 ? 30000 : 2000);
            continue;
        }
        let job = null;
        try { job = await r.json(); } catch (e) { job = null; }
        if (!job || job.id == null || typeof job.cmd !== 'string') continue;
        const answer = await toLua(job);
        try {
            await toServer('result', { id: job.id, ok: answer.ok === true, result: answer.result, err: answer.err }, 30000);
        } catch (e) { /* the server went: whoever asked times out there */ }
    }
}

NuiRouter.register('mcpLink', (d) => {
    const want = !!(d && d.on);
    const p = Number(d && d.port);
    if (Number.isInteger(p) && p >= 1024 && p <= 65535 && p !== port) {
        port = p;
        if (on) { on = false; gen++; }   // started again on the new port, below
    }
    if (want && !on) { on = true; loop(++gen); }
    else if (!want && on) { on = false; gen++; }
});
