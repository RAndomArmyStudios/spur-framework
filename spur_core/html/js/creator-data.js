// ========================================
// CHARACTER CREATOR — STATIC DATA
//
// Pure data, no DOM: the category tree the rail renders, the GTA Online-style
// face-pad pairings, the swatch palettes, and the placeholder card glyphs.
// creator.js imports all of it; nothing else does. Keeping it out of creator.js
// keeps that file about behavior and this one about content — when a category
// gains real thumbnails or a palette needs correcting, this is the only file
// that changes.
// ========================================

// ---- Placeholder glyphs ----
//
// Card art is a line-drawn SVG stand-in until real per-item thumbnails exist
// (screenshot automation is a later project). One consistent
// stroke system: 24-unit grid, 1.5 stroke, currentColor so the CSS owns the
// tint. Authored geometry, not emoji — the icon inherits selection/hover color
// for free and never fights the font stack.
function svg(inner) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" '
        + 'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + inner + '</svg>';
}

export const GLYPHS = {
    heritage: svg('<path d="M8 3c0 5.5 8 6.5 8 9s-8 3.5-8 9"/><path d="M16 3c0 5.5-8 6.5-8 9s8 3.5 8 9"/><path d="M9 6.5h6"/><path d="M9 17.5h6"/>'),
    face:     svg('<circle cx="12" cy="12" r="8.5"/><path d="M9 10.2v1.2"/><path d="M15 10.2v1.2"/><path d="M9.5 15.2c1.6 1.2 3.4 1.2 5 0"/>'),
    brow:     svg('<path d="M4 10c2-2.4 5-2.4 7-.8"/><path d="M13 9.2c2-1.6 5-1.6 7 .8"/><path d="M6.5 14.5h3"/><path d="M14.5 14.5h3"/>'),
    eye:      svg('<path d="M2.5 12S6.5 6.5 12 6.5 21.5 12 21.5 12 17.5 17.5 12 17.5 2.5 12 2.5 12Z"/><circle cx="12" cy="12" r="2.6"/>'),
    nose:     svg('<path d="M12 5v7.5c0 2-1.8 2.2-2.6 3.4-.7 1 0 2.6 1.6 2.6h2c1.6 0 2.3-1.6 1.6-2.6-.8-1.2-2.6-1.4-2.6-3.4"/>'),
    cheek:    svg('<path d="M5 8c0 7 3 11.5 7 11.5S19 15 19 8"/><path d="M8 12.5c.8 1 2 1.2 3 .6"/><path d="M16 12.5c-.8 1-2 1.2-3 .6"/>'),
    jaw:      svg('<path d="M5 6v5c0 4.5 3.2 8 7 8s7-3.5 7-8V6"/><path d="M9 15.5c1.8 1.2 4.2 1.2 6 0"/>'),
    chin:     svg('<path d="M7 11c0 4 2.2 7.5 5 7.5s5-3.5 5-7.5"/><path d="M10.2 15.8c1.1.9 2.5.9 3.6 0"/>'),
    lips:     svg('<path d="M4 12.5c2.5-.8 4-3 6-3 .8 0 1.4.8 2 .8s1.2-.8 2-.8c2 0 3.5 2.2 6 3"/><path d="M4 12.5c2.5 2.8 5 4 8 4s5.5-1.2 8-4"/>'),
    neck:     svg('<path d="M8 4c0 3.5-.5 6-2 8"/><path d="M16 4c0 3.5.5 6 2 8"/><path d="M6 20c1.5-3 2.5-4.5 6-4.5s4.5 1.5 6 4.5"/>'),
    hair:     svg('<path d="M5 15v-3a7 7 0 0 1 14 0v3"/><path d="M5 12c1.5-.8 2.5-2.6 3-4.5"/><path d="M19 12c-1.5-.8-2.5-2.6-3-4.5"/><path d="M12 5v2.5"/>'),
    // A head with stubble dots fading down its side: a hair fade.
    fade:     svg('<path d="M4.5 11.5a7.5 7.5 0 0 1 15 0v1c0 4.7-3.4 8.5-7.5 8.5s-7.5-3.8-7.5-8.5v-1Z"/><path d="M6.2 8c2.8-2.6 8.8-2.6 11.6 0"/><path d="M6.4 10.6h.01M8.6 9.9h.01M15.4 9.9h.01M17.6 10.6h.01M6.2 13.2h.01M8.2 12.4h.01M15.8 12.4h.01M17.8 13.2h.01"/>'),
    beard:    svg('<path d="M6 8v3c0 4.5 2.6 8 6 8s6-3.5 6-8V8"/><path d="M9 13v2.5"/><path d="M12 14v2.5"/><path d="M15 13v2.5"/>'),
    makeup:   svg('<path d="M10 10h4v9a1 1 0 0 1-1 1h-2a1 1 0 0 1-1-1v-9Z"/><path d="M11 10V5.5c0-1 2-1 2 0V10"/>'),
    skin:     svg('<circle cx="12" cy="12" r="8.5"/><path d="M9 9.2h.01"/><path d="M14.6 8h.01"/><path d="M15.5 13.5h.01"/><path d="M10 14.8h.01"/>'),
    chest:    svg('<path d="M7 4c0 2-1 3.5-3 4.5V20h16V8.5c-2-1-3-2.5-3-4.5"/><path d="M10.5 11c.5 1 2.5 1 3 0"/><path d="M10.5 15c.5 1 2.5 1 3 0"/>'),
    mask:     svg('<path d="M4 8c0-1.5 1-2.5 2.5-2.5h11C19 5.5 20 6.5 20 8v4c0 4-3.5 6.5-8 6.5S4 16 4 12V8Z"/><path d="M7.5 10.5h3"/><path d="M13.5 10.5h3"/>'),
    shirt:    svg('<path d="M9 4 5 6.5 6.5 10 8 9.5V20h8V9.5l1.5.5L19 6.5 15 4c0 1.2-1.2 2-3 2s-3-.8-3-2Z"/>'),
    tshirt:   svg('<path d="M9 4 5 6.5 6.5 10 8 9.5V19h8V9.5l1.5.5L19 6.5 15 4a3 3 0 0 1-6 0Z"/><path d="M10 4.5c.5 1 3.5 1 4 0"/>'),
    jacket:   svg('<path d="M9 4 5 6l1 13h5V6.5L9 4Z"/><path d="M15 4l4 2-1 13h-5V6.5L15 4Z"/><path d="M11 9.5h-1"/><path d="M14 9.5h-1"/>'),
    pants:    svg('<path d="M7 4h10l1 16h-5l-1-9-1 9H6L7 4Z"/><path d="M7 8h10"/>'),
    shoe:     svg('<path d="M4 15V9.5c2 .8 4 .8 5.5 0 1 2.2 3 3.7 6 4.3 2.5.5 4.5 1.5 4.5 3.2v1H4v-3Z"/><path d="M4 18h16"/>'),
    chain:    svg('<path d="M5 6c1.5 3.5 4 5.5 7 5.5S17.5 9.5 19 6"/><path d="M12 11.5v2"/><path d="M12 13.5l-1.8 2.2L12 18l1.8-2.3L12 13.5Z"/>'),
    vest:     svg('<path d="M8 4c0 1.5 1.6 2.5 4 2.5S16 5.5 16 4"/><path d="M8 4 6 8v12h12V8l-2-4"/><path d="M6 13h12"/>'),
    decal:    svg('<path d="M9 4 5 6.5 6.5 10 8 9.5V20h8V9.5l1.5.5L19 6.5 15 4a3 3 0 0 1-6 0Z"/><path d="m12 11 1 2h2l-1.6 1.3.6 2.2-2-1.3-2 1.3.6-2.2L9 13h2l1-2Z"/>'),
    bag:      svg('<path d="M7 8h10v11a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V8Z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/><path d="M9 12h6"/>'),
    hat:      svg('<path d="M5 14a7 7 0 0 1 14 0"/><path d="M3 14h18c0 1.2-1 2-2.5 2h-13C4 16 3 15.2 3 14Z"/>'),
    glasses:  svg('<circle cx="7.5" cy="13" r="3.5"/><circle cx="16.5" cy="13" r="3.5"/><path d="M11 13h2"/><path d="M2.5 11 4 12"/><path d="M21.5 11 20 12"/>'),
    ear:      svg('<path d="M9 9a4.5 4.5 0 0 1 9 0c0 2.5-2 3.2-2 5.5"/><circle cx="15" cy="17.5" r="2"/>'),
    watch:    svg('<circle cx="12" cy="12" r="4.5"/><path d="M12 9.5V12l1.8 1"/><path d="M9.5 7.8 10 3h4l.5 4.8"/><path d="M9.5 16.2 10 21h4l.5-4.8"/>'),
    bracelet: svg('<path d="M5 12a7 7 0 0 1 14 0 7 7 0 0 1-14 0Z"/><path d="M12 5v1.5"/><path d="M12 17.5V19"/><path d="M5.5 9.5 7 10.2"/><path d="M18.5 9.5 17 10.2"/>'),
    none:     svg('<circle cx="12" cy="12" r="8.5"/><path d="M6 6l12 12"/>'),
    // An anchor, the tattoo-flash classic.
    tattoo:   svg('<circle cx="12" cy="5" r="2"/><path d="M12 7v13"/><path d="M8.5 10h7"/><path d="M5 13c0 4 3 7 7 7s7-3 7-7"/><path d="M3.5 14.5 5 13l1.5 1.5"/><path d="M20.5 14.5 19 13l-1.5 1.5"/>'),
    // A coat hanger: a saved outfit.
    outfit:   svg('<path d="M10 6.5a2 2 0 1 1 2.6 1.9c-.4.1-.6.5-.6.9V10"/><path d="M12 10 3.6 15.6c-.8.5-.4 1.9.6 1.9h15.6c1 0 1.4-1.4.6-1.9L12 10Z"/>'),
};

