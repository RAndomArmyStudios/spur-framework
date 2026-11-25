import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';
import { setCapsuleMode, capsuleMode } from './capsule.js';
import { openPadKeyboard, closePadKeyboard } from './pad-keyboard.js';

/* ========================================
   COMPOSER — one line of text, typed into the capsule.

   The page half of client/composer.lua. Read that file's header first: it explains why the text
   field lives in spur_core at all when the only thing using it today is whip_chat.

   WHAT MOVED HERE, AND WHY IT MOVED RATHER THAN STAYING PUT.

   The input, the character counter, the command-suggestion list and the input history all used
   to live in whip_chat's page. They came across with the field, and the suggestions are the
   reason: filtering them is driven by WHAT YOU HAVE TYPED SO FAR. Left in whip_chat, every
   keystroke would have to cross the NUI boundary into Lua, hop resources, filter, and come back
   — and Tab-completion would have to make the same trip in the other direction. Moving the list
   means whip_chat pushes it ONCE, when its command set changes, and this file filters locally as
   you type.

   WHAT DELIBERATELY DID NOT MOVE: the message log, the templates, the colour codes, the mode
   registry and every byte of transport. whip_chat is still chat. This file is a text field that
   has never heard of chat — which is why a shop or a door editor can use it for a single typed
   line without pulling chat in behind it.
   ======================================== */

// The capsule element itself is deliberately NOT grabbed here. Which state it is in is capsule.js's
// to decide and nobody else's — reaching for the container from this file would give the composer
// a second way to change the mode, and two owners of one exclusive state is how it ends up in two
// states at once.
const elBubble     = document.getElementById('capsuleBubble');
// The glyph slot inside the bubble's disc. Written to; the disc and fill around it are not.
const elBubbleIcon = elBubble ? elBubble.querySelector('.sh-icon') : null;
const elInput     = document.getElementById('capsuleInput');
const elCount     = document.getElementById('capsuleCount');
const elSuggest   = document.getElementById('capsuleSuggestions');       // the frame: shown or not
const elSugList   = document.getElementById('capsuleSuggestionsList');   // the rows, scrolled inside it

/** The counter stays out of the way until the line is long enough to be worth watching. */
const COUNT_SHOWS_AT = 200;

/** How many past lines to remember. */
const MAX_HISTORY = 50;

/* ---- session state, all reset by open() ---- */
let isOpen       = false;
// ON A CONTROLLER (Chat on the wheel). The line is typed on whip's pad keyboard
// (js/pad-keyboard.js), in the keyboard's own text window above the keys, instead of in the capsule:
// the player sees what they type where they type it. The capsule stays as it is. Done hands the text to
// submit() as Enter does, so it goes through the same composerResult as a typed line. No modes on the keys;
// the keyboard's own words finish a / command's name from `suggestions`.
let padMode      = false;
const PAD_KEYBOARD_ID = 'composer';   // which keyboard is ours (closePadKeyboard)
let maxLength    = 256;
let modes        = [];       // [{ name, displayName, color }]
let modeIndex    = -1;       // -1 means "no mode", which is a valid answer
let suggestions  = [];       // [{ name, help, params }]
let filteredSug  = [];

/* ---- the minimap makes room ----
   The list floats up over the bottom-left corner, where the minimap sits (in a car, or on foot with
   it on). While the line is a command, the radar steps aside: client/hud.lua decides, this only
   says when. Sent on a change, never per keystroke. */
let commandLine = false;

function tellCommandLine(on) {
    if (on === commandLine) return;
    commandLine = on;
    nuiCallback('composerCommandList', { open: on });
}

/* ---- history survives between opens, which is the whole point of it ---- */
const history   = [];
let historyIndex = -1;
let historyDraft = '';

/* ========================================
   THE BUBBLE

   In stats mode this slot holds the microphone gauge. In composer mode it holds a glyph that
   says what pressing Enter will do — and it carries the MODE as well as the icon.

   ONE OBJECT DOING BOTH JOBS IS THE POINT. whip_chat had a separate `SAY` / `ME` / `OOC` chip
   sitting beside its input. A capsule row has no room for a bubble AND a chip AND a field, and
   two small objects competing at the left edge is exactly the visual clutter this whole change
   exists to remove. The bubble already has to be there, so it carries the mode.
   ======================================== */

/** Material "chat bubble" — one path, matching the shape buildStatElement expects elsewhere. */
const ICON_CHAT = 'M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z';

