// ========================================
// SYSTEMS — the editor column's tabs
//
//   Cards      the palette: search, the card types by kind; click to add, or drag onto the grid
//   Card       the selected card: its fields, and its value INPUTS (a typed-in value for each one
//              nothing is wired into); after a test, the last value each pin had
//   Places     every place a card needs (a line's two ends, a point's spot): Here (where you stand)
//              or Aim (put it in the world), with the line drawn while you aim its other end
//   Variables  what the system keeps: for everyone, per player or per car, and whether it is
//              remembered across restarts
//   Check      the server's check of the document, what it may do (money, items) and its approval,
//              and switching it on
//   Test       a test of the document as it is now, for you alone: going, its log, Stop
//   About      name, description, revisions, delete
//
// Fields name what they edit with data attributes (data-t = which object, data-k = which key, data-f =
// how to read it), so one delegated listener in app.js handles every field of every tab (the
// Director's way, director/panels.js; its builders are copied here, not imported: it changes often).
// ========================================

import { escapeHtml } from '../utils.js';
import { getItemDefs } from '../core/item-defs.js';
import { groupCards } from '../director/search.js';
import { findNode, problemCards, placesOf, placeText, placeValue, SCOPES, VAR_TYPES, canRemember } from './doc.js';
import { constOf, typeTitle, FAMILY_TITLE } from './pins.js';

const e = escapeHtml;

export const TABS = [
    { id: 'cards', label: 'Cards' },
    { id: 'card', label: 'Card' },
    { id: 'places', label: 'Places' },
    { id: 'vars', label: 'Variables' },
    { id: 'check', label: 'Check' },
    { id: 'test', label: 'Test' },
    { id: 'about', label: 'About' },
];

const POWER_TEXT = { money: 'move money', items: 'move items', others: 'act on other players or the whole server',
    make: 'make things of its own for the server, for good (an item)' };

export function when(v) {
    if (v === undefined || v === null || v === '') return '';
    const d = new Date(typeof v === 'number' ? (v < 1e12 ? v * 1000 : v) : String(v));
    if (isNaN(d.getTime())) return '';
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) + ', '
        + d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
}

export function powersText(powers) {
    const list = String(powers || '').split(',').filter(Boolean);
    if (!list.length) return '';
    const words = list.map((p) => POWER_TEXT[p] || p);
    return words.length > 1 ? words.slice(0, -1).join(', ') + ' and ' + words[words.length - 1] : words[0];
}

// ---- field builders (director/panels.js's) ----

function label(text, hint) {
    return `<div class="dr-label">${e(text)}${hint ? `<span>${e(hint)}</span>` : ''}</div>`;
}

function textField(t, k, value, o = {}) {
    const attrs = `data-t="${e(t)}" data-k="${e(k)}" data-f="${e(o.f || 'text')}"${o.max ? ` maxlength="${o.max}"` : ''}`
        + ` placeholder="${e(o.placeholder || '')}" spellcheck="false"`;
    const v = value === undefined || value === null ? '' : String(value);
    const box = o.big
        ? `<textarea class="dr-field" rows="3" ${attrs}>${e(v)}</textarea>`
        : `<input class="dr-field${o.mono ? ' sy-mono' : ''}" type="text" value="${e(v)}" ${attrs}>`;
    return `<div class="dr-row">${label(o.label || k, o.hint)}${box}${o.after || ''}</div>`;
}

function numberField(t, k, value, o = {}) {
    const v = typeof value === 'number' ? String(value) : '';
    return `<div class="dr-row">${label(o.label || k, o.hint)}<input class="dr-field" type="number" value="${e(v)}"`
        + ` data-t="${e(t)}" data-k="${e(k)}" data-f="number"${o.min !== undefined ? ` min="${o.min}"` : ''}`
        + `${o.max !== undefined ? ` max="${o.max}"` : ''} step="any" placeholder="${e(o.placeholder || '')}">${o.after || ''}</div>`;
}

