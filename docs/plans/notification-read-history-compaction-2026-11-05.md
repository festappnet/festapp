# Read notification history compaction

The presentation now has one read order summary per occasion and activity kind,
across days and independently sealed read batches. New unread activity retains
its own summary. Bank and email problems remain individual actionable records.
Counts include all eligible members; previews remain bounded to three contacts.
Opening a summary selects its complete captured order membership, including when
another tab reads newer activity after the snapshot was captured.

Canonical delivery facts, read receipts and seen watermarks are unchanged. Only
prepared presentation identifiers change. Migration 20261105230000 invalidates
organization 3 view leases and requests a bounded rebuild through the existing
worker. It fails if projection scopes from other organizations are present,
requiring a separately scoped rollout. No new background service is introduced.

The supplied YouTube screenshot demonstrates one updated likes summary per video.
No exact Facebook or YouTube time window is assumed. Related activity grouping
and updating an existing notification are also documented platform patterns:
https://developer.android.com/develop/ui/views/notifications/group
https://developer.apple.com/documentation/usernotifications/unnotificationcontent/threadidentifier

The regression test creates three separately read orders on different days,
checks one complete history row, adds a new unread order, reads it, and verifies
both the updated history and the unchanged older snapshot and canonical receipts.
