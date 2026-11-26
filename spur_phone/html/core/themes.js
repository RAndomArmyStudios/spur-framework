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

/* ---- the index (home): a ruled contents page. RedM (spur_phone, 25 Nov 2026): it was a grid of round stamps over a
   dock, which still read as a telephone's home screen. Now every page of the book is an entry written on a line, with
   a leader and its page number; the pages kept at hand are index tabs on the fore-edge (closed book) or a list on the
   facing page (open book), beside the owner's bookplate. --line is the ruling's pitch, --top where the first line starts. */
.os-screen{--rule:rgba(52,74,110,.26);--margin:rgba(150,40,40,.42)}
.os-screen.phone{--line:25px;--top:98px;--lm:44px}
.os-screen.tablet{--line:40px;--top:108px;--lm:68px}
.os-screen.tablet.portrait{--top:124px}
.os-screen .home::before{content:'';position:absolute;left:0;right:0;top:var(--top);bottom:54px;pointer-events:none;
  background:radial-gradient(ellipse at 88% 100%,rgba(120,80,30,.13),transparent 46%),
    linear-gradient(to bottom,transparent calc(var(--line) - 1px),var(--rule) calc(var(--line) - 1px)) 0 0/100% var(--line)}
.os-screen .home::after{content:'';position:absolute;top:0;bottom:0;left:calc(var(--lm) - 11px);width:1px;background:var(--margin);pointer-events:none}
.os-screen .idx-head{position:absolute;left:var(--lm);right:50px;top:calc(var(--top) - 44px);height:38px;box-sizing:border-box;display:flex;align-items:flex-end;justify-content:space-between;
  padding-bottom:4px;border-bottom:3px double rgba(42,33,24,.7);font-family:var(--font-head);color:var(--ink)}
.os-screen .idx-head b{font-size:25px;font-style:italic;font-weight:700;line-height:1}
.os-screen .idx-head i{font-size:11px;letter-spacing:1.5px;text-transform:uppercase;font-style:normal;color:var(--text2)}
.os-screen.tablet .idx-head b{font-size:31px}
.os-screen.tablet:not(.portrait) .idx-head{right:calc(50% + 46px)}
.os-screen.tablet.portrait .idx-head{right:76px}
.os-screen .home .grid{left:var(--lm);right:50px;top:var(--top);grid-template-columns:1fr;row-gap:0;grid-auto-rows:var(--line)}
.os-screen.tablet:not(.portrait) .home .grid{right:calc(50% + 46px)}
.os-screen.tablet.portrait .home .grid{left:var(--lm);right:76px;top:var(--top);grid-template-columns:1fr;row-gap:0}
/* an entry: a small ink mark, the name, dots, the page number */
.os-screen .app-icon,.os-screen .tile{color:var(--ink);text-shadow:none;font-weight:400}
.os-screen .grid .app-icon,.os-screen .tile{flex-direction:row;align-items:center;justify-content:flex-start;gap:8px;height:var(--line);padding:0 2px 1px;
  counter-increment:pg;font-size:inherit;text-align:left;background:none;border:0;border-radius:0;box-shadow:none}
