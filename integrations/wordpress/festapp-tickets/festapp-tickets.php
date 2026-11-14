<?php
/**
 * Plugin Name: Festapp Tickets
 * Plugin URI: https://tickets.festapp.net/
 * Description: Sell tickets and collect event registrations with Festapp Tickets forms. Add a Gutenberg block or shortcode to your WordPress site.
 * Version: 1.0.3
 * Requires at least: 6.6
 * Requires PHP: 7.4.33
 * Author: Festapp
 * Author URI: https://festapp.net/
 * License: GPL-2.0-or-later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: festapp-tickets
 * Domain Path: /languages
 *
 * @package FestappTickets
 */

namespace FestappTickets;

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}
require_once __DIR__ . '/includes/embed.php';
require_once __DIR__ . '/includes/consent.php';
require_once __DIR__ . '/includes/admin.php';

/** Register the block and shortcode backed by one renderer. */
function register() {
	load_plugin_textdomain( 'festapp-tickets', false, dirname( plugin_basename( __FILE__ ) ) . '/languages' );
	wp_register_script( 'festapp-tickets-editor', plugins_url( 'blocks/ticket-form/editor.js', __FILE__ ), array( 'wp-blocks', 'wp-element', 'wp-block-editor', 'wp-components', 'wp-i18n' ), '1.0.3', true );
	wp_localize_script(
		'festapp-tickets-editor',
		'festappTicketsEditor',
		array(
			'origins'         => allowed_origins(),
			'consentTransfer' => null !== consent_config(),
		)
	);
	wp_set_script_translations( 'festapp-tickets-editor', 'festapp-tickets', __DIR__ . '/languages' );
	wp_register_style( 'festapp-tickets', plugins_url( 'blocks/ticket-form/style.css', __FILE__ ), array(), '1.0.3' );
	register_block_type( __DIR__ . '/blocks/ticket-form', array( 'render_callback' => __NAMESPACE__ . '\render' ) );
	register_block_type( __DIR__ . '/blocks/form-link', array( 'render_callback' => __NAMESPACE__ . '\render_link' ) );
	add_shortcode( 'festapp_tickets', __NAMESPACE__ . '\shortcode' );
	add_shortcode( 'festapp_tickets_link', __NAMESPACE__ . '\link_shortcode' );
}
add_action( 'init', __NAMESPACE__ . '\register' );
add_action( 'admin_menu', __NAMESPACE__ . '\admin_menu' );
add_action( 'admin_init', __NAMESPACE__ . '\register_settings' );
// Cookie choice transfer: inert unless enabled with a valid saved configuration.
add_filter( 'wp_script_attributes', __NAMESPACE__ . '\consent_script_attributes' );
add_filter( 'plugin_action_links_' . plugin_basename( __FILE__ ), __NAMESPACE__ . '\plugin_action_links' );
