// Dashboard skins for the 3D dial (hud3d.js setSkin): each sets the face colour, fonts, numeral / tick / red colours
// and the needle; the dial itself is unchanged. skinFor() gives null for a vehicle with no skin: the default dial.
// RedM (spur_core, 26 Nov 2026): whip_core's skins were made from GTA V's cars' dial art, another game's, and are
// gone. Every list is empty until SPUR has dials of its own.
// SKIN_FONTS: every font family the skins may use (Google Fonts, except Times New Roman); a host loads the ones it needs.
export const SKIN_FONTS = ["Archivo Narrow", "Arimo", "Barlow", "Barlow Condensed", "Michroma", "Orbitron", "Rajdhani", "Russo One", "Saira", "Saira Condensed", "Saira Semi Condensed", "Times New Roman"];
export const SKINS = {};
// merged dial id -> the skin that stands for it
export const SKIN_ALIAS = {};
// spawn name -> skin id
export const SKIN_OF = {};
export const skinFor = (spawn) => SKINS[SKIN_OF[String(spawn || '').toLowerCase()]] || null;
