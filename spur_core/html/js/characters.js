import { NuiRouter } from './router.js';
import { nuiCallback, escapeHtml } from './utils.js';
import { openPadKeyboard } from './pad-keyboard.js';
import { createRing } from './pad-ring.js';

// ========================================
// CHARACTER SELECT — THE NAME STRIP
// ========================================
//
// Every slot is a place in the world with its own camera, weather and pose, and this file draws
// what sits over it: the characters' NAMES along the bottom left, the chosen one white, the others
// dimmed (no stroke or dot under it: Josh, 1 Nov). Below
// them, when that character was last played and what you can do.
//
// Clicking a name asks Lua to go there; Lua puts the screen behind a curtain, builds the shot, and
// lifts it again. Nothing here talks to the world or knows where anything is on screen.
//
// SELECTION IS TRAVEL. The name you picked is the shot you are in, and the line under the names
// says what you can do there: Play or Delete for a character, Create for the empty slot.
//
// ONE "NEW", NOT ONE PER EMPTY SLOT. Characters fill the slots in order (client/charselect.lua),
// so the empty slots all come after the last character. The strip shows the characters and then
// the FIRST empty slot as "New" — four "New"s in a row for a new player would be three too many.

let cards = [];            // [{ index, occupied, firstName, lastName, cash, lastPlayed }], one per slot
let characterCount = 0;
let maxCharacters = 4;
let selectedIndex = 1;     // slot index; the screen opens on 1
let confirming = false;    // Delete pressed: waiting for "Delete for good" or "Keep"

// ---------- helpers ----------

/**
 * When they last played, to the two largest units: "Last played 23 minutes
 * ago", "Last played 5 hours 12 minutes ago", "Last played 3 days 14 hours ago". A month or more
 * back it gives the date instead.
 *
 * The server sends the moment as epoch milliseconds (oxmysql turns the TIMESTAMP into one), so
 * the player's own time zone does not come into it — only their PC's clock.
 */
function lastPlayedText(ts) {
    if (!ts) return 'Never played';
    // A string is the older 'YYYY-MM-DD HH:MM:SS' form, which Safari-era parsers dislike; the
    // space becomes a T so it is unambiguous.
    const d = new Date(typeof ts === 'number' ? ts : String(ts).replace(' ', 'T'));
    if (isNaN(d.getTime())) return 'Never played';

    const mins = Math.floor((Date.now() - d.getTime()) / 60000);
    if (mins < 1) return 'Last played just now';   // also a clock running behind the server's

    const days  = Math.floor(mins / 1440);
    const hours = Math.floor((mins % 1440) / 60);
    const rest  = mins % 60;
    const unit = (n, word) => n + ' ' + word + (n === 1 ? '' : 's');

    if (days >= 30) {
        return 'Last played ' + d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
    }
    let ago;
    if (days > 0)       ago = unit(days, 'day') + (hours ? ' ' + unit(hours, 'hour') : '');
    else if (hours > 0) ago = unit(hours, 'hour') + (rest ? ' ' + unit(rest, 'minute') : '');
    else                ago = unit(rest, 'minute');
    return 'Last played ' + ago + ' ago';
}

function cardByIndex(i) { return cards.find(c => c.index === i) || null; }

function fullName(c) { return ((c.firstName || '') + ' ' + (c.lastName || '')).trim(); }

/** What the strip shows: every character, then the first empty slot while there is room. */
function entries() {
    const out = cards.filter(c => c.occupied);
    if (characterCount < maxCharacters) {
        const vacant = cards.find(c => !c.occupied);
        if (vacant) out.push(vacant);
    }
    return out;
}

const ICON_PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3"'
    + ' stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';

const ICON_PLAY = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">'
    + '<path d="M7 4.5v15a1 1 0 0 0 1.5.86l12.5-7.5a1 1 0 0 0 0-1.72L8.5 3.64A1 1 0 0 0 7 4.5z"/></svg>';

const ICON_BIN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"'
    + ' stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
    + '<path d="M4 7h16M10 11v6M14 11v6M5 7l1 12a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2l1-12M9 7V4h6v3"/></svg>';

