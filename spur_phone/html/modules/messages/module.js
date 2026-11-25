// Telegrams (was Messages): threads, conversations and new telegrams. UI only: threads and telegrams come from the
// framework (spur_phone:messages:*) and new ones arrive as pushes. Contact names come from the shared contacts service.
// Delete this folder and the notebook simply has no Telegrams page.
// RedM (spur_phone, 24 Nov 2026): a telegram is written and read anywhere but SENT only from a telegraph office (config.lua's
// Config.TelegraphOffices; the server checks). Away from one the draft is kept, and the page says where the nearest
// office is. The module id stays 'messages' (spur_core and saved settings read it).
// BLOCKING (14 Nov 2026): a conversation's info button blocks or unblocks its number (the shared block list,
// app.blocks). The server keeps a blocked number's telegrams from this card, so nothing here hides any; a lore
// character's number (noBlock) and the card's own get no button.
(() => {
  const { kit: K, icons: I } = window.WhipPhone;
  const GLYPH = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 4c4.7 0 8.5 3 8.5 6.8S16.7 17.6 12 17.6c-.9 0-1.8-.1-2.6-.3L5.6 19.4l1.1-3.3C4.8 14.9 3.5 13 3.5 10.8 3.5 7 7.3 4 12 4z"/></svg>';
  const CALL = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M7.2 3.2c.6-.3 1.3-.1 1.6.5l1.5 3.1c.3.6.1 1.3-.4 1.7l-1.3 1c.9 2.1 2.6 3.8 4.7 4.7l1-1.3c.4-.5 1.1-.7 1.7-.4l3.1 1.5c.6.3.8 1 .5 1.6l-.9 1.9c-.4.8-1.3 1.3-2.2 1.2C9.9 18.3 4.5 12.9 4.1 6.3C4 5.4 4.5 4.5 5.3 4.1z"/></svg>';
  const QUICK = ['ARRIVING ON THE EVENING TRAIN STOP', 'WILL WIRE LATER STOP', 'ALL WELL STOP'];
  const digits = K.digits;
  let tmpId = 0;

  const unread = (s) => s.threads.reduce((a, t) => a + (+t.unread || 0), 0);
  const thread = (s, number) => s.threads.find((t) => digits(t.number) === digits(number));
  const dayLabel = (t) => {
    const d = new Date(K.toMs(t)), now = new Date(), start = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    if (d.getTime() >= start) return 'Today';
    if (d.getTime() >= start - 864e5) return 'Yesterday';
    return d.toLocaleDateString('en-AU', { weekday: 'long', day: 'numeric', month: 'short' });
  };

  async function loadThreads(app) {
    try { const r = await app.request('threads'); app.state.threads = Array.isArray(r) ? r : []; } catch (e) { /* framework not answering yet */ }
    app.state.loaded = true;
  }
  async function openThread(app, number) {
    const s = app.state, n = digits(number);
    if (!n) return;
    s.open = n; s.compose = null; s.sheet = null; s.draft = s.drafts[n] || '';
    const t = thread(s, n);
    if (t && t.unread) { t.unread = 0; app.request('read', { number: n }).catch(() => {}); }
    if (!s.msgs[n]) {
      s.msgs[n] = null;                       // loading
      try { const r = await app.request('thread', { number: n }); s.msgs[n] = Array.isArray(r) ? r : []; }
      catch (e) { s.msgs[n] = []; app.toast(e.reason || 'Could not load the conversation'); }
    }
  }
  /** put a message on a thread (creating the thread) and move it to the top */
  function touch(s, number, msg) {
    let t = thread(s, number);
    if (!t) { t = { number, unread: 0 }; }
    t.last = { text: msg.text, time: msg.time, me: !!msg.me };
    s.threads = [t, ...s.threads.filter((x) => x !== t)];
    return t;
  }
  async function send(app, text) {
    const s = app.state, n = s.open;
    text = String(text || '').trim();
    if (!n || !text) return;
    // RedM (spur_phone, 24 Nov 2026): sent only from a telegraph office; anywhere else it stays in the draft
    if (!K.place(app, 'telegraph').ok) { app.toast('Send it from a telegraph office'); return; }
    const msg = { id: 'tmp' + (++tmpId), me: true, text, time: Date.now(), pending: true, fresh: true };
    const had = thread(s, n), hadLast = had && had.last;
    (s.msgs[n] = s.msgs[n] || []).push(msg);
    const t = touch(s, n, msg);
    s.draft = ''; s.drafts[n] = '';
    // RedM (spur_phone, 24 Nov 2026): a render leaves a focused input as it is (os.js), so a telegram sent with Enter
    // stayed in the box. Empty it here.
    const box = document.activeElement;
    if (box && box.dataset && box.dataset.bind === 'draft') box.value = '';
    setTimeout(() => { msg.fresh = false; }, 600);
    try {
      const r = await app.request('send', { number: n, text });
      msg.pending = false;
      if (r && r.id != null) msg.id = r.id;
      if (r && r.time) msg.time = r.time;
    } catch (e) {
      // refused (not at an office after all, a blocked line): the telegram goes back into the draft, not lost
      const list = s.msgs[n];
      if (Array.isArray(list)) { const i = list.indexOf(msg); if (i >= 0) list.splice(i, 1); }
      if (had) had.last = hadLast; else s.threads = s.threads.filter((x) => x !== t);
      if (!s.drafts[n]) s.drafts[n] = text;
      if (s.open === n && !s.draft) s.draft = text;
      app.toast(e.reason || 'Not sent: your telegram is kept');
    }
  }
  /** a number this phone may block: not the SIM's own, and not a lore character's (the server says which: noBlock) */
  function canBlock(app, number) {
    const n = digits(number), t = thread(app.state, n), c = app.contacts.find(n);
    return !!n && n !== digits(app.session.number) && !(t && t.noBlock) && !(c && c.noBlock);
  }
  /** the info sheet: block the conversation's number, or unblock it */
  function sheet(app) {
    const s = app.state, n = s.sheet && s.sheet.number;
    if (!n) return '';
    const blocked = app.blocks.has(n), busy = s.sheet.busy;
    const text = blocked ? 'Their telegrams reach this address card again. What they sent while blocked stays hidden.'
      : 'Their telegrams stop reaching this address card. They are not told: to them, the telegrams go.';
    return K.sheet({ title: app.contacts.name(n), close: 'closeSheet', body: `<p class="ms-p">${K.esc(text)}</p>` +
      `<div class="ms-btns">${K.button({ label: 'Cancel', act: 'closeSheet', kind: 'gray' })}` +
      `${K.button({ label: busy ? '…' : blocked ? 'Unblock' : 'Block', act: blocked ? 'unblock' : 'block', kind: blocked ? '' : 'red', d: { number: n } })}</div>` });
  }
  async function setBlocked(app, number, on) {
    const s = app.state;
    if (!s.sheet || s.sheet.busy) return;
    s.sheet.busy = true;
    try {
      await (on ? app.blocks.add(number) : app.blocks.remove(number));
      app.toast(on ? 'Address blocked' : 'Address unblocked');
      s.sheet = null;
    } catch (e) { app.toast(e.reason || 'Could not change that'); if (s.sheet) s.sheet.busy = false; }
  }

  // ---------------------------------------------------------------- screens
  function list(app, sel) {
    const s = app.state, q = s.query.trim().toLowerCase();
    const rows = s.threads.filter((t) => !q || app.contacts.name(t.number).toLowerCase().includes(q) || (t.last && String(t.last.text).toLowerCase().includes(q)));
    const items = rows.map((t) => {
      const name = app.contacts.name(t.number), last = t.last || {}, c = app.contacts.find(t.number);
      return `<button class="thread${sel && digits(sel) === digits(t.number) ? ' sel' : ''}" data-act="open" data-number="${K.esc(digits(t.number))}" data-hint="Open">${t.unread ? '<i class="unread"></i>' : ''}` +
        `${K.avatar({ name: c ? name : '', size: 50, pic: c && c.picture, frame: c && c.pictureFrame })}<div class="t-main"><div class="t-top"><span class="t-name">${K.esc(name)}</span>` +
        `<span class="t-time">${last.time ? K.esc(K.fmtWhen(last.time)) : ''}</span></div><div class="t-prev">${K.esc((last.me ? 'You: ' : '') + (last.text || ''))}</div></div></button>`;
    }).join('');
    const empty = K.empty({ icon: GLYPH, title: s.loaded ? (q ? 'No matches' : 'No telegrams') : 'Loading…', text: s.loaded && !q ? 'Write to someone in your contacts, or to a number.' : '',
      action: s.loaded && !q ? { label: 'New telegram', act: 'compose' } : null });
    return K.nav({ right: K.navBtn(I.compose, 'compose', {}, 'New telegram') }) + K.title('Telegrams') +
      K.search({ bind: 'query', value: s.query, placeholder: 'Search' }) + (items ? K.scroll(items) : empty);
  }
  function chat(app, number, withBack) {
    const s = app.state, msgs = s.msgs[number], c = app.contacts.find(number), name = app.contacts.name(number);
    const hasPhone = window.WhipPhone.calls === true && app.modules().some((m) => m.id === 'phone');   // RedM (spur_phone, 25 Nov 2026): no Call button without calls
    let body = '';
    if (msgs === null || msgs === undefined) body = K.empty({ title: 'Loading…' });
    else if (!msgs.length) body = K.empty({ title: 'No telegrams yet', text: `Write ${c ? c.name.split(' ')[0] : 'them'} a telegram.` });
    else {
      let lastDay = '';
      body = '<div class="msgs">' + msgs.map((m) => {
        const day = dayLabel(m.time), sep = day !== lastDay ? K.day(day) : '';
        lastDay = day;
        return sep + K.bubble({ me: !!m.me, text: m.text, fresh: !!m.fresh, failed: !!m.failed });
      }).join('') + (() => { const l = msgs[msgs.length - 1]; return l && l.me ? `<div class="read">${l.failed ? 'Not delivered' : l.pending ? 'On the wire…' : 'Delivered'}</div>` : ''; })() + '</div>';
    }
    if (app.blocks.has(number)) body += `<div class="ms-blocked">${I.block}You blocked this address</div>`;
    const info = canBlock(app, number) ? `<button class="ch-info" data-act="info" data-number="${K.esc(number)}" data-hint="Info">${I.info}</button>` : '';
    const head = `<div class="chat-h${info && hasPhone ? ' two' : ''}">${withBack ? `<button class="back" data-act="closeThread" data-hint="Back">${I.back}</button>` : ''}` +
      `${K.avatar({ name: c ? name : '', size: 44, pic: c && c.picture, frame: c && c.pictureFrame })}<div class="ch-n">${K.esc(name)}</div>${hasPhone ? `<button class="ch-call" data-act="call" data-number="${K.esc(number)}" data-hint="Telephone">${CALL}</button>` : ''}${info}</div>`;
    const quick = app.console ? `<div class="quick">${QUICK.map((q) => `<button class="qr" data-act="quick" data-text="${K.esc(q)}" data-hint="Send">${K.esc(q)}</button>`).join('')}</div>` : '';
    // RedM (spur_phone, 24 Nov 2026): where it can be sent from, over the form
    const at = K.place(app, 'telegraph');
    const where = at.ok ? (at.here ? `<div class="tg-where ok">At the ${K.esc(at.here)} telegraph office</div>` : '')
      : `<div class="tg-where">${K.esc(at.text)} Your telegram is kept until then.</div>`;
    return head + `<div class="scroll" data-scroll data-bottom><div>${body}</div></div>` + quick + where +
      K.composer({ bind: 'draft', value: s.draft, placeholder: 'Write a telegram', send: 'send' });
  }
  function compose(app) {
    const s = app.state, to = s.compose.to, q = to.trim().toLowerCase(), d = digits(to);
    const matches = app.contacts.sorted.filter((c) => !q || String(c.name).toLowerCase().includes(q) || (d && digits(c.number).includes(d))).slice(0, 30);
    const rows = matches.map((c) => K.row({ av: K.avatar({ name: c.name, size: 36, pic: c.picture, frame: c.pictureFrame }), label: c.name, sub: K.fmtNumber(c.number), act: 'pick', d: { number: digits(c.number) }, chev: false, hint: 'Write' }));
    if (d.length >= 7 && !matches.some((c) => digits(c.number) === d)) rows.unshift(K.row({ icon: GLYPH, label: `Wire ${K.fmtNumber(d)}`, act: 'pick', d: { number: d }, chev: false, hint: 'Write' }));
    return K.nav({ back: 'Cancel', act: 'cancelCompose', title: 'New telegram' }) +
      K.list([K.field({ label: 'To', bind: 'to', value: to, placeholder: 'Name or address', enter: 'pickTyped' })], { inset: 14 }) +
      (rows.length ? K.scroll(K.list(rows, { inset: 62 })) : K.empty({ title: app.contacts.loaded ? 'No matching contacts' : 'Loading…', text: 'Type a full address to wire it.' }));
  }

  WhipPhone.module({
    id: 'messages', name: 'Telegrams', version: '1.0.0', order: 20, dock: true, icon: GLYPH,
    css: `
.thread{display:flex;gap:11px;align-items:center;padding:9px 16px 9px 18px;width:100%;position:relative}
.thread+.thread::after{content:'';position:absolute;top:0;left:78px;right:0;border-top:.5px solid var(--sep)}
.thread .t-main{flex:1;min-width:0}
.thread .t-top{display:flex;justify-content:space-between;align-items:baseline;gap:8px}
.thread .t-name{font-weight:600;font-size:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.thread .t-time{font-size:13.5px;color:var(--text2);flex:none}
.thread .t-prev{font-size:14.5px;color:var(--text2);line-height:1.3;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;height:38px}
.thread .unread{position:absolute;left:5px;top:50%;width:9px;height:9px;margin-top:-4.5px;border-radius:50%;background:var(--accent)}
.thread.sel{background:var(--accent)}
.thread.sel .t-time,.thread.sel .t-prev{color:rgba(255,255,255,.8)}
.chat-h .ch-call{position:absolute;right:14px;top:8px;width:34px;height:34px;border-radius:50%;display:grid;place-items:center;color:var(--accent)}
.chat-h .ch-call svg{width:22px;height:22px}
.chat-h .ch-info{position:absolute;right:14px;top:8px;width:34px;height:34px;border-radius:50%;display:grid;place-items:center;color:var(--accent)}
.chat-h .ch-info svg{width:23px;height:23px}
.chat-h.two .ch-call{right:52px}
.ms-blocked{display:flex;align-items:center;justify-content:center;gap:6px;font-size:12.5px;color:var(--text2);padding:2px 16px 12px}
.ms-blocked svg{width:14px;height:14px}
.ms-p{font-size:14.5px;color:var(--text2);line-height:1.4;margin:0 2px 16px}
.ms-btns{display:flex;gap:10px}
.ms-btns .btn{flex:1}
.m-messages .split>.main .chat-h{padding-top:6px}
.m-messages .msgs .read{margin-top:2px}
/* RedM (spur_phone, 24 Nov 2026): telegram forms, and where they can be sent from */
.m-messages .bub::before{display:block;font:700 9px/1 var(--font-ui);letter-spacing:2.2px;opacity:.55;margin-bottom:5px}
.m-messages .bub.them::before{content:'TELEGRAM'}
.m-messages .bub.me::before{content:'OFFICE COPY'}
.tg-where{margin:4px 12px 0;padding:6px 10px;font-size:12.5px;font-style:italic;line-height:1.35;color:var(--text2);border-left:3px solid var(--orange);background:var(--fill)}
.tg-where.ok{border-left-color:var(--green)}
`,
    state: () => ({ threads: [], loaded: false, open: null, msgs: {}, draft: '', drafts: {}, compose: null, query: '', sheet: null }),

    // A new character or SIM: everything of the last one goes, as Bank and Business do (audit 16, CLI-1: its
    // conversations showed until the read landed, and its drafts filled in for the same number under the new SIM).
    session(app) {
      Object.assign(app.state, { threads: [], loaded: false, open: null, msgs: {}, draft: '', drafts: {}, compose: null, query: '', sheet: null });
      loadThreads(app);
    },
    open(app, args = {}) {
      const s = app.state;
      if (!s.loaded) loadThreads(app);
      app.contacts.load();
      if (args.number) openThread(app, args.number);
      else if (args.compose) s.compose = { to: '' };
    },
    route: (app) => (app.state.compose ? 'compose' : app.state.open ? 'chat' : 'list'),
    back(app) {
      const s = app.state;
      if (s.sheet) { s.sheet = null; return true; }
      if (s.compose) { s.compose = null; return true; }
      if (s.open) { s.open = null; return true; }
      return false;
    },
    x(app) {
      const s = app.state;
      if (s.open && !s.compose) return { label: 'Quick reply', run: () => send(app, QUICK[0]) };
      if (!s.compose) return { label: 'New telegram', run: () => { s.compose = { to: '' }; } };
      return null;
    },
    badge: (app) => unread(app.state),
    info(app) {
      const s = app.state, n = unread(s);
      if (!n) return 'No new telegrams';
      return `${n} unread from ${s.threads.filter((t) => t.unread).map((t) => app.contacts.name(t.number).split(' ')[0]).slice(0, 3).join(', ')}`;
    },

    render(app, v) {
      const s = app.state;
      if (s.compose) return K.screen('compose', compose(app), { slide: true });
      const sh = s.open && s.sheet && s.sheet.number === s.open ? sheet(app) : '';   // (only over its own conversation)
      if (v.size === 'tablet') {
        const sel = s.open;   // all displays render at once, so never auto-open: that would open a chat on the phone too
        const main = sel ? chat(app, sel, false) : K.empty({ icon: GLYPH, title: s.threads.length ? 'Pick a conversation' : 'No telegrams yet', action: { label: 'New telegram', act: 'compose' } });
        return K.screen('split', K.split(list(app, sel), main, sel ? 'c' + sel : 'none') + sh);
      }
      if (s.open) return K.screen('c-' + s.open, chat(app, s.open, true) + sh, { slide: true });
      return K.screen('list', list(app, null));
    },

    actions: {
      open(app, d) { return openThread(app, d.number); },
      closeThread(app) { app.state.open = null; app.state.sheet = null; },
      compose(app) { app.state.compose = { to: '' }; },
      cancelCompose(app) { app.state.compose = null; },
      pick(app, d) { return openThread(app, d.number); },
      pickTyped(app) {
        const s = app.state, to = s.compose ? s.compose.to : '', d = digits(to);
        const c = app.contacts.sorted.find((x) => String(x.name).toLowerCase() === to.trim().toLowerCase());
        if (c) return openThread(app, c.number);
        if (d.length >= 7) return openThread(app, d);
        app.toast('Pick a contact or type a full address');
      },
      send(app) { return send(app, app.state.draft); },
      quick(app, d) { return send(app, d.text); },
      call(app, d) { app.open('phone', { number: d.number, call: true }); },
      info(app, d) { if (canBlock(app, d.number)) app.state.sheet = { number: digits(d.number), busy: false }; },
      closeSheet(app) { app.state.sheet = null; },
      block(app, d) { return setBlocked(app, d.number, true); },
      unblock(app, d) { return setBlocked(app, d.number, false); },
    },
    bind: {
      draft(app, v) { const s = app.state; s.draft = v.slice(0, 500); if (s.open) s.drafts[s.open] = s.draft; },
      query(app, v) { app.state.query = v; },
      to(app, v) { if (app.state.compose) app.state.compose.to = v.slice(0, 40); },
    },
    on: {
      /** { id, number, text, time } a telegram arrived */
      incoming(app, d = {}) {
        const s = app.state, n = digits(d.number);
        if (!n || d.text == null) return;
        const msg = { id: d.id, me: false, text: String(d.text), time: d.time || Date.now(), fresh: true };
        if (Array.isArray(s.msgs[n])) s.msgs[n].push(msg);
        setTimeout(() => { msg.fresh = false; }, 600);
        const t = touch(s, n, msg);
        const viewing = app.active && app.visible && s.open === n && !s.compose;
        if (viewing) app.request('read', { number: n }).catch(() => {});
        else { t.unread = (+t.unread || 0) + 1; app.notify({ title: app.contacts.name(n), text: msg.text, kind: 'chat', args: { number: n } }); }
      },
      /** the framework replaced the thread list */
      threads(app, d) { if (Array.isArray(d)) { app.state.threads = d; app.state.loaded = true; } },
      /** { number, messages } the framework replaced one conversation */
      thread(app, d = {}) { if (d.number && Array.isArray(d.messages)) app.state.msgs[digits(d.number)] = d.messages; },
    },
  });
})();