// THE COMMAND STATE USES A TEXT GLYPH, NOT AN ICON. `/` is the character the player actually
// typed to get there, so it says what happened more directly than any drawn symbol would — and
// it matches the two-letter mode glyph below, so the bubble has one text treatment rather than
// an icon for some states and letters for others.

function bubbleSvg(path) {
    return '<svg viewBox="0 0 24 24"><path fill="currentColor" d="' + path + '"/></svg>';
}

/**
 * Repaint the bubble for the current mode / command state.
 *
 * ONLY THE GLYPH AND THE TINT ARE WRITTEN — never the bubble's own innerHTML. The disc, its
 * white ring and its fill are static markup (see index.html), and replacing them would rebuild
 * .sh-fill from scratch on every keystroke, restarting the 0.4s colour transition it carries and
 * turning a smooth re-tint into a flicker.
 *
 * Mirrors whip_chat's old refreshModeChip(): a line starting with `/` is a command whatever mode
 * is selected, because that is what Enter will actually do with it.
 */
function refreshBubble() {
    if (!elBubbleIcon) return;

    const isCommand = elInput.value.charAt(0) === '/';

    if (isCommand) {
        elBubbleIcon.innerHTML = '<span class="cap-bubble-glyph">/</span>';
        // A command is not a mode, so it does not borrow a mode's colour. Signal Blue is what
        // whip uses everywhere else to mean "this is the thing that will happen".
        elBubble.style.setProperty('--cap-bubble-color', 'var(--ui-accent)');
        elBubble.title = 'Command';
        return;
    }

    const mode = modeIndex >= 0 ? modes[modeIndex] : null;
    const label = mode ? String(mode.displayName || mode.name) : '';

    // NO MODE IS THE COMMON CASE and it gets the plain chat glyph. A named mode gets its first
    // two letters instead, because at this size a per-mode icon set would be four pixels of
    // difference and "OO" is unambiguous where a second speech bubble is not.
    elBubbleIcon.innerHTML = label
        ? '<span class="cap-bubble-glyph">' + label.slice(0, 2).toUpperCase() + '</span>'
        : bubbleSvg(ICON_CHAT);

    // A full white core, the same thing a full stat gauge reads as: live, and listening. A mode
    // with a colour of its own overrides it.
    elBubble.style.setProperty(
        '--cap-bubble-color',
        (mode && mode.color) ? mode.color : 'var(--sh-disc-fill)'
    );
    elBubble.title = label || 'Say';
}

function cycleMode() {
    if (modes.length === 0) return;
    // Wraps through -1 ("no mode") deliberately — the same cycle whip_chat had, so a player who
    // over-shoots gets back to plain Say without going all the way round again.
    modeIndex = modeIndex + 1 >= modes.length ? -1 : modeIndex + 1;
    refreshBubble();
}

function currentMode() {
    return modeIndex >= 0 && modes[modeIndex] ? modes[modeIndex].name : null;
}

/* ========================================
   SUGGESTIONS

   Ported from whip_chat/html/js/chat.js: the filtering and the parameter chips against the same
   data shape. The list arrives from whip_chat once per command-set change and is filtered here as
   you type.

   A LIST TO READ, NOT TO PICK FROM. The arrows go through what you sent before (recallHistory), so
   nothing in the list is selected; Tab finishes the name with the top row.
   ======================================== */

/** Which parameter is the caret sitting in? Only called once past the command name. */
function activeParamIndex(text) {
    const parts = text.split(' ');
    // Clamped at 0: `/tp ` splits to two parts, which would otherwise be index -1 and highlight
    // nothing at the exact moment the first parameter becomes the thing you are typing.
    return Math.max(0, parts.length - 2);
}

function hideSuggestions() {
    elSuggest.classList.remove('visible');
    elSugList.innerHTML = '';
    filteredSug = [];
}

