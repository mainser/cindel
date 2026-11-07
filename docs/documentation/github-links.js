// Keep the source Markdown links usable on GitHub. Mintlify serves .md URLs
// as Markdown exports, so links between chapters must use HTML routes here.
(() => {
  if (window.cindelGithubLinksInitialized) return;
  window.cindelGithubLinksInitialized = true;

  function normalizeChapterLinks() {
    for (const link of document.querySelectorAll('#content a[href]')) {
      if (link.hasAttribute('download')) continue;
      const url = new URL(link.href, window.location.href);
      if (url.origin !== window.location.origin) continue;
      if (!/^\/(?:0[1-9]|1[0-9]|20)-[a-z_]+\.md$/.test(url.pathname)) {
        continue;
      }
      url.pathname = url.pathname.slice(0, -3);
      link.setAttribute('href', url.pathname + url.search + url.hash);
      // Mintlify marks Markdown exports as new-tab links; these are chapters.
      link.removeAttribute('target');
      link.setAttribute('data-cindel-chapter-link', '');
    }
  }

  // Use the updated href, not the original .md prop in Mintlify's React link.
  // Leave modifier keys and new-tab links to the browser.
  document.addEventListener('click', (event) => {
    if (!(event.target instanceof Element)) return;
    const link = event.target.closest('a[data-cindel-chapter-link]');
    if (!link || event.button !== 0 || event.metaKey || event.ctrlKey ||
        event.shiftKey || event.altKey || link.target) return;
    event.preventDefault();
    event.stopPropagation();
    if (typeof window.mintlify?.navigate === 'function') {
      window.mintlify.navigate(link.getAttribute('href'));
    } else {
      window.location.assign(link.href);
    }
  }, true);

  window.addEventListener('mintlify:navigate', normalizeChapterLinks);
  normalizeChapterLinks();
})();
