# Festapp auth navigation fixes - 2026-10-02

Target: https://live.festapp.net, prod/festapp only.

Signing out from the unit editor header closed its menu, then used that menu's
BuildContext after awaiting logout. The unmounted context prevented navigation;
when it remained mounted, navigation incorrectly depended on a selected unit.
The header now captures the root router before opening the menu. Both header
and profile logout send web users to the origin root after session cleanup,
without preserving stale editor state or using a disposed context.

A consumed/reloaded /app/google-auth URL had no matching Flutter route. Startup
now routes that path to login even without handoff parameters, and AutoRoute has
an explicit redirect. The callback namespace is reserved and skips unrelated
occasion initialization. Original handoffs still enter the existing verifier
and Google continuation panel; invalid/expired attempts can show retry UI.

PR: https://github.com/festappnet/festapp/pull/196
Main: 03e659b5cd6e84bf9f19fec69ece7d7cd3f6d514
Version: 0.20.42+526
Production SHA: 4c814fca4dfeae746ab0ec1994a4925c5af0ec2c
Deployment: https://github.com/festappnet/festapp/actions/runs/36977048687

Both callback regressions failed before the fix. Nineteen targeted startup,
router, logout and post-login tests passed in the clean checkout and the original
workspace. Targeted Dart analysis reports no errors; its existing warning/info
remain. The original workspace's unrelated changes were preserved.

Production deployment completed successfully. Three consecutive independent
deployment probes confirmed 0.20.42+526. In an isolated browser, the bare callback
changed from a blank page on version 525 to the login screen on version 526.
A synthetic expired handoff displayed the retry message and Google button,
reached /login, removed callback query parameters and reported app readiness.
Production includes the current main, including ticket preview/fonts, A4 format
and image-upload fixes. No open pull requests remained at final upstream check.
An authenticated production logout was not exercised against a real account
solely for testing.
