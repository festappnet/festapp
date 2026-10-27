import { READ_SCOPE } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';

// One serializer for HTTP challenges and optional tool-result linking metadata.
export function authChallenge(config, { error, description, scopes = [READ_SCOPE] } = {}) {
    const quote = value => String(value).replace(/["\\\r\n]/g, '');
    return `Bearer resource_metadata="${config.issuer}/.well-known/oauth-protected-resource/mcp", scope="${scopes.map(quote).join(' ')}"` +
        (error ? `, error="${quote(error)}", error_description="${quote(description)}"` : '');
}
export function toolResult(result, owner, id) {
    const challenge = !result.ok && owner?.challengeFor?.(result.error?.code, id);
    const { image, ...data } = result.data ?? {};
    const structuredContent = image ? { ...result, data } : result;
    return {
        ...(!result.ok ? { isError: true } : {}),
        content: [
            { type: 'text', text: JSON.stringify(structuredContent) },
            ...(data.file?.uri ? [{type:'resource_link',uri:data.file.uri,name:data.file.fileName,mimeType:data.file.mimeType}] : []),
            ...(image ? [
                { type: 'image', mimeType: image.mimeType, data: image.data },
                { type: 'resource_link', uri: data.pdf.uri, name: 'Canonical synthetic ticket preview', mimeType: 'application/pdf' },
            ] : []),
        ],
        structuredContent,
        ...(challenge ? { _meta: { 'mcp/www_authenticate': [challenge] } } : {}),
    };
}
