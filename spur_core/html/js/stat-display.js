// A vehicle stat's reading as a person sees it: RegisterVehicleStat's `display`, checked and put in one shape on the
// server (server/vehicle_stats.lua normDisplay) before it reaches here:
//
//   display = { unit = 'psi', decimals = 0, points = { {0, -3}, {100, 30} }, ends = { 'E', 'F' } }
//
// points: how far through its range the stat is (percent) → what that reads, a straight line between each two (a
// `range` arrives as its two end points). ends: the gauge shows these at its empty and full ends instead of a number.
// The rev dial's gauges (vehicle-dial.js) and the /whip Vehicles page (wp/vehicles.js) both read stats through here.

/** What a stat `fraction` (0-1) of the way through its range reads, with its unit: '14 psi', '92°C'. '' when the
 *  stat has no points (it reads as a percentage, or as its end markers). */
export function statValueText(display, fraction) {
    const p = display && Array.isArray(display.points) ? display.points : null;
    if (!p || p.length < 2) return '';
    const x = Math.max(0, Math.min(100, (Number(fraction) || 0) * 100));
    let v;
    if (x <= p[0][0]) v = p[0][1];
    else if (x >= p[p.length - 1][0]) v = p[p.length - 1][1];
    else {
        let i = 1;
        while (i < p.length - 1 && x > p[i][0]) i++;
        const [x0, y0] = p[i - 1], [x1, y1] = p[i];
        v = x1 === x0 ? y1 : y0 + ((y1 - y0) * (x - x0)) / (x1 - x0);
    }
    const d = display.decimals || 0;
    let s = v.toFixed(d);
    if (Number(s) === 0) s = (0).toFixed(d);                  // never "-0"
    const u = typeof display.unit === 'string' ? display.unit : '';
    if (!u) return s;
    return /^[°%]/.test(u) ? s + u : s + ' ' + u;             // '92°C', '14 psi'
}

/** The gauge's end markers, [empty, full], or null. */
export function statEnds(display) {
    return display && Array.isArray(display.ends) && display.ends.length === 2 ? display.ends : null;
}
