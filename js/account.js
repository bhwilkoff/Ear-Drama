/**
 * The account on the web (WEB-DESIGN §4.11): Library's one account row, the
 * account sheet it opens, and the public deletion page (/delete-account/).
 *
 * Sign in with Apple JS and Google Identity Services are each provider's own
 * first-party script, loaded only when the person opens the sign-in sheet,
 * never at page load (§8.3). Each sign-in carries a fresh raw nonce. Every
 * Worker call is API.account's; this file only draws and asks.
 */
const AccountUI = (() => {
  'use strict';

  const APPLE_JS = 'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js';
  const GOOGLE_JS = 'https://accounts.google.com/gsi/client';
  const acct = API.account;
  const cfg = typeof CONFIG !== 'undefined' ? CONFIG : { apple: {}, google: {} };
  const hasSync = typeof Sync !== 'undefined';

  function el(tag, attrs, ...children) {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v === null || v === undefined || v === false) continue;
      if (k === 'class') n.className = v;
      else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
      else n.setAttribute(k, v === true ? '' : v);
    }
    for (const c of children.flat()) {
      if (c === null || c === undefined || c === false) continue;
      n.append(c instanceof Node ? c : document.createTextNode(String(c)));
    }
    return n;
  }
  function svg(d, cls = 'i-inline') {
    const ns = 'http://www.w3.org/2000/svg';
    const s = document.createElementNS(ns, 'svg');
    s.setAttribute('viewBox', '0 0 24 24');
    s.setAttribute('aria-hidden', 'true');
    s.setAttribute('class', cls);
    const p = document.createElementNS(ns, 'path');
    p.setAttribute('d', d);
    s.append(p);
    return s;
  }
  const PERSON = 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm0 2c-3.3 0-8 1.7-8 5v1h16v-1c0-3.3-4.7-5-8-5z';
  const SYNC = 'M12 4V1L8 5l4 4V6a6 6 0 0 1 5.7 7.9l1.5 1.5A8 8 0 0 0 12 4zm0 14a6 6 0 0 1-5.7-7.9L4.8 8.6A8 8 0 0 0 12 20v3l4-4-4-4z';
  const APPLE = 'M16.4 12.6c0-2.4 2-3.6 2.1-3.7-1.2-1.7-3-1.9-3.6-2-1.5-.2-3 .9-3.8.9-.8 0-2-.9-3.3-.9-1.7 0-3.3 1-4.2 2.5-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8s2 .8 3.3.8c1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9 0 0-2.8-1-2.8-4.2zM14 5.3c.7-.9 1.2-2 1-3.2-1 0-2.3.7-3 1.6-.7.8-1.2 2-1.1 3.1 1.2.1 2.3-.6 3.1-1.5z';

  const PROVIDER = { apple: 'Apple', google: 'Google' };
  const time = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit' });
  const dayTime = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
  function when(ms) {
    const d = new Date(ms);
    return d.toDateString() === new Date().toDateString() ? time.format(d) : dayTime.format(d);
  }
  function errorText(e) {
    const kind = e && e.kind;
    if (kind === 'offline' || (typeof navigator !== 'undefined' && navigator.onLine === false)) return 'You are offline.';
    if (kind === 'rate_limited') return 'Too many tries. Try again in a minute.';
    if (kind === 'unauthorized') return 'Your sign-in ended. Sign in again.';
    return 'Ear Drama could not be reached.';
  }

  /* ---- The providers' own scripts, loaded on demand ---- */

  const scripts = new Map();
  function loadScript(src) {
    if (!scripts.has(src)) {
      const p = new Promise((resolve, reject) => {
        const s = document.createElement('script');
        s.src = src; s.async = true;
        const t = setTimeout(() => reject(new Error(`timed out ${src}`)), 15000);
        s.onload = () => { clearTimeout(t); resolve(); };
        s.onerror = () => { clearTimeout(t); reject(new Error(`did not load ${src}`)); };
        document.head.append(s);
      });
      p.catch(() => scripts.delete(src));
      scripts.set(src, p);
    }
    return scripts.get(src);
  }

  /** Sign in with Apple JS in a popup. Returns { id_token, code }; the nonce goes in raw. */
  async function appleAuthorize(nonce) {
    await loadScript(APPLE_JS);
    const state = acct.newNonce();
    window.AppleID.auth.init({ clientId: cfg.apple.servicesId, scope: '', redirectURI: cfg.apple.redirectURI,
                               state, nonce, usePopup: true });
    const r = await window.AppleID.auth.signIn();
    const a = r && r.authorization;
    if (!a || a.state !== state || !a.id_token) throw new Error('apple sign-in answered without a matching state');
    return a;
  }

  /** Google's own button, rendered by Google Identity Services into `box`. */
  async function googleButton(box, nonce, onToken) {
    await loadScript(GOOGLE_JS);
    const g = window.google.accounts.id;
    g.initialize({ client_id: cfg.google.clientId, nonce, auto_select: false, context: 'signin', ux_mode: 'popup',
                   callback: (resp) => onToken(resp && resp.credential) });
    const dark = document.documentElement.getAttribute('data-theme') === 'dark'
      || (!document.documentElement.getAttribute('data-theme') && matchMedia('(prefers-color-scheme: dark)').matches);
    box.replaceChildren();
    g.renderButton(box, { type: 'standard', theme: dark ? 'filled_black' : 'outline', size: 'large',
                          text: 'signin_with', shape: 'rectangular', width: 280 });
  }

  /* ---- The sign-in buttons (the sheet and the deletion page share them) ---- */

  function signInButtons(onDone) {
    const avail = acct.available();
    const err = el('p', { class: 'body account-error', role: 'alert' });
    err.hidden = true;
    const fail = (e) => {
      if (e && (e.error === 'popup_closed_by_user' || e.error === 'user_cancelled_authorize')) return;
      console.error('sign-in', e);
      err.textContent = errorText(e);
      err.hidden = false;
    };
    const finish = async (provider, token, nonce) => {
      err.hidden = true;
      try { await acct.signIn(provider, token, nonce); onDone(); } catch (e) { fail(e); }
    };
    const box = el('div', { class: 'account-providers' });
    if (avail.apple) {
      box.append(el('button', { type: 'button', class: 'btn btn-apple', onclick: async () => {
        const nonce = acct.newNonce();
        try {
          const a = await appleAuthorize(nonce);
          await finish('apple', a.id_token, nonce);
        } catch (e) { fail(e); }
      } }, svg(APPLE), 'Sign in with Apple'));
    }
    if (avail.google) {
      const g = el('div', { class: 'google-button' });
      box.append(g);
      const nonce = acct.newNonce();
      googleButton(g, nonce, (token) => token ? finish('google', token, nonce) : fail(null)).catch(fail);
    }
    return el('div', {}, box, err);
  }

  /* ---- Library's account row ---- */

  let rowBox = null;
  let busy = false;

  function paintRow(box = rowBox) {
    if (!box) return;
    rowBox = box;
    const s = acct.state();
    const avail = acct.available();
    const any = avail.apple || avail.google;
    box.replaceChildren();
    if (!acct.signedIn()) {
      box.append(el('button', { type: 'button', class: 'btn btn-ghost account-open', disabled: !any,
                                onclick: openSheet }, svg(PERSON), 'Sign in'));
      if (!any) box.append(el('span', { class: 'caption' }, 'Not available yet'));
      else if (s && s.ended) box.append(el('span', { class: 'caption account-warn' }, 'Your sign-in ended.'));
      return;
    }
    const err = s.last_error;
    const status = busy ? 'Syncing' : err ? (err.kind === 'offline' ? 'Offline' : `Sync failed ${when(err.at)}`)
      : s.last_sync_at ? `Synced ${when(s.last_sync_at)}` : 'Not synced yet';
    box.append(
      el('button', { type: 'button', class: 'btn btn-ghost account-open', onclick: openSheet,
                     'aria-label': `${PROVIDER[s.provider] || ''} account` }, svg(PERSON), `${PROVIDER[s.provider] || ''} account`),
      el('span', { class: err && !busy && err.kind !== 'offline' ? 'caption account-warn' : 'caption', 'aria-live': 'polite' }, status),
      el('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Sync now', disabled: busy, onclick: syncNow }, svg(SYNC)));
  }

  async function syncNow() {
    if (!hasSync || busy) return;
    busy = true; repaint();
    try { await Sync.run(); } finally { busy = false; repaint(); }
  }

  /* ---- The account sheet: a <dialog>, opened from the row ---- */

  let sheet = null;
  function ensureSheet() {
    if (sheet) return sheet;
    sheet = el('dialog', { class: 'account-sheet', 'aria-labelledby': 'account-h' });
    sheet.addEventListener('close', () => { sheet.replaceChildren(); });
    document.body.append(sheet);
    return sheet;
  }
  function openSheet() {
    const d = ensureSheet();
    paintSheet();
    if (!d.open) d.showModal();
  }
  function paintSheet() {
    if (!sheet) return;
    const s = acct.state();
    const close = el('button', { type: 'button', class: 'icon-btn account-close', 'aria-label': 'Close',
                                 onclick: () => sheet.close() },
      svg('M6.4 5 5 6.4 10.6 12 5 17.6 6.4 19l5.6-5.6 5.6 5.6 1.4-1.4-5.6-5.6L19 6.4 17.6 5 12 10.6z', ''));
    if (!acct.signedIn()) {
      sheet.replaceChildren(close,
        el('h2', { id: 'account-h', class: 'section-header' }, 'Sign in'),
        el('p', { class: 'caption' }, 'What this device has played is kept and added to your account.'),
        signInButtons(() => { paintSheet(); if (hasSync) syncNow(); }));
      return;
    }
    const err = s.last_error;
    const msg = el('p', { class: 'body account-error', role: 'alert' });
    msg.hidden = true;
    const facts = el('dl', { class: 'facts' },
      el('div', {}, el('dt', { class: 'caption' }, 'Signed in with'), el('dd', {}, PROVIDER[s.provider] || s.provider)),
      el('div', {}, el('dt', { class: 'caption' }, 'Last sync'),
        el('dd', { class: 'tabular' }, busy ? 'Syncing' : s.last_sync_at ? when(s.last_sync_at) : 'Not yet')),
      err ? el('div', {}, el('dt', { class: 'caption' }, 'Last error'),
        el('dd', { class: 'account-warn' }, `${errorText(err)} ${when(err.at)}`)) : null);
    sheet.replaceChildren(close,
      el('h2', { id: 'account-h', class: 'section-header' }, 'Account'),
      facts,
      el('div', { class: 'actions' },
        el('button', { type: 'button', class: 'btn btn-primary', disabled: busy || !hasSync, onclick: syncNow },
          svg(SYNC), 'Sync now'),
        el('button', { type: 'button', class: 'btn', onclick: async () => {
          await (hasSync ? Sync.signOut() : acct.signOut());
          paintSheet();
        } }, 'Sign out')),
      el('button', { type: 'button', class: 'btn btn-ghost account-delete', onclick: () => deleteFlow(msg, () => sheet.close()) },
        'Delete account'),
      msg);
  }

  /** Asks first; for an Apple account, asks Apple for a fresh code so the Worker can revoke Apple's token. */
  async function deleteFlow(msg, after) {
    if (!confirm('Delete your Ear Drama account? Everything synced to it is erased from Ear Drama at once. '
      + 'Listening on this device stays.')) return;
    const s = acct.state();
    const opts = {};
    if (s && s.provider === 'apple' && acct.available().apple) {
      try {
        const a = await appleAuthorize(acct.newNonce());
        opts.appleAuthorizationCode = a.code;
        opts.appleClientId = cfg.apple.servicesId;
      } catch (e) { console.error('apple code for revocation', e); }
    }
    msg.hidden = true;
    try {
      await (hasSync ? Sync.deleteAccount(opts) : acct.deleteAccount(opts));
      after(true);
    } catch (e) {
      msg.textContent = errorText(e);
      msg.hidden = false;
    }
  }

  function repaint() { paintRow(); if (sheet && sheet.open) paintSheet(); }
  acct.onChange(repaint);
  if (hasSync) Sync.onChange(repaint);

  /* ---- /delete-account/: for someone without the app ---- */

  function mountDeletePage(box) {
    const paint = (deleted) => {
      box.replaceChildren();
      if (deleted === true) {
        box.append(el('p', { class: 'body', role: 'status' }, 'Your account is deleted.'));
        return;
      }
      const avail = acct.available();
      if (!avail.apple && !avail.google) {
        box.append(el('p', { class: 'body' }, 'Deleting an account from this page is not available yet.'));
        return;
      }
      if (!acct.signedIn()) {
        box.append(el('p', {}, 'Sign in with the account you used in Ear Drama.'), signInButtons(() => paint()));
        return;
      }
      const s = acct.state();
      const msg = el('p', { class: 'body account-error', role: 'alert' });
      msg.hidden = true;
      box.append(
        el('p', {}, `Signed in with ${PROVIDER[s.provider] || s.provider}.`),
        el('div', { class: 'actions' },
          el('button', { type: 'button', class: 'btn btn-primary', onclick: () => deleteFlow(msg, paint) }, 'Delete account'),
          el('button', { type: 'button', class: 'btn', onclick: async () => { await acct.signOut(); paint(); } }, 'Sign out')),
        msg);
    };
    paint();
  }

  const deleteBox = document.getElementById('delete-account');
  if (deleteBox) mountDeletePage(deleteBox);

  return { paintRow, openSheet, mountDeletePage };
})();