function segField(t, k, value, options, o = {}) {
    const keys = options.map(([v, text]) => {
        const on = v === value || (value === undefined && v === o.fallback);
        return `<button class="dr-seg-key${on ? ' on' : ''}" data-t="${e(t)}" data-k="${e(k)}" data-v="${e(JSON.stringify(v))}">${e(text)}</button>`;
    }).join('');
    return `<div class="dr-row">${label(o.label || k, o.hint)}<div class="dr-seg">${keys}</div>${o.after || ''}</div>`;
}

function selectField(t, k, value, options, o = {}) {
    const opts = [`<option value="">${e(o.none || '— pick one —')}</option>`]
        .concat(options.map(([v, text]) => `<option value="${e(v)}"${v === value ? ' selected' : ''}>${e(text)}</option>`));
    if (value && !options.some(([v]) => v === value)) opts.push(`<option value="${e(value)}" selected>${e(value)} (missing)</option>`);
    return `<div class="dr-row">${label(o.label || k, o.hint)}<select class="dr-field" data-t="${e(t)}" data-k="${e(k)}" data-f="select">${opts.join('')}</select></div>`;
}

const yesNo = [[true, 'Yes'], [false, 'No']];

/** A system's name for a thing it makes: cards_people.lua's C.name (`s_<short id>_<name>`). */
function systemName(short, name) {
    const clean = String(name == null ? '' : name).replace(/[^A-Za-z0-9_]/g, '').slice(0, 24) || 'x';
    return `s_${short}_${clean}`;
}

function itemOptions(ed) {
    const defs = getItemDefs() || {};
    const out = Object.keys(defs).map((k) => [k, (defs[k] && defs[k].name) ? `${defs[k].name} (${k})` : k]);
    // This system's own items (its This System's Item cards), before it is ever switched on.
    const short = ed && ed.system && ed.system.shortId;
    if (short) {
        for (const n of ed.doc.nodes) {
            if (n.type !== 'make.item') continue;
            const key = systemName(short, n.props.name == null ? 'token' : n.props.name);
            if (!defs[key]) out.push([key, `${n.props.label || 'Token'} (this system's: ${key})`]);
        }
    }
    return out.sort((a, b) => a[1].localeCompare(b[1]));
}

function problemsHtml(list) {
    return list.map((p) => `<div class="dr-prob ${p.severity === 'error' ? 'error' : 'warn'}">${e(p.message)}</div>`).join('');
}

// ---- Cards ----

/** The Systems Creator's card kinds, in the palette's order (the search uses them too). */
export const CAT_ORDER = ['when', 'flow', 'maths', 'text', 'variables', 'lists', 'values', 'players', 'jobs', 'cars', 'items', 'money',
    'world', 'npcs', 'missions'];
export const CAT_TITLE = {
    when: 'When…', flow: 'Flow', maths: 'Maths', text: 'Text', variables: 'Variables', lists: 'Lists', values: 'Values',
    players: 'Players', jobs: 'Jobs', cars: 'Cars', items: 'Items', money: 'Money', world: 'World', npcs: 'NPCs', missions: 'Missions',
};

function cardsTab(ed) {
    const groups = groupCards(ed.cards, ed.paletteQuery, null, CAT_ORDER, CAT_TITLE);
    const rows = groups.map((g) => `<div class="dr-cat kind-${e(g.cat)}">${e(g.title)}</div>`
        + g.cards.map((def) => `<div class="dr-pal-row" data-type="${e(def.type)}"><b>${e(def.title)}`
            + `${def.power ? `<i class="sy-power" title="It may ${e(powersText(def.power))}: a systems admin approves that before it is switched on">${e(def.power)}</i>` : ''}</b>`
            + (def.desc ? `<span>${e(def.desc)}</span>` : '') + '</div>').join('')).join('');
    return `<input class="dr-field dr-pal-search" type="text" placeholder="Search cards" value="${e(ed.paletteQuery || '')}" spellcheck="false">`
        + '<div class="dr-hint">Click to add a card in the middle, or drag it onto the grid. Right-click the grid to search there. White pins are "then" (what happens next); coloured pins carry values (a speed, a player).</div>'
        + (rows || '<div class="dr-none">No card matches</div>');
}

