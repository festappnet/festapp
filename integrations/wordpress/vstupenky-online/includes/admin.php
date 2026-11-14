<?php
/**
 * Local onboarding and the optional cookie choice transfer. No remote
 * administration, service credentials or API keys.
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
		<p><?php esc_html_e( 'Automatic height is enabled by default. Website appearance is controlled by the saved form setting in the service.', 'vstupenky-online' ); ?></p>
		</div>
		<div class="card">
		<h2><?php esc_html_e( '3. Preview and publish', 'vstupenky-online' ); ?></h2>
		<p><?php esc_html_e( 'The editor shows the block settings. Save the page and open its preview to see the real form, then publish when you are ready.', 'vstupenky-online' ); ?></p>
		<p><?php esc_html_e( 'Visitors buy tickets on your published page. Manage orders, payments and admission in your vstupenky.online account.', 'vstupenky-online' ); ?></p>
		</div>
		<?php consent_settings_section(); ?>
		<details>
		<summary><?php esc_html_e( 'Shortcode, display options and service information', 'vstupenky-online' ); ?></summary>
		<h2><?php esc_html_e( 'Shortcode and height', 'vstupenky-online' ); ?></h2>
		<p><code>[vstupenky_online url="https://vstupenky.online/form/saved-slug" title="Tickets for our event" measurement="host"]</code></p>
		<p><code>[vstupenky_online url="https://vstupenky.online/form/saved-slug" mode="fixed" height="800" measurement="host"]</code></p>
		<p><code>[vstupenky_online_link url="https://vstupenky.online/form/saved-slug" text="Buy tickets"]</code></p>
		<p><?php esc_html_e( 'The link shortcode and the form link block open the form in a new tab. Use style="link" for a text link instead of a button.', 'vstupenky-online' ); ?></p>
		<p><?php esc_html_e( 'Both height modes load the service helper. Fixed height (240-4000 px) scrolls within the form. The link below the form works without the helper. If your theme or security policy blocks embedding, visitors can open the form in a new tab.', 'vstupenky-online' ); ?></p>
		<p><a href="https://vstupenky.online/events?help=forms" target="_blank" rel="noopener noreferrer"><?php esc_html_e( 'Open forms', 'vstupenky-online' ); ?></a></p>
		<p><?php esc_html_e( 'Website appearance is controlled only by the saved form setting in the service. Open the form appearance settings, choose Match website appearance and save the form. The choice applies to every embed on subsequent page loads without replacing embed code. WordPress cannot override it. The seating plan keeps its own appearance.', 'vstupenky-online' ); ?></p>
		<h2><?php esc_html_e( 'External service and privacy', 'vstupenky-online' ); ?></h2>
		<p><?php esc_html_e( 'The published form connects to vstupenky.online and loads /embed.js. Unit measurement remains the default for existing blocks and shortcodes. New blocks and shortcode examples use Website measurement, recommended for websites with their own GTM and consent banner. Website measurement shares conversion contacts and transaction identifiers with page scripts through dataLayer. Configure your website tags, consent manager and privacy notice before enabling it. The plugin stores no buyer orders or service credentials in WordPress. Activation, this help page and the editor do not load the remote form.', 'vstupenky-online' ); ?></p>
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


/** Register the only plugin-owned option through the Settings API. */
function register_settings() {
	register_setting(
		'vstupenky-online-consent',
		CONSENT_OPTION,
		array(
			'type'              => 'array',
			'sanitize_callback' => __NAMESPACE__ . '\sanitize_consent_settings',
			'default'           => array(),
			'show_in_rest'      => false,
		)
	);
}

/**
 * Value shown in a field: the saved value, otherwise a detected suggestion
 * that is stored only when the administrator saves the form.
 *
 * @param array  $settings Saved settings.
 * @param string $field    Field name.
 * @return array Value and whether it is an unsaved suggestion.
 */
function consent_field_value( $settings, $field ) {
	$saved = isset( $settings[ $field ] ) && is_string( $settings[ $field ] ) ? $settings[ $field ] : '';
	if ( '' !== $saved ) {
		return array( $saved, false );
	}
	$detected = detected_consent_value( $field );
	return array( $detected, '' !== $detected );
}

/**
 * One text input row with its validation and detection state.
 *
 * @param array  $settings    Saved settings.
 * @param string $field       Field name.
 * @param string $label       Translated label.
 * @param string $description Translated help.
 * @param string $placeholder Example value.
 */
