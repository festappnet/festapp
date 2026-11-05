# Bell click-to-content correction

The user clarified the remaining delay as roughly 0.5-1 second. Earlier SQL
samples did not measure the whole click path. An isolated release-mode Flutter
browser trace of the real bell, backed by synthetic local Supabase data with
111 occasions, 445 authorized scopes and 124 deliveries, found one open request
and no preparing polls or context/badge wait at the click. First ready content
painted after 146.3 ms, including a 113.7 ms loopback TTFB and about 1 ms JSON
decode. A rapid navigation replay painted after 90.2 ms. These are local browser
observations, not production network or production p95 measurements.

The local fixture selects legacy v218 context because canonical activation
metadata is empty in main; the production tenant selects v219. Occasion-admin
bell interaction is covered, but a full canonical unit-admin journey is not
claimed. A proposed local v218 adapter was removed before measurement.

On production data a transaction-local function profile found two scope reads,
174 canonical bank-admin evaluations, and three identical display fingerprints
in one ready open. The correction materializes current user bank-account
permissions once inside each SQL statement, preserves the canonical bank-admin
predicate, organization-linked account requirement and connection aliases, and
materializes the payload fingerprint once. No permission result crosses request
or SQL statement snapshot boundaries. No client prefetch or permission cache was
introduced. Temporary session-local candidates, each rolled back, returned the
same 30 item JSON objects: old 262.8/215.3/214.4 ms versus new
126.0/121.5/119.9 ms. Timezone catalogue validation alone measured 54.0 ms and is
unchanged. The 50 ms design goal is not claimed.

The browser also proved that reopening showed retained rows at 33.3 ms before
the new authorized response, with the updated synthetic title painted at
107.4 ms. The controller now clears old rows before a fresh open, so that old
content is never mistaken for an authorized fast result. Its new regression
failed on the old implementation, then passed. An existing bell fixture was
updated from the obsolete badge RPC to the current prepared badge contract.

Validation: 51 Flutter tests, targeted Dart analysis, 38 SQL files including
source parity, 1560 canonical access equivalence cases with shared/demo/foreign
bank aliases, and five migration/protocol tests passed. The wide-scope open
measured 32.5 ms locally. Restoring only the old payload made the fingerprint
regression fail (three computations instead of one); the corrected source
passes. Earlier sealed migrations remain unchanged; forward 213000 owns this
delta. Final local CI, post-change browser and production release observations
are recorded separately when available.
