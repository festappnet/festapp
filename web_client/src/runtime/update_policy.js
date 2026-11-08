// Every asynchronous executor re-evaluates this immediately before its effect.
export function allowUpdate(reason, {context, phase, publicWeb, draftProtected}) {
    if (publicWeb && draftProtected && reason !== 'corrupt-runtime') return false;
    switch (reason) {
        case 'automatic-update': return publicWeb === true && !draftProtected;
        case 'legacy-migration':
        case 'corrupt-runtime': return true;
        case 'startup':
        case 'manual-startup': return phase !== 'ready';
        case 'background':
        case 'explicit-update': return context !== 'public-embed' || phase !== 'ready';
        default: return false;
    }
}