// ---- Card ----

function placeButtons(target, key, has) {
    return '<div class="dr-btns sy-place-btns">'
        + `<button class="dr-btn" data-act="place-here" data-t="${e(target)}" data-k="${e(key)}" title="Where you are standing now">Here</button>`
        + `<button class="dr-btn" data-act="place-aim" data-t="${e(target)}" data-k="${e(key)}" title="Aim at the ground in the world, E to put it there">Aim in the world</button>`
        + (has ? `<button class="dr-btn ghost" data-act="place-clear" data-t="${e(target)}" data-k="${e(key)}">Clear</button>` : '')
        + '</div>';
}

function propField(ed, node, f) {
    const t = 'node:' + node.id;
    const v = node.props[f.key];
    const lab = (f.label || f.key) + (f.required ? ' *' : '');
    const dflt = f.default !== undefined && f.default !== null ? String(f.default) : '';
    switch (f.kind) {
        case 'text':
            return textField(t, f.key, v, { label: lab, max: f.maxLength, big: (f.maxLength || 0) > 80, placeholder: dflt, hint: f.hint || '' });
        case 'number':
        case 'duration':
            return numberField(t, f.key, v, { label: lab, min: f.min, max: f.max, hint: f.kind === 'duration' ? 'seconds' : '', placeholder: dflt });
        case 'bool':
            return segField(t, f.key, v, yesNo, { label: lab, fallback: f.default === true });
        case 'select': {
            const opts = (f.options || []).map((o) => [o, o]);
            const short = opts.length <= 4 && opts.reduce((n, [o]) => n + String(o).length, 0) <= 26;
            return short ? segField(t, f.key, v, opts, { label: lab, fallback: f.default }) : selectField(t, f.key, v, opts, { label: lab });
        }
        case 'scope':
            return segField(t, f.key, v, SCOPES, { label: lab, fallback: f.default || 'everyone' });
        case 'formula': {
            const err = ed.formulaError(node);
            return textField(t, f.key, v, { label: lab, max: 200, mono: true, placeholder: dflt,
                hint: 'each name becomes an input',
                after: err ? `<div class="dr-prob error">${e(err)}</div>` : '' });
        }
        case 'item': {
            const items = itemOptions(ed);
            return items.length ? selectField(t, f.key, v, items, { label: lab, none: '— pick an item —' })
                : textField(t, f.key, v, { label: lab, max: 50, placeholder: 'item key' });
        }
        case 'var': {
            const vars = ed.doc.vars.filter((x) => !f.varType || x.type === f.varType);
            return selectField(t, f.key, v, vars.map((x) => [x.id, `${x.id} (${typeTitle(x.type)})`]),
                { label: lab, hint: vars.length ? '' : `make one in Variables${f.varType ? ` (${typeTitle(f.varType)})` : ''}`, none: '— pick a variable —' });
        }
        case 'place': {
            const p = placeValue(v);
            return `<div class="dr-row">${label(lab, p ? placeText(p) : 'not placed yet')}</div>` + placeButtons(t, f.key, !!p);
        }
        default:
            return `<div class="dr-row">${label(lab)}<div class="dr-none">${e(String(v))}</div></div>`;
    }
}

