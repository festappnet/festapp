# Form entry transition and ticket scanner

A one-form selector replaces its list with the detail route. The default native
page transition introduced a second slide inside Forms, after the outer tab
transition. The regression injects the actual production detail transition into
a backend-free routed fixture, performs automatic single-form selection, and
checks the native route animation before settling. It failed with an incomplete
entry animation. A zero-duration custom detail route fixes the redundant slide;
the same test verifies that explicit subtab switching still animates.

The ticket scanner handler uses the occasion link and refreshes the table after
scanning; it does not consume selected rows. Its header action no longer requires
selection. Feature/role gating and cancellation's selection requirement stay intact.

108 navigation/unit/ticket-usage tests pass; scoped Dart analysis has no errors
or warnings, with two existing informational diagnostics. Publish shared source
on main; initially deploy only prod/festapptickets on vstupenky.online. The user
will request further domain rollout after testing this version.

Context switches previously replaced the whole administration screen with a plain
spinner while the new boundary loaded. Reuse the normal adaptive app bar and
known context metadata as loading chrome, with no protected child router/grid
constructed. Normal access/failure checks still gate destination content; header
controls are excluded from focus and pointer interaction while pending. The
occasion regression reproduces the missing header after the native route settles,
then verifies matching header bounds while loading. The unit regression verifies
the full-size pending shell and that destination content is not created early.
