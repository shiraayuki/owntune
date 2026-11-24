// Shared helper for the M1 v3 mockups.
// ?mode=dark|light (default dark), ?accent=ff7a59 (dark mode only; light mode is
// always monochrome "Paper"). index.html can also switch both via postMessage.
(function () {
  const root = document.documentElement;
  const params = new URLSearchParams(location.search);

  function syncControls(mode, accent) {
    document.querySelectorAll('[data-accent]').forEach((el) =>
      el.classList.toggle('on', el.dataset.accent === (accent || 'ff7a59')));
    document.querySelectorAll('[data-seg]').forEach((el) =>
      el.classList.toggle('on', el.dataset.seg === mode));
  }

  function apply(mode, accent) {
    root.dataset.mode = mode;
    root.dataset.accent = accent || '';
    syncControls(mode, accent);
    if (mode === 'dark' && accent) {
      root.style.setProperty('--accent', '#' + accent);
    } else {
      root.style.removeProperty('--accent');
    }
  }
  apply(params.get('mode') || 'dark', params.get('accent'));
  window.addEventListener('message', (e) => {
    if (e.data && e.data.mode) apply(e.data.mode, e.data.accent);
  });

  // SF Symbols-like glyphs (outline unless noted).
  const icons = {
    'music-note': '<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/>',
    'music-note-fill': '<path d="M9 18V5l11-2v13" fill="none"/><circle cx="6" cy="18" r="3" fill="currentColor"/><circle cx="17" cy="16" r="3" fill="currentColor"/><path d="M9 5l11-2v4L9 9z" fill="currentColor"/>',
    'stack': '<rect x="4" y="8" width="16" height="12" rx="2"/><path d="M6 5h12M8 2h8"/>',
    'stack-fill': '<rect x="4" y="8" width="16" height="12" rx="2" fill="currentColor"/><path d="M6 5h12M8 2h8"/>',
    'mic': '<rect x="9" y="2" width="6" height="11" rx="3"/><path d="M5 10a7 7 0 0 0 14 0M12 17v4M8 21h8"/>',
    'mic-fill': '<rect x="9" y="2" width="6" height="11" rx="3" fill="currentColor"/><path d="M5 10a7 7 0 0 0 14 0M12 17v4M8 21h8"/>',
    'search': '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
    'plus': '<path d="M12 5v14M5 12h14"/>',
    'ellipsis': '<circle cx="5" cy="12" r="1.6" fill="currentColor"/><circle cx="12" cy="12" r="1.6" fill="currentColor"/><circle cx="19" cy="12" r="1.6" fill="currentColor"/>',
    'chevron-right': '<path d="m9 5 7 7-7 7"/>',
    'chevron-left': '<path d="m15 5-7 7 7 7"/>',
    'check': '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
    'xmark': '<path d="M6 6l12 12M18 6 6 18"/>',
    'play': '<path d="M7 4.5v15l12.5-7.5z" fill="currentColor" stroke="none"/>',
    'shuffle': '<path d="M3 6h4l10 12h4M3 18h4l3-3.6M14 9.6 17 6h4M18 3l3 3-3 3M18 15l3 3-3 3"/>',
    'sort': '<path d="M7 4v16M3 16l4 4 4-4M17 20V4M13 8l4-4 4 4"/>',
    'gear': '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
    'trash': '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
    'album': '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2.5"/>',
    'person': '<circle cx="12" cy="8" r="4"/><path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6"/>',
    'person-fill': '<circle cx="12" cy="8" r="4" fill="currentColor"/><path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6z" fill="currentColor"/>',
    'doc-copy': '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"/>',
    'warn': '<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17v.5"/>',
    'moon': '<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>',
    'palette': '<path d="M12 3a9 9 0 0 0 0 18c1.1 0 1.5-.8 1.5-1.5 0-1.3-1-1.7-1-3 0-.8.7-1.5 1.5-1.5H16a5 5 0 0 0 5-5c0-3.9-4-7-9-7z"/><circle cx="7.5" cy="11" r="1.2" fill="currentColor"/><circle cx="10" cy="7" r="1.2" fill="currentColor"/><circle cx="15" cy="7.5" r="1.2" fill="currentColor"/>',
    'disk': '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 14h.01M11 14h6"/>',
    'info': '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>',
    'notes-empty': '<path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/>',
  };
  const sprite = Object.entries(icons)
    .map(([id, body]) => `<symbol id="i-${id}" viewBox="0 0 24 24">${body}</symbol>`)
    .join('');
  document.addEventListener('DOMContentLoaded', () => {
    syncControls(root.dataset.mode, root.dataset.accent);
    document.body.insertAdjacentHTML(
      'afterbegin',
      `<svg width="0" height="0" style="position:absolute">${sprite}</svg>`,
    );
  });
})();
