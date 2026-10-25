# Help action onboarding, 2026-10-25

Help links carry an allowlisted section intent, never an occasion ID or arbitrary
return URL. `HelpDestination` owns that contract for both documentation locales.
Registration and Google continuation retain it through the existing login routes.
Password registration still requires the ordinary credentials/code exchange.

After login, the existing permission-filtered event chooser offers creation.
It reuses the registered user's organizer, or the normal organizer-creation dialog
when none exists and the tenant permits creation. Multiple organizers require an
explicit choice. The selected unit is reloaded and `occasions.create` comes from
the canonical backend capability projection. Drafts and event creation use the
existing unit dashboard and setup wizard. Saved drafts can be resumed after
cancellation or physical reload. Help continuation suppresses only the wizard's
generic completion navigation, then enters the originally requested section
through the normal administration boundary. Scanner settings use the actual
webclient and its independently authorized scanner session.

A real walkthrough exposed an existing autosave lifecycle bug: the communication
preview requested a flush while its parent was building. Notifying the widget
tree before installing cleanup could strand `_pending` and prevent subsequent
changes from being saved. Flush now skips clean drafts, starts outside the build
stack, and clears pending state in `finally`. Event finalization succeeded after
this correction; the SQL review requirement was preserved.

## Evidence and limits

Owned isolated backend: `festapp-wizard-help-20261025`, API 56821, DB 56822.
Owned same-origin HTTP preview: 57982. The former preview redirected login to the
old production build; it now serves the current local Flutter and webclient app.
Interactive evidence is in ignored `.private/help-onboarding-20261025/`.

- Real UI signup from `/login?redirect=/help-action/forms`; signup and subsequent
  login URLs retained exactly the same intent.
- Canonical register Edge function created a real synthetic Auth user and its
  `My events` organizer with zero occasions. Only email delivery was simulated:
  a narrowly scoped local fixture accepted that synthetic queued message and
  read its encrypted prepared message into a private local mailbox. No actual
  email, OAuth provider, bank API or payment was invoked.
- Signed in through the actual credential exchange and Auth token endpoint.
- Created a wizard draft, left it, physically reloaded the login help URL, chose
  the saved draft and resumed its actual saved question.
- Configured a synthetic local bank account without any API token, returned to
  the wizard, confirmed review, finalized the event through the canonical RPC.
- Result: `/x3rvvkym/reservations/forms/help_onboarding_prvni_akce_2026/editor`,
  the expected event title and Forms tab selected. Screenshot
  `new-account-final-forms.png` and interaction steps 001-138 record this.
- Existing signed-in account: selected the new event from a scanner-settings help
  link and reached the real webclient's Scanner display settings, including the
  Back to tickets link and authenticated settings controls (steps 139-150).
- Separate legacy-style local account without any organizer: logged in through a
  products help link, created its organizer in the normal dialog and reached the
  first event wizard. Leaving retained the help intent (steps 151-163).
- Synced authoritative main `e89037ef0` before publication; its setup appearance
  and preview changes merged without conflicts.
- Targeted Flutter checks after merge: 16 tests passed (destination contract, post-login
  routing, communication/email template widgets and setup preview performance). Hosting login-return
  checks: 2 passed. Debug Flutter web build succeeded.

These are local integration results, not evidence of a production deployment or
real email/OAuth delivery. Production publication still requires the repository's
independent review and normal single-tenant release gates.

## Web sign-in correction

The public entry now uses `/events?help=<allowlisted-intent>` and the same
`LoginModal` as the web header. Previously shared `/login?redirect=/help-action/...`
links redirect to that web entry. Signed-out visitors see the actual catalogue
and standard web login/registration UI; Flutter is not loaded until authentication
has completed. The existing modal preserves the help URL across registration and
password login. Google return sanitization allows exactly the same validated
help URL, including through account/profile proof, without permitting arbitrary
return queries or external URLs.

After authentication, the standard Flutter runtime handoff opens
`/flutter?redirect=<encoded login-with-help-intent>`. The shell restores the login
intent before bootstrap and the authenticated administration flow chooses an
event or starts/resumes the existing first-event wizard. No second authentication
implementation was introduced.

Real headless UI follow-up against the same local backend:

- Opened the exact reported orders URL in a fresh isolated browser. Result:
  `/events?help=orders`, normal web login dialog, no `flt-glass-pane`.
- Closed and reopened the dialog with the ordinary header sign-in button.
- Signed in via the standard web form, selected `Slavnostní ples U Lípy`, and
  reached `/b67pnakx/reservations/orders/current` with Orders selected.
- Evidence screenshot: `.private/help-web-login-20261025/web-login.png`.
- A separate synthetic account with zero events signed in through the web form,
  reached the no-event chooser and started the existing first-event wizard.
- Targeted web authentication/navigation tests passed (15), hosting/help/SEO/CSP
  checks passed (36, including nested-shell regression), and the webclient
  production build succeeded. Four old hosting assertions failed unchanged on
  the previous commit as well; they now match the existing public-origin
  referrer policy and accept no-store together with no-transform. Sensitive
  callback no-referrer assertions remain unchanged.
- No Dart source changed in this follow-up.
