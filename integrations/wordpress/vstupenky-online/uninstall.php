<?php
/**
 * Remove the only plugin-owned option. Service orders are never touched.
 *
 * @package VstupenkyOnline
 */

if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
	exit;
}
delete_option( 'vstupenky_online_consent_transfer' );