// ---- Face feature pads ----
//
// GTA Online's Features screen: eleven elements, most edited as a 2-axis
// "scatter graph" you drag a point across. Same idea here — each pad drives two
// SetPedFaceFeature indices at once, with fine sliders underneath for exact
// values (pads for feel, sliders for precision).
//
// `x`/`y` are NATIVE feature indices (0-based, matching the JS faceFeatures
// array; Lua reads them 1-based at the apply site). Y is authored so dragging
// UP means "more / higher" — creator.js flips screen coordinates.
//
// `neg`/`pos` label the pad's left/bottom and right/top. Where GTA's own +1
// runs the other way to them, the pad and its sliders show the value negated
// (featureSign); where it runs the labels' own way, the feature is listed in
// FEATURE_SAME_WAY by its index. Each was checked in game (Josh) by dragging
// it to both ends. Saved values are the game's, untouched.
//   negated (GTA's +1 is the label's neg end):  1 nose height, 2 nose length,
//     3 nose bridge, 5 nose twist, 6 brow height, 8 cheekbone height, 15 chin height
//   the labels' own way:  0 nose width, 4 nose tip, 7 brow depth,
//     9 cheekbone width, 13 jaw width, 14 jaw shape, 16 chin length,
//     17 chin width, 18 chin cleft
//   not checked yet (the slider-only ones):  10 cheeks, 11 eye opening,
//     12 lips, 19 neck
export const FEATURE_SAME_WAY = new Set([0, 4, 7, 9, 13, 14, 16, 17, 18]);
export function featureSign(idx) { return FEATURE_SAME_WAY.has(Number(idx)) ? 1 : -1; }

