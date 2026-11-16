# Festapp Tickets for WordPress

The submission receipt captured on 2026-11-14 records **festappnet**, version
**1.0.3**, provisional slug **festapp-tickets**, automatic scan **Pass** and
manual review **Awaiting Review** at that time. It does not attest a later
review decision, public listing or assigned SVN repository.
The shared implementation and distinct service origins were disclosed in the
submission. [Submission receipt](evidence/global-submission-20261114.json).

The international plugin uses the same canonical `shared/` PHP, Gutenberg,
CSS and translation sources as vstupenky.online. `products.json` supplies the
brand, namespace, block and shortcode names, service origin, version and
distribution text. Change shared behavior in the templates, then generate
both products for any shared release. Never edit generated plugin files.

## Artifact identity after source consolidation

The dated receipts below preserve the exact submitted ZIP and its SHA-256.
The canonical shared templates have since gained managed cookie-choice import.
A package generated from current main therefore needs its own current source,
artifact and verification records, even when its version label matches the
historical candidate. Use the current release gates in [SUBMISSION.md](SUBMISSION.md);
the dated test results below attest the captured artifact only.

## Prepare the international package

Run from `integrations/wordpress`:

```sh
python3 scripts/package.py --product festapp-tickets
python3 scripts/stage-submission.py --product festapp-tickets
```

The installable archive is `dist/festapp-tickets-1.0.3.zip`; its SHA-256 is in
the adjacent `.sha256` file. The offline directory proposal is
`dist/festapp-tickets-wordpress-org-draft/`, with matching trunk/tag sources
and the existing international catalog artwork. These commands do not submit
or publish the plugin. Catalog assets have historical verification only until
checked again against the candidate. `stage-submission.py` prepares files;
it does not confer a release seal or WordPress.org approval.

## Install and use

1. On WordPress 6.6 or newer with PHP 7.4.33 or newer, open **Plugins > Add New > Upload Plugin**, select the ZIP, install it and activate **Festapp Tickets**.
2. Open **Settings > Festapp Tickets** or select **Get started** in the plugin list.
3. Create your event and save a public form in your [Festapp Tickets account](https://tickets.festapp.net/login). Copy that form's public URL.
4. Add the **Festapp Tickets** block to a page, paste the URL, preview the page on desktop and mobile, then publish it.

For the classic editor or another shortcode-compatible editor:

```text
[festapp_tickets url="https://tickets.festapp.net/form/saved-slug" title="Tickets for our event" measurement="host"]
```

Replace `saved-slug` with the saved form's actual slug. The plugin accepts only
public form URLs on `https://tickets.festapp.net`, without extra parameters or
fragments. It provides automatic height, optional fixed height, a standalone
fallback link and multiple forms per page. The saved form owns appearance;
WordPress stores no organizer credentials or customer orders. The English
interface also includes Czech translations. Both branded plugins can coexist.

`measurement="host"` selects the website dataLayer and requires the website's
own tags and consent handling. It does not enable tracking or grant consent.
`measurement="unit"` selects Festapp's configured Unit runtime; missing values
retain Unit mode. Consult the bundled readme for the full service disclosure.

## Verification and publication boundary

Publication was authorized on 2026-11-14 under the existing `festappnet`
publisher. Plugin Check 2.1.0 found zero errors on both supported WordPress/PHP
fixtures, with the known bundled-translation warning. PHP syntax and WPCS
checks passed; see [release checks](evidence/global-release-checks-20261114.json).
The name search found an unrelated FEST App service offering a WordPress
integration. The owner reviewed it and confirmed that our name and product
are different. A shared word alone does not establish confusing similarity;
this finding does not block submission of Festapp Tickets. The shared source
and separate service origins will be disclosed to the directory reviewers.
No separate review-team email is required. Browser observations are in
[the preflight record](evidence/global-publication-preflight-20261114.json);
submission and publication states require their own external receipts.

The prepared 1.0.3 archive passed 60 coexistence/security assertions on each
of WordPress 6.6/PHP 7.4.33 and WordPress 7.1.3/PHP 8.5.12, plus real PHP/editor
translation loading, independent activation and the production-origin gate.
The editor default tests, minimum-version metadata tests and ZIP/source/stage
integrity checks also passed. Exact artifact and results:
[preparation receipt](evidence/global-preparation-20261114.json).

Use the existing `tests/dual-products.php`, `tests/dual-translations.php` and
`tests/dual-lifecycle.php` against installed ZIPs in the isolated WordPress
fixture described in [README.md](README.md). These exercise the actual CMS,
separate product identities, block/shortcode rendering, origin validation,
translations and activation. `tests/measurement-defaults.test.mjs` covers the
editor's explicit measurement default for both products.

Local CMS checks do not establish a live organizer's payment setup, payment
gateway compatibility or a production purchase. WordPress.org review,
hosting and public release remain separate operations. The earlier
Czech-only submission and its approval do not cover this international plugin.