/** A value input nothing is wired into: what it takes when the card runs. */
function inputField(ed, node, pin) {
    const t = 'value:' + node.id;
    const c = constOf(node, pin);
    const typed = c && c.typed ? c.value : undefined;
    const dflt = pin.default !== undefined && pin.default !== null ? String(pin.default) : '';
    const lab = pin.label || pin.key;
    const hint = typeTitle(pin.type);
    switch (pin.type) {
        case 'number':
            return numberField(t, pin.key, typed, { label: lab, hint, placeholder: dflt || (pin.optional ? '(optional)' : 'needs a value') });
        case 'text':
            return textField(t, pin.key, typed, { label: lab, hint, max: 300, placeholder: dflt || (pin.optional ? '(optional)' : 'needs a value') });
        case 'bool':
            return segField(t, pin.key, typed, yesNo, { label: lab, hint, fallback: pin.default });
        case 'any':
            // A number, yes/no or text, read from what is typed: 80 is a number, true a yes.
            return textField(t, pin.key, typed, { label: lab, hint: 'a number, true / false, or text', max: 300, f: 'any',
                placeholder: dflt || (pin.optional ? '(optional)' : 'needs a value') });
        case 'vector': {
            const p = placeValue(typed);
            return `<div class="dr-row">${label(lab, p ? placeText(p) : 'wire a place in, or set one')}</div>` + placeButtons(t, pin.key, !!p);
        }
        default:
            return `<div class="dr-row">${label(lab, hint)}<div class="dr-none">${pin.optional ? 'Optional: ' : ''}wire ${e(typeTitle(pin.type))} into it</div></div>`;
    }
}

function lastValuesHtml(ed, node, vp) {
    const vals = ed.testValues && ed.testValues[node.id];
    if (!vals) return '';
    const rows = [...vp.inputs, ...vp.outputs].filter((p) => vals[p.key] !== undefined)
        .map((p) => `<div class="sy-val"><span>${e(p.label || p.key)}</span><b>${e(vals[p.key])}</b></div>`).join('');
    return rows ? `<div class="dr-sep"></div><div class="dr-title2">Last values (the test)</div>${rows}` : '';
}

function cardTab(ed) {
    const ids = [...ed.selected];
    if (ids.length === 0) return '<div class="dr-hint">Click a card on the grid to see its settings here.</div>';
    if (ids.length > 1) {
        return `<div class="dr-title2">${ids.length} cards selected</div>`
            + '<div class="dr-btns"><button class="dr-btn" data-act="dup-sel">Duplicate</button>'
            + '<button class="dr-btn danger" data-act="del-sel">Delete</button></div>';
    }
    const node = findNode(ed.doc, ids[0]);
    if (!node) return '';
    const def = ed.cards.get(node.type);
    const mine = ed.problemList.filter((p) => p.node === node.id);
    if (!def) {
        return `<div class="dr-title2">${e(node.type)}</div>`
            + '<div class="dr-prob error">This card type is not on this server. It is kept as it is.</div>'
            + '<div class="dr-btns"><button class="dr-btn danger" data-act="del-sel">Delete</button></div>';
    }
    const vp = ed.typed.valuePins(node, def, ed.doc);
    let html = `<div class="dr-title2"><i class="dr-dot kind-${e(def.category)}"></i>${e(def.title)}<span class="dr-idtag">${e(node.id)}</span></div>`
        + (def.desc ? `<div class="dr-hint">${e(def.desc)}</div>` : '')
        + (def.power ? `<div class="dr-hint sy-power-hint">It may ${e(powersText(def.power))}: a systems admin approves that before the system is switched on. In a test it only says what it would do.</div>` : '')
        + problemsHtml(mine)
        + (def.props || []).map((f) => propField(ed, node, f)).join('');
    if (vp.inputs.length) {
        html += '<div class="dr-sep"></div><div class="dr-title2">Inputs</div>';
        for (const pin of vp.inputs) {
            const link = ed.doc.links.find((l) => l.to.node === node.id && l.to.pin === pin.key);
            if (link) {
                const from = findNode(ed.doc, link.from.node);
                const fdef = from && ed.cards.get(from.type);
                html += `<div class="dr-row">${label(pin.label || pin.key, typeTitle(pin.type))}`
                    + `<div class="dr-where link" data-act="goto-node" data-id="${e(link.from.node)}">From ${e(fdef ? fdef.title : link.from.node)}</div></div>`;
            } else {
                html += inputField(ed, node, pin);
            }
        }
    }
    if (vp.outputs.length) {
        html += '<div class="dr-sep"></div><div class="dr-title2">Gives</div>'
            + vp.outputs.map((p) => `<div class="sy-val"><span><i class="sy-fam v-${e(ed.typed.family(p.type))}"></i>${e(p.label || p.key)}</span><b>${e(typeTitle(p.type))}</b></div>`).join('');
    }
    html += lastValuesHtml(ed, node, vp);
    html += '<div class="dr-btns"><button class="dr-btn" data-act="dup-sel">Duplicate</button>'
        + '<button class="dr-btn danger" data-act="del-sel">Delete</button></div>';
    return html;
}