function consent_input_row( $settings, $field, $label, $description, $placeholder = '' ) {
	list( $value, $suggested ) = consent_field_value( $settings, $field );

	$id         = 'vstupenky-online-consent-' . str_replace( '_', '-', $field );
	$mismatches = consent_mismatches();
	?>
	<tr>
		<th scope="row"><label for="<?php echo esc_attr( $id ); ?>"><?php echo esc_html( $label ); ?></label></th>
		<td>
			<input type="text" class="regular-text code" id="<?php echo esc_attr( $id ); ?>" name="<?php echo esc_attr( CONSENT_OPTION . '[' . $field . ']' ); ?>" value="<?php echo esc_attr( $value ); ?>" placeholder="<?php echo esc_attr( $placeholder ); ?>" autocomplete="off" spellcheck="false">
			<?php if ( '' !== $description ) : ?>
			<p class="description"><?php echo esc_html( $description ); ?></p>
			<?php endif; ?>
			<?php if ( $suggested ) : ?>
			<p class="description"><?php esc_html_e( 'Suggested from this website. It is saved only when you click Save settings.', 'vstupenky-online' ); ?></p>
			<?php endif; ?>
			<?php if ( isset( $mismatches[ $field ] ) ) : ?>
			<div class="notice notice-warning inline"><p>
				<?php
				/* translators: %s: value currently reported by the website. */
				echo esc_html( sprintf( __( 'The website now reports %s. Transfer is refused until you confirm that the notice behind the new value covers the form.', 'vstupenky-online' ), $mismatches[ $field ] ) );
				?>
				<button type="submit" class="button button-secondary" name="<?php echo esc_attr( CONSENT_OPTION . '[adopt]' ); ?>" value="<?php echo esc_attr( $field ); ?>"><?php esc_html_e( 'Confirm and save the new value', 'vstupenky-online' ); ?></button>
			</p></div>
			<?php endif; ?>
		</td>
	</tr>
	<?php
}

