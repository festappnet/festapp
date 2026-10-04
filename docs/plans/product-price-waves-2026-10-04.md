# Product price waves

Shared occasion terms are metadata over the existing `eshop.planned_changes` queue.
The grid toolbar opens a vertical timeline: current product state first, followed
by shared terms in chronological order. Product controls stack on narrow screens.
Each product at a term can change its price, availability, or both.
Blank price and unchanged availability remove only that cell's pending targets.
Currency stays fixed. Input and displayed time use device local time; RPCs persist UTC.

Existing individual schedules remain visible. Creating a shared term adopts only
unambiguous price/visibility targets at the same instant, preserving values and revisions.
Moving an individual price detaches it from a wave without moving visibility.
Moving a wave updates all remaining targets atomically. Cancelling removes pending
targets only; applied history survives and applied product state is never reverted.

Mutations require tenant-scoped order-editor permission, wave revision and target
revisions. Locks follow wave, products in ID order, then plans. Worker application
uses the existing product/plan locks and scheduler. Wave moves recheck application
after waiting for product locks. Product deletion removes pending visibility too.

Automatic refresh includes due availability changes and pauses during editing.
Local nonexistent wall times are rejected; an unchanged existing ambiguous time
retains its original UTC instant. New ambiguous local input uses the platform's offset.

Validation includes real PostgreSQL lock contention, stale public checkout after
hiding, editor/viewer/tenant permissions, widget editing, narrow-screen rendering
and isolated headless screenshots of real widgets with synthetic preview data.
Screenshots are visual evidence, not production editing or end-to-end backend proof.