function refreshSuggestions() {
    if (!elSuggest || !elSugList) return;

    const text = elInput.value;

    // Suggestions are for commands. A plain chat line has nothing to suggest, and showing the
    // whole command list the moment the box opens would bury the screen for the common case.
    if (text.charAt(0) !== '/') {
        hideSuggestions();
        return;
    }

    const firstSpace = text.indexOf(' ');
    const typedName  = firstSpace === -1 ? text : text.slice(0, firstSpace);

    // THE MATCH CHANGES ONCE YOU ARE PAST THE COMMAND NAME. Before the first space it is a PREFIX
    // match, so you see everything you might be reaching for. After it the command is settled, so
    // it is an EXACT match: one row, showing that command's parameter hints (`/tp 100` shows x, y, z,
    // not `/tpm` and `/tpwaypoint` too).
    filteredSug = firstSpace === -1
        ? suggestions.filter((s) => s.name.startsWith(typedName))
        : suggestions.filter((s) => s.name === typedName);

    if (filteredSug.length === 0) {
        hideSuggestions();
        return;
    }

    const paramIdx = firstSpace === -1 ? -1 : activeParamIndex(text);

    elSugList.innerHTML = '';
    elSugList.scrollTop = 0;
    filteredSug.forEach((sug) => {
        const row = document.createElement('div');
        row.className = 'cap-sug';

        const name = document.createElement('span');
        name.className = 'cap-sug-name';
        name.textContent = sug.name;
        row.appendChild(name);

        if (Array.isArray(sug.params) && sug.params.length > 0) {
            const wrap = document.createElement('span');
            wrap.className = 'cap-sug-params';
            sug.params.forEach((p, pi) => {
                const chip = document.createElement('span');
                chip.className = 'cap-sug-param' + (pi === paramIdx ? ' active' : '');
                chip.textContent = p.name;
                chip.title = p.help || '';
                wrap.appendChild(chip);
            });
            row.appendChild(wrap);
        }

        if (sug.help) {
            const help = document.createElement('span');
            help.className = 'cap-sug-help';
            help.textContent = sug.help;
            row.appendChild(help);
        }

        elSugList.appendChild(row);
    });

    elSuggest.classList.add('visible');
}

/** Tab: the command's name finished from the top row. */
function completeSuggestion() {
    if (!filteredSug[0]) return;
    const name = filteredSug[0].name;
    const sp   = elInput.value.indexOf(' ');
    const rest = sp === -1 ? '' : elInput.value.slice(sp);
    elInput.value = name + (rest || ' ');
    onInputChanged();
}

/* ========================================
   INPUT
   ======================================== */

function onInputChanged() {
    const text = elInput.value;

    elInput.classList.toggle('is-command', text.charAt(0) === '/');
    refreshBubble();
    refreshSuggestions();
    tellCommandLine(isOpen && !padMode && text.charAt(0) === '/');

    const left = maxLength - text.length;
    elCount.textContent = String(left);
    elCount.classList.toggle('visible', text.length >= COUNT_SHOWS_AT);
    elCount.classList.toggle('at-limit', text.length >= maxLength);
}

function pushHistory(text) {
    if (!text) return;
    if (history[0] === text) return;      // no consecutive duplicates
    history.unshift(text);
    while (history.length > MAX_HISTORY) history.pop();
}

function recallHistory(direction) {
    if (history.length === 0) return;

    if (historyIndex === -1 && direction > 0) historyDraft = elInput.value;

    historyIndex += direction;
    if (historyIndex < -1) historyIndex = -1;
    if (historyIndex >= history.length) historyIndex = history.length - 1;

    elInput.value = historyIndex === -1 ? historyDraft : history[historyIndex];
    onInputChanged();

    // Caret to the end, which is where you want it when recalling a line to edit.
    requestAnimationFrame(() => {
        elInput.selectionStart = elInput.selectionEnd = elInput.value.length;
    });
}

/* ========================================
   OPEN / CLOSE
   ======================================== */

function open(data) {
    isOpen      = true;
    maxLength   = Number(data.maxLength) || 256;
    modes       = Array.isArray(data.modes) ? data.modes : [];
    suggestions = Array.isArray(data.suggestions) ? data.suggestions : [];
    modeIndex   = -1;
    filteredSug = [];
    historyIndex = -1;
    historyDraft = '';

    padMode = data.pad === true;
    if (padMode) {
        openPadKeyboard({
            id: PAD_KEYBOARD_ID,
            title: data.title || 'Type',
            placeholder: data.placeholder || '',
            value: data.prefill || '',
            maxLength,
            dim: false,   // the screen behind stays as it is: a log being answered must stay readable
            // A / command's name finishes from the same list a keyboard player's suggestions come from.
            commands: suggestions.map((s) => s && s.name),
            // Only while this session is the one up: a keyboard closed by a newer one answers too.
            onDone: (text) => { if (isOpen && padMode) submit(false, text); },
            onCancel: () => { if (isOpen && padMode) submit(true); },
        });
        return;
    }

    elInput.maxLength  = maxLength;
    elInput.placeholder = data.placeholder || '';
    elInput.value = data.prefill || '';

    setCapsuleMode('composer');
    onInputChanged();

    // THE FRAME DELAY MATTERS. CEF will not focus an element that was display:none when the
    // call was made, and it is the mode class that reveals the field. whip_chat hit this exact
    // wall; the note is carried across rather than rediscovered.
    requestAnimationFrame(() => {
        elInput.focus();
        elInput.selectionStart = elInput.selectionEnd = elInput.value.length;
    });
}

