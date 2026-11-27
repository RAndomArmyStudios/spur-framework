// ========================================
// THE SPEECH TASK'S VOICES AND LINES (html/js/director/panels.js)
//
// RedM (spur_core, 26 Nov 2026): whip_core listed GTA V's voices and lines here. They are another game's and are
// gone; the lists are empty until RDR2's are gathered, so a speech step's Voice and Line are plain fields.
// Each voice is [ its name, its label, its group (a: passers-by, g: gangs, s: jobs and services, n: others),
// which lines it has (a bit each, base64) ].
// ========================================

export const SPEECH_LINES = [];

export const SPEECH_VOICES = [];

/** The voices as the page reads them: { lines, voices: [ { name, label, group, lines: [line index] } ], byName }. */
export function readSpeech() {
    const voices = SPEECH_VOICES.map(([name, label, group, b64]) => {
        const bin = atob(b64);
        const has = [];
        for (let i = 0; i < SPEECH_LINES.length; i++) if (bin.charCodeAt(i >> 3) & (1 << (i & 7))) has.push(i);
        return { name, label, group, lines: has };
    });
    return { lines: SPEECH_LINES, voices, byName: new Map(voices.map((v) => [v.name, v])) };
}
