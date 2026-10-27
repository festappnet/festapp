<?php
/**
 * Plugin Name: vstupenky.online
 * Plugin URI: https://vstupenky.online/
 * Description: Embed a saved vstupenky.online ticket form with a block or shortcode.
 * Version: 1.0.3
 * Requires at least: 6.6
 * Requires PHP: 7.4.33
 * Author: Festapp
 * Author URI: https://festapp.net/
 * License: GPL-2.0-or-later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: vstupenky-online
 * Domain Path: /languages
 *
 * @package VstupenkyOnline
 */

namespace VstupenkyOnline;

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}
require_once __DIR__ . '/includes/embed.php';
require_once __DIR__ . '/includes/admin.php';

/** Register the block and shortcode backed by one renderer. */
function register() {
	load_plugin_textdomain( 'vstupenky-online', false, dirname( plugin_basename( __FILE__ ) ) . '/languages' );
	wp_register_script( 'vstupenky-online-editor', plugins_url( 'blocks/ticket-form/editor.js', __FILE__ ), array( 'wp-blocks', 'wp-element', 'wp-block-editor', 'wp-components', 'wp-i18n' ), '1.0.3', true );
	wp_localize_script( 'vstupenky-online-editor', 'vstupenkyOnlineEditor', array( 'origins' => allowed_origins() ) );
	wp_set_script_translations( 'vstupenky-online-editor', 'vstupenky-online', __DIR__ . '/languages' );
	wp_register_style( 'vstupenky-online', plugins_url( 'blocks/ticket-form/style.css', __FILE__ ), array(), '1.0.3' );
	register_block_type( __DIR__ . '/blocks/ticket-form', array( 'render_callback' => __NAMESPACE__ . '\render' ) );
	add_shortcode( 'vstupenky_online', __NAMESPACE__ . '\shortcode' );
}
add_action( 'init', __NAMESPACE__ . '\register' );
add_action( 'admin_menu', __NAMESPACE__ . '\admin_menu' );
add_filter( 'plugin_action_links_' . plugin_basename( __FILE__ ), __NAMESPACE__ . '\plugin_action_links' );
