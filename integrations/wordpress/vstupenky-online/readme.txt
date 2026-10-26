=== vstupenky.online ===
Contributors: festappnet
Tags: tickets, events, registration, embed, forms
Requires at least: 6.6.4
Tested up to: 7.1
Requires PHP: 7.4.33
Stable tag: 1.0.1
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Embed a saved public vstupenky.online ticket form with a block or shortcode. Manage your event and orders in the external service.

== Description ==

This is a frontend integration with the Czech vstupenky.online service. You need an organizer account and a saved, published form in that service. The plugin provides one Gutenberg block, one shortcode and local onboarding under Settings > vstupenky.online. No WooCommerce or API keys are required. The plugin is free. The external service has its own organizer pricing and terms; see https://vstupenky.online/pro-poradatele for its current offer. WordPress does not process service fees.

Create and save a form in vstupenky.online. Copy its public URL, then insert the vstupenky.online block and paste the URL. Publish the page. Use only https://vstupenky.online/form/saved-slug, without query parameters or fragments. The editor shows local controls, never a remote administration screen.

Shortcode:
[vstupenky_online url="https://vstupenky.online/form/saved-slug" title="Tickets for our event"]

Fixed height:
[vstupenky_online url="https://vstupenky.online/form/saved-slug" mode="fixed" height="800"]

Website appearance (optional):
[vstupenky_online url="https://vstupenky.online/form/saved-slug" inherit_style="true"]

"Use the WordPress theme instead of the app appearance" is enabled by default. It overrides the app font, background and colors only for this embedding. Disable it in the block or set inherit_style="false" to use the appearance configured in the app. Custom font-face URLs are passed to the form; their servers must allow cross-origin font loading. Unreadable stylesheets or blocked fonts retain the supplied font-family fallback. The seat map keeps the service appearance. This option requires /embed.js even with fixed height.

Height is limited to 240-4000 pixels. Automatic mode uses the existing service helper. A standalone form link remains available without the helper. Multiple forms can appear on one page. Event settings, inventory, order processing, payments, ticket delivery and admission remain owned by vstupenky.online. The plugin does not implement any payment gateway. Embedded payment methods and browser compatibility require verification for the particular event; card gateways and bank-app handoffs are not guaranteed.

= External service and privacy =

On a published page with a configured form, the visitor's browser connects to https://vstupenky.online to load /form/<saved-slug>?embed=1. Automatic height or website appearance also loads https://vstupenky.online/embed.js once per page. This connection shares the visitor's IP address, browser information and any referrer allowed by the site's policy. The visitor enters purchase data directly into the service iframe. The helper exchanges resize/viewport/scroll, optional bounded presentation/font settings and displayed ticket counts/prices with the form. Customer contact details, order identifiers, payment instructions, authentication secrets and order submissions are not passed to WordPress.

The service may use its configured backend, assets, storage and payment providers. Review its privacy information and the needs of your own website before publishing; this plugin does not claim that the service is cookie-free. The WordPress plugin does not add analytics or tracking pixels. The external service has its own privacy practices, described in its privacy policy. Optional website appearance loads the website font URLs inside the service iframe. Activation, local help and editing do not fetch the remote form. WordPress stores the public URL and presentation attributes, not customer orders, organizer passwords or service API keys. No server-side HTTP request is made by the plugin.

Service: https://vstupenky.online/
Terms: https://vstupenky.online/terms/
Privacy: https://vstupenky.online/privacy/
Privacy choices: https://vstupenky.online/privacy/choices/
Support: https://vstupenky.online/support/
Contact: info@festapp.net

= Source =

All PHP, JavaScript and CSS sources ship unminified in this plugin. JavaScript uses WordPress-provided editor dependencies. No compilation or bundled React is required. The external /embed.js source and protocol are maintained by the service, independently of this plugin.

== Installation ==

1. In Plugins > Add New > Upload Plugin, upload vstupenky-online-1.0.1.zip and activate it.
2. Click Get started in the plugin list, or open Settings > vstupenky.online, and read the three setup steps and service/privacy disclosure.
3. Save a form in your organizer account, copy its public URL, add the block or shortcode and publish.
4. Preview the published page, including mobile layout and the standalone link.

== Frequently Asked Questions ==

= Can I manage orders in WordPress? =
No. Sign in to vstupenky.online to manage events and orders.

= Does a visitor need a WordPress account? =
No. The public form runs in the service iframe. Event-specific requirements are controlled by the service.

= Why was my URL rejected? =
Use the exact saved public form URL on https://vstupenky.online. Other domains, personal links, fragments, query parameters and administration URLs are rejected. Development origins require explicit local WordPress configuration and cannot be supplied in block attributes.

= What if my site's security policy blocks embedding? =
Allow https://vstupenky.online in frame-src and, for automatic height or website appearance, script-src. Do not add an unverified iframe sandbox. Use fixed mode or the standalone link if necessary. Never automatically repeat a purchase after an uncertain result; check with the organizer first.

= What happens on deactivation or deletion? =
The plugin owns no tables, options or remote orders, and performs no remote writes on activation, deactivation or uninstall. Service orders remain. Deactivation can expose raw shortcode text; remove the block/shortcode or replace it with a normal public link.

== Screenshots ==

1. Local onboarding and service disclosure.
2. Gutenberg block controls without remote administration.
3. Published form with a standalone fallback link.
4. Two forms on a mobile-width page (Chrome, not Safari).
5. Seat selection in the embedded form.

== Changelog ==

= 1.0.1 =
* Clearly identify the WordPress appearance option as a local override of the app appearance.

== Upgrade Notice ==

= 1.0.1 =
No database migration. Existing block and shortcode settings are retained.
