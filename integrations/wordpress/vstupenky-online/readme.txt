=== vstupenky.online ===
Contributors: festappnet
Tags: tickets, events, registration, gutenberg, shortcode
Requires at least: 6.6
Tested up to: 7.1
Requires PHP: 7.4.33
Stable tag: 1.0.9
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Sell tickets and collect event registrations with vstupenky.online forms. Add a Gutenberg block or shortcode to your WordPress site.

== Description ==

Sell event tickets and collect registrations directly on your WordPress website with an embedded vstupenky.online form. Add the Gutenberg block to a page or post, or use a shortcode with your saved public form URL.

Use the same workflow for balls, concerts, theatre performances, festivals, workshops and conferences. Create the event and its ticket or registration form in vstupenky.online, then display that form on your own website.

The free plugin connects WordPress to the Czech vstupenky.online service. An organizer account and a saved, published form are required. No WooCommerce or service API keys are needed. The external service has its own organizer pricing and terms; see https://vstupenky.online/ for its current offer. WordPress does not process service fees.

= Features =

* Ticket sales and event registration forms on WordPress pages and posts.
* A native Gutenberg block and a shortcode using the same saved form URL.
* Responsive embeds with automatic height or a fixed height you choose.
* Multiple forms on one page and a standalone link to open each form separately.
* A descriptive form title for screen readers.
* Website appearance controlled centrally in the saved form settings.
* A Czech interface for plugin setup and the block editor.
* Optional measurement integration for websites with their own GTM and consent banner.

= Get started in three steps =

1. Create your event in vstupenky.online and save a public ticket or registration form.
2. Copy its public URL, add the vstupenky.online block to WordPress and paste the URL. A shortcode is available if you do not use the block editor.
3. Preview the form on desktop and mobile, then publish your page.

Local setup help is available under Settings > vstupenky.online and through the Get started link in the plugin list. You do not need to paste administration links or sign in to the service inside the WordPress editor.

= Tickets, registrations and seating plans =

The embedded form follows the event configuration in vstupenky.online, including ticket types, available capacity and any configured seating plan. Event management, order processing, payments, ticket delivery and admission remain in the external service.

The plugin does not implement a payment gateway. Payment methods depend on the organizer's configuration and the service. Verify the complete purchase flow for your event and browser, including any card gateway or bank-app handoff, before opening sales.

= Gutenberg block and shortcode =

Paste the exact saved public form URL on https://vstupenky.online. Query parameters, fragments, personal order links and administration URLs are not accepted.

Example:

    [vstupenky_online url="https://vstupenky.online/form/saved-slug" title="Tickets for our event" measurement="host"]

Fixed height:

    [vstupenky_online url="https://vstupenky.online/form/saved-slug" mode="fixed" height="800" measurement="host"]

= Appearance and mobile layout =

Automatic height follows the form content. Fixed and fallback height can be set between 240 and 4000 pixels. Both modes use the service helper; a standalone form link remains available if the helper is blocked.

To match your website, open the form appearance settings in vstupenky.online, choose Match website appearance and save the form. The setting applies to every embed on subsequent page loads without replacing the block or shortcode. WordPress cannot override it. The seating plan keeps its own appearance.

= Optional measurement =

New blocks and the shortcode examples use Website dataLayer, recommended for websites with their own GTM and consent banner. Existing blocks and shortcodes without a measurement setting retain the Festapp Unit runtime. Use measurement="unit" to select Unit mode; missing or invalid values also retain Unit mode.

The measurement setting selects a destination; it does not enable tracking or grant consent. Both modes require an approved website origin and enabled measurement in Festapp. Unit mode reads website Consent Mode only after the organizer enables Use consent from my website banner in Festapp and confirms that the banner covers the embedded form.

= Documentation and support =

Setup guide: https://vstupenky.online/napoveda/wordpress/
Organizer help: https://vstupenky.online/napoveda/
Service and organizer pricing: https://vstupenky.online/
Support: https://vstupenky.online/support/

= External service and privacy =

On a published page with a configured form, the visitor's browser connects to https://vstupenky.online to load /form/saved-slug?embed=1. Both height modes also load https://vstupenky.online/embed.js once per page. This connection shares the visitor's IP address, browser information and any referrer allowed by the site's policy. The visitor enters purchase data directly into the service iframe. The helper exchanges resize/viewport/scroll, optional bounded presentation/font settings and displayed ticket counts/prices with the form. In Unit measurement mode, customer contacts and transaction identifiers remain outside the host page. Explicitly selecting Website dataLayer forwards approved measurement events, including conversion email, phone and transaction identifiers, to page scripts. Payment instructions, authentication secrets and order submissions are never forwarded.

