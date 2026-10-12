# Attendance identity privacy cutover

The additive migration `20261009133000_event_attendance_summary.sql` is safe
before the updated Flutter client. It exposes only event ID, total participant
count and the caller's own attendance flag. It applies the existing event-read
authorization rules. All direct `event_users` readers in the current Flutter
source now use this RPC. Editor participant lists retain their authorized RPC.

This additive release does **not** remove the existing public UUID exposure.
Installed older clients fetch `event_users.select()` and count all returned
rows. Restricting table rows silently makes their capacity displays inaccurate.
Column revocation also breaks their `select(*)`; a masking view would require
renaming the table and reworking foreign keys, SQL function dependencies and
PostgREST embedded relationships. Neither is a transparent narrow fix.

Release order:

1. Apply the additive RPC migration.
2. Release the updated web and supported mobile clients. Verify child-event
   counts, detail counts and the signed-in flag, with and without login.
3. Establish that legacy readers are retired, or explicitly authorize ending
   support for their counts. A web release alone does not update mobile apps.
4. Remove the `Enable read for all` SELECT policy on `public.event_users`.
   Retain the existing authenticated own-row policy and SELECT grant so older
   own-state readers and authorized editor RPCs keep working. Record the same
   change in canonical `database/policies/02_policies.sql` and a forward
   migration at that point.
5. Run `event_attendance_summary_test.sql` and authenticated/anonymous smoke.
   The test already exercises the final policy removal inside its rolled-back
   transaction, including blocked raw UUID reads and preserved total counts.

Do not restore anonymous row access as a count fallback. If a current client
fails to call the aggregate RPC, correct its deployment or RPC contract.
