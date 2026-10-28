import { orderDescriptors } from '../operations/orders.mjs';
import { scopesForOperation } from '../../../../packages/festapp_contracts/mcp-permissions.mjs';

// Transport boundaries, never a replacement for DelegatedOwner authorization.
export const MAKE_CLIENT_ID = 'festapp-make';
export const MAKE_READ_OPERATIONS = Object.freeze([
    'context.inspect', 'access.inspect', 'orders.report', 'orders.list', 'orders.inspect',
]);
export const MAKE_SCOPES = Object.freeze([...new Set(MAKE_READ_OPERATIONS.flatMap(scopesForOperation))]);
export const MAKE_LIMITS = Object.freeze({
    pageSize: orderDescriptors.find(d => d.id === 'orders.list').input.shape.limit.unwrap().maxValue,
    maxPages: 50, totalInputCap: 3200, defaultTotal: 10, rpcSampleLimit: 500,
});
