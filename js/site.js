/**
 * The site pages (credits, privacy, take-down requests): the one place the
 * take-down address is written. Every element with data-takedown-email gets it
 * as its text and a mailto link.
 */

// OWNER: set the address take-down requests go to (the same one registered
// with the U.S. Copyright Office for the designated agent, if they match).
const TAKEDOWN_EMAIL = 'ben@learningischange.com';

(function () {
  'use strict';
  const saved = (() => { try { return localStorage.getItem('app_theme'); } catch { return null; } })();
  if (saved === 'dark' || saved === 'light') document.documentElement.setAttribute('data-theme', saved);

  document.querySelectorAll('[data-takedown-email]').forEach((a) => {
    a.textContent = TAKEDOWN_EMAIL;
    a.setAttribute('href', `mailto:${TAKEDOWN_EMAIL}?subject=${encodeURIComponent('Take-down request')}`);
  });
})();