// ---------- rendering ----------

function nameHtml(c) {
    const selected = c.index === selectedIndex;
    const label = c.occupied ? '<span>' + escapeHtml(fullName(c)) + '</span>' : ICON_PLUS + '<span>New</span>';
    return '<button type="button" class="cs-name' + (selected ? ' selected' : '') + (c.occupied ? '' : ' new') + '"'
         + ' aria-pressed="' + (selected ? 'true' : 'false') + '"'
         + ' data-action="csSelect" data-index="' + c.index + '">' + label + '</button>';
}

/**
 * Under the names: the pill with the quieter action under it (#cs-actions is a column), and
 * beside them when that character was last played.
 */
function footHtml(c) {
    if (!c) return { meta: '', warn: false, actions: '' };

    // Step two of three: the question. "Yes, delete" opens the last step (the delete form).
    if (confirming && c.occupied) {
        return {
            meta: 'Delete ' + escapeHtml(fullName(c)) + '? This cannot be undone',
            warn: true,
            actions: '<button type="button" class="cs-play danger" data-action="openDeleteForm">Yes, delete</button>'
                   + '<button type="button" class="cs-textbtn" data-action="keepSelected">Keep</button>',
        };
    }

    if (c.occupied) {
        return {
            meta: escapeHtml(lastPlayedText(c.lastPlayed)),
            warn: false,
            actions: '<button type="button" class="cs-play" data-action="playSelected">' + ICON_PLAY + '<span>Play</span></button>'
                   + '<button type="button" class="cs-textbtn danger" data-action="confirmDeleteSelected">' + ICON_BIN + '<span>Delete</span></button>',
        };
    }

    if (characterCount >= maxCharacters) {
        return { meta: 'Every slot is taken', warn: false, actions: '' };
    }
    return {
        meta: 'Nobody here yet',
        warn: false,
        actions: '<button type="button" class="cs-play" data-action="toggleCreateForm">' + ICON_PLUS + '<span>Create character</span></button>',
    };
}

/** The name size steps down until every name fits on one line (long names, four characters). */
const NAME_SIZES = [61, 54, 47, 40, 34];

/** Past the smallest size (a server allowing many characters, up to 30) the row scrolls
 *  sideways instead, and the chosen name is kept in view (keepChosenInView). */
function fitNames(row) {
    row.classList.remove('cs-names-scroll');
    for (let i = 0; i < NAME_SIZES.length; i++) {
        row.style.setProperty('--cs-name-size', NAME_SIZES[i] + 'px');
        if (row.scrollWidth <= row.clientWidth) return;
    }
    row.classList.add('cs-names-scroll');
}

function keepChosenInView(row) {
    if (!row.classList.contains('cs-names-scroll')) return;
    const chosen = row.querySelector('.cs-name.selected');
    if (chosen) chosen.scrollIntoView({ inline: 'center', block: 'nearest' });
}

function render() {
    const row = document.getElementById('cs-names');
    row.innerHTML = entries().map(nameHtml).join('');
    fitNames(row);
    keepChosenInView(row);
    // The names' face (css/characters.css) loads the first time it is used, and widths measured
    // before that are the fallback's: measured again once it is in.
    if (document.fonts && document.fonts.status !== 'loaded') {
        document.fonts.ready.then(() => { fitNames(row); keepChosenInView(row); });
    }

    const foot = footHtml(cardByIndex(selectedIndex));
    const meta = document.getElementById('cs-meta');
    meta.innerHTML = foot.meta;
    meta.classList.toggle('warn', foot.warn);
    document.getElementById('cs-actions').innerHTML = foot.actions;
}

/** "Last played 23 minutes ago" goes stale while the screen sits open, so the line is written
 *  again every half minute. Only its text: rebuilding the buttons would take focus off them. */
let clockTimer = null;

function startClock() {
    if (clockTimer) return;
    clockTimer = setInterval(() => {
        if (confirming) return;
        const c = cardByIndex(selectedIndex);
        if (!c || !c.occupied) return;
        document.getElementById('cs-meta').textContent = lastPlayedText(c.lastPlayed);
    }, 30000);
}

