// Receipt controls must remain readable when external icon fonts are unavailable.
const paths = {
    copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V4H4v12h4"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    check_circle: '<circle cx="12" cy="12" r="9"/><path d="m7 12 3 3 7-7"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10v1"/>',
    error: '<circle cx="12" cy="12" r="9"/><path d="M12 6v7m0 3v1"/>',
};

export function orderIcon(name) {
    return `<svg aria-hidden="true" focusable="false" width="100%" height="100%" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${paths[name] || paths.error}</svg>`;
}
