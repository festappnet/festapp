=== Festapp Tickets ===
Contributors: festappnet
Tags: tickets, events, registration, embed, forms
Requires at least: 6.6
Tested up to: 7.1
Requires PHP: 7.4.33
Stable tag: 1.0.0
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Embed a saved public Festapp Tickets ticket form with a block or shortcode. Manage your event and orders in the external service.

== Description ==

This is a frontend integration with the international Festapp Tickets service. You need an organizer account and a saved, published form in that service. The plugin provides one Gutenberg block, one shortcode and local onboarding under Settings > Festapp Tickets. No WooCommerce or API keys are required. The plugin is free. The external service has its own organizer pricing and terms; see https://tickets.festapp.net/ for its current offer. WordPress does not process service fees.

Create and save a form in Festapp Tickets. Copy its public URL, then insert the Festapp Tickets block and paste the URL. Publish the page. Use only https://tickets.festapp.net/form/saved-slug, without query parameters or fragments. The editor shows local controls, never a remote administration screen.

Shortcode:
[festapp_tickets url="https://tickets.festapp.net/form/saved-slug" title="Tickets for our event"]

Fixed height:
[festapp_tickets url="https://tickets.festapp.net/form/saved-slug" mode="fixed" height="800"]

Keep the form appearance for this embed:
[festapp_tickets url="https://tickets.festapp.net/form/saved-slug" inherit_style="false"]

Choose Match website appearance for each block, or set inherit_style="false" in its shortcode to keep the form appearance. Save and publish the page after changing it. The shared /embed.js helper loads in both height modes. Custom fonts must permit cross-origin loading. The seat map keeps its own appearance.

Height is limited to 240-4000 pixels. Automatic mode uses the existing service helper. A standalone form link remains available without the helper. Multiple forms can appear on one page. Event settings, inventory, order processing, payments, ticket delivery and admission remain owned by Festapp Tickets. The plugin does not implement any payment gateway. Embedded payment methods and browser compatibility require verification for the particular event; card gateways and bank-app handoffs are not guaranteed.

= External service and privacy =

On a published page with a configured form, the visitor's browser connects to https://tickets.festapp.net to load /form/<saved-slug>?embed=1. Both height modes also load https://tickets.festapp.net/embed.js once per page. This connection shares the visitor's IP address, browser information and any referrer allowed by the site's policy. The visitor enters purchase data directly into the service iframe. The helper exchanges resize/viewport/scroll, optional bounded presentation/font settings and displayed ticket counts/prices with the form. Customer contact details, order identifiers, payment instructions, authentication secrets and order submissions are not passed to WordPress.

The service may use its configured backend, assets, storage and payment providers. Review its privacy information and the needs of your own website before publishing; this plugin does not claim that the service is cookie-free. The WordPress plugin does not add analytics or tracking pixels. The external service has its own privacy practices, described in its privacy policy. Optional website appearance loads the website font URLs inside the service iframe. Activation, local help and editing do not fetch the remote form. WordPress stores the public URL and presentation attributes, not customer orders, organizer passwords or service API keys. No server-side HTTP request is made by the plugin.

Service: https://tickets.festapp.net/
Terms: https://tickets.festapp.net/terms/
Privacy: https://tickets.festapp.net/privacy/
Privacy choices: https://tickets.festapp.net/privacy/choices/
Support: https://tickets.festapp.net/support/
Contact: info@festapp.net

= Source =

All PHP, JavaScript and CSS sources ship unminified in this plugin. JavaScript uses WordPress-provided editor dependencies. No compilation or bundled React is required. The external /embed.js source and protocol are maintained by the service, independently of this plugin.

== Installation ==

1. In Plugins > Add New > Upload Plugin, upload festapp-tickets-1.0.0.zip and activate it.
2. Click Get started in the plugin list, or open Settings > Festapp Tickets, and read the three setup steps and service/privacy disclosure.
3. Save a form in your organizer account, copy its public URL, add the block or shortcode and publish.
4. Preview the published page, including mobile layout and the standalone link.

== Frequently Asked Questions ==

= Can I manage orders in WordPress? =
No. Sign in to Festapp Tickets to manage events and orders.

= Does a visitor need a WordPress account? =
No. The public form runs in the service iframe. Event-specific requirements are controlled by the service.

= Why was my URL rejected? =
Use the exact saved public form URL on https://tickets.festapp.net. Other domains, personal links, fragments, query parameters and administration URLs are rejected. Development origins require explicit local WordPress configuration and cannot be supplied in block attributes.

= What if my site's security policy blocks embedding? =
Allow https://tickets.festapp.net in frame-src and, for the helper, script-src. Do not add an unverified iframe sandbox. Use fixed mode or the standalone link if necessary. Never automatically repeat a purchase after an uncertain result; check with the organizer first.

= What happens on deactivation or deletion? =
The plugin owns no tables, options or remote orders, and performs no remote writes on activation, deactivation or uninstall. Service orders remain. Deactivation can expose raw shortcode text; remove the block/shortcode or replace it with a normal public link.

== Screenshots ==

1. Local onboarding and service disclosure.
2. Gutenberg block controls without remote administration.
3. Published form with a standalone fallback link.
4. Two forms on a mobile-width page (Chrome, not Safari).
5. Seat selection in the embedded form.

== Changelog ==

= 1.0.0 =
* Clearly identify the WordPress appearance option as a local override of the app appearance.

== Upgrade Notice ==

= 1.0.0 =
No database migration. Existing block and shortcode settings are retained.
