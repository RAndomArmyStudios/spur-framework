import { NuiRouter } from './router.js';
// The one escape, safe in attributes too.
import { escapeHtml as escHtml } from './utils.js';

// ========================================
// 3D INTERACTION SYSTEM — THE NUI RENDERER'S BROWSER HALF
//
// Renders circle/E indicators at screen positions
// provided by client/interact_nui.lua each frame.
// State is sent only on change; positions arrive as
// a flat array and only when one actually moved.
//
// ONE OF TWO RENDERERS. client/interact.lua decides
// what should be shown; this draws it as divs, while
// client/interact_world.lua draws the same prompts as
// textured polygons in the world and never talks to
// this file at all. Config.InteractRenderer picks.
//
// The positions arriving here are always a frame or
// two old — NUI is asynchronous, so whatever this
// paints is composited after the game has moved on.
// That delay is not fixable from inside the browser,
// and it is the reason the world renderer exists.
// ========================================

(function() {
    const layer = document.getElementById('interact-layer');

    // RedM (spur_core, 23 Nov 2026): RDR2 has no DUI textures, so the world renderer's badges cannot be drawn and this
    // renderer is the one players see. A prompt's icon is a glyph's name ('bank', 'back', 'deposit'), not a key
    // letter, so the circle shows the glyph (js/glyphs.js). A short name with no glyph is a key ('E'), shown as is.
    function setKey(keyEl, icon) {
        if (!keyEl) return;
        const name = String(icon || 'E');
        if (keyEl.dataset.icon === name) return;
        keyEl.dataset.icon = name;
        const glyphs = (window.WhipGlyphs && window.WhipGlyphs.glyphs) || {};
        if (glyphs[name]) keyEl.innerHTML = glyphs[name];
        else keyEl.textContent = name.length <= 3 ? name : 'E';
    }
    let indicators = {};  // [id] = { el, labelEl, active, focused }
    const fadingOut  = {};  // [id] = DOM element (being removed with fade)

    // Must match --it-fade in css/interact.css, in milliseconds.
    //
    // This is how long an element is kept alive after its fade starts, so it has to be at least
    // the CSS duration — shorter and the node is removed mid-transition, which reads as the
    // prompt blinking out instead of fading. If you retune --it-fade, retune this with it.
    const FADE_DURATION = 250;

    /**
     * Create a new indicator element (or reclaim from fading).
     */
    function createIndicator(id, item) {
        let el = null;

        // Reclaim from fading out if possible
        //
        // BACK TO VISIBLE, WITH THIS ITEM'S STATE: every visible state in interact.css needs
        // `.visible`, not just `fading-out` off. Its old active/focused classes and text are reset
        // too, since the state below starts from nothing.
        if (fadingOut[id]) {
            el = fadingOut[id];
            delete fadingOut[id];
            el.classList.remove('fading-out', 'active', 'focused');
            el.classList.add('visible');
            setKey(el.querySelector('.interact-key'), item.icon);
            const lblEl = el.querySelector('.interact-label');
            if (lblEl) lblEl.textContent = item.label || 'Interact';
        }

        if (!el) {
            el = document.createElement('div');
            el.className = 'interact-indicator';
            // THE KEY LIVES INSIDE THE CIRCLE and the label is a sibling, not a child of a box.
            // The circle is no longer something that collapses to make room for a panel — it IS
            // the prompt, and it stays on the object while the label opens out beside it. There
            // is no wrapper around the two because there is no longer a panel to draw.
            el.innerHTML =
                '<div class="interact-circle"><span class="interact-key"></span></div>' +
                '<span class="interact-label">' + escHtml(item.label || 'Interact') + '</span>';
            setKey(el.querySelector('.interact-key'), item.icon);
            layer.appendChild(el);

            // Trigger fade-in on next frame
            requestAnimationFrame(function() {
                el.classList.add('visible');
            });
        }

        const labelEl = el.querySelector('.interact-label');

        indicators[id] = {
            el:      el,
            labelEl: labelEl,
            active:  false,
            focused: false,
        };

        // Apply initial state if provided
        if (item.active) {
            el.classList.add('active');
            indicators[id].active = true;
        }
        if (item.focused) {
            el.classList.add('focused');
            indicators[id].focused = true;
        }
        if (item.dist != null) {
            const maxDist = 5;
            const d = Math.min(item.dist, maxDist);
            const scale = 1.0 - ((d / maxDist) * 0.55);
            el.style.setProperty('--interact-scale', scale.toFixed(3));
        }

        return indicators[id];
    }

    /**
     * Apply a state change to an existing indicator.
     */
    function applyState(item) {
        let ind = indicators[item.id];
        if (!ind) {
            // New indicator — create it
            ind = createIndicator(item.id, item);
            return;
        }

        const el = ind.el;

        // Label
        if (item.label != null && ind.labelEl) {
            if (ind.labelEl.textContent !== item.label) {
                ind.labelEl.textContent = item.label;
            }
        }

        // The glyph in the circle — a door's padlock turning open, as the server's icon changes.
        if (item.icon != null) setKey(el.querySelector('.interact-key'), item.icon);

        // Active state
        if (item.active != null && item.active !== ind.active) {
            if (item.active) {
                el.classList.add('active');
            } else {
                el.classList.remove('active');
            }
            ind.active = item.active;
        }

        // Focused state
        if (item.focused != null && item.focused !== ind.focused) {
            if (item.focused) {
                el.classList.add('focused');
            } else {
                el.classList.remove('focused');
            }
            ind.focused = item.focused;
        }

        // Distance-based scale
        if (item.dist != null) {
            const maxDist = 5;
            const d = Math.min(item.dist, maxDist);
            const scale = 1.0 - ((d / maxDist) * 0.55);
            el.style.setProperty('--interact-scale', scale.toFixed(3));
        }
    }

    /**
     * Fade out and remove an indicator element.
     */
    function fadeOutAndRemove(id) {
        const ind = indicators[id];
        if (!ind) return;

        const el = ind.el;
        el.classList.remove('visible');
        el.classList.add('fading-out');
        fadingOut[id] = el;
        delete indicators[id];

        setTimeout(function() {
            if (fadingOut[id] === el) {
                if (el.parentNode) el.parentNode.removeChild(el);
                delete fadingOut[id];
            }
        }, FADE_DURATION);
    }

    /**
     * Process a frame update from Lua.
     * @param {Object} msg
     *   msg.positions — flat array [id, sx, sy, id, sx, sy, ...]
     *   msg.state     — (optional) array of state changes [{id, label, icon, active, focused, dist}]
     *   msg.removed   — (optional) array of IDs to remove
     */
    function interactFrame(msg) {
        layer.style.display = 'block';

        // 1. Apply state changes (new items or changed state)
        if (msg.state) {
            for (let i = 0; i < msg.state.length; i++) {
                applyState(msg.state[i]);
            }
        }

        // 2. Update positions from flat array
        const positions = msg.positions;
        if (positions) {
            const w = window.innerWidth;
            const h = window.innerHeight;
            for (let j = 0; j < positions.length; j += 3) {
                const id = positions[j];
                const sx = positions[j + 1];
                const sy = positions[j + 2];
                const ind = indicators[id];
                if (ind) {
                    ind.el.style.left = (sx * w) + 'px';
                    ind.el.style.top  = (sy * h) + 'px';
                }
            }
        }

        // 3. Remove indicators that left range
        if (msg.removed) {
            for (let k = 0; k < msg.removed.length; k++) {
                fadeOutAndRemove(msg.removed[k]);
            }
        }
    }

    /**
     * Hide all interaction indicators.
     */
    function interactHide() {
        for (const id in indicators) {
            const el = indicators[id].el;
            el.classList.remove('visible');
            el.classList.add('fading-out');
            fadingOut[id] = el;

            (function(capturedId, capturedEl) {
                setTimeout(function() {
                    if (fadingOut[capturedId] === capturedEl) {
                        if (capturedEl.parentNode) capturedEl.parentNode.removeChild(capturedEl);
                        delete fadingOut[capturedId];
                    }
                }, FADE_DURATION);
            })(id, el);
        }
        indicators = {};

        setTimeout(function() {
            if (Object.keys(indicators).length === 0 && Object.keys(fadingOut).length === 0) {
                layer.style.display = 'none';
            }
        }, FADE_DURATION);
    }

    // Expose globally for main.js message handler
    window.interactFrame  = interactFrame;
    window.interactHide   = interactHide;
})();


// ROUTER REGISTRATION — see router.js's header. IIFE file; functions resolved via window.
NuiRouter.register('interactFrame', (d) => interactFrame(d));
NuiRouter.register('interactHide', () => interactHide());