# Email order overview heading

- Source main: 4f74b6145e11075bd4299ad3a423f74d741698d4 (PR #327).
- Order symbol moved into Czech/English overview heading, standalone row removed.
- Deno orderSymbol_test.ts: 15 passed.
- Verified canonical hostname, runtime database and organization 3 before deployment.
- Deployed only canonical `_shared/orderOverview.ts`, after matching previous source digest, with runtime lock and retained backup in `/var/lib/festapp-rehearsal-evidence/email-overview-heading-20261006`.
- Installed SHA256: 4122286c3e55c553d232b229bce25e031c3995fd106a3038d0afd7980527f8ed.
- Edge runtime restarted and running; empty request returns expected 400 Invalid email request. No email sent as a verification action.
- Concurrent narrower-column web release 0.20.127+611 succeeded: https://github.com/festappnet/festapp/actions/runs/37502143816 ; public verification passed three consecutive probes.