// ---- Places ----

function placesTab(ed) {
    const list = placesOf(ed.doc, ed.cards);
    if (!list.length) {
        return '<div class="dr-hint">Cards that happen somewhere in the world list their places here: a line across a road (When a Car Crosses a Line), a prompt (When a Point Is Used).</div>'
            + '<div class="dr-none">No card here needs a place</div>';
    }
    const rows = list.map((x) => {
        const p = x.value;
        const t = 'node:' + x.node.id;
        return '<div class="dr-item open"><div class="dr-world-edit">'
            + `<div class="dr-row"><div class="dr-label link" data-act="goto-node" data-id="${e(x.node.id)}">${e(x.def.title)} · ${e(x.field.label || x.field.key)}`
            + `<span>${p ? e(placeText(p)) : 'not placed yet'}</span></div>`
            + `<div class="dr-pills">${p ? '<span class="dr-pill ok">Placed</span>' : '<span class="dr-pill warn">Not placed</span>'}</div></div>`
            + placeButtons(t, x.field.key, !!p)
            + '</div></div>';
    }).join('');
    return '<div class="dr-hint">Here puts it where you stand. Aim in the world hides this screen: aim at the ground and press E (the system\'s other places are drawn, and a line\'s other end with it).</div>' + rows;
}

// ---- Variables ----

function varsTab(ed) {
    const rows = ed.doc.vars.map((v) => {
        const t = 'var:' + v.id;
        const uses = ed.usesOfVar(v.id);
        let start = '';
        if (v.type === 'bool') start = segField(t, 'default', v.default, yesNo, { label: 'Starts as', fallback: false });
        else if (v.type === 'number') start = numberField(t, 'default', v.default, { label: 'Starts as', placeholder: '0' });
        else if (v.type === 'text') start = textField(t, 'default', v.default, { label: 'Starts as', max: 100 });
        return '<div class="dr-item open"><div class="dr-world-edit">'
            + `<div class="dr-row">${label('Name', 'letters, digits and _')}<input class="dr-field" type="text" value="${e(v.id)}" data-act-change="rename-var" data-id="${e(v.id)}" spellcheck="false"></div>`
            + selectField(t, 'type', v.type, VAR_TYPES, { label: 'Holds' })
            + segField(t, 'scope', v.scope || 'everyone', SCOPES, { label: 'Kept', fallback: 'everyone' })
            + start
            + (canRemember(v) ? segField(t, 'remember', v.remember === true, yesNo, { label: 'Remembered', hint: 'across restarts', fallback: false }) : '')
            + `<div class="dr-btns"><button class="dr-btn danger" data-act="remove-var" data-id="${e(v.id)}">Remove${uses ? ` (used by ${uses})` : ''}</button></div>`
            + '</div></div>';
    }).join('');
    return '<div class="dr-btns"><button class="dr-btn" data-act="add-var">+ Variable</button></div>'
        + '<div class="dr-hint">For everyone: one value the whole system shares. Per player: each character their own (gone when they log out, unless remembered). Per car: each car its own. Remembered (numbers, yes/no and text): kept across restarts.</div>'
        + (rows || '<div class="dr-none">No variables</div>');
}

