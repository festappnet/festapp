<?php
/**
 * Plugin Name: vstupenky.online test fixture - Complianz on a local port
 * Description: Disposable test fixture only. Complianz derives its cookie path from home_url() including the port (":59811/"), which WebKit rejects; production sites have no port.
 * Version: 0.0.0
 * License: GPL-2.0-or-later
 *
 * @package VstupenkyOnlineTests
 */

if ( ! defined( 'ABSPATH' ) || 'local' !== wp_get_environment_type() ) {
	return;
}
add_filter(
	'cmplz_cookie_path',
	function ( $path ) {
		return 0 === strpos( $path, ':' ) ? '/' : $path;
	}
);
