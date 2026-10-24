<?php
/**
 * Local onboarding. No remote administration, settings or API keys.
 *
 * @package VstupenkyOnline
 */

namespace VstupenkyOnline;

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/** Register capability-protected help. */
function admin_menu() {
	add_options_page( 'vstupenky.online', 'vstupenky.online', 'manage_options', 'vstupenky-online', __NAMESPACE__ . '\admin_page' );
}

/**
 * Make the first step discoverable directly after activation.
 *
 * @param array $links Existing plugin actions.
 * @return array
 */
function plugin_action_links( $links ) {
	if ( current_user_can( 'manage_options' ) ) {
		array_unshift( $links, '<a href="' . esc_url( admin_url( 'options-general.php?page=vstupenky-online' ) ) . '">' . esc_html__( 'Get started', 'vstupenky-online' ) . '</a>' );
	}
	return $links;
}

/** Render help using native WordPress layout and controls. */
function admin_page() {
	if ( ! current_user_can( 'manage_options' ) ) {
		return;
	}
	?>
	<div class="wrap">
		<h1><?php esc_html_e( 'Tickets on your website', 'vstupenky-online' ); ?></h1>
		<p><?php esc_html_e( 'Embed a form from your vstupenky.online account. Manage events, orders and admission in the service.', 'vstupenky-online' ); ?></p>
		<div class="card">
		<h2><?php esc_html_e( '1. Prepare your form', 'vstupenky-online' ); ?></h2>
		<p><?php esc_html_e( 'Create an organizer account in vstupenky.online, use the sign-in details from its email, then create your event and save a public form. A WordPress login does not create a service account.', 'vstupenky-online' ); ?></p>
		<p><a class="button button-primary" href="https://vstupenky.online/login" target="_blank" rel="noopener noreferrer"><?php esc_html_e( 'Create an account or sign in', 'vstupenky-online' ); ?></a></p>
		<p><?php esc_html_e( 'Paid sales also require your payment and organizer details in the service.', 'vstupenky-online' ); ?></p>
		<ol>
			<li><?php esc_html_e( 'Sign in to vstupenky.online, open your event and save the form.', 'vstupenky-online' ); ?></li>
			<li><?php esc_html_e( 'Copy the public URL in the form https://vstupenky.online/form/saved-slug. Do not use a personal order link or administration URL.', 'vstupenky-online' ); ?></li>
		</ol>
		</div>
		<div class="card">
		<h2><?php esc_html_e( '2. Add the form to a page', 'vstupenky-online' ); ?></h2>
		<p><?php esc_html_e( 'Open a new or existing WordPress page. Use the block inserter (+), search for vstupenky.online and paste your public form URL into the block.', 'vstupenky-online' ); ?></p>
		<?php if ( current_user_can( 'edit_pages' ) ) : ?>
		<p><a class="button button-secondary" href="<?php echo esc_url( admin_url( 'post-new.php?post_type=page' ) ); ?>"><?php esc_html_e( 'Create a page', 'vstupenky-online' ); ?></a></p>
		<?php endif; ?>
		<p><?php esc_html_e( 'Automatic height and website styling are already enabled. Start with these defaults; change them only if your page needs it.', 'vstupenky-online' ); ?></p>
		</div>
		<div class="card">
		<h2><?php esc_html_e( '3. Preview and publish', 'vstupenky-online' ); ?></h2>
		<p><?php esc_html_e( 'The editor shows the block settings. Save the page and open its preview to see the real form, then publish when you are ready.', 'vstupenky-online' ); ?></p>
		<p><?php esc_html_e( 'Visitors buy tickets on your published page. Manage orders, payments and admission in your vstupenky.online account.', 'vstupenky-online' ); ?></p>
		</div>
		<details>
		<summary><?php esc_html_e( 'Shortcode, display options and service information', 'vstupenky-online' ); ?></summary>
		<h2><?php esc_html_e( 'Shortcode and height', 'vstupenky-online' ); ?></h2>
		<p><code>[vstupenky_online url="https://vstupenky.online/form/saved-slug" title="Tickets for our event"]</code></p>
		<p><code>[vstupenky_online url="https://vstupenky.online/form/saved-slug" mode="fixed" height="800"]</code></p>
		<p><?php esc_html_e( 'Automatic height loads the service helper. Fixed height (240-4000 px) scrolls within the form. The link below the form works without the helper. If your theme or security policy blocks embedding, visitors can open the form in a new tab.', 'vstupenky-online' ); ?></p>
		<p><?php esc_html_e( 'Match website style is enabled by default. Disable it in the block, or add inherit_style="false" to the shortcode. The form uses the website font family and colors; the seat map keeps its own appearance. This option loads the service helper even with fixed height. Custom fonts must permit cross-origin loading.', 'vstupenky-online' ); ?></p>
		<h2><?php esc_html_e( 'External service and privacy', 'vstupenky-online' ); ?></h2>
		<p><?php esc_html_e( 'The published form connects to vstupenky.online. The service receives the IP address and browser information; visitors enter purchase data directly into the service. Automatic height also loads /embed.js. The plugin does not copy orders or credentials into WordPress and adds no analytics. Review storage, cookies and consent requirements for the service and your website. Activation, this help page and the editor do not load the remote form.', 'vstupenky-online' ); ?></p>
		<p>
			<a href="https://vstupenky.online/" target="_blank" rel="noopener noreferrer"><?php esc_html_e( 'Open vstupenky.online', 'vstupenky-online' ); ?></a> |
			<a href="https://vstupenky.online/privacy/" target="_blank" rel="noopener noreferrer"><?php esc_html_e( 'Privacy policy', 'vstupenky-online' ); ?></a> |
			<a href="https://vstupenky.online/terms/" target="_blank" rel="noopener noreferrer"><?php esc_html_e( 'Service terms', 'vstupenky-online' ); ?></a> |
			<a href="https://vstupenky.online/support/" target="_blank" rel="noopener noreferrer"><?php esc_html_e( 'Support', 'vstupenky-online' ); ?></a>
		</p>
		<p><?php esc_html_e( 'If a purchase result is uncertain, check the order with the organizer before buying again. Payments and seat availability are controlled by the service. Deactivation or deletion does not delete service orders; raw shortcode text may then appear on the page.', 'vstupenky-online' ); ?></p>
		</details>
	</div>
	<?php
}