// ---- Check ----

function checkTab(ed) {
    const dirty = ed.history.isDirty(ed.doc);
    const errors = ed.problemList.filter((p) => p.severity === 'error');
    const warns = ed.problemList.filter((p) => p.severity !== 'error');
    let html = '<div class="dr-btns"><button class="dr-btn" data-act="check">Check now</button></div>';
    if (ed.checkedAt) {
        html += errors.length || warns.length
            ? `<div class="dr-sum ${errors.length ? 'error' : 'warn'}"><i class="sy-glyph"></i>${errors.length} error${errors.length === 1 ? '' : 's'}, ${warns.length} warning${warns.length === 1 ? '' : 's'}</div>`
            : '<div class="dr-sum ok">No problems</div>';
        html += ed.problemList.map((p, i) => {
            const n = p.node && findNode(ed.doc, p.node);
            const def = n && ed.cards.get(n.type);
            const cards = problemCards(p).filter((id) => findNode(ed.doc, id));
            return `<div class="dr-prob ${p.severity === 'error' ? 'error' : 'warn'}${cards.length ? ' link' : ''}" data-act="goto-prob" data-i="${i}">`
                + '<i class="sy-glyph"></i>' + (n ? `<b>${e(def ? def.title : n.type)}</b> ` : '') + e(p.message) + '</div>';
        }).join('');
    } else {
        html += '<div class="dr-hint">Check reads the system the way the server will run it. Errors stop it from being switched on or tested; warnings do not.</div>';
    }
    // What it may do, and who said it may: the saved revision's (what an approval is for) unless it is
    // being edited, then what Check last said of the document as it is.
    const powers = (dirty ? ed.powers : ed.savedPowers) || '';
    html += '<div class="dr-sep"></div><div class="dr-title2">What it may do</div>';
    if (!powers) {
        html += '<div class="dr-sum">Nothing of value: no money, no items</div>';
    } else {
        html += `<div class="dr-sum warn">It may ${e(powersText(powers))}</div>`;
        html += ed.approvedOk
            ? `<div class="dr-hint">Revision ${ed.baseRev} is approved for that${ed.approvedBy ? ` by ${e(ed.approvedBy)}` : ''}.</div>`
            : `<div class="dr-hint">A systems admin approves revision ${ed.baseRev} for that before it is switched on${dirty ? ' (save first)' : ''}.</div>`;
        if (!ed.approvedOk && ed.admin && !dirty) {
            html += `<div class="dr-btns"><button class="dr-btn" data-act="approve">Approve revision ${ed.baseRev} to ${e(powersText(powers))}</button></div>`;
        }
    }
    html += '<div class="dr-sep"></div><div class="dr-title2">In the world</div>';
    if (ed.on) {
        html += `<div class="dr-sum ok">On, at revision ${ed.onRev}</div>`;
        if (ed.onRev !== ed.baseRev) html += `<div class="dr-hint">Revision ${ed.baseRev} is newer: switch it on to put it live.</div>`;
    } else {
        html += `<div class="dr-sum">${ed.system && ed.system.status === 'faulted' ? `Off: it switched itself off (${e(ed.system.reason || 'too many errors')})` : 'Off'}</div>`;
    }
    if (ed.admin) {
        html += '<div class="dr-btns">'
            + `<button class="dr-btn primary" data-act="activate"${dirty ? ' disabled' : ''}>Switch on revision ${ed.baseRev}</button>`
            + (ed.on ? '<button class="dr-btn" data-act="deactivate">Switch off</button>' : '')
            + '</div>'
            + (dirty ? '<div class="dr-hint">Save first: what is switched on is a saved revision.</div>' : '');
    } else {
        html += '<div class="dr-hint">A systems admin switches systems on and off.</div>';
    }
    return html;
}

