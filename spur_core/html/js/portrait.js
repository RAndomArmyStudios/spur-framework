import { NuiRouter } from './router.js';
import { nuiCallback } from './utils.js';

// ========================================
// PORTRAIT — the game's headshot of the player, made into a small picture (client/portrait.lua)
// ========================================
//
// The game hands over a TXD name; https://nui-img/<txd>/<txd> serves it with a CORS header, so it can
// be drawn onto a canvas and read back (crossOrigin 'anonymous' — without it the canvas is tainted
// and toDataURL throws). 128 px square, as webp (a few KB); png where webp cannot be written.
// The picture goes back to the client, then the server, which keeps it for the /whip panel; and it is
// kept here for the player's own screens (myPortrait, below).

const SIZE = 128;

// THE PLAYER'S OWN PORTRAIT, for their own screens (the shop's talk capsule, js/shop-talk.js): the one
// just taken, else the server's copy of this character's last, asked once. undefined = not known yet,
// null = they have none. Forgotten at each spawn (client/portrait.lua): it may be another character.
let own;
let ownGen = 0;
let asking = null;

/** This character's portrait as a data: URL, or null. */
export function myPortrait() {
    if (own !== undefined) return Promise.resolve(own);
    if (!asking) {
        const gen = ownGen;
        asking = nuiCallback('myPortrait', {}).then((res) => {
            const answered = res && res.ok === true;
            const url = answered && typeof res.image === 'string' && res.image.indexOf('data:image/') === 0 ? res.image : null;
            if (gen === ownGen && answered) own = url;   // {} is a call that failed: asked again next time
            return url;
        }, () => null).then((url) => { asking = null; return url; });
    }
    return asking;
}

// `id`: a headshot someone asked for (client/portrait.lua TakeHeadshot): the picture goes back to them, and is
// neither this character's portrait nor saved as one.
function capture(txd, id) {
    if (typeof txd !== 'string' || !txd) return;
    const asked = Number.isInteger(id);
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
        try {
            const canvas = document.createElement('canvas');
            canvas.width = SIZE;
            canvas.height = SIZE;
            canvas.getContext('2d').drawImage(img, 0, 0, SIZE, SIZE);
            let data = canvas.toDataURL('image/webp', 0.9);
            if (data.indexOf('data:image/webp') !== 0) data = canvas.toDataURL('image/png');
            if (asked) { nuiCallback('portraitTaken', { id, image: data }); return; }
            own = data;
            ownGen++;
            nuiCallback('portraitSave', { image: data });
        } catch (e) {
            console.error('[portrait] the headshot could not be read', e);
            if (asked) nuiCallback('portraitTaken', { id });
        }
    };
    img.onerror = () => {
        console.error('[portrait] the headshot did not load');
        if (asked) nuiCallback('portraitTaken', { id });
    };
    img.src = 'https://nui-img/' + txd + '/' + txd + '?t=' + Date.now();
}

NuiRouter.register('portraitCapture', (d) => capture(d && d.txd, d && d.id));
NuiRouter.register('portraitForget', () => { own = undefined; ownGen++; });
