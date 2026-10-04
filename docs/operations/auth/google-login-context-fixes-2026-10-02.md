# Festapp Google login context fixes - 2026-10-02

Target: https://live.festapp.net, prod/festapp only.

Reported symptoms: account proof email was empty, the ordinary login form
flashed before admin navigation, and user admin context was incomplete. Google
unlink was also ordered before logout in the profile.

The proof panel now prefills the provider email on mount and subsequent state
changes, preserving manual edits. Authenticated continuation remains busy through
navigation. Google admin navigation replaces the login stack; successful
navigation resets continuation state and navigation failures offer retry.

External session finalization now forces authenticated app-config loading and
checks its user identity before publishing success. Previously the optional
post-login refresh could fail on missing occasion context, be logged and swallowed,
and finish without requesting app config. A mocked real SDK-to-service regression
reproduced that exact missing RPC before the fix. It now checks the installed
Bearer token and loaded user, organization and two units.

Profile action order: logout, change password, Google link/unlink, delete account.

PR: https://github.com/festappnet/festapp/pull/200
Main: fea89efd2b9884f38ed5c457659e7d4f9142ddc8
Production: 67f909384155a0ce54dfad7c49b54623aa61bbb4
Version: 0.20.46+530
Deployment: https://github.com/festappnet/festapp/actions/runs/36981569322

Verification: 22 targeted Flutter tests passed. The visual/interaction panel matrix
covers 360, 390, 768 and 1440 widths, Czech/English, both themes, proof and loading
states, email edits, and held navigation completion. Panel matrix passed again
after adding initial-mount and manual-email-preservation assertions. Targeted
Dart analysis has informational diagnostics only, without errors or warnings.
Tenant drift passed against current main, including PRs 197-199 ticket changes.

Production deployment completed successfully. Three consecutive independent
production probes confirmed coherent version 0.20.46+530. No real production account linking or
logout was performed solely for automated validation. User workspace changes
were preserved; only the scoped patch and new regression test were applied back.