/** Settings for the cookie choice transfer to forms opened in a new tab. */
function consent_settings_section() {
	$settings = consent_settings();
	$provider = isset( $settings['provider'] ) && is_string( $settings['provider'] ) ? $settings['provider'] : '';
	if ( '' === $provider ) {
		$provider = '' !== detected_consent_value( 'policy_id' ) ? 'complianz' : ( '' !== detected_consent_value( 'cbid' ) ? 'cookiebot' : '' );
	}
	$active = null !== consent_config();
	$name   = CONSENT_OPTION;
	$origin = detected_consent_value( 'origin' );
	?>
	<div class="card" id="vstupenky-online-consent" style="max-width:820px">
	<h2><?php esc_html_e( 'Cookie choice in forms opened in a new tab', 'vstupenky-online' ); ?></h2>
	<p><?php esc_html_e( 'Optional. When a visitor has already saved a choice in your website cookie banner, a form opened from a link on this website can take over that choice instead of asking again. Withdrawal on the website also reaches the open form. Without a saved choice, or when anything does not match, the form shows its own cookie notice.', 'vstupenky-online' ); ?></p>
	<p><strong><?php echo esc_html( $active ? __( 'Status: enabled on this website.', 'vstupenky-online' ) : __( 'Status: off. Forms opened in a new tab show their own cookie notice.', 'vstupenky-online' ) ); ?></strong></p>
	<h3><?php esc_html_e( 'Required in vstupenky.online', 'vstupenky-online' ); ?></h3>
	<ol>
		<li><?php esc_html_e( 'In the measurement settings of your organizer account, enable “Use consent from my website banner”.', 'vstupenky-online' ); ?></li>
		<li>
		<?php
		if ( '' !== $origin ) {
			/* translators: %s: origin of this website, for example https://example.com. */
			echo esc_html( sprintf( __( 'Add %s under “My websites” and wait until the platform approves it.', 'vstupenky-online' ), $origin ) );
		} else {
			esc_html_e( 'This website must use HTTPS. Add its address under “My websites” and wait until the platform approves it.', 'vstupenky-online' );
		}
		?>
		</li>
	</ol>
	<p><?php esc_html_e( 'WordPress cannot read these settings from the service. If either is missing, nothing is transferred and the form shows its own notice.', 'vstupenky-online' ); ?></p>
	<form method="post" action="<?php echo esc_url( admin_url( 'options.php' ) ); ?>">
		<?php settings_fields( 'vstupenky-online-consent' ); ?>
		<table class="form-table" role="presentation">
			<tr>
				<th scope="row"><?php esc_html_e( 'Transfer', 'vstupenky-online' ); ?></th>
				<td><label><input type="checkbox" name="<?php echo esc_attr( $name . '[enabled]' ); ?>" value="1" <?php checked( ! empty( $settings['enabled'] ) ); ?>> <?php esc_html_e( 'Take over the website cookie choice in forms opened in a new tab', 'vstupenky-online' ); ?></label></td>
			</tr>
			<tr>
				<th scope="row"><label for="vstupenky-online-consent-provider"><?php esc_html_e( 'Website cookie banner', 'vstupenky-online' ); ?></label></th>
				<td><select id="vstupenky-online-consent-provider" name="<?php echo esc_attr( $name . '[provider]' ); ?>">
					<option value=""><?php esc_html_e( 'Select', 'vstupenky-online' ); ?></option>
					<?php foreach ( consent_providers() as $key => $label ) : ?>
					<option value="<?php echo esc_attr( $key ); ?>" <?php selected( $provider, $key ); ?>><?php echo esc_html( $label ); ?></option>
					<?php endforeach; ?>
				</select>
				<p class="description"><?php esc_html_e( 'Fill in the common fields and the fields of the selected banner. Fields of other banners are ignored.', 'vstupenky-online' ); ?></p></td>
			</tr>
			<?php
			consent_input_row( $settings, 'organization', __( 'Organization ID', 'vstupenky-online' ), '', '1' );
			consent_input_row( $settings, 'unit', __( 'Unit ID', 'vstupenky-online' ), '', '2' );
			consent_input_row( $settings, 'consent_revision', __( 'Form consent revision', 'vstupenky-online' ), __( 'The value analytics.consent_revision from the form metadata. Ask vstupenky.online support if you do not have it. It changes when the measurement notice, its purposes or recipients change.', 'vstupenky-online' ), 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' );
			?>
		</table>
		<h3>Complianz</h3>
		<table class="form-table" role="presentation">
			<?php consent_input_row( $settings, 'policy_id', __( 'Complianz policy ID', 'vstupenky-online' ), __( 'The policy ID whose archived notice covers the form. Complianz increases it when you ask visitors to consent again. Use opt-in consent without consent per service or forced statistics.', 'vstupenky-online' ), '42' ); ?>
		</table>
		<h3>Cookiebot</h3>
		<table class="form-table" role="presentation">
			<?php
			consent_input_row( $settings, 'cbid', __( 'Domain group ID (CBID)', 'vstupenky-online' ), __( 'Keep exactly one Cookiebot uc.js loader on the page.', 'vstupenky-online' ), '12345678-1234-1234-1234-123456789abc' );
			consent_input_row( $settings, 'origin', __( 'Website origin', 'vstupenky-online' ), __( 'The exact HTTPS address of this website without a path, as used by Cookiebot.', 'vstupenky-online' ), 'https://example.com' );
			consent_input_row( $settings, 'consent_valid_from', __( 'Notice valid from (UTC)', 'vstupenky-online' ), __( 'Only choices saved at or after this time transfer. Leave empty to use the moment you save.', 'vstupenky-online' ), '2026-11-11T00:00:00.000Z' );
			consent_input_row( $settings, 'max_age_seconds', __( 'Consent lifetime (seconds)', 'vstupenky-online' ), __( 'At most the consent expiry configured in Cookiebot, and at most 31536000. 180 days is 15552000.', 'vstupenky-online' ), '15552000' );
			?>
			<tr>
				<th scope="row"></th>
				<td><button type="submit" class="button button-secondary" name="<?php echo esc_attr( $name . '[adopt]' ); ?>" value="consent_valid_from"><?php esc_html_e( 'Set the notice time to now and save', 'vstupenky-online' ); ?></button>
				<p class="description"><?php esc_html_e( 'Use after you renew consents in Cookiebot because the notice changed.', 'vstupenky-online' ); ?></p></td>
			</tr>
		</table>
		<h3>CookieConsent v3</h3>
		<table class="form-table" role="presentation">
			<?php
			consent_input_row( $settings, 'revision', __( 'CookieConsent revision', 'vstupenky-online' ), __( 'The positive revision configured in CookieConsent with mode opt-in. The website must expose the library as window.CookieConsent.', 'vstupenky-online' ), '1' );
			consent_input_row( $settings, 'analytics_category', __( 'Analytics category', 'vstupenky-online' ), __( 'Optional. Defaults to analytics.', 'vstupenky-online' ), 'analytics' );
			consent_input_row( $settings, 'marketing_category', __( 'Marketing category', 'vstupenky-online' ), __( 'Optional. Defaults to marketing.', 'vstupenky-online' ), 'marketing' );
			?>
		</table>
		<p><?php esc_html_e( 'Saving is your assertion that the archived notice of your banner covers the form, its analytics and marketing purposes, recipients and the separate measurement domain. It is not a visitor consent record. Values are never updated automatically. When the notice or the form consent revision changes, update them here; until then forms show their own notice.', 'vstupenky-online' ); ?></p>
		<p><?php esc_html_e( 'When enabled, the service helper loads on every page, and new-tab links to public forms in content and menus are marked. Links with download, referrerpolicy or a page-wide referrer policy keep their usual behavior. Links opening in the same tab are not changed.', 'vstupenky-online' ); ?></p>
		<?php submit_button( __( 'Save settings', 'vstupenky-online' ) ); ?>
	</form>
	</div>
	<?php
}

/** Warn administrators when the live website no longer matches the assertion. */
function consent_notice() {
	$screen = function_exists( 'get_current_screen' ) ? get_current_screen() : null;
	if ( ! current_user_can( 'manage_options' ) || ! $screen || ! in_array( $screen->id, array( 'dashboard', 'plugins' ), true ) || ! consent_mismatches() ) {
		return;
	}
	?>
	<div class="notice notice-warning"><p>
		<?php esc_html_e( 'vstupenky.online: your website cookie banner settings changed. Forms opened in a new tab show their own cookie notice until you review and confirm the cookie choice transfer.', 'vstupenky-online' ); ?>
		<a href="<?php echo esc_url( admin_url( 'options-general.php?page=vstupenky-online#vstupenky-online-consent' ) ); ?>"><?php esc_html_e( 'Review the setting', 'vstupenky-online' ); ?></a>
	</p></div>
	<?php
}