function stopClock() {
    if (clockTimer) clearInterval(clockTimer);
    clockTimer = null;
}

// ---------- interaction ----------

/** Picking a name travels to its shot. */
function csSelect(i) {
    if (i === selectedIndex) return;
    selectedIndex = i;
    confirming = false;
    // Repaint FIRST. The journey takes as long as streaming a corner of the map takes, and a
    // strip that did not answer until it finished would feel broken.
    render();
    nuiCallback('selectSlot', { index: i });
}

function playSelected() {
    const c = cardByIndex(selectedIndex);
    if (!c || !c.occupied) return;
    nuiCallback('selectCharacter', { index: c.index });
}

// ---------- deleting: three steps ----------
//
// Delete, then the question in the strip ("Yes, delete" / Keep), then a form
// where the character's name has to be typed and the button HELD for ten seconds. Only the end of
// the hold asks the server. A pad can do none of it: typing is the keyboard's.

/** Step one: Delete turns the line under the names into the question. */
function confirmDeleteSelected() {
    const c = cardByIndex(selectedIndex);
    if (!c || !c.occupied) return;
    confirming = true;
    render();
}

function keepSelected() {
    if (!confirming) return;
    confirming = false;
    render();
}

/** How long the button has to be held down. */
const HOLD_MS = 10000;

/** The name as it has to be typed: spaces tidied, any case. */
function sameName(typed, name) {
    const tidy = (s) => String(s || '').trim().replace(/\s+/g, ' ').toLowerCase();
    return tidy(typed) !== '' && tidy(typed) === tidy(name);
}

function deleteFormOpen() {
    return document.getElementById('delete-form').classList.contains('visible');
}

/** Step three: the form. From "Yes, delete". */
function openDeleteForm() {
    const c = cardByIndex(selectedIndex);
    if (!c || !c.occupied || !confirming) return;
    document.getElementById('del-name').textContent = fullName(c);
    const input = document.getElementById('inp-del-name');
    input.value = '';
    input.placeholder = fullName(c);
    holdReset();
    updateHoldReady();
    document.getElementById('delete-form').classList.add('visible');
    document.getElementById('cs-modal').classList.add('visible');
    input.focus();
}

/** Keep, Escape, the pad's back, or the screen going away. Back to the strip, not deleting. */
function closeDeleteForm() {
    holdReset();
    const form = document.getElementById('delete-form');
    if (!form.classList.contains('visible')) return;
    form.classList.remove('visible');
    document.getElementById('cs-modal').classList.remove('visible');
    document.getElementById('inp-del-name').value = '';
    confirming = false;
    render();
}

/** The hold button only wakes up once the name is typed right. */
function updateHoldReady() {
    const c = cardByIndex(selectedIndex);
    const ok = !!c && sameName(document.getElementById('inp-del-name').value, fullName(c));
    const btn = document.getElementById('del-hold');
    btn.disabled = !ok;
    if (!ok) holdReset();
}

// THE HOLD. Timed by the clock, not by counting frames, so a slow frame cannot shorten it. Letting
// go, leaving the button, the window losing focus or the name changing all start it again from 0.
let holdStart = 0;
let holdFrame = 0;

function holdLabel(text) { document.getElementById('del-hold-label').textContent = text; }

function holdBegin() {
    const btn = document.getElementById('del-hold');
    if (btn.disabled || holdFrame) return;
    holdStart = performance.now();
    btn.classList.add('holding');
    const fill = btn.querySelector('.del-hold-fill');
    const tick = (now) => {
        const done = Math.min(1, (now - holdStart) / HOLD_MS);
        fill.style.transform = 'scaleX(' + done + ')';
        if (done >= 1) {
            holdFrame = 0;
            finishDelete();
            return;
        }
        holdLabel('Keep holding — ' + Math.ceil((HOLD_MS - (now - holdStart)) / 1000) + 's');
        holdFrame = requestAnimationFrame(tick);
    };
    holdFrame = requestAnimationFrame(tick);
}

