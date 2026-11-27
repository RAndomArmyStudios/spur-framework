// ============================================
// WHIP ASSETS — which media pack holds a picture, a video or a map file (the NUI's half)
// ============================================
//
// The same answer as shared/assets.lua (WhipAssets.url), from the same index (js/assets-index.js, made by
// dev/assets_index.mjs): whipAssetUrl('img/props/p_bench03x.webp') is
// 'https://cfx-nui-whip_media_props/img/props/p_bench03x.webp', or null when no area holds it. A plain script, as
// the index is: a page loads both with <script> (assets-index.js first); a module imports both (js/utils.js).

(function () {
    'use strict';

    /** The resource whose folder has `path`, or null. An area split over several resources goes by the name: the
     *  last whose run of names starts at or before it. */
    function resourceFor(path) {
        const p = String(path || '').replace(/^\/+/, '').toLowerCase();
        let found = null, foundLen = -1;
        for (const c of globalThis.WHIP_ASSET_CHUNKS || []) {
            const d = c.dir;
            if (d.length >= foundLen && p.startsWith(d + '/')) {
                if (d.length > foundLen) { found = null; foundLen = d.length; }
                if (!c.from || p.slice(d.length + 1) >= c.from) found = c.resource;
            }
        }
        return found;
    }

    globalThis.whipAssetUrl = function (path) {
        const res = resourceFor(path);
        return res ? 'https://cfx-nui-' + res + '/' + String(path).replace(/^\/+/, '') : null;
    };
})();