export const FEATURE_GROUPS = [
    { id: 'brow',        label: 'Brow',         glyph: 'brow',
      x: { idx: 7,  label: 'Depth',   neg: 'In',      pos: 'Out' },
      y: { idx: 6,  label: 'Height',  neg: 'Down',    pos: 'Up' } },
    { id: 'noseShape',   label: 'Nose Shape',   glyph: 'nose',
      x: { idx: 0,  label: 'Width',   neg: 'Narrow',  pos: 'Wide' },
      y: { idx: 1,  label: 'Height',  neg: 'Down',    pos: 'Up' } },
    { id: 'noseProfile', label: 'Nose Profile', glyph: 'nose',
      x: { idx: 2,  label: 'Length',  neg: 'Short',   pos: 'Long' },
      y: { idx: 3,  label: 'Bridge',  neg: 'Low',     pos: 'High' } },
    { id: 'noseTip',     label: 'Nose Tip',     glyph: 'nose',
      x: { idx: 5,  label: 'Twist',   neg: 'Left',    pos: 'Right' },
      y: { idx: 4,  label: 'Tip',     neg: 'Raised',  pos: 'Lowered' } },
    { id: 'cheekbones',  label: 'Cheekbones',   glyph: 'cheek',
      x: { idx: 9,  label: 'Width',   neg: 'Narrow',  pos: 'Wide' },
      y: { idx: 8,  label: 'Height',  neg: 'Low',     pos: 'High' } },
    { id: 'jaw',         label: 'Jaw',          glyph: 'jaw',
      x: { idx: 13, label: 'Width',   neg: 'Narrow',  pos: 'Wide' },
      y: { idx: 14, label: 'Shape',   neg: 'Round',   pos: 'Square' } },
    { id: 'chinProfile', label: 'Chin Profile', glyph: 'chin',
      x: { idx: 16, label: 'Length',  neg: 'Short',   pos: 'Long' },
      y: { idx: 15, label: 'Height',  neg: 'Low',     pos: 'High' } },
    { id: 'chinShape',   label: 'Chin Shape',   glyph: 'chin',
      x: { idx: 17, label: 'Width',   neg: 'Narrow',  pos: 'Wide' },
      y: { idx: 18, label: 'Cleft',   neg: 'Flat',    pos: 'Deep' } },
    // Single-axis elements — slider-only panels, no pad.
    { id: 'eyeOpen',     label: 'Eyes',         glyph: 'eye',
      x: { idx: 11, label: 'Opening', neg: 'Squint',  pos: 'Wide' } },
    { id: 'cheeks',      label: 'Cheeks',       glyph: 'cheek',
      x: { idx: 10, label: 'Fullness', neg: 'Gaunt',  pos: 'Puffed' } },
    { id: 'lips',        label: 'Lips',         glyph: 'lips',
      x: { idx: 12, label: 'Thickness', neg: 'Thin',  pos: 'Full' } },
    { id: 'neck',        label: 'Neck',         glyph: 'neck',
      x: { idx: 19, label: 'Thickness', neg: 'Thin',  pos: 'Thick' } },
];

