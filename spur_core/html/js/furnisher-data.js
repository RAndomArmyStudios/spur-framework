// ========================================
// THE FURNISHER — STATIC DATA
//
// Pure data, no DOM: the line-drawn glyphs the rail and the catalog fall back to. Split out of
// furnisher.js for the same reason creator-data.js is split out of creator.js — that file is about
// behaviour and this one is about content, so adding a category's picture touches one file and
// changing how the grid behaves touches the other.
//
// EVERYTHING ELSE COMES FROM THE SERVER. The clusters, the categories and the props themselves
// arrive in the propCatalogSync payload (server/prop_catalog.lua), so adding a category to
// config.lua reaches the editor without a second list here to keep in step. What CANNOT travel
// that way is artwork, which is why the glyph a category names is looked up in the map below.
// ========================================

// One consistent stroke system, copied deliberately from creator-data.js: 24-unit grid, 1.5 stroke,
// currentColor so the CSS owns the tint. Authored geometry rather than emoji — an icon that
// inherits hover and selection colour for free, and never fights the font stack.
function svg(inner) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" '
        + 'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + inner + '</svg>';
}

export const GLYPHS = {
    sofa:    svg('<path d="M5 12V8a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v4"/><path d="M3 12.5a1.5 1.5 0 0 1 3 0V15h12v-2.5a1.5 1.5 0 0 1 3 0V18H3Z"/><path d="M5.5 18v2"/><path d="M18.5 18v2"/>'),
    table:   svg('<path d="M2.5 9h19"/><path d="M5 9v10"/><path d="M19 9v10"/><path d="M5 13h14"/>'),
    cabinet: svg('<rect x="4.5" y="4" width="15" height="16" rx="1.5"/><path d="M12 4v16"/><path d="M9.6 11.5h.01"/><path d="M14.4 11.5h.01"/>'),
    bed:     svg('<path d="M3 19v-9a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2h8a2 2 0 0 1 2 2v5"/><path d="M3 15h18"/>'),
    pan:     svg('<path d="M3 11h12v2a5 5 0 0 1-5 5H8a5 5 0 0 1-5-5v-2Z"/><path d="M15 12h6"/>'),
    tap:     svg('<path d="M4 13h16"/><path d="M4 13a8 8 0 0 0 16 0"/><path d="M12 13V8a3 3 0 0 1 3-3h1.5"/><path d="M14.5 5V3.5"/>'),
    lamp:    svg('<path d="M8 4h8l3 7H5l3-7Z"/><path d="M12 11v8"/><path d="M8.5 19.5h7"/>'),
    tv:      svg('<rect x="2.5" y="5" width="19" height="12" rx="1.5"/><path d="M8 20.5h8"/><path d="M12 17v3.5"/>'),
    frame:   svg('<rect x="4" y="4" width="16" height="16" rx="1.5"/><path d="M7 16l3.5-4.5 2.5 3 2-2.5L17 16Z"/>'),
    plant:   svg('<path d="M8 20h8l-.9-6H8.9L8 20Z"/><path d="M12 14c0-3 1.5-5.5 4-6.5-.5 3-2 5.5-4 6.5Z"/><path d="M12 14c0-2.5-1.5-4.5-4-5 .5 2.5 2 4.5 4 5Z"/><path d="M12 14V9"/>'),
    rug:     svg('<path d="M3 8h18l-2.5 9H5.5L3 8Z"/><path d="M6.5 11h11"/><path d="M7.5 14h9"/>'),
    box:     svg('<path d="M3.5 7.5 12 4l8.5 3.5v9L12 20l-8.5-3.5v-9Z"/><path d="M3.5 7.5 12 11l8.5-3.5"/><path d="M12 11v9"/>'),
    // Scenes (the Director's props) and the world builder's tabs.
    barrier: svg('<rect x="3" y="7" width="18" height="6" rx="1"/><path d="M7 7l-3 6"/><path d="M12 7l-3 6"/><path d="M17 7l-3 6"/><path d="M6 13v6"/><path d="M18 13v6"/>'),
    cash:    svg('<rect x="2.5" y="6.5" width="19" height="11" rx="1.5"/><circle cx="12" cy="12" r="2.5"/><path d="M6 9.5v5"/><path d="M18 9.5v5"/>'),
    bag:     svg('<path d="M5 9h14l-1 11H6L5 9Z"/><path d="M9 9V7a3 3 0 0 1 6 0v2"/>'),
    wrench:  svg('<path d="M14.5 5.5a4 4 0 0 0 4.9 4.9L11 18.8a2 2 0 0 1-2.8-2.8l8.4-8.4"/><path d="M14.5 5.5 17 3l1.5 3.5L22 8l-2.6 2.4"/>'),
    tent:    svg('<path d="M3 20 12 4l9 16H3Z"/><path d="M12 4v16"/><path d="M9 20l3-6 3 6"/>'),
    person:  svg('<circle cx="12" cy="7" r="3.5"/><path d="M5 20.5a7 7 0 0 1 14 0"/>'),
    paw:     svg('<ellipse cx="12" cy="16" rx="4.5" ry="3.8"/><circle cx="6" cy="10.5" r="1.8"/><circle cx="9.5" cy="6.5" r="1.8"/><circle cx="14.5" cy="6.5" r="1.8"/><circle cx="18" cy="10.5" r="1.8"/>'),
    // The world builder's NPCs: a lore character (Lore characters), and a ped typed by its name (Input ped name).
    star:    svg('<path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.8l-5.2 2.8 1-5.8-4.3-4.1 5.9-.9Z"/>'),
    keyboard: svg('<rect x="2.5" y="6" width="19" height="12" rx="1.5"/><path d="M6 10h.01M9.5 10h.01M13 10h.01M16.5 10h.01M8.5 14h7"/>'),
    car:     svg('<path d="M4 15v-3l2-5h12l2 5v3"/><path d="M3 15h18v3H3Z"/><circle cx="7.5" cy="18" r="1.5"/><circle cx="16.5" cy="18" r="1.5"/><path d="M6.5 12h11"/>'),
    pin:     svg('<path d="M12 21s-6.5-6.2-6.5-11a6.5 6.5 0 0 1 13 0c0 4.8-6.5 11-6.5 11Z"/><circle cx="12" cy="10" r="2.5"/>'),
    door:    svg('<path d="M6 21V4a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v17"/><path d="M4 21h16"/><path d="M14.5 12.5h.01"/>'),
    chest:   svg('<rect x="3.5" y="9" width="17" height="10" rx="1"/><path d="M3.5 9a8.5 4.5 0 0 1 17 0"/><path d="M3.5 13h17"/><path d="M11 12h2v3h-2Z"/>'),
    // Every prop in the game (28 Oct 2026): the categories and clusters past the furniture ones (config.lua).
    food:      svg('<path d="M6.5 8h11l-1.3 12H7.8L6.5 8Z"/><path d="M5 8h14"/><path d="M12.5 8l1.5-4.5h3"/>'),
    briefcase: svg('<rect x="3" y="7.5" width="18" height="12" rx="1.5"/><path d="M9 7.5v-2a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/><path d="M3 12.5h18"/>'),
    shirt:     svg('<path d="M8 4 3.5 6.5 5 11l2-.8V20h10v-9.8l2 .8 1.5-4.5L16 4"/><path d="M8 4a4 3 0 0 0 8 0"/>'),
    medkit:    svg('<rect x="3.5" y="7" width="17" height="12.5" rx="1.5"/><path d="M9 7V5h6v2"/><path d="M12 10.5V16"/><path d="M9.25 13.25h5.5"/>'),
    bin:       svg('<path d="M5 7h14"/><path d="M10 7V5h4v2"/><path d="M6.5 7l1 13h9l1-13"/><path d="M10 10.5V17"/><path d="M14 10.5V17"/>'),
    gun:       svg('<path d="M3 7.5h17.5v4h-9l-1.2 7.5H6.8l1.3-7.5H3Z"/><path d="M11.5 11.5c0 2 1 2.5 2.5 2.5"/>'),
    pill:      svg('<rect x="2.8" y="8.5" width="18.4" height="7" rx="3.5" transform="rotate(-45 12 12)"/><path d="M9.5 9.5l5 5"/>'),
    dice:      svg('<rect x="4" y="4" width="16" height="16" rx="2.5"/><path d="M8.5 8.5h.01M15.5 8.5h.01M12 12h.01M8.5 15.5h.01M15.5 15.5h.01"/>'),
    ball:      svg('<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17"/><path d="M12 3.5a12 12 0 0 1 0 17"/><path d="M12 3.5a12 12 0 0 0 0 17"/>'),
    note:      svg('<path d="M9 18V5.5l10-2v12"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="16.5" cy="15.5" r="2.5"/>'),
    ramp:      svg('<path d="M3 19 21 9v10H3Z"/><path d="M15 12.4V19"/>'),
    sign:      svg('<path d="M12 3v18"/><path d="M5 6h11l3 2.5L16 11H5V6Z"/><path d="M9 21h6"/>'),
    building:  svg('<path d="M4 21V5l8-2v18"/><path d="M12 8l8 2v11"/><path d="M3 21h18"/><path d="M7 8h2M7 12h2M7 16h2M15 13h2M15 17h2"/>'),
    wheel:     svg('<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="3"/><path d="M12 3.5V9M12 15v5.5M3.5 12H9M15 12h5.5"/>'),
    tree:      svg('<path d="M12 3l6 8h-3.5l4.5 6H5l4.5-6H6l6-8Z"/><path d="M12 17v4"/>'),
    // What a category with no glyph of its own, or one naming a glyph that is not here, draws.
    // A missing picture must never be a missing card.
    none:    svg('<circle cx="12" cy="12" r="8.5"/><path d="M6 6l12 12"/>'),
};
