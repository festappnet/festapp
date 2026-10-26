# A24 web component and real-form acceptance

2026-10-21, isolated local headless Chrome session `stripe-a24`, explicit empty CLI configuration on every invocation. Synthetic local backend only. No order submission or payment; no Flutter process.

## Component coverage

Actual `OrderResult` and `renderOrderOverview` through `automation/stripe/build-component-preview.mjs`: all 12 states (preparing/open/pending/declined/paid/expired/action_required/refund_pending/partially_refunded/refunded/disputed/unknown), each at 320px with German, dark theme and 200% text. All 24 render combinations stayed within the 320px viewport. The overview refresh control now inherits 32px text and measures 47px high (44px minimum), rather than browser-default 21px. Keyboard focus is visible and on-screen. Axe WCAG2 A/AA: zero violations on sampled overview.

## Actual public form

Local `/form/stripe-e2e-form`, synthetic 156.78 CZK admission and answers. Keyboard radio selection, Continue by Enter, review and Escape only. Tested at 320 x 800, dark theme, German review and 200% root font.

Fixed concrete findings:
- Email/name/surname controls now expose their actual connected labels, including distinct repeated-ticket input IDs.
- Review exposes a named dialog, moves focus to localized Close, contains Tab/Shift+Tab in the top-level modal and returns focus to Continue on Escape.
- Review body is a keyboard-focusable scroll region; Tab reaches body and final order button, then wraps to Close. The final button was never activated.
- Long synthetic email, product/currency and translated content wrap without clipping; no descendant exceeds the viewport.
- Missing German review/title/close translations were filled by the primary agent in canonical/public catalogs.

Final screenshot: [320px actual review, dark/German/200% text](js-a24-real-form-dark-large.png). All answers and selected product remained after closing the review. Horizontal document width remained 320px.

Final axe WCAG2 A/AA: zero violations; contrast check had two incomplete results due to layered sheet geometry. Computed opaque foreground/background checks: review heading white on rgb(40,40,42), 14.71:1; submit black on rgb(165,182,218), 10.30:1. Screenshot visually confirms unobscured focused scroll region and reachable fixed submit control.

## Regression validation

`pnpm --dir web_client exec node --test tests/forms/payment_accessibility.test.js tests/forms/order_overview.test.js tests/forms/price_change_refresh.test.js`

14 passed. Tests cover connected labels, named dialog, focus entry/wrap/return, scroll focusability, no submission during Escape, overview behavior and payment refresh preservation. Browser session closed.

This closes the requested JS component and actual-form keyboard/mobile/theme subset. It does not claim native-device, assistive screen-reader, every-tenant or Flutter coverage.
