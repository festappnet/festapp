<?php
/**
 * Plugin Name: vstupenky.online test fixture - CookieConsent v3 website
 * Description: Disposable test fixture only. Loads CookieConsent v3 in opt-in mode, as a website would.
 * Version: 0.0.0
 * License: GPL-2.0-or-later
 *
 * @package VstupenkyOnlineTests
 */

if ( ! defined( 'ABSPATH' ) || 'local' !== wp_get_environment_type() ) {
	return;
}
add_action(
	'wp_enqueue_scripts',
	function () {
		$src = get_option( 'vo_test_cookieconsent_src' );
		if ( ! is_string( $src ) || ! preg_match( '~\Ahttp://127\.0\.0\.1:[0-9]+/[a-z0-9/_.-]+\z~', $src ) ) {
			return;
		}
		wp_enqueue_style( 'vo-test-cookieconsent', $src . '/cookieconsent.css', array(), null );
		wp_enqueue_script( 'vo-test-cookieconsent', $src . '/cookieconsent.umd.js', array(), null, true );
		// The UMD build exposes window.CookieConsent, as the helper requires.
		wp_add_inline_script(
			'vo-test-cookieconsent',
			// Automated browsers report navigator.webdriver; keep the notice visible.
			'CookieConsent.run({mode:"opt-in",revision:42,hideFromBots:false,categories:{necessary:{enabled:true,readOnly:true},analytics:{},marketing:{}},'
			. 'language:{default:"en",translations:{en:{consentModal:{title:"Cookies",description:"Test website notice.",acceptAllBtn:"Accept all",acceptNecessaryBtn:"Reject all",showPreferencesBtn:"Manage"},'
			. 'preferencesModal:{title:"Cookie preferences",acceptAllBtn:"Accept all",acceptNecessaryBtn:"Reject all",savePreferencesBtn:"Save",'
			. 'sections:[{title:"Necessary",linkedCategory:"necessary"},{title:"Analytics",linkedCategory:"analytics"},{title:"Marketing",linkedCategory:"marketing"}]}}}}});'
		);
	}
);
