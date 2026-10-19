# Shared Edge Function boundaries

Endpoint-specific authorization stays at the request boundary. `auth.ts`
supports the established system-secret or user-token contract; importing a
service-role client never authorizes the caller. The full route inventory and
release procedure are in the [Edge reference](../../../docs/backend/edge_functions.md).

## Email ownership

Producers render/enqueue through the shared email adapters and durable SQL
intents. `process-email-queue` alone sends through `emailSender.ts` after the
fenced global send permit. `emailWorkerEnvironment.ts` restricts transport
credentials to that worker. Keep encryption, retry state and post-actions on the
same queue boundary; see [SES delivery](../../../docs/setup/aws_ses.md).

Template and wrapper inheritance belongs to the existing
[template resolver](../../../lib/components/email_templates/README.md).
Provider acceptance is distinct from delivery feedback.

## One ticket renderer

`ticketGeneration.ts` resolves saved layouts/resources and normalizes order
content. `drawLayoutTicket` in `generateTicket.ts` renders PDFs for download,
email and preview. Fonts come from the pinned catalog under `ticket-assets/`;
never fetch a font from a client-supplied URL. Preserve identical font metrics,
QR rules and product bindings across the Flutter canvas and PDF output.

The [ticket layout contract](../../../lib/components/ticket_layout/README.md)
explains schema, persistence and preview lifecycles. Historical geometry readers
belong only to the offline product-type converter, not the runtime import graph.
