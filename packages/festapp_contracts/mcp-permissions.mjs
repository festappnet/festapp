/** Functional delegation contract shared by issuer and tenant consent UI.
 * Adding a scope never expands an already issued grant or token. */
export const MCP_PERMISSIONS = Object.freeze({
    'festapp:history:delete': {label:'historyDelete',operations:['history.delete'],requires:['festapp:order-history:read']},
    'festapp:orders:delete': {label:'ordersDelete',operations:['orders.deletion.inspect','orders.delete'],requires:['festapp:orders:read']},
    'festapp:lifecycle:read': {label:'lifecycleRead',operations:['lifecycle.inspect','lifecycle.pending','occasions.setup.inspect'],requires:[]},
    'festapp:lifecycle:write': {label:'lifecycleWrite',operations:['occasions.copy','occasions.delete','lifecycle.resume'],requires:['festapp:lifecycle:read']},
    'festapp:setup:finalize': {label:'setupFinalize',operations:['occasions.setup.finalize'],requires:['festapp:lifecycle:read']},
    'festapp:units:delete': {label:'unitsDelete',operations:['units.delete'],requires:[]},
    'festapp:quotes:read': {label:'quotesRead',operations:['units.quotes.list'],requires:[]},
    'festapp:quotes:write': {label:'quotesWrite',operations:['units.quotes.save','units.quotes.delete'],requires:['festapp:quotes:read']},
    'festapp:legal:read': {label:'legalRead',operations:['units.legal.inspect'],requires:[]},
    'festapp:legal:write': {label:'legalWrite',operations:['units.legal.save','units.legal.submit'],requires:['festapp:legal:read']},
    'festapp:banks:read': {label:'banksRead',operations:['banks.list','banks.candidates','banks.status','banks.operations','banks.observations'],requires:[]},
    'festapp:bank-users:read': {label:'bankUsersRead',operations:['banks.users'],requires:['festapp:banks:read']},
    'festapp:banks:write': {label:'banksWrite',operations:['banks.save','banks.link','banks.user','banks.sync','banks.suspend','banks.resume'],requires:['festapp:banks:read']},
    'festapp:cards:read': {label:'cardsRead',operations:['cards.status','cards.disconnectImpact'],requires:[]},
    'festapp:cards:write': {label:'cardsWrite',operations:['cards.pause','cards.disconnect'],requires:['festapp:cards:read']},
    'festapp:refund-decisions:read': {label:'refundDecisionsRead',operations:['cards.refund.inspect'],requires:['festapp:orders:read']},
    'festapp:refund-decisions:write': {label:'refundDecisionsWrite',operations:['cards.refund.decide'],requires:['festapp:refund-decisions:read']},
    'festapp:history:read': {label:'historyRead',operations:['history.commits','history.commit','history.activity'],requires:[]},
    'festapp:order-history:read': {label:'orderHistoryRead',operations:['history.orders','history.email'],requires:['festapp:orders:read']},
    'festapp:feedback:read': {label:'feedbackRead',operations:['feedback.list'],requires:[]},
    'festapp:report-exports:read': {label:'reportExportsRead',operations:['reports.export'],requires:['festapp:orders:read']},
    'festapp:export-people:read': {label:'peopleExportsRead',operations:['exports.people'],requires:['festapp:people:read']},
    'festapp:export-orders:read': {label:'orderExportsRead',operations:['exports.orders'],requires:['festapp:orders:read']},
    'festapp:export-events:read': {label:'programExportsRead',operations:['exports.events'],requires:['festapp:program:read']},
    'festapp:export-places:read': {label:'mapExportsRead',operations:['exports.places'],requires:['festapp:map:read']},
    'festapp:export-speakers:read': {label:'speakerExportsRead',operations:['exports.speakers'],requires:['festapp:speakers:read']},
    'festapp:export-feedback:read': {label:'feedbackExportsRead',operations:['exports.feedback'],requires:['festapp:feedback:read']},
    'festapp:program:read': {label:'programRead',operations:["events.list","events.inspect","events.roles","exclusiveGroups.list","exclusiveGroups.inspect"],requires:[]},
    'festapp:program:write': {label:'programWrite',operations:["events.save","events.delete","exclusiveGroups.save","exclusiveGroups.delete"],requires:['festapp:program:read']},
    'festapp:map:read': {label:'mapRead',operations:["places.list","places.inspect","places.icons","placeTypes.list","placeTypes.inspect","paths.list","paths.inspect"],requires:[]},
    'festapp:map:write': {label:'mapWrite',operations:["places.save","places.delete","places.move","placeTypes.save","placeTypes.delete","paths.save","paths.delete"],requires:['festapp:map:read']},
    'festapp:speakers:read': {label:'speakersRead',operations:["speakers.list","speakers.inspect","topics.list","topics.inspect","eventSpeakers.inspect","counseling.list"],requires:[]},
    'festapp:speakers:write': {label:'speakersWrite',operations:["speakers.save","speakers.delete","topics.save","topics.delete","eventSpeakers.save","counseling.createSlots","counseling.deleteEmptySlots","counseling.deleteSlot"],requires:['festapp:speakers:read']},
    'festapp:activities:read': {label:'activitiesRead',operations:["activities.inspect"],requires:[]},
    'festapp:activities:write': {label:'activitiesWrite',operations:["activities.saveDraft","activities.discardDraft","activities.publish"],requires:['festapp:activities:read']},
    'festapp:services:read': {label:'servicesRead',operations:["services.list"],requires:[]},
    'festapp:services:write': {label:'servicesWrite',operations:["services.create","services.update","services.delete"],requires:['festapp:services:read']},
    'festapp:attendance:write': {label:'attendanceWrite',operations:['attendance.set'],requires:['festapp:program:read']},
    'festapp:scanner:read': {label:'scannerRead',operations:['scanner.inspect'],requires:[]},
    'festapp:scanner:admit': {label:'scannerAdmit',operations:['scanner.admit'],requires:['festapp:scanner:read']},
    'festapp:blueprints:read': {label:'blueprintsRead',operations:['blueprints.list','blueprints.inspect','blueprints.validate','blueprints.fonts'],requires:[]},
    'festapp:blueprints:write': {label:'blueprintsWrite',operations:['blueprints.save','blueprints.prepare_text'],requires:['festapp:blueprints:read']},
    'festapp:ticket-artwork:preview': {label:'ticketArtworkPreview',operations:['ticket_layouts.preview'],requires:[]},
    'festapp:ticket-artwork:write': {label:'ticketArtworkWrite',operations:['ticket_layouts.save','ticket_layouts.pending','ticket_layouts.resume'],requires:['festapp:ticket-artwork:preview']},
    'festapp:people:read': {label:'peopleRead',operations:['profiles.list','profiles.inspect'],requires:[]},
    'festapp:people:write': {label:'peopleWrite',operations:['profiles.create','profiles.save','profiles.delete','profiles.import','profiles.importTickets'],requires:['festapp:people:read']},
    'festapp:people:roles': {label:'peopleRoles',operations:['profiles.roles'],requires:['festapp:people:read']},
    'festapp:groups:read': {label:'groupsRead',operations:['groups.list','groups.inspect'],requires:[]},
    'festapp:groups:write': {label:'groupsWrite',operations:['groups.save','groups.delete','groups.addMembers','groups.replaceAssignments'],requires:['festapp:groups:read']},
    'festapp:unit-people:read': {label:'unitPeopleRead',operations:['units.people.list'],requires:[]},
    'festapp:unit-people:write': {label:'unitPeopleWrite',operations:['units.people.create','units.people.profile'],requires:['festapp:unit-people:read']},
    'festapp:unit-people:roles': {label:'unitPeopleRoles',operations:['units.people.roles'],requires:['festapp:unit-people:read']},
    'festapp:unit-people:revoke': {label:'unitPeopleRevoke',operations:['units.people.revoke'],requires:['festapp:unit-people:read']},
    'festapp:occasion-settings:read': {label:'occasionSettingsRead',operations:['occasions.settings.inspect','occasions.game.inspect'],requires:[]},
    'festapp:occasion-settings:write': {label:'occasionSettingsWrite',operations:['occasions.settings.save','occasions.publicLink','occasions.setPublicLink','occasions.game.save'],requires:['festapp:occasion-settings:read']},
    'festapp:unit-settings:read': {label:'unitSettingsRead',operations:['units.settings.inspect'],requires:[]},
    'festapp:unit-settings:write': {label:'unitSettingsWrite',operations:['units.settings.save'],requires:['festapp:unit-settings:read']},
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
// These names are existing external OAuth contracts, shared by every host.
export const READ_SCOPE = 'festapp:ticket-layouts:read';
export const CREATE_SCOPE = 'festapp:occasions:create';
export const READ_OPERATIONS = Object.freeze(['context.inspect', 'access.inspect', 'ticket_layouts.inspect']);
export function scopesForOperation(operation) {
    if (READ_OPERATIONS.includes(operation)) return [READ_SCOPE];
    if (operation === 'occasions.create') return [READ_SCOPE, CREATE_SCOPE];
    const scope = MCP_SCOPES.find(s => MCP_PERMISSIONS[s].operations.includes(operation));
    if (!scope) return null; // Unknown hosted operations must fail closed.
    const required = new Set([READ_SCOPE]);
    const include = s => { MCP_PERMISSIONS[s].requires.forEach(include); required.add(s); };
    include(scope);
    if(['occasions.copy','occasions.setup.finalize'].includes(operation))required.add(CREATE_SCOPE);
    return [...required];
}
export function validPermissions(permissions) {
    return Array.isArray(permissions) && permissions.every(p => Object.hasOwn(MCP_PERMISSIONS, p) &&
        MCP_PERMISSIONS[p].requires.every(required => permissions.includes(required)));
}
