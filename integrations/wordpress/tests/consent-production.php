<?php
// Run by check-production.mjs with WP_ENVIRONMENT_TYPE=production: the
// configured helper and marked links use only the production origin.
if ( ! defined( 'WP_CLI' ) || ! WP_CLI || 'production' !== wp_get_environment_type() ) { exit( 1 ); }
$option = 'vstupenky_online_consent_transfer';
VstupenkyOnline\register_settings();
update_option( $option, array( 'enabled' => '1', 'provider' => 'complianz', 'organization' => '1', 'unit' => '2', 'consent_revision' => str_repeat( 'a', 32 ), 'policy_id' => '42' ) );
try {
	if ( 'https://vstupenky.online' !== VstupenkyOnline\consent_origin() ) { WP_CLI::error( 'Production consent origin' ); }
	VstupenkyOnline\enqueue_consent_helper();
	ob_start(); wp_scripts()->do_items( array( VstupenkyOnline\helper_handle( 'https://vstupenky.online' ) ) ); $html = ob_get_clean();
	if ( false === strpos( $html, 'src="https://vstupenky.online/embed.js"' ) || false === strpos( $html, 'data-festapp-consent=' ) || false !== strpos( $html, '127.0.0.1' ) ) { WP_CLI::error( 'Production helper carries the configuration' ); }
	$local = VstupenkyOnline\mark_consent_links( '<a href="http://127.0.0.1:59801/form/test" target="_blank" rel="noopener">x</a>' );
	$live  = VstupenkyOnline\mark_consent_links( '<a href="https://vstupenky.online/form/test" target="_blank" rel="noopener">x</a>' );
	if ( false !== strpos( $local, 'data-festapp-consent-link' ) || false === strpos( $live, 'data-festapp-consent-link' ) ) { WP_CLI::error( 'Production marks only production form links' ); }
} finally {
	delete_option( $option );
}
WP_CLI::success( 'Production cookie choice transfer uses only the production origin' );
