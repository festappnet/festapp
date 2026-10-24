import { emailTlds } from './email_tlds.g.js';

// Syntax and requiredness belong to the caller. This is not a deliverability check.
export function classifyEmailDomainSuffix(email) {
    const domain = email.trim().split('@').at(-1);
    const suffix = domain.split('.').at(-1).toLowerCase();
    return { suffix, status: emailTlds.has(suffix) ? 'knownSuffix' : 'unrecognizedSuffix' };
}
