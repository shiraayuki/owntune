// Extra glyphs for the roadmap mockups, on top of ../m1-v3/mockup.js and
// ../m2-v1/m2.js.
(function () {
  const icons = {
    'download': '<path d="M12 3v12M7 10l5 5 5-5"/><path d="M4 17v3h16v-3"/>',
    'download-circle': '<circle cx="12" cy="12" r="9"/><path d="M12 7.5v8M8.5 12.5 12 16l3.5-3.5"/>',
    'globe': '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.2 3 14.8 0 18M12 3c-3 3.2-3 14.8 0 18"/>',
    'photo': '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="8.5" cy="10" r="1.6"/><path d="m21 16-5-5-8 8"/>',
    'folder': '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
    'pencil': '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="m13.5 6.5 4 4"/>',
    'clock': '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    'list-add': '<path d="M3 6h12M3 11h12M3 16h7"/><path d="M17.5 13v8M13.5 17h8"/>',
    'select': '<circle cx="12" cy="12" r="9"/><path d="m8 12.5 3 3 5-6"/>',
    'chart': '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
    'cloud': '<path d="M7 18h10.5a4 4 0 0 0 .6-7.95A6 6 0 0 0 6.6 9.2 4.4 4.4 0 0 0 7 18z"/>',
    'tv': '<rect x="3" y="5" width="18" height="12" rx="2"/><path d="m10 8.5 4.5 2.5-4.5 2.5z" fill="currentColor"/><path d="M8 20h8"/>',
    'arrow-up-doc': '<path d="M7 3h7l5 5v13H7z"/><path d="M14 3v5h5M13 18v-6M10.5 14.5 13 12l2.5 2.5"/>',
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
