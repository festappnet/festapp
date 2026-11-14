=== Festapp Tickets ===
Contributors: festappnet
Tags: tickets, events, registration, gutenberg, shortcode
Requires at least: 6.6
Tested up to: 7.1
Requires PHP: 7.4.33
Stable tag: 1.0.3
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Sell tickets and collect event registrations with Festapp Tickets forms. Add a Gutenberg block or shortcode to your WordPress site.

== Description ==

Sell event tickets and collect registrations directly on your WordPress website with an embedded Festapp Tickets form. Add the Gutenberg block to a page or post, or use a shortcode with your saved public form URL.

Use the same workflow for balls, concerts, theatre performances, festivals, workshops and conferences. Create the event and its ticket or registration form in Festapp Tickets, then display that form on your own website.

The free plugin connects WordPress to the international Festapp Tickets service. An organizer account and a saved, published form are required. No WooCommerce or service API keys are needed. The external service has its own organizer pricing and terms; see https://tickets.festapp.net/ for its current offer. WordPress does not process service fees.

= Features =

* Ticket sales and event registration forms on WordPress pages and posts.
* A native Gutenberg block and a shortcode using the same saved form URL.
* Responsive embeds with automatic height or a fixed height you choose.
* Multiple forms on one page and a standalone link to open each form separately.
* A descriptive form title for screen readers.
* Website appearance controlled centrally in the saved form settings.
* A Czech interface for plugin setup and the block editor.
* Optional measurement integration for websites with their own GTM and consent banner.
* Optional transfer of the website's saved Complianz, Cookiebot or CookieConsent v3 choice to forms opened in a new tab.
* A form link block and shortcode that open the form in a new tab.

= Get started in three steps =

1. Create your event in Festapp Tickets and save a public ticket or registration form.
2. Copy its public URL, add the Festapp Tickets block to WordPress and paste the URL. A shortcode is available if you do not use the block editor.
3. Preview the form on desktop and mobile, then publish your page.

Local setup help is available under Settings > Festapp Tickets and through the Get started link in the plugin list. You do not need to paste administration links or sign in to the service inside the WordPress editor.

= Tickets, registrations and seating plans =

The embedded form follows the event configuration in Festapp Tickets, including ticket types, available capacity and any configured seating plan. Event management, order processing, payments, ticket delivery and admission remain in the external service.

The plugin does not implement a payment gateway. Payment methods depend on the organizer's configuration and the service. Verify the complete purchase flow for your event and browser, including any card gateway or bank-app handoff, before opening sales.

= Gutenberg block and shortcode =

Paste the exact saved public form URL on https://tickets.festapp.net. Query parameters, fragments, personal order links and administration URLs are not accepted.

Example:

    [festapp_tickets url="https://tickets.festapp.net/form/saved-slug" title="Tickets for our event" measurement="host"]

Fixed height:

    [festapp_tickets url="https://tickets.festapp.net/form/saved-slug" mode="fixed" height="800" measurement="host"]

= Appearance and mobile layout =

Automatic height follows the form content. Fixed and fallback height can be set between 240 and 4000 pixels. Both modes use the service helper; a standalone form link remains available if the helper is blocked.

To match your website, open the form appearance settings in Festapp Tickets, choose Match website appearance and save the form. The setting applies to every embed on subsequent page loads without replacing the block or shortcode. WordPress cannot override it. The seating plan keeps its own appearance.

= Optional measurement =

New blocks and the shortcode examples use Website dataLayer, recommended for websites with their own GTM and consent banner. Existing blocks and shortcodes without a measurement setting retain the Festapp Unit runtime. Use measurement="unit" to select Unit mode; missing or invalid values also retain Unit mode.

The measurement setting selects a destination; it does not enable tracking or grant consent. Both modes require an approved website origin and enabled measurement in Festapp. Unit mode reads website Consent Mode only after the organizer enables Use consent from my website banner in Festapp and confirms that the banner covers the embedded form.

= Cookie choice in forms opened in a new tab =

A form opened in a new tab normally shows its own cookie notice. Optionally, it can take over the choice a visitor already saved in the website's Complianz, Cookiebot or CookieConsent v3 banner, including a refusal. Withdrawal on the website also reaches the open form. Configure it under Settings > Festapp Tickets. It is off by default.

The organizer must also enable Use consent from my website banner in Festapp Tickets and have this website's HTTPS origin approved under My websites. Enter the organization ID, Unit ID and the form's consent revision, and the banner's policy ID, CBID and validity, or revision. Saving these values asserts that the banner's archived notice covers the form; they are never generated or updated automatically. When anything does not match, nothing is transferred and the form shows its own notice. Detected values from active Complianz and Cookiebot plugins are only suggestions until you save them.

When enabled, https://tickets.festapp.net/embed.js loads on every public page, and links to public forms that open in a new tab in content, widgets and menus are marked. Marked links no longer use the noopener and noreferrer link relations, so the form receives the website origin as referrer and can talk to the website tab. Links with download or referrerpolicy are not changed. The form link block and the link shortcode create marked links:

    [festapp_tickets_link url="https://tickets.festapp.net/form/saved-slug" text="Buy tickets"]

