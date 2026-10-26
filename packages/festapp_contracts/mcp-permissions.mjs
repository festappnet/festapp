/** Functional delegation contract shared by issuer and tenant consent UI.
 * Adding a scope never expands an already issued grant or token. */
export const MCP_PERMISSIONS = Object.freeze({
    'festapp:forms:read': { label: 'formsRead', operations: ['forms.list','forms.inspect'], requires: [] },
    'festapp:forms:write': { label: 'formsWrite', operations: ['forms.publicLink','forms.setPublicLink','forms.paymentOptions','forms.create','forms.save','forms.duplicate','forms.delete'], requires: ['festapp:forms:read'] },
    'festapp:email-templates:read': { label: 'emailTemplatesRead', operations: ['email_templates.list','email_templates.inspect','email_templates.banner.inspect','email_templates.preview'], requires: [] },
    'festapp:email-templates:write': { label: 'emailTemplatesWrite', operations: ['email_templates.change','email_templates.banner.change'], requires: ['festapp:email-templates:read'] },
    'festapp:orders:create': {label:'ordersCreate',operations:['forms.previewOrder','forms.createOrder'],requires:['festapp:orders:read','festapp:forms:read']},
    'festapp:waitlist:accept': {label:'waitlistAccept',operations:['waitlist.previewAccept','waitlist.accept'],requires:['festapp:waitlist:write','festapp:orders:create']},
    'festapp:waitlist:read': {label:'waitlistRead',operations:['waitlist.detail'],requires:['festapp:orders:read']},
    'festapp:waitlist:write': {label:'waitlistWrite',operations:['waitlist.proposal','waitlist.send','waitlist.cancel','waitlist.decline','waitlist.withdraw'],requires:['festapp:waitlist:read','festapp:orders:read']},
    'festapp:orders:read': { label: 'ordersRead', operations: ['orders.report', 'orders.list', 'orders.inspect'], requires: [] },
    'festapp:orders:write': { label: 'ordersWrite', operations: ['orders.update', 'orders.cancel'], requires: ['festapp:orders:read'] },
    'festapp:payments:write': { label: 'paymentsWrite', operations: ['orders.mark_paid', 'payments.record'], requires: ['festapp:orders:read'] },
    'festapp:tickets:send': { label: 'ticketsSend', operations: ['orders.send_tickets'], requires: ['festapp:orders:read'] },
    'festapp:seats:read': { label: 'seatsRead', operations: ['seats.list'], requires: [] },
    'festapp:seats:release-holds': { label: 'seatsReleaseHolds', operations: ['seats.preview_release','seats.release_holds'], requires: ['festapp:seats:read'] },
    'festapp:seats:create-orders': { label: 'seatsCreateOrders', operations: ['seats.preview_order','seats.create_order'], requires: ['festapp:seats:read','festapp:orders:read'] },
    'festapp:seats:cancel-tickets': { label: 'seatsCancelTickets', operations: ['seats.preview_cancel','seats.cancel_tickets'], requires: ['festapp:seats:read','festapp:orders:read'] },
    'festapp:seats:swap': { label: 'seatsSwap', operations: ['seats.preview_swap','seats.swap'], requires: ['festapp:seats:read','festapp:orders:read'] },
    'festapp:seats:block': { label: 'seatsBlock', operations: ['seats.preview_block','seats.block'], requires: ['festapp:seats:read'] },
    'festapp:inventory:read': { label: 'inventoryRead', operations: ['inventory.pools.list','inventory.contexts.list','inventory.pools.inspect','inventory.resources.list'], requires: [] },
    'festapp:inventory:write': { label: 'inventoryWrite', operations: ['inventory.change'], requires: ['festapp:inventory:read'] },
    'festapp:standing-inventory:write': { label: 'standingInventoryWrite', operations: ['inventory.prepare_standing'], requires: ['festapp:products:read'] },
    'festapp:product-schedules:read': { label: 'productSchedulesRead', operations: ['product_schedules.list'], requires: ['festapp:products:read'] },
    'festapp:product-schedules:write': { label: 'productSchedulesWrite', operations: ['product_schedules.change'], requires: ['festapp:products:read', 'festapp:product-schedules:read'] },
    'festapp:product-options:read': { label: 'productOptionsRead', operations: ['products.options'], requires: ['festapp:products:read'] },
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