The service may use its configured backend, assets, storage and payment providers. Review its privacy information and the needs of your own website before publishing; this plugin does not claim that the service is cookie-free. The plugin installs no tracking tags; in Website dataLayer mode the website owns its tags and consent handling. Unit mode uses the configured Festapp runtime and requires the organizer's explicit consent-bridge setting before reading website Consent Mode. The external service has its own privacy practices, described in its privacy policy. Optional website appearance loads the website font URLs inside the service iframe. Activation, local help and editing do not fetch the remote form. WordPress stores the public URL and presentation attributes, not customer orders, organizer passwords or service API keys. No server-side HTTP request is made by the plugin.

Service: https://vstupenky.online/
Terms: https://vstupenky.online/terms/
Privacy: https://vstupenky.online/privacy/
Privacy choices: https://vstupenky.online/privacy/choices/
Support: https://vstupenky.online/support/
Contact: info@festapp.net

= Source =

All PHP, JavaScript and CSS sources ship unminified in this plugin. JavaScript uses WordPress-provided editor dependencies. No compilation or bundled React is required. The external /embed.js source and protocol are maintained by the service, independently of this plugin.

== Installation ==

1. In WordPress, open Plugins > Add New, search for vstupenky.online, click Install Now and activate the plugin. You can also upload the plugin ZIP manually.
2. Click Get started in the plugin list, or open Settings > vstupenky.online, and read the three setup steps and service/privacy disclosure.
3. Save a form in your organizer account, copy its public URL, add the block or shortcode and publish.
4. Preview the published page, including mobile layout and the standalone link.

== Frequently Asked Questions ==

= Is the plugin free? =
Yes. The WordPress plugin is free. The vstupenky.online service has separate organizer pricing and terms, available at https://vstupenky.online/. An organizer account is required.

= Do I need WooCommerce? =
No. The plugin embeds the public vstupenky.online form directly using its Gutenberg block or shortcode. No WooCommerce installation or service API keys are required.

= Can I sell tickets with assigned seats? =
Yes, when your event form includes a seating plan configured in vstupenky.online. The embedded form displays the service's seat selection and availability.

= Can I manage orders in WordPress? =
No. Sign in to vstupenky.online to manage events and orders.

= Does a visitor need a WordPress account? =
No. The public form runs in the service iframe. Event-specific requirements are controlled by the service.

= Why was my URL rejected? =
Use the exact saved public form URL on https://vstupenky.online. Other domains, personal links, fragments, query parameters and administration URLs are rejected. Development origins require explicit local WordPress configuration and cannot be supplied in block attributes.

= What if my site's security policy blocks embedding? =
Allow https://vstupenky.online in frame-src and, for the helper, script-src. Do not add an unverified iframe sandbox. Use fixed mode or the standalone link if necessary. Never automatically repeat a purchase after an uncertain result; check with the organizer first.

= What happens on deactivation or deletion? =
The plugin owns no tables, options or remote orders, and performs no remote writes on activation, deactivation or uninstall. Service orders remain. Deactivation can expose raw shortcode text; remove the block/shortcode or replace it with a normal public link.

= How do I transfer cookie choices from my website? =

In Festapp, open Organizer settings > Measurement > My websites. Save changes,
select your website and cookie banner, and explicitly confirm policy coverage.
Copy the resulting JSON into Configuration exported from Festapp in this
extension's settings, then enable the import. No internal IDs or revisions are
entered manually. The form checks current approval; local import acceptance
alone does not establish a working transfer. Only this extension's form-link
block/shortcode and fallback links participate. Manual links stay unchanged.
Cookie choice transfer does not preserve analytics visitor identity.

== Screenshots ==

1. Local onboarding and service disclosure.
2. Gutenberg block controls without remote administration.
3. Published form with a standalone fallback link.
4. Two forms on a mobile-width page (Chrome, not Safari).
5. Seat selection in the embedded form.

== Changelog ==

= 1.0.9 =
* Import the server-confirmed cookie choice configuration from Festapp. Only the extension’s own form links participate; manual links remain unchanged.

== Upgrade Notice ==

= 1.0.9 =
Configure and confirm your website in Festapp, then explicitly import its JSON export. Transfer stays off until enabled. No manual scope IDs or revisions are required.
