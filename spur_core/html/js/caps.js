/* ========================================
   CAPS — what this browser can do

   Cfx.re's browser is moving from Chromium 103 to Chromium 144. whip runs on both, so it never asks "which version is this?" — it asks the browser,
   feature by feature, and uses the new way where the answer is yes and the old way where it is no.

   window.WhipCaps, set by this file:
     chrome            the browser's Chrome version (0 when it does not say)
     has               the :has() selector
     colorMix          color-mix()
     relativeColor     relative colours: rgb(from var(--x) r g b / 50%)
     textBalance       text-wrap: balance (and pretty) — even lines, no word left alone
     startingStyle     @starting-style + transition-behavior: allow-discrete: fade in from
                       display: none, fade out before it, in CSS alone
     heightAuto        interpolate-size: allow-keywords — transitions to and from height: auto
     anchor            CSS anchor positioning: a menu or card placed on its anchor, kept on screen
     fieldSizing       field-sizing: content — inputs and text boxes that grow with their text
     viewTransitions   document.startViewTransition — one change of screen, cross-faded
     schedulerYield    scheduler.yield() — let the browser draw between chunks of a long job
     webgpu            navigator.gpu is there (not a promise that a GPU adapter is)
     zoomScreenPx      inside a CSS-zoomed box getBoundingClientRect is in SCREEN pixels. False on
                       Cfx.re's Chromium 103, which measured such boxes unzoomed (Chrome 128
                       standardised zoom). Measured, not looked up.
     gameView          Cfx.re's new game view: CfxGameViewRenderer, and gl.CFX_BIND_GAME_VIEW on a
                       WebGL2 texture. (<object type="application/x-cfx-game-view"> shows the game
                       on both builds; this is what a page needs to read the picture itself.)

   And three helpers:
     WhipCaps.transition(update)   run `update` as a view transition where there are any, plainly
                                   where not. On both, `update` runs AFTER the call returns, never
                                   during it, and the promise carries no value: only "the DOM has
                                   changed" (await it before reading what `update` made)
     WhipCaps.yieldToBrowser()     a promise to await between chunks of a long job
     WhipCaps.snapshot()           the flags alone, as a plain object (for Lua)

   On <html>: class caps-<flag> for every flag that is true (caps-anchor, caps-game-view ...) and
   data-chrome="<version>". In CSS, @supports is safe only for a feature Cfx.re's Chromium 103 does not
   have at all (text-wrap, anchor positioning, field-sizing, interpolate-size, @starting-style); for
   :has() use .caps-has, and for zoomScreenPx and gameView the classes are the only way to ask.

   NEVER JUST "THE BROWSER PARSES IT". Cfx.re's Chromium 103 ran with every experimental web feature
   switched on, so a half-built feature parses there: CSS.supports('selector(:has(a))') is true on it.
   And any value with var() in it passes CSS.supports / @supports in every Chrome (it is only checked
   when the style is worked out), so a test never puts var() in. A flag is true only where the browser
   has it, asked with plain values, AND its Chrome version shipped it finished.

   A CLASSIC SCRIPT, NOT A MODULE: the DUI pages (html/interact3d, html/bubble3d) load it with a
   plain <script> tag, like js/glyphs.js, and index.html loads it in <head> so the classes are on
   <html> before the first paint. Another resource's page may load it too:
   <script src="https://cfx-nui-spur_core/html/js/caps.js"></script>
   ======================================== */

