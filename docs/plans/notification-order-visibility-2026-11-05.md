# Order visibility correction

The user explicitly confirmed that hidden membership protects participant profiles
and their enrollment announcements, while orders have no hidden-buyer exception.
The reported order exists, but publication returned no event because its contact
matched a hidden membership. This was not queue lag or read-history compaction.

Canonical subject visibility and prepared subject indexing share one private
order-activity classifier. Purchases, cancellations, waitlist transitions and
order-linked email incidents remain visible through the existing authorized
order-reader scopes. Hidden participant and unrelated hidden personal-email
surfaces remain excluded. Prepared own-order activity is unread until explicitly
read; installed legacy APIs retain their existing compatibility behavior.

Migration 20261105233000 requests only a bounded rebuild of organization 3 derived
views. It changes no business rows, canonical read receipts or seen watermarks.
The reported missing event is replayed separately through the canonical idempotent
order producer after deployment, with its exact source key and observed order
identity guarded in a protected operational receipt. Historical hidden orders
are not globally replayed.

Regression coverage creates orders through the real checkout function with a
hidden authenticated buyer, checks exactly one published event, the bell and the
new-items signal for a frozen open view, fresh unread selection and preserved
old read receipts. Existing hidden participant and personal-email tests remain.