= Documentation and support =

Setup help is available under Settings > Festapp Tickets. Support: https://tickets.festapp.net/support/

= External service and privacy =

On a published page with a configured form, the visitor's browser connects to https://tickets.festapp.net to load /form/saved-slug?embed=1. Both height modes also load https://tickets.festapp.net/embed.js once per page. With the optional cookie choice transfer enabled, every public page loads it, and a form opened from a marked link receives the website origin as referrer and exchanges the saved analytics and marketing choice with the website tab. No choice is stored in URLs or new cookies by WordPress. This connection shares the visitor's IP address, browser information and any referrer allowed by the site's policy. The visitor enters purchase data directly into the service iframe. The helper exchanges resize/viewport/scroll, optional bounded presentation/font settings and displayed ticket counts/prices with the form. In Unit measurement mode, customer contacts and transaction identifiers remain outside the host page. Explicitly selecting Website dataLayer forwards approved measurement events, including conversion email, phone and transaction identifiers, to page scripts. Payment instructions, authentication secrets and order submissions are never forwarded.

The service may use its configured backend, assets, storage and payment providers. Review its privacy information and the needs of your own website before publishing; this plugin does not claim that the service is cookie-free. The plugin installs no tracking tags; in Website dataLayer mode the website owns its tags and consent handling. Unit mode uses the configured Festapp runtime and requires the organizer's explicit consent-bridge setting before reading website Consent Mode. The external service has its own privacy practices, described in its privacy policy. Optional website appearance loads the website font URLs inside the service iframe. Activation, local help and editing do not fetch the remote form. WordPress stores the public URL and presentation attributes, and optionally the cookie choice transfer settings in one option, not customer orders, organizer passwords or service API keys. No server-side HTTP request is made by the plugin.

Service: https://tickets.festapp.net/
Terms: https://tickets.festapp.net/terms/
Privacy: https://tickets.festapp.net/privacy/
Privacy choices: https://tickets.festapp.net/privacy/choices/
Support: https://tickets.festapp.net/support/
Contact: info@festapp.net

= Source =

All PHP, JavaScript and CSS sources ship unminified in this plugin. JavaScript uses WordPress-provided editor dependencies. No compilation or bundled React is required. The external /embed.js source and protocol are maintained by the service, independently of this plugin.

== Installation ==

1. In WordPress, open Plugins > Add New, search for Festapp Tickets, click Install Now and activate the plugin. You can also upload the plugin ZIP manually.
2. Click Get started in the plugin list, or open Settings > Festapp Tickets, and read the three setup steps and service/privacy disclosure.
3. Save a form in your organizer account, copy its public URL, add the block or shortcode and publish.
4. Preview the published page, including mobile layout and the standalone link.

== Frequently Asked Questions ==

= Is the plugin free? =
Yes. The WordPress plugin is free. The Festapp Tickets service has separate organizer pricing and terms, available at https://tickets.festapp.net/. An organizer account is required.

= Do I need WooCommerce? =
No. The plugin embeds the public Festapp Tickets form directly using its Gutenberg block or shortcode. No WooCommerce installation or service API keys are required.

= Can I sell tickets with assigned seats? =
Yes, when your event form includes a seating plan configured in Festapp Tickets. The embedded form displays the service's seat selection and availability.

= Can I manage orders in WordPress? =
No. Sign in to Festapp Tickets to manage events and orders.

= Does a visitor need a WordPress account? =
No. The public form runs in the service iframe. Event-specific requirements are controlled by the service.

= Why was my URL rejected? =
Use the exact saved public form URL on https://tickets.festapp.net. Other domains, personal links, fragments, query parameters and administration URLs are rejected. Development origins require explicit local WordPress configuration and cannot be supplied in block attributes.

= What if my site's security policy blocks embedding? =
Allow https://tickets.festapp.net in frame-src and, for the helper, script-src. Do not add an unverified iframe sandbox. Use fixed mode or the standalone link if necessary. Never automatically repeat a purchase after an uncertain result; check with the organizer first.

= What happens on deactivation or deletion? =
The plugin owns no tables or remote orders, and performs no remote writes on activation, deactivation or uninstall. Its only option, the optional cookie choice transfer settings, is deleted on uninstall. Service orders remain. Deactivation can expose raw shortcode text; remove the block/shortcode or replace it with a normal public link.

== Screenshots ==

1. Local onboarding and service disclosure.
2. Gutenberg block controls without remote administration.
3. Published form with a standalone fallback link.
4. Two forms on a mobile-width page (Chrome, not Safari).
5. Seat selection in the embedded form.

== Changelog ==

= 1.0.3 =
* Optionally take over the website's saved Complianz, Cookiebot or CookieConsent v3 choice in forms opened in a new tab; add a form link block and shortcode.

= 1.0.2 =
* Add an explicit measurement destination with conversion-sharing disclosure; retain Unit mode for existing embeds.

= 1.0.1 =
* Control embedded appearance only through the saved form setting; remove local overrides.

== Upgrade Notice ==

= 1.0.3 =
Optional cookie choice transfer to forms opened in a new tab, off by default. Existing embeds, links and measurement settings are unchanged until an administrator enables it.
