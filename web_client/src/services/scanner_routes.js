// Pure resolver also embedded by the PWA and deployment generators.
export function resolveScannerRoute(path) {
    const legacy = path.match(/^\/(?:[^/]+\/)?check\/([1-9][0-9]*)\/?$/);
    if (legacy) return { page: 'program', eventId: legacy[1], canonical: `/scan/program/${legacy[1]}` };
    if (path === '/login-qr' || path === '/login-qr/') return { page: 'reception' };
    if (path === '/scan' || path === '/scan/') return { page: 'scan' };
    const sub = path.match(/^\/scan\/(settings|history|offline)\/?$/);
    if (sub) return { page: sub[1] };
    const program = path.match(/^\/scan\/program\/([1-9][0-9]*)\/?$/);
    if (program) return { page: 'program', eventId: program[1] };
    const code = path.match(/^\/scan\/([^/]+)$/);
    if (code && !['program','settings','history','offline'].includes(code[1])) {
        try { const decoded = decodeURIComponent(code[1]); if (/^[A-Za-z0-9_-]{1,100}$/.test(decoded)) return { page: 'scan', code: decoded }; } catch {}
    }
    return null;
}
