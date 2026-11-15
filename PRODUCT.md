# Festapp product context

Festapp serves event organizers and their customers through an existing Flutter
application, public web sales forms, order overviews and shared email delivery.
Authoritative architecture and ownership live in `docs/architecture/ai_context.md`
and component READMEs; this file records the incumbent UI context for design review.

Customer self-service extends the existing order overview. The existing email
button remains the entry point. Submitted answers are customer read-only, including names and phones. Staff handle
corrections. Customers see server-authorized cancellation and move operations,
verify a specific proposal through the order's stored email, review consequences
and explicitly confirm. Organizer approval and required reasons are independent
rules. A submitted request, a canceled order and a settled refund are distinct.

Use existing typography, controls, spacing and localized terminology. Maintain
keyboard access, status announcements and usable touch targets. Preserve a clear
reading order on narrow screens. Server state determines success, availability
and financial facts. Do not expose credentials, internal infrastructure or
administrative implementation details in customer copy.

The feature defaults off and is prepared locally. Deployment and activation are
separate authorized operations. The current implementation scope and boundaries
are in `docs/plans/customer-self-service-plan-2026-11-15.md`.