// ---- Test ----

const LOG_LEVELS = [['', 'Everything'], ['error', 'Errors'], ['warn', 'Warnings'], ['info', 'Notes']];

function testTab(ed) {
    const t = ed.test;
    let html = '<div class="dr-hint">Test runs the system as it is now (saved or not) for you alone, beside the live one if it is on: the live one leaves you be until the test ends. No money moves (a Fine only says what it would do); items it gives you are real, and taken back when the test ends or starts again. Play it in the game; F9 comes back here with it still running, F5 starts it again.</div>';
    if (!t || t.status === 'none') {
        html += `<div class="dr-btns"><button class="dr-btn primary" data-act="test">Test it</button></div>`;
        if (ed.lastReport) html += reportHtml(ed, ed.lastReport, false);
        return html;
    }
    html += reportHtml(ed, t, t.status === 'running');
    return html;
}

function reportHtml(ed, r, live) {
    const errs = r.errors || 0;
    let html = live
        ? `<div class="dr-sum ok">Testing · ${Math.floor((r.seconds || 0) / 60)}m ${(r.seconds || 0) % 60}s · ${r.pulses || 0} going · ${r.steps || 0} cards run${errs ? ` · ${errs} error${errs === 1 ? '' : 's'}` : ''}</div>`
            + '<div class="dr-btns"><button class="dr-btn danger" data-act="test-stop">Stop the test</button>'
            + '<button class="dr-btn" data-act="test-play" title="Close this and play: the test keeps running">Play it</button>'
            + '<button class="dr-btn ghost" data-act="test">Start again</button></div>'
        : `<div class="dr-sum">Last test: ${r.steps || 0} cards run${errs ? `, ${errs} error${errs === 1 ? '' : 's'}` : ''}${r.reason ? ' · ' + e(r.reason) : ''}</div>`
            + '<div class="dr-btns"><button class="dr-btn ghost" data-act="clear-test">Clear</button></div>';
    const lines = (Array.isArray(r.log) ? r.log : Object.values(r.log || {}));
    const lvl = ed.logLevel || '', q = (ed.logQuery || '').toLowerCase();
    const shown = lines.filter((l) => (!lvl || l.level === lvl) && (!q || String(l.msg || '').toLowerCase().includes(q))).slice(-80).reverse();
    html += '<div class="dr-sep"></div><div class="dr-title2">Log</div>'
        + `<div class="sy-logbar"><select class="dr-field sy-log-level">${LOG_LEVELS.map(([v, t]) => `<option value="${v}"${v === lvl ? ' selected' : ''}>${t}</option>`).join('')}</select>`
        + `<input class="dr-field sy-log-search" type="text" placeholder="Filter" value="${e(ed.logQuery || '')}" spellcheck="false"></div>`
        + (shown.length ? '<div class="sy-log">' + shown.map((l) => {
            const n = l.node && findNode(ed.doc, l.node);
            const def = n && ed.cards.get(n.type);
            return `<div class="sy-log-line ${e(l.level || 'info')}${n ? ' link' : ''}"${n ? ` data-act="goto-node" data-id="${e(l.node)}"` : ''}>`
                + `<span class="sy-log-at">${e(String(l.ago || 0))}s</span>${l.level === 'error' ? '<i class="sy-glyph"></i>' : ''}`
                + (def ? `<b>${e(def.title)}</b> ` : '') + e(l.msg || '') + '</div>';
        }).join('') + '</div>' : '<div class="dr-none">Nothing yet</div>');
    if (live) html += '<div class="dr-hint">Hover a pin on the grid to see the last value it had.</div>';
    return html;
}

// ---- About ----