// ---- Category tree ----
//
// The left rail, in render order. `cluster` breaks the rail into its visual
// groups; `cam` is the camera preset requested on switch (client/appearance.lua
// validates against its preset map). Kinds:
//   heritage  — parent-pick sub-tabs + blend sliders
//   features  — one card per FEATURE_GROUPS entry, pad/slider options panel
//   eyes      — eye color cards
//   hair      — style cards, texture + color swatch options; a Fade sub-tab (shared/hair_fades.lua): the
//               stubble drawn on the scalp under the style, one or None
//   overlays  — one sub-tab per overlay key; type cards; opacity/color options
//   component — drawable cards + texture options (comp = GTA component id)
//   prop      — drawable cards with a leading None + texture options
//   tattoos   — one part of the body's tattoos (zone, client/appearance.lua tattoosFor): cards that
//               go on and come off, any number at once, with a leading None that takes them all off
//   outfits   — the character's saved outfits (their clothes and accessories), one card each to put
//               it on; the band saves what is on now, renames and deletes
// `one` is one item's name where it is not the label ("Top 5", not "Tops 5"): the band's heading.
// `yaw` turns the camera round the ped on switching to the category (180 face-on, 0 from behind,
// 90 the ped's right side, 270 its left); without one the camera stays where the player put it.
export const CATEGORIES = [
    { id: 'heritage',  label: 'Heritage',   cluster: 'face',    kind: 'heritage',  glyph: 'heritage', cam: 'torso' },
    { id: 'features',  label: 'Features',   cluster: 'face',    kind: 'features',  glyph: 'face',     cam: 'torso' },
    { id: 'eyes',      label: 'Eyes',       cluster: 'face',    kind: 'eyes',      glyph: 'eye',      cam: 'torso' },
    { id: 'hair',      label: 'Hair',       cluster: 'face',    kind: 'hair',      glyph: 'hair',     cam: 'torso' },
    { id: 'eyebrows',  label: 'Eyebrows',   cluster: 'face',    kind: 'overlays',  glyph: 'brow',     cam: 'torso',
      overlays: [ { key: 'eyebrows', label: 'Eyebrows' } ] },
    { id: 'beard',     label: 'Beard',      cluster: 'face',    kind: 'overlays',  glyph: 'beard',    cam: 'torso',
      overlays: [ { key: 'beard', label: 'Beard' } ] },
    { id: 'makeup',    label: 'Makeup',     cluster: 'face',    kind: 'overlays',  glyph: 'makeup',   cam: 'torso',
      overlays: [ { key: 'makeup', label: 'Makeup' }, { key: 'blush', label: 'Blush' }, { key: 'lipstick', label: 'Lipstick' } ] },
    { id: 'skin',      label: 'Skin Detail', cluster: 'face',   kind: 'overlays',  glyph: 'skin',     cam: 'torso',
      overlays: [ { key: 'blemishes', label: 'Blemishes' }, { key: 'ageing', label: 'Ageing' }, { key: 'complexion', label: 'Complexion' }, { key: 'sunDamage', label: 'Sun Damage' }, { key: 'moles', label: 'Moles' } ] },
    { id: 'chestHair', label: 'Chest Hair', cluster: 'face',    kind: 'overlays',  glyph: 'chest',    cam: 'torso',
      overlays: [ { key: 'chestHair', label: 'Chest Hair' } ] },

    { id: 'mask',      label: 'Mask',       cluster: 'apparel', kind: 'component', glyph: 'mask',     cam: 'torso', comp: 1 },
    { id: 'tops',      label: 'Tops',       cluster: 'apparel', kind: 'component', glyph: 'jacket',   cam: 'torso', comp: 11, one: 'Top' },
    { id: 'undershirt', label: 'Undershirt', cluster: 'apparel', kind: 'component', glyph: 'tshirt',  cam: 'torso', comp: 8 },
    { id: 'arms',      label: 'Arms',       cluster: 'apparel', kind: 'component', glyph: 'shirt',    cam: 'torso', comp: 3 },
    { id: 'legs',      label: 'Legs',       cluster: 'apparel', kind: 'component', glyph: 'pants',    cam: 'legs',  comp: 4 },
    { id: 'shoes',     label: 'Shoes',      cluster: 'apparel', kind: 'component', glyph: 'shoe',     cam: 'legs',  comp: 6 },
    { id: 'accessory', label: 'Accessory',  cluster: 'apparel', kind: 'component', glyph: 'chain',    cam: 'torso', comp: 7 },
    { id: 'armor',     label: 'Armor',      cluster: 'apparel', kind: 'component', glyph: 'vest',     cam: 'torso', comp: 9 },
    { id: 'decal',     label: 'Decal',      cluster: 'apparel', kind: 'component', glyph: 'decal',    cam: 'torso', comp: 10 },
    { id: 'bag',       label: 'Bag',        cluster: 'apparel', kind: 'component', glyph: 'bag',      cam: 'torso', comp: 5 },

    { id: 'hat',       label: 'Hat',        cluster: 'props',   kind: 'prop',      glyph: 'hat',      cam: 'torso', prop: 0 },
    { id: 'glasses',   label: 'Glasses',    cluster: 'props',   kind: 'prop',      glyph: 'glasses',  cam: 'torso', prop: 1 },
    { id: 'ear',       label: 'Ear',        cluster: 'props',   kind: 'prop',      glyph: 'ear',      cam: 'torso', prop: 2 },
    { id: 'watch',     label: 'Watch',      cluster: 'props',   kind: 'prop',      glyph: 'watch',    cam: 'torso', prop: 6 },
    { id: 'bracelet',  label: 'Bracelet',   cluster: 'props',   kind: 'prop',      glyph: 'bracelet', cam: 'torso', prop: 7 },

    // Each arm from its own side, the right leg from the front-right (the left from the usual front-left).
    { id: 'tatHead',     label: 'Head',      cluster: 'tattoos', kind: 'tattoos', glyph: 'tattoo', cam: 'torso', zone: 'head',  yaw: 217 },
    { id: 'tatTorso',    label: 'Torso',     cluster: 'tattoos', kind: 'tattoos', glyph: 'tattoo', cam: 'torso', zone: 'torso', yaw: 180 },
    { id: 'tatLeftArm',  label: 'Left Arm',  cluster: 'tattoos', kind: 'tattoos', glyph: 'tattoo', cam: 'torso', zone: 'larm',  yaw: 270 },
    { id: 'tatRightArm', label: 'Right Arm', cluster: 'tattoos', kind: 'tattoos', glyph: 'tattoo', cam: 'torso', zone: 'rarm',  yaw: 90 },
    { id: 'tatLeftLeg',  label: 'Left Leg',  cluster: 'tattoos', kind: 'tattoos', glyph: 'tattoo', cam: 'legs',  zone: 'lleg',  yaw: 217 },
    { id: 'tatRightLeg', label: 'Right Leg', cluster: 'tattoos', kind: 'tattoos', glyph: 'tattoo', cam: 'legs',  zone: 'rleg',  yaw: 143 },

    // The whole body, to see an outfit on.
    { id: 'outfits',     label: 'Saved',     cluster: 'outfits', kind: 'outfits', glyph: 'outfit', cam: 'body' },
];

