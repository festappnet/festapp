// Small local SVG vocabulary shared by scanner controls and status feedback.
const paths = {
    sound: '<path d="M4 9h4l5-4v14l-5-4H4zM17 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
    back: '<path d="M20 12H4m6-6-6 6 6 6"/>',
    scan: '<path d="M8 3H5a2 2 0 0 0-2 2v3m13-5h3a2 2 0 0 1 2 2v3M3 16v3a2 2 0 0 0 2 2h3m13-5v3a2 2 0 0 1-2 2h-3M7 12h10"/>',
    camera: '<path d="m14 4 2 3h4a1 1 0 0 1 1 1v11H3V8a1 1 0 0 1 1-1h4l2-3z"/><circle cx="12" cy="13" r="3"/>',
    manual: '<path d="M4 5h16v14H4zM7 9h2m2 0h2m2 0h2M7 13h2m2 0h2m2 0h2M8 16h8"/>',
    history: '<path d="M3 11a9 9 0 1 1 2 7M3 4v7h7m2-5v6l4 2"/>',
    offline: '<path d="M7 17H6a4 4 0 0 1-.6-8 7 7 0 0 1 13.2 0A4 4 0 0 1 18 17h-1m-5-5v9m-3-3 3 3 3-3"/>',
    theme: '<path d="M20.5 14A9 9 0 0 1 10 3.5 9 9 0 1 0 20.5 14Z"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    arrow: '<path d="M4 12h16m-6-6 6 6-6 6"/>',
    ticket: '<path d="M3 6h18v4a2 2 0 0 0 0 4v4H3v-4a2 2 0 0 0 0-4zM15 6v3m0 3v1m0 3v2"/>',
    ticket_check: '<path d="M3 6h18v4a2 2 0 0 0 0 4v4H3v-4a2 2 0 0 0 0-4zM8 12l3 3 5-6"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    alert: '<path d="m12 3 10 18H2zM12 9v4m0 3v1"/>',
    switch: '<path d="M4 8h15m-4-4 4 4-4 4M20 16H5m4-4-4 4 4 4"/>',
    stop: '<rect x="6" y="6" width="12" height="12" rx="2"/>',
};
export const icon = name => `<svg class="scan-icon" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${paths[name] || paths.scan}</svg>`;
