// RedM (spur_phone, 24 Nov 2026): rewritten. The notebook's look: CSS layered over the base stylesheet (style.js),
// a default cover and the name it goes by. whip_phone's was night glass with the WHIP wordmark and web fonts; this is
// ink on paper in a leather cover, in the fonts every Windows machine has (Georgia, Palatino Linotype, Book Antiqua
// for the hand, Courier New for the telegraph's typewriter). No logo and no font files.
//
// The cover's colours come per page as CSS variables (wallpaper.js makeWallpaper → os.js View.paintWallpaper):
// --cover (the leather), --ribbon (the bookmark), --paper (the leaves).
//
// Interface kept for os.js: THEMES, DEFAULT_THEME, themeCSS(id).

const PAPER = `
.os-screen,.os-screen.light{
  --font-ui:Georgia,'Palatino Linotype','Book Antiqua',Palatino,'Times New Roman',serif;
  --font-display:Georgia,'Palatino Linotype','Book Antiqua',serif;--font-head:'Palatino Linotype','Book Antiqua',Georgia,serif;
  --font-mono:'Courier New',Courier,monospace;
  --r-icon:50%;--r-card:2px;--r-tile:3px;--r-btn:3px;--r-dock:0;--r-sheet:3px;--r-field:2px;
  --paper:#efe4cc;--cover:#8a5a32;--ribbon:#6e1b1b;
  --ink:#2a2118;--ink-soft:rgba(42,33,24,.62);
  --bg:var(--paper);--bg2:rgba(255,250,235,.5);--bg3:rgba(60,40,20,.08);--bg4:rgba(60,40,20,.14);
  --fill:rgba(60,40,20,.08);--fill2:rgba(60,40,20,.16);
  --text:var(--ink);--text2:rgba(42,33,24,.64);--text3:rgba(42,33,24,.36);--sep:rgba(60,40,20,.24);
  --accent:#7a1f1f;--green:#3d6b3a;--red:#9b2a1f;--orange:#a8641d;--yellow:#a8842a;--purple:#5b3a6b;--pink:#8b3a5a;--teal:#2f6b6b;--indigo:#34406b;
  --bubble-them:#f2e3b3;--glass:var(--paper);--sb-color:var(--ink);
  --slip:#f7efdc;--form:#f2e3b3;
  background:var(--paper);color:var(--ink);font-weight:400;
}
.os-screen.phone{--sb-h:50px;border-radius:2px 5px 5px 2px}
.os-screen.tablet{--sb-h:34px;border-radius:3px}
/* the spread's gutter, over the index (under the cover and the pages' own) */
.os-screen.tablet:not(.portrait)::after{content:'';position:absolute;top:0;bottom:0;left:50%;width:40px;margin-left:-20px;pointer-events:none;z-index:25;
  background:linear-gradient(90deg,rgba(60,40,20,0),rgba(60,40,20,.12) 40%,rgba(60,40,20,.26) 50%,rgba(60,40,20,.12) 60%,rgba(60,40,20,0))}
.os-screen .punch{display:none}
.os-screen .big-title{font-family:var(--font-head);font-weight:700;font-style:italic;letter-spacing:0;border-bottom:1px solid var(--sep);margin:0 18px 10px;padding:0 0 6px}
.os-screen.tablet .big-title{margin:4px 26px 12px;padding:0 0 8px}
.os-screen .list-h{font-size:11.5px;font-weight:700;letter-spacing:1.6px;color:var(--text2)}
.os-screen .nav .back,.os-screen .nav .n-act{font-style:italic}
.os-screen .nav .n-title{font-family:var(--font-head);font-weight:700;letter-spacing:.2px}

/* ---- the page's head line: time and date in ink, the ribbon hanging at the right */
.os-screen .sb{color:var(--sb-color);font-weight:400;font-style:italic}
.os-screen.phone .sb{padding:0 22px 0 24px;font-size:14px}
.os-screen.tablet .sb{padding:0 30px;font-size:13px}
.os-screen .sb-r{align-self:flex-start;padding:0 0 6px 14px}
.os-screen .ribbon-tab{display:block;width:13px;height:34px;background:var(--ribbon);clip-path:polygon(0 0,100% 0,100% 100%,50% 76%,0 100%);
  box-shadow:0 2px 3px rgba(0,0,0,.35);transition:height .2s}
.os-screen.tablet .ribbon-tab{height:28px}
.os-screen .sb-r:hover .ribbon-tab{height:40px}
.os-screen.cc-open .sb,.os-screen.in-call .sb{--sb-color:var(--ink)}
.os-screen.locked .sb{--sb-color:rgba(243,231,204,.85)}

/* ---- the cover (lock screen): leather, a paper label with the owner's name, a strap */
.os-screen .lock-clock{display:none}
.os-screen .lock{color:#f3e7cc;background-color:var(--cover);
  background-image:radial-gradient(ellipse at 30% 20%,rgba(255,255,255,.1),transparent 60%),radial-gradient(ellipse at 80% 90%,rgba(0,0,0,.25),transparent 55%),
    repeating-linear-gradient(35deg,rgba(0,0,0,.04) 0 2px,transparent 2px 5px);
  box-shadow:inset 0 0 0 6px rgba(0,0,0,.12),inset 0 0 30px rgba(0,0,0,.35)}
.os-screen .lock::after{content:'';position:absolute;top:0;bottom:0;right:16%;width:9px;background:rgba(0,0,0,.42);box-shadow:1px 0 0 rgba(255,255,255,.06);pointer-events:none}
.os-screen .cover-label{position:absolute;left:50%;transform:translateX(-50%);width:62%;padding:14px 10px 12px;text-align:center;
  background:#efe4cc;color:#2a2118;font-family:var(--font-head);border:1px solid rgba(0,0,0,.45);
  box-shadow:inset 0 0 0 3px #efe4cc,inset 0 0 0 4px rgba(42,33,24,.55),0 2px 6px rgba(0,0,0,.4)}
.os-screen.phone .cover-label{top:20%}
.os-screen.tablet .cover-label{top:16%;width:34%}
.os-screen .cover-label b{display:block;font-size:19px;font-style:italic;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.os-screen .cover-label span{display:block;margin-top:4px;font-size:10.5px;letter-spacing:3.5px;text-transform:uppercase;color:rgba(42,33,24,.7)}
.os-screen .unlock-hint{font-style:italic;font-weight:400;color:rgba(243,231,204,.8);text-shadow:none}
.os-screen.phone .notifs{bottom:84px}
.os-screen .notif{background:var(--slip);color:var(--ink);border-radius:2px;border:1px solid rgba(60,40,20,.3);
  backdrop-filter:none;-webkit-backdrop-filter:none;box-shadow:0 3px 8px rgba(0,0,0,.4);transform:rotate(-.4deg)}
.os-screen .notif:nth-child(2n){transform:rotate(.5deg)}
.os-screen .notif .n-top{color:var(--text2)}
.os-screen .notif .n-title{font-weight:700}
.os-screen .notif .n-text{color:var(--ink)}

/* ---- the index (home): ink stamps for the pages, a ruled foot instead of a dock */
.os-screen .app-icon{color:var(--ink);text-shadow:none;font-weight:400}
.os-screen .app-icon span{font-family:var(--font-head);font-size:12.5px;font-style:italic}
.os-screen .ico,.os-screen .ico.cal{background:none!important;color:var(--ink);box-shadow:none;border-radius:50%;overflow:visible}
.os-screen .ico::after{inset:4%;border-radius:50%;box-shadow:none;border:1.6px solid currentColor;opacity:.85}
.os-screen .ico::before{content:'';position:absolute;inset:13%;border-radius:50%;border:.8px solid currentColor;opacity:.45}
.os-screen .ico svg{width:48%;height:48%;position:relative}
.os-screen .ico svg[fill="#fff"],.os-screen .ico svg [fill="#fff"]{fill:currentColor}
.os-screen .ico svg[stroke="#fff"],.os-screen .ico svg [stroke="#fff"]{stroke:currentColor}
.os-screen.mk .app-icon .ico{transition:transform .16s,color .16s}
.os-screen.mk.in-mouse .app-icon:hover .ico{transform:rotate(-6deg);color:var(--accent)}
.os-screen .dock{background:none;backdrop-filter:none;-webkit-backdrop-filter:none;border-radius:0;border-top:1px solid var(--sep);box-shadow:none}
.os-screen.phone .dock{left:22px;right:22px;bottom:18px;height:82px}
.os-screen .tablet .dock .div,.os-screen.tablet .dock .div{background:var(--sep)}
.os-screen .dots i,.os-screen .dots button{background:rgba(42,33,24,.25)}
.os-screen .dots i.on,.os-screen .dots button.on{background:var(--ink)}
.os-screen .home.arranging .slot .ico-ghost{box-shadow:inset 0 0 0 1.5px var(--sep);border-radius:50%}
.os-screen .home.arranging .slot.over .ico-ghost{background:var(--fill);box-shadow:inset 0 0 0 2px var(--ink)}
.os-screen .app-icon.held .ico,.os-screen .app-icon.over .ico{box-shadow:0 0 0 2px var(--ink)}
.os-screen .empty-home{color:var(--ink);text-shadow:none}
.os-screen .empty-home span{color:var(--text2)}
/* controller index: index cards */
.os-screen .chome .ch-title{color:var(--ink);text-shadow:none;font-style:italic}
.os-screen .chome .pg{background:transparent;color:var(--text2);box-shadow:inset 0 0 0 1px var(--sep);border-radius:2px}
.os-screen .chome .pg.on{background:var(--ink);color:var(--paper);box-shadow:none}
.os-screen .tile{background:var(--slip);color:var(--ink);border:1px solid var(--sep);border-radius:2px;box-shadow:0 2px 5px rgba(60,40,20,.18);font-weight:400;font-family:var(--font-head)}
.os-screen .chome .ch-info{color:var(--ink);text-shadow:none}
.os-screen .ch-info span{color:var(--text2)}

/* ---- pages (apps): paper, ink, hairlines */
.os-screen .app-win,.os-screen .app{background:var(--paper)}
.os-screen .split>.side,.os-screen .split>.main,.os-screen .chat-h,.os-screen .composer{background:transparent}
.os-screen.tablet:not(.portrait) .split>.side{width:50%;border-right:0;box-shadow:inset -16px 0 18px -16px rgba(60,40,20,.4)}
.os-screen.tablet:not(.portrait) .split>.main{box-shadow:inset 16px 0 18px -16px rgba(60,40,20,.4)}
.os-screen .list{background:var(--bg2);border:1px solid var(--sep);border-radius:2px;box-shadow:none}
.os-screen .row{font-size:15.5px}
.os-screen .row .r-ico{background:none!important;color:var(--ink)!important;box-shadow:inset 0 0 0 1.2px var(--sep);border-radius:50%}
.os-screen .row .r-ico svg[fill="#fff"],.os-screen .row .r-ico svg [fill="#fff"]{fill:currentColor}
.os-screen .row.sel,.os-screen .thread.sel,.os-screen .mail-row.sel{background:var(--ink);color:var(--paper)}
.os-screen .row.sel .r-sub,.os-screen .row.sel .r-val{color:rgba(239,228,204,.75)}
.os-screen .row.sel .av,.os-screen .thread.sel .av,.os-screen .mail-row.sel .av{background:var(--slip);color:var(--ink)}
.os-screen .thread.sel .t-time,.os-screen .thread.sel .t-prev{color:rgba(239,228,204,.75)}
.os-screen .row.sel .r-ico{color:var(--paper)!important;box-shadow:inset 0 0 0 1.2px rgba(239,228,204,.45)}
.os-screen .row.sel .chev{color:rgba(239,228,204,.6)}
.os-screen .row:active{background:var(--fill)}
.os-screen .sw{background:rgba(60,40,20,.18);border-radius:3px;width:46px;height:26px}
.os-screen .sw::after{width:20px;height:20px;top:3px;left:3px;border-radius:2px;background:var(--paper);box-shadow:0 1px 2px rgba(0,0,0,.35)}
.os-screen .sw.on{background:var(--ink)}
.os-screen .sw.on::after{transform:translateX(20px)}
.os-screen .btn{height:40px;border-radius:3px;background:var(--ink);color:var(--paper);font-family:var(--font-head);font-weight:700;font-size:15px;letter-spacing:.3px}
.os-screen .btn.gray{background:transparent;color:var(--ink);box-shadow:inset 0 0 0 1.2px var(--ink)}
.os-screen .btn.red{background:var(--red);color:var(--slip)}
.os-screen .btn.green{background:var(--green);color:var(--slip)}
.os-screen .btn.ghost{background:transparent;color:var(--accent);box-shadow:none;font-style:italic}
.os-screen .btn[disabled],.os-screen .btn.off{opacity:.45;cursor:default}
.os-screen .seg{background:transparent;box-shadow:inset 0 0 0 1px var(--sep);border-radius:3px}
.os-screen .seg button{border-radius:2px;font-family:var(--font-head)}
.os-screen .seg button.on{background:var(--ink);color:var(--paper);box-shadow:none}
.os-screen .search{background:transparent;border-radius:0;border-bottom:1px solid var(--sep);color:var(--text2)}
.os-screen .pill{border-radius:2px;font-family:var(--font-head)}
.os-screen .av{background:rgba(60,40,20,.1);color:var(--ink);box-shadow:inset 0 0 0 1px var(--sep)}
.os-screen .tabbar{background:transparent;border-top:1px solid var(--sep)}
.os-screen .tabbar button{font-family:var(--font-head);font-style:italic}
.os-screen .tabbar button.on{color:var(--accent)}
.os-screen .tabbar .t-badge,.os-screen .badge{background:#8b1e1e;color:var(--slip);font-family:var(--font-ui);box-shadow:0 1px 2px rgba(0,0,0,.35)}
.os-screen .kempty i{color:var(--text3)}
.os-screen .kempty b{font-family:var(--font-head);font-style:italic}
.os-screen input[type=range]{background:rgba(60,40,20,.2)}
.os-screen input[type=range]::-webkit-slider-thumb{background:var(--ink);border-radius:2px;width:14px;height:24px}
/* telegrams: typed on forms. Ones received are on the yellow blank, ones sent on the office copy */
.os-screen .bub{border-radius:2px;font-family:var(--font-mono);font-size:14.5px;line-height:1.35;letter-spacing:.1px;padding:8px 12px}
.os-screen .bub.me{background:var(--slip);color:var(--ink);border:1px solid rgba(60,40,20,.35);box-shadow:1px 2px 0 rgba(60,40,20,.12)}
.os-screen .bub.them{background:var(--form);color:var(--ink);border:1px solid rgba(60,40,20,.28);box-shadow:-1px 2px 0 rgba(60,40,20,.1)}
.os-screen .typing{background:var(--form);border-radius:2px}
.os-screen .composer .field{border:0;border-bottom:1.2px solid var(--ink);border-radius:0;background:transparent}
.os-screen .composer input{font-family:var(--font-mono)}
.os-screen .composer .send{background:var(--ink);border-radius:2px}
.os-screen .composer .plus{background:transparent;box-shadow:inset 0 0 0 1px var(--sep);color:var(--ink)}
.os-screen .qr{background:transparent;border-radius:2px;font-family:var(--font-head)}
.os-screen .sheet{background:var(--paper);box-shadow:0 -8px 26px rgba(0,0,0,.35);border-top:1px solid var(--sep)}
.os-screen.tablet .sheet{border:1px solid var(--sep)}
.os-screen .sheet h3{font-family:var(--font-head);font-style:italic}
.os-screen .sheet .grab{background:var(--sep)}
.os-screen .sheet-bg{background:rgba(40,28,16,.38)}
.os-screen .toast{background:var(--ink);color:var(--paper);border-radius:3px;font-style:italic}
.os-screen .card{background:var(--slip);color:var(--ink);border:1px solid var(--sep);box-shadow:0 2px 6px rgba(60,40,20,.2)}
.os-screen .card::after{display:none}
.os-screen .fab{background:var(--ink);color:var(--paper)}

/* ---- the ribbon (was the Control Centre): paper slips over a dimmed page */
.os-screen .cc{background:rgba(40,28,16,.4);backdrop-filter:none;-webkit-backdrop-filter:none;color:var(--ink)}
.os-screen .cc-tile{background:var(--slip);color:var(--ink);border:1px solid var(--sep);border-radius:2px;box-shadow:0 3px 8px rgba(0,0,0,.3);font-family:var(--font-head)}
.os-screen .cc-tile svg[fill="#fff"],.os-screen .cc-tile svg [fill="#fff"]{fill:currentColor}
.os-screen .cc-tile svg[stroke="#fff"]{stroke:currentColor}
.os-screen .cc-tile.on{background:var(--ink);color:var(--paper)}
.os-screen .cc-tile .cc-ico{color:inherit}
.os-screen .cc-tile.cc-fold{background:var(--ribbon);color:#f3e7cc;border-color:rgba(0,0,0,.3)}
.os-screen .cc-fold svg{stroke:#f3e7cc}

/* ---- notices (banners): slips of paper; the call's Answer / Decline as inked discs */
.os-screen .banner{background:var(--slip);color:var(--ink);border-radius:2px;border:1px solid rgba(60,40,20,.32);
  backdrop-filter:none;-webkit-backdrop-filter:none;box-shadow:0 6px 16px rgba(0,0,0,.35);padding:8px 12px;min-height:58px}
.os-screen.phone .banner{left:12px;right:12px;top:calc(60px + var(--i, 0) * 66px)}
.os-screen.tablet .banner{top:calc(40px + var(--i, 0) * 66px)}
.os-screen .banner .ico{width:38px;height:38px;font-size:38px}
.os-screen .banner .b-t{font-family:var(--font-head);font-weight:700}
.os-screen .banner .b-t span{font-weight:400;font-style:italic;opacity:.65}
.os-screen .banner .b-x{opacity:1}
.os-screen .banner[data-kind="error"]{border-left:4px solid var(--red)}
.os-screen .banner[data-kind="warning"]{border-left:4px solid var(--orange)}
.os-screen .banner[data-kind="success"]{border-left:4px solid var(--green)}
.os-screen .banner .b-acts{display:flex;gap:8px;margin-left:10px;flex:none}
.os-screen .banner .b-act{width:40px;height:40px;border-radius:50%;display:grid;place-items:center;background:var(--ink);color:var(--slip)}
.os-screen .banner .b-act svg{width:46%;height:46%}
.os-screen .banner .b-act.t-accept{background:var(--green)}
.os-screen .banner .b-act.t-reject{background:var(--red)}

/* ---- the foot line (home), the controller's hints, the highlight */
.os-screen .home-bar{background:rgba(42,33,24,.5);height:3px;border-radius:2px}
.os-screen.locked .home-bar{background:rgba(243,231,204,.45)}
.os-screen.app-open .home-bar,.os-screen.app-open.sb-light .home-bar,.os-screen.app-open.sb-dark .home-bar{background:rgba(42,33,24,.5)}
.os-screen .hints{background:var(--paper);border-top:1px solid var(--sep)}
.os-screen .hint{color:var(--text2);font-family:var(--font-head)}
.os-screen .hint:hover,.os-screen.in-mouse .hint{background:var(--fill);color:var(--ink);box-shadow:none}
.os-screen .kg{color:var(--ink);box-shadow:inset 0 0 0 1.5px rgba(42,33,24,.6);font-family:var(--font-ui)}
.os-screen .kg.k-keys{box-shadow:inset 0 0 0 1px rgba(42,33,24,.5),inset 0 -2px 0 rgba(42,33,24,.15)}
.os-screen.mk.in-mouse .row:hover,.os-screen.mk.in-mouse .thread:hover,.os-screen.mk.in-mouse .mail-row:hover,.os-screen.mk.in-mouse .notif:hover{background:rgba(60,40,20,.07)}
.os-screen.mk .kf,.os-screen.console .kf{box-shadow:0 0 0 2px var(--ink),0 0 0 5px rgba(60,40,20,.15)!important}
.os-screen.mk .row.kf,.os-screen.mk .thread.kf,.os-screen.mk .mail-row.kf,
.os-screen.console .row.kf,.os-screen.console .thread.kf,.os-screen.console .mail-row.kf,.os-screen.console .qr.kf,.os-screen.console .pg.kf,
.os-screen.console .notif.kf,.os-screen.console .tile.kf{background:var(--ink)!important;color:var(--paper)!important;box-shadow:0 4px 12px rgba(60,40,20,.3)!important}
.os-screen.mk .kf .r-sub,.os-screen.mk .kf .r-val,.os-screen.console .kf .r-sub,.os-screen.console .kf .r-val,.os-screen.console .kf .chev,
.os-screen.console .notif.kf .n-top,.os-screen.console .notif.kf .n-text{color:rgba(239,228,204,.75)!important}
.os-screen.mk .app-icon.kf{box-shadow:none!important}
.os-screen.mk .app-icon.kf .ico{color:var(--accent);box-shadow:none;transform:rotate(-6deg)}
.os-screen .lock.kf{box-shadow:none!important}

/* ---- no voice system: over the Telephone page, with a way back to the index */
.os-screen .voice-down{background:var(--paper);color:var(--ink);font-family:var(--font-head);font-weight:400;font-style:italic}
.os-screen .voice-down .vd-icon{color:var(--red)}
.os-screen .voice-down .vd-back{margin-top:6px;font-style:normal}
`;

export const THEMES = {
  paper: {
    name: 'Paper', note: 'ink on paper in a leather cover', osName: 'Memoranda', logo: false, darkOnly: false,
    wallpaper: 'tan', css: PAPER,
  },
};
export const DEFAULT_THEME = 'paper';   // the notebook has one look (the theme plumbing stays so it can change in one place)

/** CSS text for a theme (no font files: system fonts only). */
export function themeCSS(id) {
  const t = THEMES[id] || THEMES[DEFAULT_THEME];
  return `${t.fontFace || ''}\n${t.css || ''}`;
}