function aboutTab(ed) {
    let html = textField('doc', 'name', ed.doc.name, { label: 'Name', max: 80 })
        + textField('doc', 'description', ed.doc.description, { label: 'Description', max: 500, big: true });
    html += `<div class="dr-hint">Key ${e(ed.key)}${ed.system && ed.system.shortId ? ` · short id ${e(ed.system.shortId)} (what its names in the game are made from)` : ''}</div>`;
    html += '<div class="dr-sep"></div><div class="dr-title2">Saved revisions</div>';
    if (!ed.revisions) {
        html += '<div class="dr-btns"><button class="dr-btn" data-act="history">Show revisions</button></div>';
    } else if (!ed.revisions.length) {
        html += '<div class="dr-none">None</div>';
    } else {
        html += ed.revisions.map((r) => `<div class="dr-rev"><div><b>Revision ${r.rev}</b>`
            + `<span>${e(r.by || 'someone')} · ${e(when(r.at))}${r.note ? ' · ' + e(r.note) : ''}${r.approved ? ` · approved to ${e(powersText(r.approved))}` : ''}</span></div>`
            + `<button class="dr-btn ghost" data-act="load-rev" data-rev="${r.rev}">Open</button></div>`).join('');
    }
    if (ed.admin) {
        html += '<div class="dr-sep"></div><div class="dr-btns">'
            + `<button class="dr-btn danger" data-act="delete-system"${ed.on ? ' disabled title="Switch it off first"' : ''}>Delete this system</button></div>`;
    }
    return html;
}

export function renderTab(ed) {
    switch (ed.tab) {
        case 'cards': return cardsTab(ed);
        case 'card': return cardTab(ed);
        case 'places': return placesTab(ed);
        case 'vars': return varsTab(ed);
        case 'check': return checkTab(ed);
        case 'test': return testTab(ed);
        case 'about': return aboutTab(ed);
        default: return '';
    }
}

// ---- writing fields ----

/** The object a field edits. */
export function targetOf(ed, spec) {
    const i = spec.indexOf(':');
    const kind = i < 0 ? spec : spec.slice(0, i);
    const id = i < 0 ? '' : spec.slice(i + 1);
    const doc = ed.doc;
    if (kind === 'doc') return doc;
    if (kind === 'settings') return doc.settings;
    if (kind === 'node') { const n = findNode(doc, id); return n ? n.props : null; }
    if (kind === 'value') {
        const n = findNode(doc, id);
        if (!n) return null;
        if (!n.values || typeof n.values !== 'object' || Array.isArray(n.values)) n.values = {};
        return n.values;
    }
    if (kind === 'var') return doc.vars.find((v) => v.id === id) || null;
    return null;
}

/** What a field reading `any` holds: a number when it reads as one, true / false, else the text. */
function readAny(s) {
    const t = s.trim();
    if (t === '') return undefined;
    if (/^-?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?$/i.test(t)) return parseFloat(t);
    if (t === 'true') return true;
    if (t === 'false') return false;
    return s;
}

/** Write a field's value into the document. Answers true when something changed. */
export function writeField(ed, el) {
    const obj = targetOf(ed, el.dataset.t);
    if (!obj) return false;
    const k = el.dataset.k;
    const before = JSON.stringify(obj[k]);
    const f = el.dataset.f;
    if (f === 'number') {
        const n = parseFloat(el.value);
        if (isNaN(n)) delete obj[k]; else obj[k] = n;
    } else if (f === 'any') {
        const v = readAny(el.value);
        if (v === undefined) delete obj[k]; else obj[k] = v;
    } else if (f === 'select' || f === 'text') {
        if (el.value === '' && k !== 'name') delete obj[k]; else obj[k] = el.value;
    }
    return JSON.stringify(obj[k]) !== before;
}

/** A segmented key pressed. */
export function writeSeg(ed, el) {
    const obj = targetOf(ed, el.dataset.t);
    if (!obj) return false;
    let v;
    try { v = JSON.parse(el.dataset.v); } catch (_) { return false; }
    if (obj[el.dataset.k] === v) return false;
    obj[el.dataset.k] = v;
    return true;
}

export { FAMILY_TITLE };