// The groups, as the panel's top-level switch (its words). CLUSTER_ORDER
// is render order.
export const CLUSTER_ORDER = ['face', 'apparel', 'props', 'tattoos', 'outfits'];
export const CLUSTER_LABELS = { face: 'Face', apparel: 'Apparel', props: 'Accessories', tattoos: 'Tattoos', outfits: 'Outfits' };

// A tattoo's side (TattooList's facing) → the camera's turn round the ped when it goes on (`yaw` above).
export const TATTOO_FACING_YAW = {
    front: 180, back: 0, left: 270, right: 90, frontleft: 225, frontright: 135, chest: 180, stomach: 180,
};

// The most tattoos one character keeps: the server's APPEARANCE_TATTOO_MAX (server/events_misc.lua).
export const TATTOO_MAX = 40;

// Overlays whose color swatches use the hair palette vs the makeup palette —
// mirrors OVERLAY_COLOR_TYPE in client/appearance.lua (1 = hair, 2 = makeup).
// Keys absent here have no color controls at all.
export const OVERLAY_PALETTE = {
    beard: 'hair', eyebrows: 'hair', chestHair: 'hair',
    makeup: 'makeup', blush: 'makeup', lipstick: 'makeup',
};

// ---- Eye colors ----
// GTA's 32 fixed eye colors, with approximate swatch hexes. 12-31 are the
// novelty set; the swatch is a best-effort hint, the ped is the real preview.
export const EYE_COLORS = [
    { name: 'Green',        hex: '#41694c' }, { name: 'Emerald',      hex: '#218352' },
    { name: 'Light Blue',   hex: '#67a3c1' }, { name: 'Ocean Blue',   hex: '#2e5f8a' },
    { name: 'Light Brown',  hex: '#8a6845' }, { name: 'Dark Brown',   hex: '#503c2b' },
    { name: 'Hazel',        hex: '#7a6b3f' }, { name: 'Dark Gray',    hex: '#555a5e' },
    { name: 'Light Gray',   hex: '#9aa2a6' }, { name: 'Pink',         hex: '#c97b9c' },
    { name: 'Yellow',       hex: '#c9b25c' }, { name: 'Purple',       hex: '#6f4f8f' },
    { name: 'Blackout',     hex: '#1b1b1b' }, { name: 'Shades of Gray', hex: '#6e6e6e' },
    { name: 'Tequila Sunrise', hex: '#c56a2b' }, { name: 'Atomic',    hex: '#7fd12e' },
    { name: 'Warp',         hex: '#c22fb0' }, { name: 'ECola',        hex: '#a01f1f' },
    { name: 'Space Ranger', hex: '#2fc2b8' }, { name: 'Ying Yang',    hex: '#e8e8e8' },
    { name: 'Bullseye',     hex: '#b03030' }, { name: 'Lizard',       hex: '#77a02f' },
    { name: 'Dragon',       hex: '#c2842f' }, { name: 'Extra Terrestrial', hex: '#8fb0b5' },
    { name: 'Goat',         hex: '#c2b48f' }, { name: 'Smiley',       hex: '#e0d048' },
    { name: 'Possessed',    hex: '#e8e0d0' }, { name: 'Demon',        hex: '#8a1010' },
    { name: 'Infected',     hex: '#a0b048' }, { name: 'Alien',        hex: '#485ab0' },
    { name: 'Undead',       hex: '#b0a890' }, { name: 'Zombie',       hex: '#606848' },
];

