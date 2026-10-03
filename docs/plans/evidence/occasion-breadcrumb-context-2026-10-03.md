# Retained breadcrumb contexts - 2026-10-03

Switching A -> B -> A through the real RouterService breadcrumb caller and
returning with native Back lost the initial history subtab on the shipped code.
The regression failed repeatedly with `/occasion-a/reservations/orders/current`
instead of `/occasion-a/reservations/orders/history`.

AutoRoute uses route keys in child-controller selection as well as native match
IDs. UnitAdminRoute, AdminRoute and ReservationsRoute now use their expanded
paths as keys so different contexts do not share the page-type key. Authorized
nested routers stay mounted while global context belongs to another instance;
their content is hidden behind a loading screen. Context listeners only reload
the visible native route and only rebuild when denial state actually changes.
Initial denial still creates no protected children.

Validation: 96 targeted navigation/unit widget tests passed; scoped analysis
reported no errors or warnings. The fixture now uses the production no-transition
route behavior and expanded path keys. The new regression asserts bounded
settling, exactly one context load per switch, and the original subtab after Back.

Full-app local check used synthetic Auth/REST data on loopback port 56521 and an
isolated headless agent-browser session, with production notification SDK calls
stubbed by the existing E2E entry point. Actual occasion-picker handlers were
clicked, not direct router calls. A -> B -> A -> B rendered the order grid each
time; observed `get_app_config_v218` requests were one per switch. This confirms
local settling; the user's entire persistent production refresh loop was not
independently captured. The original regression was a lost retained subtab.

The separate existing local-preview checkout was based on 5e13d80b8 and missed
later shipped sidebar/dialog/context changes. No other Flutter server was
running when inspected. A fresh Festapp preview will use the release checkout
rather than that stale local branch.
