# Email domain suffixes

`iana-tlds.txt` is the complete, versioned IANA snapshot from
https://data.iana.org/TLD/tlds-alpha-by-domain.txt (root zone context:
https://www.iana.org/domains/root/db). Both clients derive their sets from it.
This checks only the final domain label, not the domain or mailbox existence.
Unknown suffixes require a field-specific, value-specific confirmation.

To update explicitly, download to a temporary file with `curl --fail`, inspect
its header and diff against the snapshot, then replace the snapshot and run
`node automation/generate_email_tlds.mjs`. Never redirect a download onto the
last good snapshot. Commit the reviewed snapshot and both generated files together.
`node automation/generate_email_tlds.mjs --check` verifies them offline; builds
and runtime do not fetch anything. The existing web startup CI script and
`pnpm --dir web_client test` both run this offline check. No manual additions to generated sets.

Contact syntax is checked separately by `EmailAddress` (Dart) and `isValidEmail`
(web), using the same `address-cases.json` conformance cases. Addresses must have
one mailbox, a dot-separated DNS domain, valid labels, and fit the 64-character
local part / 254-character total limits. ASCII mailbox names and punycode domains
are supported. Syntax validation does not prove mailbox existence or delivery.
Unknown but well-formed domain suffixes still use the explicit confirmation flow.
