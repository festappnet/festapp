# vstupenky.online for Make

Connect your vstupenky.online account with OAuth and select the events you want
to share. No API key, shared password or language model is required. The
connection reads sales summaries and order status; it cannot change orders,
record payments, send tickets or export buyer contacts.

## Modules

- **List Accessible Events** lists only events available to this connection.
  Events with identical names remain separate; use their IDs.
- **Get Event Sales Summary** returns one canonical report for one event,
  including currencies, waiting tickets and warnings.
- **List Orders** returns one bundle per order, with cursor pagination.
- **Get an Order** returns one matching order from the selected event.
- **Make an API Call** calls one of the five documented read operations. Select
  its relative path and enter a JSON body. The transport uses POST; write
  operations and foreign URLs remain forbidden.

## Limits and reconnecting

The list limit defaults to **10 total bundles**. Clear the field to request all
available results within technical bounds. Backend pages contain at most 50
orders. A run can fail at 50 pages, Make's 40-second execution bound, or an API
rate limit. An oversized request fails explicitly rather than becoming a
silently incomplete export. Do not interpret an error as zero sales.

Access tokens refresh automatically. Consent has a fixed lifetime of **seven
days**; refresh does not extend it. Reauthorize the Make connection when consent
expires or is revoked. The service checks your current event permissions on
every read. Sharing this connection does not give another user permission to
read events outside its consent.

Order identifiers, symbols, stored state, ticket counts, currencies and amounts
are available. Buyer names, email addresses, notes, registration responses and
ticket QR content are withheld by the service before data reaches Make.
Keep amounts in their original representation and currency. Current order
value, received money and valid ticket count are separate measures.

## A recurring sales overview

Choose **Get Event Sales Summary**, select one event by its ID, then map the
returned report to your destination. If updating a spreadsheet, use one fixed
row for that event and update that row on reruns. Serialize writes to the same
row. The connector itself does not append rows or perform destination writes.

Lists are not a consistent database snapshot. Another app may already have
written earlier bundles when a later page fails; Make cannot generally roll
those writes back. Use the single-report module for a periodic overview, and
do not treat this connector as an accounting export or exactly-once sync.

Make credits and organization limits apply to scenario execution. The app does
not activate paid plans or automatic credit purchases.

## Errors and support

An expired/revoked connection requires reauthorization. Permission errors require
checking the selected event and current account rights. Invalid inputs must be
corrected. Throttling or a temporary upstream failure can require a later retry;
do not configure another unbounded retry loop. `PAGINATION_LIMIT_EXCEEDED`
means the requested export did not complete.

[API schemas and authentication](https://mcp.vstupenky.online/make/v1).
[Privacy](https://vstupenky.online/privacy/).
[Service terms](https://vstupenky.online/terms/).
Support: info@festapp.net.