// ---- Hair palette (indices 0-63) ----
// Approximate hexes for SetPedHairColor's fixed palette: naturals first
// (black → brown → blonde), then reds, grays, and the fashion tail. The dye on
// the ped is authoritative; the swatch just has to be recognizably "that one".
export const HAIR_COLORS = [
    '#1b1a1c', '#252325', '#2f2b2c', '#372a25', '#3f2c1e', '#4a331f', '#5b4023', '#6b4c31',
    '#775837', '#82653e', '#8f7246', '#9c8050', '#a98e5c', '#b69c66', '#c4ab72', '#d2ba80',
    '#dcc78e', '#e5d29b', '#ecdcac', '#f2e5bd', '#5e3c26', '#4e2513', '#57120b', '#661410',
    '#711a10', '#7f2214', '#8f2d17', '#a03c1c', '#af4a22', '#bc5b2b', '#c96f38', '#d48147',
    '#3f3f42', '#59595c', '#747477', '#8f8f92', '#a9a9ac', '#c2c2c5', '#d9d9db', '#eeeeef',
    '#26437c', '#2d5aa0', '#3f74b8', '#5b90c9', '#1d5c44', '#2a7a54', '#3f9c66', '#5cba7e',
    '#5b2a72', '#743a90', '#8f4fae', '#aa68c6', '#8f2a5c', '#ae3a74', '#c9548e', '#dd74a6',
    '#9c1f2e', '#b62838', '#cc3644', '#dd4c55', '#c9642a', '#dd7c35', '#e89644', '#f0b055',
];