(function () {
    'use strict';

    var ua = (navigator && navigator.userAgent) || '';
    var m = ua.match(/Chrome\/(\d+)/);
    var chrome = m ? parseInt(m[1], 10) : 0;

    // Shipped, finished, in this Chrome version (or the version is unknown: trust the browser)
    function since(version) {
        return chrome === 0 || chrome >= version;
    }

    function supports(property, value) {
        try { return !!(window.CSS && CSS.supports(property, value)); } catch (e) { return false; }
    }

    function supportsSelector(selector) {
        try { return !!(window.CSS && CSS.supports('selector(' + selector + ')')); } catch (e) { return false; }
    }

    // Inside zoom: 2, a 100px box: about 200 wide in screen pixels, about 100 where Chromium 103
    // measured zoomed boxes unzoomed (js/pad-cursor.js and the inventory's padZoom do the same)
    function measureZoom() {
        var root = document.documentElement;
        if (!root) return false;
        var outer = document.createElement('div');
        var inner = document.createElement('div');
        outer.style.cssText = 'position:absolute;left:0;top:0;zoom:2;visibility:hidden;pointer-events:none';
        inner.style.cssText = 'width:100px;height:1px';
        outer.appendChild(inner);
        root.appendChild(outer);
        var w = inner.getBoundingClientRect().width;
        root.removeChild(outer);
        return w > 150;
    }

    var FLAGS = ['has', 'colorMix', 'relativeColor', 'textBalance', 'startingStyle', 'heightAuto', 'anchor',
        'fieldSizing', 'viewTransitions', 'schedulerYield', 'webgpu', 'zoomScreenPx', 'gameView'];

    var caps = window.WhipCaps || {};
    var zoomMeasured = null;   // once: a layout change cannot change the answer

    function detect() {
        caps.chrome = chrome;
        caps.has = since(105) && supportsSelector(':has(a)');
        caps.colorMix = since(111) && supports('color', 'color-mix(in srgb, red 50%, blue)');
        caps.relativeColor = since(122) && supports('color', 'rgb(from red r g b / 50%)');
        caps.textBalance = since(114) && supports('text-wrap', 'balance');
        caps.startingStyle = since(117) && typeof window.CSSStartingStyleRule !== 'undefined'
            && supports('transition-behavior', 'allow-discrete');
        caps.heightAuto = since(129) && supports('interpolate-size', 'allow-keywords');
        caps.anchor = since(125) && supports('anchor-name', '--a');
        caps.fieldSizing = since(123) && supports('field-sizing', 'content');
        caps.viewTransitions = since(111) && typeof document.startViewTransition === 'function';
        caps.schedulerYield = since(129) && !!(window.scheduler && typeof window.scheduler.yield === 'function');
        caps.webgpu = since(113) && !!navigator.gpu;
        if (zoomMeasured === null) {
            try { zoomMeasured = measureZoom(); } catch (e) { zoomMeasured = false; }
        }
        caps.zoomScreenPx = zoomMeasured;
        caps.gameView = typeof window.CfxGameViewRenderer === 'function';
    }

    function kebab(name) {
        return name.replace(/[A-Z]/g, function (c) { return '-' + c.toLowerCase(); });
    }

    function applyClasses() {
        var root = document.documentElement;
        if (!root) return;
        for (var i = 0; i < FLAGS.length; i++) {
            root.classList.toggle('caps-' + kebab(FLAGS[i]), caps[FLAGS[i]] === true);
        }
        root.setAttribute('data-chrome', String(chrome));
    }

    /** The flags alone, as a plain object. */
    caps.snapshot = function () {
        var out = { chrome: caps.chrome };
        for (var i = 0; i < FLAGS.length; i++) out[FLAGS[i]] = caps[FLAGS[i]] === true;
        return out;
    };

    /** Ask again (Cfx.re adds the game view to the page as it is made) and set the classes again. */
    caps.refresh = function () {
        detect();
        applyClasses();
        return caps.snapshot();
    };

    /** `update` as a view transition where there are any, plainly where not. A promise for when the
     *  DOM has changed (a throw in `update` rejects it, either way).
     *
     *  THE SAME ON BOTH BROWSERS. startViewTransition runs `update` later and its promise carries no
     *  value, so the plain path does too. Run straight away, code that read the DOM right after the
     *  call, or used the value, would work on Chromium 103 and break on 144. */
    caps.transition = function (update) {
        if (caps.viewTransitions) {
            return document.startViewTransition(update).updateCallbackDone.then(function () {});
        }
        return Promise.resolve().then(function () { return update(); }).then(function () {});
    };

    /** Await between chunks of a long job, so the browser can draw in between. */
    caps.yieldToBrowser = function () {
        if (caps.schedulerYield) return window.scheduler.yield();
        return new Promise(function (resolve) { setTimeout(resolve, 0); });
    };

    caps.refresh();
    window.WhipCaps = caps;

    // Once more when the page is in: anything Cfx.re injected late is counted, and on a page that
    // loaded this before <html> existed the classes land now
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () { caps.refresh(); });
    }
})();
