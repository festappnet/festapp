/** Functional delegation contract shared by issuer and tenant consent UI.
 * Adding a scope never expands an already issued grant or token. */
export const MCP_PERMISSIONS = Object.freeze({
    'festapp:orders:read': { label: 'ordersRead', operations: ['orders.report', 'orders.list', 'orders.inspect'], requires: [] },
    'festapp:orders:write': { label: 'ordersWrite', operations: ['orders.update', 'orders.cancel'], requires: ['festapp:orders:read'] },
    'festapp:payments:write': { label: 'paymentsWrite', operations: ['orders.mark_paid', 'payments.record'], requires: ['festapp:orders:read'] },
    'festapp:tickets:send': { label: 'ticketsSend', operations: ['orders.send_tickets'], requires: ['festapp:orders:read'] },
    'festapp:inventory:read': { label: 'inventoryRead', operations: ['inventory.pools.list','inventory.contexts.list','inventory.pools.inspect','inventory.resources.list'], requires: [] },
    'festapp:inventory:write': { label: 'inventoryWrite', operations: ['inventory.change'], requires: ['festapp:inventory:read'] },
    'festapp:standing-inventory:write': { label: 'standingInventoryWrite', operations: ['inventory.prepare_standing'], requires: ['festapp:products:read'] },
    'festapp:product-schedules:read': { label: 'productSchedulesRead', operations: ['product_schedules.list'], requires: ['festapp:products:read'] },
    'festapp:product-schedules:write': { label: 'productSchedulesWrite', operations: ['product_schedules.change'], requires: ['festapp:products:read', 'festapp:product-schedules:read'] },
    'festapp:products:read': { label: 'productsRead', operations: ['products.list'], requires: [] },
    'festapp:products:write': { label: 'productsWrite', operations: ['products.save', 'products.delete'], requires: ['festapp:products:read'] },
});
export const MCP_SCOPES = Object.freeze(Object.keys(MCP_PERMISSIONS));
export function scopesForOperation(operation) {
    const scope = MCP_SCOPES.find(s => MCP_PERMISSIONS[s].operations.includes(operation));
    return scope ? [...MCP_PERMISSIONS[scope].requires, scope] : [];
}
export function validPermissions(permissions) {
    return Array.isArray(permissions) && permissions.every(p => Object.hasOwn(MCP_PERMISSIONS, p) &&
        MCP_PERMISSIONS[p].requires.every(required => permissions.includes(required)));
}
