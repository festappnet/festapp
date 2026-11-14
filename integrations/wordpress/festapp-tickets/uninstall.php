<?php
/**
 * Remove the only plugin-owned option. Service orders are never touched.
 *
 * @package FestappTickets
 */

if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
	exit;
}
delete_option( 'festapp_tickets_consent_transfer' );