/** Tear the field down locally. Does NOT talk to Lua — see submit() for that. */
function close() {
    const wasPad = padMode;
    isOpen = false;
    padMode = false;
    tellCommandLine(false);   // the minimap comes back with the field gone
    // On a pad the field was the keyboard's: it goes (quietly, if Lua closed us), the capsule was never moved.
    if (wasPad) { closePadKeyboard(PAD_KEYBOARD_ID); return; }
    elInput.value = '';
    elInput.blur();
    if (elSuggest && elSugList) hideSuggestions();
    elCount.classList.remove('visible', 'at-limit');
    if (capsuleMode() === 'composer') setCapsuleMode('stats');
}

/**
 * Hand the line to Lua and close.
 *
 * CLOSING BEFORE THE CALLBACK RESOLVES IS DELIBERATE. The Lua side releases NUI focus as the
 * very first thing it does, unconditionally, before any check can return early — so waiting for
 * a reply here would only add a frame of a field that no longer has the keyboard.
 */
function submit(canceled, typed) {
    // `typed`: the pad keyboard's text (padMode); otherwise what is in the capsule's field.
    const raw  = typed !== undefined ? String(typed) : elInput.value;
    const text = canceled ? '' : raw.trim().slice(0, maxLength);
    const mode = canceled ? null : currentMode();

    if (!canceled && text) pushHistory(text);

    close();

    nuiCallback('composerResult', {
        canceled: !!canceled || text.length === 0,
        message: text,
        mode: mode,
    });
}

/* ========================================
   KEYS

   A KEY SCOPE RATHER THAN A BARE document LISTENER, because spur_core's page has fourteen other
   things that also want keys and the router already arbitrates between them (see router.js).
   Registering here means the composer takes its turn in the same ordering as every panel instead
   of racing them.

   PRIORITY 2 — above everything except the creator's total swallow at 0. While the composer has
   the keyboard, every key belongs to it; a key leaking into a panel underneath would type into
   one thing and act on another. In practice nothing else can be open at the same time (whip_chat
   refuses to open the composer over a UI), so this is a guard against a future panel rather than
   against a current one.

   NO onNav, AND THAT IS THE CORRECT ANSWER RATHER THAN A GAP. A scope without onNav reports as
   "no controller support", which makes Lua leave the pad alone entirely — see activeNavScope()
   in router.js. Taking the pad over for a text field would disable gameplay controls for a
   player who has no way to type into it.
   ======================================== */

NuiRouter.registerKeyScope({
    name: 'composer',
    priority: 2,
    // Not on a pad: the keyboard's own scope has the keys and the pad then (js/pad-keyboard.js).
    isOpen: () => isOpen && !padMode,
    onKey: (e) => {
        switch (e.key) {
            case 'Escape':
                e.preventDefault();
                submit(true);
                break;

            case 'Enter':
                e.preventDefault();
                submit(false);
                break;

            case 'Tab':
                e.preventDefault();
                if (filteredSug.length > 0) completeSuggestion();
                else cycleMode();
                break;

            // What you sent before, messages and commands alike: Up goes back, Down comes forward
            // to the line you were typing. Never through the suggestion list.
            case 'ArrowUp':
                e.preventDefault();
                recallHistory(1);
                break;

            case 'ArrowDown':
                e.preventDefault();
                recallHistory(-1);
                break;

            // ---- THE LOG LIVES IN ANOTHER FRAME ----
            //
            // PageUp and PageDown scroll whip_chat's message list, which is a different document
            // and does not have the keyboard while this field does. Without forwarding them,
            // scrollback silently stops working and NOTHING ERRORS — the keys simply arrive at a
            // frame that is not listening. It is two keys and one callback; leaving it out is
            // the kind of regression that gets noticed a week later.
            case 'PageUp':
                e.preventDefault();
                nuiCallback('composerScroll', { delta: -1 });
                break;

            case 'PageDown':
                e.preventDefault();
                nuiCallback('composerScroll', { delta: 1 });
                break;

            // Everything else — the actual typing — is deliberately NOT prevented. The scope
            // consumes the key as far as the router is concerned (no panel underneath sees it),
            // and the character still reaches the focused input, which is what we want.
            default:
                break;
        }
    },
});

if (elInput) elInput.addEventListener('input', onInputChanged);

/* ========================================
   ROUTER
   ======================================== */

NuiRouter.register('composerOpen',  (d) => open(d));
NuiRouter.register('composerClose', () => close());
