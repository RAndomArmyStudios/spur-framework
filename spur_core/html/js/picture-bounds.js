// ============================================
// PICTURE BOUNDS — where the thing is in each of the media packs' pictures
// ============================================
//
// For each picture of a prop (p), a car (v) and a ped (n), by model: the box round what is drawn in it,
// [left, top, right, bottom] in thousandths of the picture. utils.js fitPicture shows that box as big as its
// place allows. A picture not here is shown whole.
//
// RedM (spur_core, 26 Nov 2026): whip_core's boxes were for GTA V's props, cars and peds (its media packs), another
// game's, and are gone. SPUR has no picture packs yet, so every list is empty.

export const BOUNDS = {
    p: {},
    v: {},
    n: {},
};
