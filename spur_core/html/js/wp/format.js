// ========================================
// /whip — the words and numbers the admin pages print, written once
//
// Every page imports these instead of keeping its own copy. The copies had drifted: four "how long
// ago" helpers read seconds, server seconds and milliseconds, and one reading the wrong one put
// "Last played: Just now" on everybody (31d5beed).
//
// A TIME arrives from the server three ways: oxmysql sends a TIMESTAMP as epoch MILLISECONDS,
// UNIX_TIMESTAMP() and os.time() send SECONDS, and a few rows send a date string. toMs() reads all
// three, and every time helper here goes through it, so a page cannot pick the wrong one.
// ========================================

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const two = (n) => String(n).padStart(2, '0');

/** "1 text", "3 texts"; `many` when the word for more than one is not just one + s ("2 people"). */
export const plural = (n, one, many) => n + ' ' + (n === 1 ? one : (many || one + 's'));

/** A moment as epoch ms, from milliseconds, seconds or a date string. NaN when it is none of them. */
export function toMs(v) {
    if (typeof v === 'number') return v > 1e12 ? v : v * 1000;
    if (v === null || v === undefined || v === '') return NaN;
    return new Date(v).getTime();
}

/** Seconds since a moment (NaN for none). `now`: the clock to measure from, in ms; the PC's by default. */
export function age(v, now) {
    return Math.floor(((now === undefined ? Date.now() : now) - toMs(v)) / 1000);
}

/** How long ago, short: "just now", "5m ago", "3h ago", "2d ago", "3w ago", "4mo ago", and "never" for no
 *  moment. opts.now: the clock to measure from, in ms (a page that keeps the server's). opts.seconds: under
 *  a minute in seconds ("12s ago"), for a live feed. A PC clock a little behind the server's reads as just
 *  now, not as the future. */
export function ago(v, opts) {
    const o = opts || {};
    const s = age(v, o.now);
    if (!v || isNaN(s)) return 'never';
    if (s < 60) return o.seconds && s > 0 ? s + 's ago' : 'just now';
    if (s < 3600) return Math.floor(s / 60) + 'm ago';
    if (s < 86400) return Math.floor(s / 3600) + 'h ago';
    if (s < 604800) return Math.floor(s / 86400) + 'd ago';
    if (s < 2592000) return Math.floor(s / 604800) + 'w ago';
    return Math.floor(s / 2592000) + 'mo ago';
}

/** The day: "3 Oct", with the year when it is not this one ("3 Oct 2025"). `none`: what no moment reads as. */
export function date(v, none = '—') {
    const ms = toMs(v);
    if (!v || isNaN(ms)) return none;
    const d = new Date(ms);
    return d.getDate() + ' ' + MONTHS[d.getMonth()] + (d.getFullYear() !== new Date().getFullYear() ? ' ' + d.getFullYear() : '');
}

/** The day and the time: "3 Oct, 14:02" (with the year when it is not this one). */
export function dateTime(v, none = '—') {
    const ms = toMs(v);
    if (!v || isNaN(ms)) return none;
    const d = new Date(ms);
    return date(ms) + ', ' + two(d.getHours()) + ':' + two(d.getMinutes());
}

/** The time of day to the second: "14:02:33". */
export function timeOfDay(v) {
    const d = new Date(toMs(v));
    return two(d.getHours()) + ':' + two(d.getMinutes()) + ':' + two(d.getSeconds());
}

/** A length of time in SECONDS on a clock: "4:05", "1:02:09" past the hour. `tenths`: to the tenth ("4:05.3"). */
export function clock(sec, tenths) {
    const t = Math.max(0, Number(sec) || 0);
    const s = tenths ? Math.round(t * 10) / 10 : Math.floor(t);
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
    return (h ? h + ':' + two(m) : String(m)) + ':' + (tenths ? x.toFixed(1).padStart(4, '0') : two(x));
}

/** Dollars: "$1,250". */
export const money = (n) => '$' + (Number(n) || 0).toLocaleString('en-US');

/** A setting's number: a whole one as it is, the rest to three places at most. */
export function number(n) {
    if (typeof n !== 'number') return String(n);
    return Number.isInteger(n) ? String(n) : String(Math.round(n * 1000) / 1000);
}

/** A coordinate or a distance to a fixed number of places, one unless told: "12.5". */
export const fixed = (n, dp = 1) => (Number(n) || 0).toFixed(dp);

/** A phone number the way people write one: "555-123-4567". */
export const phoneNumber = (n) => (n && n.length === 10) ? n.slice(0, 3) + '-' + n.slice(3, 6) + '-' + n.slice(6) : (n || 'Unknown');
