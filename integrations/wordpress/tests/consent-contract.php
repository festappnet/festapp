<?php
// Cookie choice transfer to forms opened in a new tab, in real WordPress with
// both installed ZIPs. Leaves no saved option behind.
if ( ! defined( 'WP_CLI' ) || ! WP_CLI || 'local' !== wp_get_environment_type() ) { exit( 1 ); }
global $consent_checks; $consent_checks = 0;
function consent_assert( $ok, $name ) { global $consent_checks; ++$consent_checks; if ( ! $ok ) { WP_CLI::error( $name ); } }
function consent_stored( $option ) { global $wpdb; wp_cache_delete( $option, 'options' ); wp_cache_delete( 'alloptions', 'options' ); return (bool) $wpdb->get_var( $wpdb->prepare( "SELECT COUNT(*) FROM {$wpdb->options} WHERE option_name = %s", $option ) ); }
function consent_script( $ns, $origin ) {
	unset( $GLOBALS['wp_scripts'] );
	call_user_func( $ns . '\\enqueue_consent_helper' );
	$handle = call_user_func( $ns . '\\helper_handle', $origin );
	ob_start(); wp_scripts()->do_items( array( $handle ) ); $html = ob_get_clean();
	$tags = new WP_HTML_Tag_Processor( $html );
	while ( $tags->next_tag( 'script' ) ) {
		if ( $origin . '/embed.js' === $tags->get_attribute( 'src' ) ) { return $tags; }
	}
	return null;
}
$base = array( 'organization' => '1', 'unit' => '2', 'consent_revision' => str_repeat( 'a', 32 ) );
$providers = array(
	'complianz'     => array( 'policy_id' => '42' ),
	'cookiebot'     => array( 'cbid' => '12345678-1234-1234-1234-123456789abc', 'origin' => 'https://organizer.example', 'consent_valid_from' => '2026-11-11T00:00:00.000Z', 'max_age_seconds' => '15552000' ),
	'cookieconsent' => array( 'revision' => '42' ),
);
$expected = array(
	'complianz'     => array( 'provider' => 'complianz', 'organization' => 1, 'unit' => 2, 'consentRevision' => str_repeat( 'a', 32 ), 'policyId' => '42' ),
	'cookiebot'     => array( 'provider' => 'cookiebot', 'organization' => 1, 'unit' => 2, 'consentRevision' => str_repeat( 'a', 32 ), 'cbid' => '12345678-1234-1234-1234-123456789abc', 'origin' => 'https://organizer.example', 'consentValidFrom' => '2026-11-11T00:00:00.000Z', 'maxAgeSeconds' => 15552000 ),
	'cookieconsent' => array( 'provider' => 'cookieconsent', 'organization' => 1, 'unit' => 2, 'consentRevision' => str_repeat( 'a', 32 ), 'revision' => 42 ),
);
$invalid = array(
	'complianz'     => array( array( 'policy_id' => '0' ), array( 'policy_id' => '4 2' ), array( 'policy_id' => '' ), array( 'consent_revision' => str_repeat( 'A', 32 ) ), array( 'consent_revision' => str_repeat( 'a', 31 ) ), array( 'organization' => '0' ), array( 'unit' => '-2' ), array( 'unit' => '2.5' ) ),
	'cookiebot'     => array( array( 'cbid' => 'not-a-cbid' ), array( 'origin' => 'http://organizer.example' ), array( 'origin' => 'https://organizer.example/' ), array( 'origin' => 'https://organizer.example/path' ), array( 'origin' => 'https://organizer.example:443' ), array( 'origin' => 'https://Organizer.example' ), array( 'consent_valid_from' => '2026-11-11T00:00:00Z' ), array( 'consent_valid_from' => '2026-11-11T00:00:00.000+00:00' ), array( 'consent_valid_from' => '2026-02-30T00:00:00.000Z' ), array( 'max_age_seconds' => '0' ), array( 'max_age_seconds' => '31536001' ) ),
	'cookieconsent' => array( array( 'revision' => '0' ), array( 'revision' => 'x' ), array( 'analytics_category' => 'marketing' ), array( 'marketing_category' => 'a b' ), array( 'analytics_category' => str_repeat( 'a', 129 ) ) ),
);
foreach ( array( array( 'vstupenky-online', 'vstupenky_online', 'VstupenkyOnline', 'https://vstupenky.online', 'http://127.0.0.1:59801' ), array( 'festapp-tickets', 'festapp_tickets', 'FestappTickets', 'https://tickets.festapp.net', 'http://127.0.0.1:59804' ) ) as $p ) {
	list( $slug, $shortcode, $ns, $production, $local ) = $p;
	$option = $shortcode . '_consent_transfer';
	$f = function ( $name, ...$args ) use ( $ns ) { return call_user_func_array( $ns . '\\' . $name, $args ); };
	delete_option( $option );
	$f( 'register_settings' ); // Settings API sanitizer, as on admin_init.
	consent_assert( $local === $f( 'consent_origin' ), 'local WordPress uses the deployment-owned origin' );
	// Validation mirrors the helper; nothing is repaired.
	foreach ( $providers as $provider => $fields ) {
		$valid = $f( 'consent_validate', array( 'provider' => $provider ) + $fields + $base );
		consent_assert( array() === $valid['errors'] && $expected[ $provider ] === $valid['config'], 'valid ' . $provider . ' configuration' );
		foreach ( $invalid[ $provider ] as $i => $change ) {
			$result = $f( 'consent_validate', array_merge( array( 'provider' => $provider ) + $fields + $base, $change ) );
			consent_assert( null === $result['config'] && array() !== $result['errors'], 'invalid ' . $provider . ' case ' . $i );
		}
	}
	consent_assert( null === $f( 'consent_validate', array( 'provider' => 'gcm' ) + $base )['config'], 'unknown provider and no Consent Mode fallback' );
	$mapped = $f( 'consent_validate', array( 'provider' => 'cookieconsent', 'revision' => '3', 'analytics_category' => 'stats', 'marketing_category' => 'ads' ) + $base );
	consent_assert( array( 'analytics' => 'stats', 'marketing' => 'ads' ) === $mapped['config']['categories'], 'custom CookieConsent categories' );
	// Disabled by default: markup and scripts are unchanged.
	$url = $local . '/form/test';
	$off = $f( 'render', array( 'url' => $url ) );
	consent_assert( false !== strpos( $off, '<a href="' . $url . '" target="_blank" rel="noopener noreferrer">' ) && false === strpos( $off, 'data-festapp-consent' ), 'disabled fallback link unchanged' );
	consent_assert( null === $f( 'consent_config' ) && null === consent_script( $ns, $local ), 'disabled transfer loads no site-wide helper' );
	$content = '<p><a href="' . $url . '" target="_blank" rel="noopener">Buy</a></p>';
	consent_assert( $content === apply_filters( 'the_content', $content ) || false === strpos( apply_filters( 'the_content', $content ), 'data-festapp-consent-link' ), 'disabled transfer does not mark content' );
	// Sanitizer: enabled only when valid; inputs are retained for correction.
	wp_set_current_user( 1 );
	update_option( $option, array( 'enabled' => '1', 'provider' => 'complianz', 'policy_id' => '' ) + $base );
	$saved = get_option( $option );
	consent_assert( false === $saved['enabled'] && '1' === $saved['organization'], 'invalid enabled settings are saved disabled' );
	$errors = get_settings_errors( $option );
	consent_assert( 1 === count( $errors ), 'one settings error for invalid input' );
	update_option( $option, array( 'enabled' => '1', 'provider' => 'cookiebot', 'consent_valid_from' => '', 'consent_revision' => strtoupper( str_repeat( 'b', 32 ) ) ) + $providers['cookiebot'] + $base );
	$saved = get_option( $option );
	consent_assert( true === $saved['enabled'] && $f( 'is_utc_instant', $saved['consent_valid_from'] ) && abs( strtotime( $saved['consent_valid_from'] ) - time() ) < 120, 'empty Cookiebot notice time defaults to confirmation time' );
	consent_assert( str_repeat( 'b', 32 ) === $saved['consent_revision'], 'revision is normalized to lowercase' );
	consent_assert( $saved === $f( 'sanitize_consent_settings', $saved ), 'sanitizer is idempotent' );
	$adopt = $f( 'sanitize_consent_settings', array( 'adopt' => 'cbid' ) + $saved );
	consent_assert( $saved['cbid'] === $adopt['cbid'], 'adopt without a detected value keeps the saved value' );
	// Enabled: site-wide helper with the exact attribute JSON.
	foreach ( $providers as $provider => $fields ) {
		update_option( $option, array( 'enabled' => '1', 'provider' => $provider ) + $fields + $base );
		$tag = consent_script( $ns, $local );
		consent_assert( null !== $tag, 'site-wide helper enqueued for ' . $provider );
		consent_assert( $expected[ $provider ] === json_decode( $tag->get_attribute( 'data-festapp-consent' ), true ), 'exact data-festapp-consent JSON for ' . $provider );
		consent_assert( ( 'ignore' === $tag->get_attribute( 'data-cookieconsent' ) ) === ( 'cookiebot' === $provider ), 'Cookiebot ignore marker only for Cookiebot' );
		consent_assert( ( 'functional' === $tag->get_attribute( 'data-category' ) ) === ( 'complianz' === $provider ), 'Complianz functional marker only for Complianz' );
		consent_assert( true === $tag->get_attribute( 'defer' ), 'helper remains deferred' );
	}
	$production_tag = consent_script( $ns, $production );
	consent_assert( null === $production_tag, 'configuration belongs to one helper origin' );
	// Links.
	$on = $f( 'render', array( 'url' => $url ) );
	consent_assert( false !== strpos( $on, '<a href="' . $url . '" target="_blank" data-festapp-consent-link>' ) && false === strpos( $on, 'noopener' ), 'enabled fallback link is marked without noopener' );
	consent_assert( false !== strpos( $f( 'render', array( 'url' => $production . '/form/test' ) ), 'rel="noopener noreferrer"' ), 'other origin fallback keeps native link' );
	$block = render_block( array( 'blockName' => $slug . '/form-link', 'attrs' => array( 'url' => $url, 'text' => 'Koupit <b>vstupenky</b>' ), 'innerBlocks' => array(), 'innerHTML' => '', 'innerContent' => array() ) );
	consent_assert( '<p class="' . $slug . '-form-link"><a class="wp-element-button ' . $slug . '-button" href="' . $url . '" target="_blank" data-festapp-consent-link>Koupit vstupenky</a></p>' === $block, 'form link block markup' );
	$short = do_shortcode( '[' . $shortcode . '_link url="' . $url . '" style="link"]' );
	consent_assert( false !== strpos( $short, 'class="' . $slug . '-text-link"' ) && false !== strpos( $short, 'data-festapp-consent-link' ) && false !== strpos( $short, '>Buy tickets</a>' ), 'link shortcode markup' );
	consent_assert( false === strpos( do_shortcode( '[' . $shortcode . '_link url="' . $url . '?email=x"]' ), '<a ' ), 'link shortcode validates the URL' );
	// Input => expected rel when marked (false: unchanged).
	$cases = array(
		'<a href="' . $url . '" target="_blank" rel="noopener">x</a>'                    => null,
		'<a href="' . $url . '" target="_blank" rel="nofollow noopener noreferrer">x</a>' => 'nofollow',
		'<a href="' . $url . '" target="_blank" rel>x</a>'                                => null,
		'<a href="' . $url . '">same tab</a>'                                              => false,
		'<a href="' . $url . '" target="_self">x</a>'                                      => false,
		'<a href="' . $url . '" target="_blank" download>x</a>'                           => false,
		'<a href="' . $url . '" target="_blank" referrerpolicy="no-referrer">x</a>'       => false,
		'<a href="' . $url . '?utm_source=x" target="_blank" rel="noopener">x</a>'         => false,
		'<a href="' . $url . '/admin" target="_blank" rel="noopener">x</a>'                => false,
		'<a href="' . $production . '/form/test" target="_blank" rel="noopener">x</a>'     => false,
		'<a href="https://example.com/?u=' . rawurlencode( $url ) . '" target="_blank">x</a>' => false,
		'<script>var a = \'<a href="' . $url . '" target="_blank">\';</script>'         => false,
	);
	foreach ( $cases as $input => $rel ) {
		$out = $f( 'mark_consent_links', $input );
		if ( false === $rel ) {
			consent_assert( $input === $out, 'content link left unchanged: ' . $input );
			continue;
		}
		$tags = new WP_HTML_Tag_Processor( $out );
		$tags->next_tag( 'a' );
		consent_assert( true === $tags->get_attribute( 'data-festapp-consent-link' ) && $rel === $tags->get_attribute( 'rel' ) && $url === $tags->get_attribute( 'href' ) && '_blank' === $tags->get_attribute( 'target' ), 'content link marked: ' . $input );
	}
	// WP 6.6's tag processor does not match upper-case attribute names: such
	// links stay native there (fail closed) and are marked on newer cores.
	$upper = '<A HREF="' . $url . '" TARGET="_blank">x</A>';
	consent_assert( in_array( $f( 'mark_consent_links', $upper ), array( $upper, '<A data-festapp-consent-link HREF="' . $url . '" TARGET="_blank">x</A>' ), true ), 'upper-case link is marked or left native' );
	$marked = $f( 'mark_consent_links', '<a href="' . $url . '" target="_blank" rel="noopener">x</a>' );
	consent_assert( $marked === $f( 'mark_consent_links', $marked ), 'marking is idempotent' );
	$rendered = apply_filters( 'the_content', '<!-- wp:paragraph --><p><a href="' . $url . '" target="_blank" rel="noreferrer noopener">Vstupenky</a></p><!-- /wp:paragraph -->' );
	consent_assert( 1 === substr_count( $rendered, 'data-festapp-consent-link' ) && false === strpos( $rendered, 'noopener' ), 'the_content marks block content once' );
	$menu = $f( 'mark_menu_link', array( 'href' => $url, 'target' => '_blank', 'rel' => 'noopener' ) );
	consent_assert( '' === $menu['rel'] && '1' === $menu['data-festapp-consent-link'], 'classic menu link is marked' );
	consent_assert( array( 'href' => $url, 'target' => '' ) === $f( 'mark_menu_link', array( 'href' => $url, 'target' => '' ) ), 'same-tab menu link unchanged' );
	// Detected values are suggestions; mismatches produce a notice and an explicit adopt.
	update_option( $option, array( 'enabled' => '1', 'provider' => 'complianz', 'policy_id' => '2' ) + $base );
	if ( ! defined( 'CMPLZ_VERSION' ) ) { define( 'CMPLZ_VERSION', 'contract' ); }
	update_option( 'complianz_active_policy_id', 3 );
	consent_assert( array( 'policy_id' => '3' ) === $f( 'consent_mismatches' ), 'changed Complianz policy is detected' );
	consent_assert( '2' === get_option( $option )['policy_id'] && null !== $f( 'consent_config' ), 'detected value never overwrites the saved assertion' );
	set_current_screen( 'dashboard' );
	ob_start(); $f( 'consent_notice' ); $notice = ob_get_clean();
	consent_assert( false !== strpos( $notice, 'notice-warning' ) && false !== strpos( $notice, 'page=' . $slug . '#' . $slug . '-consent' ), 'dashboard notice links to review' );
	set_current_screen( 'edit-post' );
	ob_start(); $f( 'consent_notice' ); consent_assert( '' === ob_get_clean(), 'notice limited to dashboard and plugins' );
	ob_start(); $f( 'admin_page' ); $page = ob_get_clean();
	consent_assert( false !== strpos( $page, 'value="policy_id"' ) && false !== strpos( $page, 'options.php' ) && false === strpos( $page, '<script' ), 'settings page offers explicit confirmation without scripts' );
	$sub = get_user_by( 'login', 'vo-subscriber' ); wp_set_current_user( $sub->ID ); set_current_screen( 'dashboard' );
	ob_start(); $f( 'consent_notice' ); consent_assert( '' === ob_get_clean(), 'subscriber sees no notice' );
	wp_set_current_user( 1 );
	update_option( $option, array( 'adopt' => 'policy_id' ) + get_option( $option ) );
	consent_assert( '3' === get_option( $option )['policy_id'] && array() === $f( 'consent_mismatches' ), 'explicit confirmation adopts the detected value' );
	delete_option( $option );
	ob_start(); $f( 'admin_page' ); $page = ob_get_clean();
	consent_assert( false !== strpos( $page, 'value="3"' ) && ! consent_stored( $option ), 'suggestion is prefilled but not saved' );
	delete_option( 'complianz_active_policy_id' );
	// Uninstall removes the only plugin option.
	update_option( $option, array( 'enabled' => false ) );
	consent_assert( consent_stored( $option ), 'option stored before uninstall' );
	if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) { define( 'WP_UNINSTALL_PLUGIN', $slug . '/' . $slug . '.php' ); }
	include WP_PLUGIN_DIR . '/' . $slug . '/uninstall.php';
	consent_assert( ! consent_stored( $option ), 'uninstall deletes the option' );
}
WP_CLI::success( $consent_checks . ' cookie choice transfer assertions; WP ' . get_bloginfo( 'version' ) . ', PHP ' . PHP_VERSION );
