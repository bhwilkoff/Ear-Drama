/* The take-down form (takedown/index.html). Posts to the private case record
   (worker/src/takedown.js); catalog/DECISIONS.md 029. */
(function () {
  'use strict';
  const ENDPOINT = 'https://eardrama-api.benwilkoff.workers.dev/v1/takedown';
  const FALLBACK = 'Please try again, or use the email address below.';
  const FIELD_NAMES = {
    links: 'the links', name: 'your name', email: 'a valid email address',
    work: 'the work you hold rights in', address: 'your postal address',
    phone: 'your phone number', reason: 'why it should come down',
    signature: 'your signature', goodFaith: 'the good-faith statement',
    accurate: 'the accuracy statement',
  };

  const form = document.getElementById('takedown-form');
  const status = document.getElementById('takedown-status');
  if (!form) return;

  function showFor(kind) {
    form.querySelectorAll('[data-for]').forEach((el) => { el.hidden = el.dataset.for !== kind; });
  }
  form.addEventListener('change', (e) => { if (e.target.name === 'kind') showFor(e.target.value); });

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const data = new FormData(form);
    const body = Object.fromEntries(data.entries());
    body.goodFaith = data.has('goodFaith');
    body.accurate = data.has('accurate');
    const button = form.querySelector('button');
    button.disabled = true;
    status.textContent = 'Sending…';
    try {
      const res = await fetch(ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(20000),
      });
      const out = await res.json().catch(() => ({}));
      if (res.ok && out.ref) {
        form.reset();
        showFor('copyright');
        status.textContent = `Received. Your case number is ${out.ref}.`;
      } else if (out.error === 'missing') {
        status.textContent = `Please add ${FIELD_NAMES[out.field] || 'the missing detail'}.`;
      } else {
        status.textContent = `This request could not be sent. ${FALLBACK}`;
      }
    } catch {
      status.textContent = `This request could not be sent. ${FALLBACK}`;
    }
    button.disabled = false;
  });
})();
