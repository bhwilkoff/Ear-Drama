/* Joins D2b-2's making screens to Direction D's shell: every section links to D's screen. */
(function () {
  const to = { Home: 'home', Browse: 'browse', Stations: 'stations', Surprise: 'home', Search: 'search', Library: 'library' };
  const fix = () => {
    document.querySelectorAll('.ed-nav-item').forEach((a) => { const l = a.textContent.trim(); if (to[l]) a.href = `index.html?s=${to[l]}`; });
  };
  fix();
  new MutationObserver(fix).observe(document.getElementById('app'), { childList: true });
})();
