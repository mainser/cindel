// Navigation belongs to the website shell; the chapter remains plain Markdown.
(() => {
  if (window.cindelStartLinksInitialized) return;
  window.cindelStartLinksInitialized = true;

  function renderStartLinks() {
    const existing = document.getElementById('cindel-start-links');
    if (window.location.pathname !== '/introduction') {
      existing?.remove();
      return;
    }
    const content = document.getElementById('content');
    if (!content || existing) return;

    const navigation = document.createElement('nav');
    navigation.id = 'cindel-start-links';
    navigation.className = 'cindel-start-links';
    navigation.setAttribute('aria-label', 'Explore the documentation');
    const pages = [
      ['Getting Started', '/getting-started'],
      ['Data Modeling', '/data-modeling'],
      ['Queries', '/queries'],
      ['Advanced Reference', '/advanced-reference'],
    ];
    for (const [title, href] of pages) {
      const link = document.createElement('a');
      link.className = 'cindel-start-link';
      link.href = href;
      const label = document.createElement('span');
      label.textContent = title;
      const arrow = document.createElement('span');
      arrow.setAttribute('aria-hidden', 'true');
      arrow.textContent = '\u2197';
      link.append(label, arrow);
      navigation.append(link);
    }
    content.before(navigation);
  }

  window.addEventListener('mintlify:navigate', renderStartLinks);
  renderStartLinks();
})();
