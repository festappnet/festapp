import { emailTlds } from './email_tlds.g.js';

// Syntax and requiredness belong to the caller. This is not a deliverability check.
export function classifyEmailDomainSuffix(email) {
    const value = email.trim();
    const domain = value.slice(value.lastIndexOf('@') + 1);
    const suffix = domain.slice(domain.lastIndexOf('.') + 1).toLowerCase();
    return { suffix, status: emailTlds.has(suffix) ? 'knownSuffix' : 'unrecognizedSuffix' };
}