function holdReset() {
    if (holdFrame) cancelAnimationFrame(holdFrame);
    holdFrame = 0;
    const btn = document.getElementById('del-hold');
    if (!btn) return;
    btn.classList.remove('holding');
    btn.querySelector('.del-hold-fill').style.transform = 'scaleX(0)';
    holdLabel('Hold to delete');
}

/** Held for the whole ten seconds: now the server is asked. */
function finishDelete() {
    const c = cardByIndex(selectedIndex);
    const form = document.getElementById('delete-form');
    form.classList.remove('visible');
    document.getElementById('cs-modal').classList.remove('visible');
    document.getElementById('inp-del-name').value = '';
    holdReset();
    confirming = false;
    render();
    if (c && c.occupied) nuiCallback('deleteCharacter', { index: c.index });
}

(function bindDeleteHold() {
    const btn = document.getElementById('del-hold');
    const input = document.getElementById('inp-del-name');
    if (!btn || !input) return;

    input.addEventListener('input', updateHoldReady);

    btn.addEventListener('pointerdown', (e) => {
        if (e.button !== 0) return;
        e.preventDefault();
        holdBegin();
    });
    ['pointerup', 'pointerleave', 'pointercancel'].forEach((type) => btn.addEventListener(type, holdReset));

    // The keyboard can hold it too: Space or Enter down on the focused button, up to let go.
    btn.addEventListener('keydown', (e) => {
        if ((e.key === ' ' || e.key === 'Enter') && !e.repeat) { e.preventDefault(); holdBegin(); }
    });
    btn.addEventListener('keyup', (e) => {
        if (e.key === ' ' || e.key === 'Enter') holdReset();
    });

    window.addEventListener('blur', holdReset);
})();

// ---------- create form ----------
//
// Kept as a panel: there is no way to type a name by looking at scenery.

const isPad = () => document.documentElement.dataset.input === 'pad';
const formOpen = () => document.getElementById('create-form').classList.contains('visible');

/* ON A CONTROLLER. The D-pad walks a white ring (pad-ring.js) over the fields and
   the two buttons. A on a name or the date types it on whip's keyboard (pad-keyboard.js), A on Gender
   steps to the next one, A on a button presses it; B closes the form, as Cancel. */
const formRing = createRing({
    root: () => document.getElementById('create-form'),
    selector: '#inp-first, #inp-last, #inp-dob, #inp-gender, .btn-submit, .btn-cancel',
});

/** A date typed on the keyboard as the field holds it (YYYY-MM-DD), or null. Eight digits will do. */
function typedDate(text) {
    const d = String(text).replace(/\D/g, '');
    if (d.length !== 8) return null;
    const iso = `${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6, 8)}`;
    const at = new Date(iso + 'T00:00:00Z');
    // 1995-02-30 is not a day: the Date rolls it over, so it comes back as something else.
    return (!isNaN(at) && at.toISOString().slice(0, 10) === iso) ? iso : null;
}

/** A on the ringed control. */
function formPress(el) {
    if (!el) { formRing.set(document.getElementById('inp-first')); return; }
    if (el.id === 'inp-gender') {
        el.selectedIndex = (el.selectedIndex + 1) % el.options.length;
        return;
    }
    if (el.id === 'inp-dob') {
        openPadKeyboard({
            title: 'Date of birth (YYYY-MM-DD)', value: el.value, numeric: true, maxLength: 10,
            onDone: (text) => {
                if (!formOpen()) return;
                const iso = typedDate(text);
                if (!iso) { uiNotify({ text: 'Type the date as year-month-day, like 1995-04-12', type: 'error', duration: 4000 }); return; }
                if (el.max && iso > el.max) { uiNotify({ text: 'The date of birth must be on or before ' + el.max, type: 'error', duration: 4000 }); return; }
                el.value = iso;
            },
        });
        return;
    }
    if (el.tagName === 'INPUT') {
        openPadKeyboard({
            title: el.id === 'inp-first' ? 'First name' : 'Last name', value: el.value, maxLength: el.maxLength > 0 ? el.maxLength : 30,
            onDone: (text) => { if (formOpen()) el.value = text.trim(); },
        });
        return;
    }
    el.click();   // Create / Cancel: the mouse's own click (bindCsActions)
}