.os-screen.tablet .grid .app-icon,.os-screen.tablet .tile{gap:11px}
.os-screen .grid .app-icon span,.os-screen .tile span{order:1;font-family:var(--font-head);font-size:17px;font-style:italic;line-height:1.15;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.os-screen.tablet .grid .app-icon span,.os-screen.tablet .tile span{font-size:22px}
.os-screen .grid .app-icon::after,.os-screen .tile::after{content:'';order:3;flex:1 1 12px;min-width:12px;align-self:flex-end;margin:0 2px 6px;border-bottom:2px dotted rgba(42,33,24,.6)}
.os-screen.tablet .grid .app-icon::after,.os-screen.tablet .tile::after{margin-bottom:11px}
.os-screen .grid .app-icon::before,.os-screen .tile::before{content:counter(pg);order:4;min-width:16px;text-align:right;font-family:var(--font-head);font-size:15px;font-style:italic;color:var(--text2)}
.os-screen.tablet .grid .app-icon::before,.os-screen.tablet .tile::before{font-size:19px}
.os-screen .ico,.os-screen .ico.cal{background:none!important;color:var(--ink);box-shadow:none;border-radius:50%;overflow:visible}
.os-screen .ico::after{inset:4%;border-radius:50%;box-shadow:none;border:1.6px solid currentColor;opacity:.85}
.os-screen .ico::before{content:'';position:absolute;inset:13%;border-radius:50%;border:.8px solid currentColor;opacity:.45}
.os-screen .ico svg{width:48%;height:48%;position:relative}
.os-screen .ico svg[fill="#fff"],.os-screen .ico svg [fill="#fff"]{fill:currentColor}
.os-screen .ico svg[stroke="#fff"],.os-screen .ico svg [stroke="#fff"]{stroke:currentColor}
.os-screen .grid .ico,.os-screen .tile .ico,.os-screen.mk .grid .ico{order:0;flex:none;width:19px;height:19px;font-size:19px}
.os-screen.tablet .grid .ico,.os-screen.tablet .tile .ico,.os-screen.mk.tablet .grid .ico{width:27px;height:27px;font-size:27px}
.os-screen .grid .ico::before,.os-screen .grid .ico::after,.os-screen .tile .ico::before,.os-screen .tile .ico::after{display:none}
.os-screen .grid .ico svg,.os-screen .tile .ico svg{width:100%;height:100%}
.os-screen .grid .badge,.os-screen .tile .badge,.os-screen.mk .grid .badge{position:static;order:2;min-width:17px;height:17px;padding:0 4px;font-size:11px;border-radius:9px}
.os-screen.mk .app-icon .ico{transition:transform .16s,color .16s}
.os-screen.mk.in-mouse .grid .app-icon:hover{color:var(--accent)}
.os-screen.mk.in-mouse .grid .app-icon:hover span{text-decoration:underline;text-decoration-thickness:1px;text-underline-offset:3px}
.os-screen.mk.in-mouse .app-icon:hover .ico{transform:rotate(-6deg);color:var(--accent)}
/* a blank line: only shows while an entry is being moved */
.os-screen .slot{height:var(--line)}
.os-screen .slot .ico-ghost,.os-screen .slot span{display:none}
.os-screen .home.arranging .slot{outline:1px dashed var(--sep);outline-offset:-3px}
.os-screen .home.arranging .slot.over,.os-screen .grid .app-icon.over{background:var(--fill);outline:1.5px solid var(--ink);outline-offset:-3px}
.os-screen .app-icon.held{background:var(--slip);box-shadow:0 3px 9px rgba(60,40,20,.35);transform:rotate(-.6deg)}
.os-screen .app-icon.held .ico,.os-screen .app-icon.over .ico{box-shadow:none;transform:none!important}
.os-screen .home.arranging .app-icon:not(.held):not(.over) .ico{animation:none}
/* the pages kept at hand. Closed book: index tabs down the fore-edge */
.os-screen .dock,.os-screen.phone .dock,.os-screen.tablet .dock,.os-screen.tablet.portrait .dock{background:none;backdrop-filter:none;-webkit-backdrop-filter:none;border:0;border-radius:0;box-shadow:none;transform:none;
  left:auto;right:0;top:calc(var(--top) + 4px);bottom:auto;width:38px;height:auto;padding:0;flex-direction:column;justify-content:flex-start;align-items:flex-end;gap:7px}
.os-screen .dock .app-icon{width:38px;height:48px;justify-content:center;border-radius:6px 0 0 6px;background:#d9bf86;
  border:1px solid rgba(60,40,20,.38);border-right:0;box-shadow:-2px 2px 4px rgba(60,40,20,.22),inset 0 1px 0 rgba(255,255,255,.35)}
.os-screen .dock .app-icon:nth-child(4n+2){background:#c9b38f}
.os-screen .dock .app-icon:nth-child(4n+3){background:#b9c0a0}
.os-screen .dock .app-icon:nth-child(4n+4){background:#d3a98c}
.os-screen .dock .app-icon span{display:none}
.os-screen .dock .ico,.os-screen.phone .dock .ico,.os-screen.tablet .dock .ico,.os-screen.tablet.portrait .dock .ico{width:22px;height:22px;font-size:22px}
.os-screen .dock .ico::before,.os-screen .dock .ico::after{display:none}
.os-screen .dock .ico svg{width:100%;height:100%}
.os-screen .dock .badge{top:-5px;left:-7px;min-width:18px;height:18px;font-size:11px;padding:0 4px}
.os-screen.mk.in-mouse .dock .app-icon{transition:width .15s}
.os-screen.mk.in-mouse .dock .app-icon:hover{width:45px}
.os-screen.tablet.portrait .dock{width:46px;gap:9px}
.os-screen.tablet.portrait .dock .app-icon{width:46px;height:60px}
.os-screen.tablet.portrait .dock .ico{width:27px;height:27px;font-size:27px}
/* open book: they are written on the facing page under their own heading */
.os-screen.tablet:not(.portrait) .dock{left:calc(50% + 52px);right:56px;top:calc(var(--top) - 44px);width:auto;gap:0;align-items:stretch}
.os-screen.tablet:not(.portrait) .dock::before{content:'Kept at hand';height:38px;margin-bottom:6px;box-sizing:border-box;padding-top:3px;border-bottom:3px double rgba(42,33,24,.7);
  font-family:var(--font-head);font-size:31px;font-style:italic;font-weight:700;line-height:1;color:var(--ink)}
.os-screen.tablet:not(.portrait) .dock .app-icon{width:auto;height:var(--line);flex-direction:row;justify-content:flex-start;gap:11px;padding:0 2px 1px;
  background:none;border:0;border-radius:0;box-shadow:none;margin:0}
.os-screen.tablet:not(.portrait) .dock .app-icon span{display:block;order:1;font-family:var(--font-head);font-size:22px;font-style:italic;line-height:1.15}
.os-screen.tablet:not(.portrait) .dock .ico{order:0;flex:none;width:27px;height:27px;font-size:27px}
.os-screen.tablet:not(.portrait) .dock .badge{position:static;order:2}
.os-screen.tablet:not(.portrait).mk.in-mouse .dock .app-icon:hover{width:auto;color:var(--accent)}
.os-screen.tablet:not(.portrait).mk.in-mouse .dock .app-icon:hover span{text-decoration:underline;text-decoration-thickness:1px;text-underline-offset:3px}
/* the bookplate, pasted on the facing page (open book only) */
.os-screen .idx-plate{display:none}
.os-screen.tablet .idx-plate{display:block;position:absolute;width:290px;padding:16px 14px 18px;text-align:center;transform:rotate(-1.2deg);
  background:var(--slip);color:var(--ink);font-family:var(--font-head);border:1px solid rgba(42,33,24,.5);
  box-shadow:inset 0 0 0 4px var(--slip),inset 0 0 0 5px rgba(42,33,24,.5),0 3px 8px rgba(60,40,20,.28)}
.os-screen.tablet:not(.portrait) .idx-plate{left:calc(75% - 140px);bottom:92px}
.os-screen.tablet.portrait .idx-plate{left:calc(50% - 145px);bottom:150px}
.os-screen .idx-plate span{display:block;font-size:10.5px;letter-spacing:2px;text-transform:uppercase;white-space:nowrap;color:var(--text2)}
.os-screen .idx-plate b{display:block;margin-top:9px;padding-bottom:5px;border-bottom:1px solid rgba(42,33,24,.45);font-size:23px;font-style:italic;font-weight:700;
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
/* the leaf's number at the foot: one numeral for every leaf of the index */
.os-screen .dots,.os-screen.phone .dots,.os-screen.tablet .dots,.os-screen.tablet.portrait .dots{left:0;right:0;bottom:16px;gap:14px;counter-reset:leaf;align-items:baseline}
.os-screen.tablet:not(.portrait) .dots{right:50%}
.os-screen .dots button{counter-increment:leaf;width:auto;height:auto;min-width:18px;padding:2px 4px;border-radius:0;background:none;
  font-family:var(--font-head);font-size:14px;font-style:italic;color:var(--text3)}
.os-screen .dots button::after{content:counter(leaf,lower-roman)}
.os-screen .dots button.on{background:none;color:var(--ink);border-bottom:1.5px solid var(--ink)}
.os-screen .empty-home{color:var(--ink);text-shadow:none}
.os-screen .empty-home span{color:var(--text2)}
/* with a controller: the same contents page, the line under the highlight inked in */
.os-screen .chome .ch-head,.os-screen.phone .chome .ch-head,.os-screen.tablet .chome .ch-head{left:var(--lm);right:50px;top:calc(var(--top) - 44px);height:38px;align-items:flex-end;padding-bottom:4px;box-sizing:border-box;border-bottom:3px double rgba(42,33,24,.7)}
.os-screen.tablet:not(.portrait) .chome .ch-head{right:calc(50% + 46px)}
.os-screen.tablet.portrait .chome .ch-head{right:76px}
.os-screen .chome .ch-title{color:var(--ink);text-shadow:none;font-style:italic;font-size:25px;line-height:1;letter-spacing:0}
.os-screen.tablet .chome .ch-title{font-size:31px}
.os-screen .chome .pg{background:transparent;color:var(--text2);box-shadow:inset 0 0 0 1px var(--sep);border-radius:2px;height:22px;padding:0 8px;font-size:12px}
.os-screen .chome .pg.on{background:var(--ink);color:var(--paper);box-shadow:none}
.os-screen .chome .tiles,.os-screen.phone .chome .tiles,.os-screen.tablet .chome .tiles,.os-screen.tablet.portrait .chome .tiles{left:var(--lm);right:50px;top:var(--top);gap:0;grid-template-columns:1fr;grid-auto-rows:var(--line)}
.os-screen.phone .chome .tiles{grid-auto-rows:calc(var(--line)*2)}
.os-screen.phone .chome .tile{height:calc(var(--line)*2);align-items:flex-end;padding-bottom:5px}
.os-screen.phone .chome .tile::after{margin-bottom:2px}
.os-screen.tablet.portrait .chome .tiles{right:76px}
.os-screen.tablet:not(.portrait) .chome .tiles{right:56px;grid-auto-flow:column;grid-template-columns:none;grid-template-rows:repeat(12,var(--line));
  grid-auto-columns:calc(50% - 46px);column-gap:98px}
.os-screen .chome .idx-plate{display:none}
.os-screen .tile.held{transform:none;background:var(--slip);box-shadow:0 3px 9px rgba(60,40,20,.35)}
.os-screen.console .tile.kf{transform:none}
.os-screen.console .tile.kf::before{color:inherit}
.os-screen.console .tile.kf .ico{color:inherit}
.os-screen.console .tile.kf::after{border-color:currentColor}
.os-screen .chome .ch-info{color:var(--ink);text-shadow:none;font-family:var(--font-head);font-style:italic}
.os-screen .chome .ch-info span{color:var(--text2)}
.os-screen.phone .chome .ch-info{left:var(--lm);right:50px;top:auto;bottom:62px}
.os-screen.tablet:not(.portrait) .chome .ch-info{left:var(--lm);width:auto;right:calc(50% + 46px);top:auto;bottom:66px}
.os-screen.tablet.portrait .chome .ch-info{left:var(--lm);right:76px;top:auto;bottom:80px}
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
/* RedM (spur_phone, 25 Nov 2026): no home bar. On a page of the book, a small written way back to the contents;
   on the cover and on the contents page, nothing. */
.os-screen .home-bar,.os-screen.tablet .home-bar{width:auto;height:auto;left:50%;margin-left:0;transform:translateX(-50%);bottom:3px;background:none!important;border-radius:0;
  padding:1px 10px;font-family:var(--font-head);font-size:11.5px;font-style:italic;line-height:1.1;color:var(--text2);white-space:nowrap}
.os-screen .home-bar::after{content:'\\2039  contents'}
.os-screen.mk.in-mouse .home-bar:hover{color:var(--accent);text-decoration:underline;text-underline-offset:2px}
.os-screen:not(.app-open) .home-bar,.os-screen.locked .home-bar{display:none}
/* the leaves' fore-edge on the closed book, the stitching down the open book's gutter */
.os-screen.phone:not(.locked){box-shadow:inset -1px 0 0 rgba(60,40,20,.3),inset -3px 0 0 rgba(255,250,235,.6),inset -4px 0 0 rgba(60,40,20,.2),inset -6px 0 0 rgba(255,250,235,.5),inset -7px 0 0 rgba(60,40,20,.12),inset 16px 0 14px -10px rgba(60,40,20,.3)}
.os-screen.tablet:not(.portrait)::before{content:'';position:absolute;top:8px;bottom:8px;left:50%;width:2px;margin-left:-1px;pointer-events:none;z-index:26;
  background:repeating-linear-gradient(to bottom,rgba(255,248,228,.75) 0 9px,transparent 9px 17px)}
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