// ---- Makeup palette (indices 0-63) ----
// SetPedHeadOverlayColor color type 2: reds and pinks up front, then plums,
// oranges, nudes, and the fashion tail. Approximate, same contract as above.
export const MAKEUP_COLORS = [
    '#980c10', '#a4161c', '#b12227', '#bd3232', '#c94545', '#d45b5b', '#dd7272', '#e58a8a',
    '#7c1025', '#8f1a32', '#a22641', '#b43550', '#c44860', '#d25d72', '#df7385', '#ea8b98',
    '#5c1030', '#701a3e', '#84264d', '#96345d', '#a8446e', '#b8567f', '#c76a90', '#d47fa2',
    '#3c1440', '#4e1e52', '#602a64', '#723876', '#844888', '#965a99', '#a76eaa', '#b884bb',
    '#8a2f10', '#9e3f16', '#b2501e', '#c46228', '#d47534', '#e28942', '#ee9e52', '#f7b364',
    '#6e3a20', '#82492a', '#965936', '#a86a44', '#b97b53', '#c88d64', '#d6a077', '#e2b38b',
    '#4a2a1c', '#5a3626', '#6a4331', '#7a513d', '#8a604a', '#9a7058', '#aa8168', '#b99379',
    '#20161a', '#33232a', '#46313a', '#59404a', '#6c505b', '#7f616c', '#92737e', '#a58691',
];