function toggleCreateForm() {
    const form = document.getElementById('create-form');
    if (form.classList.contains('visible')) { hideCreateForm(); }
    else {
        form.classList.add('visible');
        document.getElementById('cs-modal').classList.add('visible');
        // On a pad the ring is the highlight (below); a focused field would be a second one.
        if (isPad()) formRing.set(document.getElementById('inp-first'));
        else document.getElementById('inp-first').focus();
    }
}

function hideCreateForm() {
    const form = document.getElementById('create-form');
    form.classList.remove('visible');
    document.getElementById('cs-modal').classList.remove('visible');
    formRing.clear();
    document.getElementById('inp-first').value = '';
    document.getElementById('inp-last').value = '';
    document.getElementById('inp-dob').value = '';
    document.getElementById('inp-gender').value = 'male';
}

function submitCreate() {
    const firstName = document.getElementById('inp-first').value.trim();
    const lastName = document.getElementById('inp-last').value.trim();
    const dob = document.getElementById('inp-dob').value;
    const gender = document.getElementById('inp-gender').value;
    if (!firstName || firstName.length < 2) { uiNotify({ text: 'First name must be at least 2 characters', type: 'error', duration: 4000 }); return; }
    if (!lastName || lastName.length < 2) { uiNotify({ text: 'Last name must be at least 2 characters', type: 'error', duration: 4000 }); return; }
    if (!dob) { uiNotify({ text: 'Please select a date of birth', type: 'error', duration: 4000 }); return; }
    nuiCallback('createCharacter', { firstName, lastName, dateOfBirth: dob, gender });
}

/** The strip's main action: Play a character, or open the form on the empty slot. */
function primaryAction() {
    const c = cardByIndex(selectedIndex);
    if (!c) return;
    if (c.occupied) { playSelected(); return; }
    if (characterCount < maxCharacters) toggleCreateForm();
}

// ---------- keyboard ----------
// A key SCOPE, not a raw document listener. Priority 5: the character scene is a full-screen
// modal that exists only pre-spawn, so nothing but the creator (0) can legitimately outrank it.

NuiRouter.registerKeyScope({
    name: 'character-select',
    priority: 5,
    isOpen: () => {
        const app = document.getElementById('app');
        return !!app && app.style.display === 'block';
    },
    onKey: (e) => {
        if (document.getElementById('create-form').classList.contains('visible')) {
            if (e.key === 'Enter') { e.preventDefault(); submitCreate(); }
            else if (e.key === 'Escape') { e.preventDefault(); hideCreateForm(); }
            return;
        }

        // The delete form: typing goes to its field and holding to its button (their own
        // listeners). Only Escape is ours — and nothing here travels, so arrow keys stay in the
        // field.
        if (deleteFormOpen()) {
            if (e.key === 'Escape') { e.preventDefault(); closeDeleteForm(); }
            return;
        }

        // Asking about a delete: Escape keeps them. Enter does NOT delete — that takes the click.
        if (confirming) {
            if (e.key === 'Escape') { e.preventDefault(); keepSelected(); return; }
            if (e.key === 'Enter') { e.preventDefault(); return; }
        }

        if (e.key === 'Enter') { e.preventDefault(); primaryAction(); return; }

        // Left/right walk the names — and therefore travel — so the screen is usable without a
        // mouse. There is no "deselect": you are always somewhere.
        if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
            e.preventDefault();
            csStep(e.key === 'ArrowRight' ? 1 : -1);
        }
    },

    /* CONTROLLER. See client/controller.lua — a gamepad produces no keyboard events, so this
       arrives as intent rather than as a synthesised arrow key.

       A on the empty place opens the create form, which the pad fills with the ring and whip's
       keyboard (formPress, above). A pad still cannot delete: that is a held click. */
    onNav: (nav) => {
        if (formOpen()) {
            if (nav === 'back') { hideCreateForm(); return; }
            if (nav === 'select') { formPress(formRing.el()); return; }
            if (nav === 'up' || nav === 'down' || nav === 'left' || nav === 'right') {
                if (!formRing.el()) formRing.set(document.getElementById('inp-first'));
                else formRing.step(nav);
            }
            return;
        }
        if (deleteFormOpen()) {
            if (nav === 'back') closeDeleteForm();
            return;
        }
        if (confirming) {
            if (nav === 'back') keepSelected();
            return;
        }

        if (nav === 'select') { primaryAction(); return; }
        if (nav === 'left')  { csStep(-1); return; }
        if (nav === 'right') { csStep(1); return; }
    },

    // The hint strip, on a controller (controller.js): what onNav above does right now. On the
    // empty place A is New only while there is room for one more (primaryAction). In Whiplash's look (css/ui.css
    // #pad-hints.pad-hints-bare), under the names (Josh, 1 Nov).
    padHintsLook: 'bare',
    padHints: () => {
        if (formOpen()) {
            const el = formRing.el();
            const a = !el ? null
                : el.id === 'inp-gender' ? 'Change'
                : el.tagName === 'INPUT' ? 'Type'
                : el.classList.contains('btn-submit') ? 'Create' : 'Cancel';
            return a ? [['dpad', 'Move'], ['a', a], ['b', 'Cancel']] : [['dpad', 'Move'], ['b', 'Cancel']];
        }
        if (deleteFormOpen()) return [['b', 'Back']];
        if (confirming) return [['b', 'Keep']];
        const c = cardByIndex(selectedIndex);
        if (c && c.occupied) return [['dpad', 'Choose'], ['a', 'Play']];
        return (c && characterCount < maxCharacters) ? [['dpad', 'Choose'], ['a', 'New']] : [['dpad', 'Choose']];
    },
});

