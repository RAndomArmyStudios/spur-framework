// ========================================
// ERROR TAP — the page's half (shared/error_tap.lua keeps them)
// ========================================
//
// The page's errors reach only the F8 console, which nothing else can read. So each one also goes to client Lua,
// which keeps the last few hundred for tools (export GetErrorLog: whip_devlink's whip_errors). Imported first, so it
// hears the other modules' errors as they load:
//   an error nobody caught, a promise rejected with nobody to catch it, and console.error (how whip's page reports
//   what failed: the 3D map, a module that did not load)
// A burst is capped at BURST a second; what is over it is counted and said once.

const BURST = 20;
const TEXT_MAX = 2000;

const queue = [];
let sending = false;
let windowStart = 0, inWindow = 0, dropped = 0;

function say(v) {
    if (v instanceof Error) return v.stack || v.message;
    if (typeof v === 'object' && v !== null) { try { return JSON.stringify(v); } catch (e) { return String(v); } }
    return String(v);
}

async function flush() {
    if (sending) return;
    sending = true;
    while (queue.length) {
        try {
            await fetch('https://spur_core/errorTap', {
                method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(queue[0]),
            });
            queue.shift();
        } catch (e) {
            break;   // Lua is not listening yet: tried again with the next one
        }
    }
    sending = false;
}

function push(text) {
    const now = Date.now();
    if (now - windowStart > 1000) {
        if (dropped) queue.push({ text: `(${dropped} more page errors in a burst, not kept)` });
        windowStart = now; inWindow = 0; dropped = 0;
    }
    if (++inWindow > BURST) { dropped++; return; }
    queue.push({ text: String(text).slice(0, TEXT_MAX) });
    if (queue.length > 100) queue.splice(0, queue.length - 100);
    flush();
}

window.addEventListener('error', (ev) => {
    const where = ev.filename ? ` (${ev.filename.replace(/^.*\/html\//, '')}:${ev.lineno}:${ev.colno})` : '';
    push(`${ev.message}${where}${ev.error && ev.error.stack ? '\n' + ev.error.stack : ''}`);
});

window.addEventListener('unhandledrejection', (ev) => {
    push('a promise failed with nobody to catch it: ' + say(ev.reason));
});

const consoleError = console.error.bind(console);
console.error = (...args) => {
    consoleError(...args);
    push(args.map(say).join(' '));
};
