<?php
// Prepares one browser scenario in the disposable WordPress (WP-CLI only).
// Arguments: provider (complianz|cookiebot|cookieconsent|off), form origin,
// Cookiebot website origin, Cookiebot notice time, Cookiebot blocking mode.
if ( ! defined( 'WP_CLI' ) || ! WP_CLI || 'local' !== wp_get_environment_type() ) { exit( 1 ); }
list( $provider, $form, $website, $valid_from, $blocking ) = array_pad( $args, 5, '' );
$form_url = $form . '/form/consent-link';
$content  = '<!-- wp:paragraph --><p id="content-link"><a href="' . $form_url . '" target="_blank" rel="noreferrer noopener">Koupit vstupenky v textu</a></p><!-- /wp:paragraph -->'
	. '<!-- wp:paragraph --><p id="same-tab"><a href="' . $form_url . '">Stejná záložka</a></p><!-- /wp:paragraph -->'
	. '<!-- wp:vstupenky-online/form-link {"url":"' . $form_url . '","text":"Koupit vstupenky"} /-->'
	. '<!-- wp:vstupenky-online/ticket-form {"url":"' . $form_url . '","title":"Vstupenky"} /-->';
$page = get_page_by_path( 'consent-transfer' );
$id   = wp_insert_post( array( 'ID' => $page ? $page->ID : 0, 'post_type' => 'page', 'post_status' => 'publish', 'post_name' => 'consent-transfer', 'post_title' => 'Převzetí souhlasu', 'post_content' => $content ), true );
if ( is_wp_error( $id ) ) { WP_CLI::error( $id->get_error_message() ); }
$plugins = array(
	'complianz'     => 'complianz-gdpr/complianz-gpdr.php',
	'cookiebot'     => 'cookiebot/cookiebot.php',
	'cookieconsent' => 'vstupenky-online-tests/cookieconsent-site.php',
);
foreach ( $plugins as $key => $file ) {
	if ( $key !== $provider && is_plugin_active( $file ) ) { deactivate_plugins( $file ); }
}
$port_fix = 'vstupenky-online-tests/complianz-local-port.php';
if ( ( 'complianz' === $provider ) !== is_plugin_active( $port_fix ) ) {
	'complianz' === $provider ? activate_plugin( $port_fix ) : deactivate_plugins( $port_fix );
}
if ( isset( $plugins[ $provider ] ) && ! is_plugin_active( $plugins[ $provider ] ) ) {
	$result = activate_plugin( $plugins[ $provider ] );
	if ( is_wp_error( $result ) ) { WP_CLI::error( $result->get_error_message() ); }
}
$base     = array( 'enabled' => '1', 'provider' => $provider, 'organization' => '1', 'unit' => '2', 'consent_revision' => str_repeat( 'a', 32 ) );
$settings = array(
	'complianz'     => array( 'policy_id' => (string) get_option( 'complianz_active_policy_id', 1 ) ),
	'cookieconsent' => array( 'revision' => '42' ),
	'cookiebot'     => array( 'cbid' => '09e4e631-f8c7-434e-8387-315da47220fe', 'origin' => $website, 'consent_valid_from' => $valid_from, 'max_age_seconds' => '15552000' ),
);
VstupenkyOnline\register_settings();
if ( 'cookieconsent' === $provider ) {
	update_option( 'vo_test_cookieconsent_src', $form . '/node_modules/vanilla-cookieconsent/dist' );
}
if ( 'cookiebot' === $provider ) {
	update_option( 'cookiebot-cbid', $settings['cookiebot']['cbid'] );
	update_option( 'cookiebot-cookie-blocking-mode', 'manual' === $blocking ? 'manual' : 'auto' );
}
if ( isset( $settings[ $provider ] ) ) {
	update_option( VstupenkyOnline\CONSENT_OPTION, $base + $settings[ $provider ] );
} else {
	delete_option( VstupenkyOnline\CONSENT_OPTION );
}
WP_CLI::success( 'Scenario ' . $provider . ' prepared; transfer ' . ( VstupenkyOnline\consent_config() ? 'enabled' : 'off' ) );
