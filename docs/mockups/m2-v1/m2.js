// Extra glyphs for the M2 mockups, on top of ../m1-v3/mockup.js.
(function () {
  const icons = {
    'house': '<path d="M3 11.5 12 3.5l9 8"/><path d="M5.5 10v10h4.5v-6h4v6h4.5V10"/>',
    'house-fill': '<path d="M12 2.6 2.2 11.3l1.4 1.6 1.4-1.2V21h5.5v-6h3v6H19v-9.3l1.4 1.2 1.4-1.6z" fill="currentColor" stroke="none"/>',
    'note-list': '<path d="M3 6h11M3 11h11M3 16h7"/><path d="M17.5 18V8.5l3.5-1"/><circle cx="15.3" cy="18" r="2.2"/>',
    'pause': '<rect x="6" y="4.5" width="4" height="15" rx="1.2" fill="currentColor" stroke="none"/><rect x="14" y="4.5" width="4" height="15" rx="1.2" fill="currentColor" stroke="none"/>',
    'forward': '<path d="M2.5 6.5v11l8.5-5.5zM12 6.5v11l8.5-5.5z" fill="currentColor" stroke="currentColor" stroke-width="1.2"/>',
    'backward': '<path d="M21.5 6.5v11L13 12zM12 6.5v11L3.5 12z" fill="currentColor" stroke="currentColor" stroke-width="1.2"/>',
    'repeat': '<path d="M4 11.5V9.5a3 3 0 0 1 3-3h12.5M16.5 3.5l3 3-3 3M20 12.5v2a3 3 0 0 1-3 3H4.5M7.5 20.5l-3-3 3-3"/>',
    'repeat-1': '<path d="M4 11.5V9.5a3 3 0 0 1 3-3h12.5M16.5 3.5l3 3-3 3M20 12.5v2a3 3 0 0 1-3 3H4.5M7.5 20.5l-3-3 3-3"/><text x="12" y="14.6" text-anchor="middle" font-size="7.5" font-weight="800" font-family="system-ui" fill="currentColor" stroke="none">1</text>',
    'chevron-down': '<path d="m5 9 7 7 7-7"/>',
    'queue': '<path d="M9 6h12M9 12h12M9 18h12"/><circle cx="4" cy="6" r="1.3" fill="currentColor"/><circle cx="4" cy="12" r="1.3" fill="currentColor"/><circle cx="4" cy="18" r="1.3" fill="currentColor"/>',
    'grip': '<path d="M4 8h16M4 12h16M4 16h16"/>',
    'play-next': '<path d="M3 6h11M3 11h7M3 16h7"/><path d="M14 11.5v8l6.5-4z" fill="currentColor"/>',
    'play-later': '<path d="M3 6h16M3 11h16M3 16h8"/><path d="M17.5 14v7M14 17.5h7"/>',
    'bars': '<path d="M5 20v-8M10 20V5M15 20V9M20 20v-5"/>',
  };
  const sprite = Object.entries(icons)
    .map(([id, body]) => `<symbol id="i-${id}" viewBox="0 0 24 24">${body}</symbol>`)
    .join('');
  document.addEventListener('DOMContentLoaded', () => {
    document.body.insertAdjacentHTML(
      'afterbegin',
      `<svg width="0" height="0" style="position:absolute">${sprite}</svg>`,
    );
  });
})();
