import {
    canonicalBackendActivationSha256,
    canonicalBackendProfileSha256,
} from '../../../../automation/lib/backend_activation_manifest.mjs';
import { parseSupabaseOrigin } from '../../../../automation/lib/supabase_client_config.mjs';
import { parseProfile } from './profile.mjs';
import { check } from '../errors.mjs';
// Read only selected literal assignments. Never source or execute project.conf.
export function profileFromTenant(text, name) {
    const fields = {};
    const selected = new Set([
        'WEB_LINK',
        'BACKEND_ACTIVATION_TENANT_ID',
        'BACKEND_ACTIVATION_PHASE',
        'BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL',
        'BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY',
        'BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID',
        'BACKEND_ACTIVATION_CANONICAL_PROFILE_SHA256',
    ]);
    for (const line of text.split('\n')) {
        const match = line.match(/^([A-Z_]+)=(.*)$/);
        if (!match || !selected.has(match[1])) continue;
        check(!(match[1] in fields), 'INVALID_PROFILE');
        let value = match[2].trim();
        if (
            (value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))
        )
            value = value.slice(1, -1);
        check(!/[`$\\\r\n]/.test(value), 'INVALID_PROFILE');
        fields[match[1]] = value;
    }
    check(fields.BACKEND_ACTIVATION_PHASE === 'canonical', 'INVALID_PROFILE');
    const tenantId = fields.BACKEND_ACTIVATION_TENANT_ID;
    const backendOrigin = parseSupabaseOrigin(
        fields.BACKEND_ACTIVATION_CANONICAL_SUPABASE_URL,
    );
    const publicApiKey = fields.BACKEND_ACTIVATION_CANONICAL_SUPABASE_ANON_KEY;
    const organizationId = Number(
        fields.BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID,
    );
    const canonicalProfileSha256 = canonicalBackendProfileSha256({
        tenantId,
        canonicalOrigin: backendOrigin,
        canonicalAnonKey: publicApiKey,
        canonicalOrganizationId: organizationId,
    });
    check(
        !fields.BACKEND_ACTIVATION_CANONICAL_PROFILE_SHA256 ||
            fields.BACKEND_ACTIVATION_CANONICAL_PROFILE_SHA256 ===
                canonicalProfileSha256,
        'INVALID_PROFILE',
    );
    const parsed = parseProfile({
        schemaVersion: 1,
        name,
        kind: 'canonical',
        tenantId,
        backendOrigin,
        publicApiKey,
        organizationId,
        activationUrl: new URL('/backend-activation.json', fields.WEB_LINK)
            .href,
        generation: 1,
        activationSha256: canonicalBackendActivationSha256(tenantId),
        canonicalProfileSha256,
    });
    const { binding, ...profile } = parsed;
    return profile;
}