/** Walk the selection by one name, wrapping at both ends — the keyboard's and the pad's. */
function csStep(delta) {
    const list = entries();
    if (!list.length) return;
    const at = list.findIndex(c => c.index === selectedIndex);
    const next = (at < 0)
        ? 0
        : (at + delta + list.length) % list.length;
    csSelect(list[next].index);
}

// ========================================
// DELEGATED ACTIONS
//
// One listener on #app dispatching a Map of data-action names, no inline handlers and no
// propagation tricks.
// ========================================
(function bindCsActions() {
    const root = document.getElementById('app');
    const CLICK = new Map([
        ['csSelect',              el => csSelect(Number(el.dataset.index))],
        ['playSelected',          () => playSelected()],
        ['confirmDeleteSelected', () => confirmDeleteSelected()],
        ['openDeleteForm',        () => openDeleteForm()],
        ['closeDeleteForm',       () => closeDeleteForm()],
        ['keepSelected',          () => keepSelected()],
        ['toggleCreateForm',      () => toggleCreateForm()],
        ['submitCreate',          () => submitCreate()],
    ]);
    root.addEventListener('click', (e) => {
        const el = e.target.closest('[data-action]');
        if (!el) return;
        const fn = CLICK.get(el.dataset.action);
        if (fn) fn(el);
    });
})();

// ========================================
// ROUTER REGISTRATION — this file's NUI actions, beside the state they write.
// ========================================
NuiRouter.register('showCharacters', (d) => {
    closeDeleteForm();   // a fresh list rebuilds the screen: nothing half-deleted carries over
    cards = d.cards || [];
    characterCount = d.characterCount || 0;
    maxCharacters = d.maxCharacters || 4;
    // Lua opens on slot 1 and travels there itself; the strip just has to agree.
    selectedIndex = 1;
    confirming = false;
    // 'block', not 'flex' — the overlay positions its pieces absolutely over the world. Shown
    // BEFORE the render, so fitNames measures real widths rather than a hidden, zero-width row.
    document.getElementById('app').style.display = 'block';
    render();
    startClock();
});
// Bring the overlay back without rebuilding it — used when a character selection is abandoned,
// so the player is not left staring at a black screen.
NuiRouter.register('show', () => {
    document.getElementById('app').style.display = 'block';
    startClock();
});
NuiRouter.register('hide', () => {
    document.getElementById('app').style.display = 'none';
    closeDeleteForm();
    confirming = false;
    stopClock();
    hideCreateForm();
});
