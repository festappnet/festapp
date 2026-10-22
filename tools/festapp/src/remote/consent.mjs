import { z } from 'zod';
import { verifySelection } from '../operations/access.mjs';
import { check } from '../errors.mjs';
import { verifyOrderPermissions } from './config.mjs';

const consent = z.strictObject({ consentVersion: z.literal(2), selection: z.unknown(), permissions: z.array(z.string()).max(4) });

/** The existing Edge exchange transports this opaque consent. Only the issuer
 * interprets membership and functional permissions or persists a delegation. */
export function verifyConsent(raw, available, canCreate, requestedPermissions) {
    if (raw?.consentVersion !== undefined) {
        const parsed = consent.safeParse(raw);
        check(parsed.success, 'FORBIDDEN');
        return { selected: verifySelection(parsed.data.selection, available, canCreate),
            permissions: verifyOrderPermissions(parsed.data.permissions, requestedPermissions) };
    }
    return { selected: verifySelection(raw, available, canCreate), permissions: [] };
}
