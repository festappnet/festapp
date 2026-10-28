import { check } from '../errors.mjs';
import { z } from 'zod';
import { scopesForOperation } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';

import { MAKE_READ_OPERATIONS, MAKE_SCOPES, MAKE_LIMITS } from './make-contract.mjs';

export function makeDocumentation(config, catalog) {
    return {
        openapi: '3.1.0',
        info: { title: 'vstupenky.online - Make read API', version: '1.0.0',
            description: 'Read-only order-summary projection. Explicit event consent expires after seven days; refresh does not extend consent. Lists are not a database snapshot.' },
        servers: [{ url: config.issuer + '/make/v1' }],
        'x-oauth-resource': config.resource,
        paths: Object.fromEntries(catalog.filter(d => MAKE_READ_OPERATIONS.includes(d.id)).map(d => [
            '/operations/' + d.id, { post: { operationId: d.id, description: d.description,
                security: [{ oauth: scopesForOperation(d.id) }],
                requestBody: { required: true, content: { 'application/json': { schema: z.toJSONSchema(d.input, { io: 'input' }) } } },
                responses: { '200': { description: 'Canonical successful operation envelope.',
                    content: { 'application/json': { schema: z.toJSONSchema(d.output, { io: 'output' }) } } },
                    default: { description: 'Failed authentication, permission, input, pagination or upstream contract. Never a successful bundle.' } },
            } },
        ])),
        components: { securitySchemes: { oauth: { type: 'oauth2', flows: { authorizationCode: {
            authorizationUrl: config.issuer + '/auth', tokenUrl: config.issuer + '/token',
            scopes: Object.fromEntries(MAKE_SCOPES.map(scope => [scope, scope])),
        } } } } },
    };
}

export function makeStatus(result) {
    if (result.ok) return 200;
    const code = result.error?.code;
    if (['AUTHENTICATION_REQUIRED', 'MFA_REQUIRED'].includes(code)) return 401;
    if (['FORBIDDEN', 'INSUFFICIENT_SCOPE'].includes(code)) return 403;
    if (code === 'NOT_FOUND_OR_INACCESSIBLE') return 404;
    if (code === 'INVALID_INPUT') return 422;
    if (code === 'TEMPORARILY_LIMITED') return 429;
    if (code === 'TIMEOUT') return 504;
    return 502;
}

export function validateMakePage(operation, input, result, headers = {}) {
    if (!result.ok) return;
    if (operation === 'orders.inspect') {
        check(result.data.orders.length > 0, 'NOT_FOUND_OR_INACCESSIBLE');
        check(result.data.orders.length === 1 && result.data.orders[0].id === input.orderId &&
            result.data.orders[0].occasionId === input.occasionId, 'UPSTREAM_CONTRACT_FAILURE');
        return;
    }
    if (operation !== 'orders.list') return;
    const { orders, nextCursor } = result.data;
    let previous = input.before ?? Infinity;
    for (const row of orders) {
        check(Number.isSafeInteger(row.id) && row.id > 0 && row.id < previous,
            'UPSTREAM_CONTRACT_FAILURE');
        previous = row.id;
    }
    check(nextCursor === null || (orders.length > 0 && nextCursor === previous),
        'UPSTREAM_CONTRACT_FAILURE');
    const pageText = headers['x-festapp-make-page'];
    const limitText = headers['x-festapp-make-total-limit'];
    check(pageText === undefined || /^[1-9][0-9]*$/.test(pageText), 'INVALID_INPUT');
    check(limitText === undefined || limitText === '' || /^[1-9][0-9]*$/.test(limitText), 'INVALID_INPUT');
    const page = pageText === undefined ? 1 : Number(pageText);
    const totalLimit = !limitText ? Infinity : Number(limitText);
    check(Number.isSafeInteger(page) && page <= MAKE_LIMITS.maxPages &&
        (totalLimit === Infinity || Number.isSafeInteger(totalLimit)), 'PAGINATION_LIMIT_EXCEEDED');
    // Fail before Make's own request ceiling, rather than silently ending an
    // all-results export. A caller asking for exactly 2500 rows can still finish.
    check(page < MAKE_LIMITS.maxPages || nextCursor === null || totalLimit <= page * MAKE_LIMITS.pageSize,
        'PAGINATION_LIMIT_EXCEEDED');
}
