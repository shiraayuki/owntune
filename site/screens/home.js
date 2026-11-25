// Extra glyphs for the Home mockups, on top of mockup.js, m2.js and roadmap.js.
(function () {
  const icons = {
    'heart': '<path d="M12 20.5s-8.5-5-8.5-11A4.6 4.6 0 0 1 12 7a4.6 4.6 0 0 1 8.5 2.5c0 6-8.5 11-8.5 11z"/>',
    'heart-fill': '<path d="M12 20.5s-8.5-5-8.5-11A4.6 4.6 0 0 1 12 7a4.6 4.6 0 0 1 8.5 2.5c0 6-8.5 11-8.5 11z" fill="currentColor"/>',
    'flame': '<path d="M12 3c1 3.2 5.5 5.6 5.5 10.5a5.5 5.5 0 0 1-11 0c0-2 .9-3.4 2-4.5.2 1.4.9 2.2 1.8 2.5C10 8.8 10.4 5.6 12 3z" fill="currentColor"/>',
    'headphones': '<path d="M4 17v-4a8 8 0 0 1 16 0v4"/><rect x="3" y="14" width="4" height="7" rx="1.5"/><rect x="17" y="14" width="4" height="7" rx="1.5"/>',
    'sparkles': '<path d="M10 4l1.6 4.4L16 10l-4.4 1.6L10 16l-1.6-4.4L4 10l4.4-1.6zM18 14l.9 2.1L21 17l-2.1.9L18 20l-.9-2.1L15 17l2.1-.9z"/>',
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
