<?php
// Executes inside real WordPress with the installed ZIP, no mocked WP functions.
if ( ! defined( 'WP_CLI' ) || ! WP_CLI ) { exit( 1 ); }
global $checks;
$checks = 0;
function vo_assert( $condition, $name ) {
	global $checks;
	++$checks;
	if ( ! $condition ) { WP_CLI::error( $name ); }
}
$url = 'https://vstupenky.online/form/ulozeny-odkaz';
vo_assert( false !== VstupenkyOnline\validate_url( $url ), 'public URL' );
vo_assert( false !== VstupenkyOnline\validate_url( 'https://vstupenky.online/form/%C4%8Desk%C3%BD' ), 'canonical Unicode' );
$bad = array( '', array(), null, 'javascript:alert(1)', 'http://vstupenky.online/form/x', 'https://www.vstupenky.online/form/x', 'https://vstupenky.online.evil.invalid/form/x', 'https://vstupenky.online@evil.invalid/form/x', 'https://evil@vstupenky.online/form/x', 'https://vstupenky.online:443/form/x', '//vstupenky.online/form/x', $url . '?embed=1', $url . '#secret', $url . '/', $url . "\n", $url . '/..', $url . '%2Fxx', $url . '%252Fxx', $url . '%00', 'https://vstupenky.online/form/%78', 'https://vstupenky.online/form/%c4%8d', 'https://vstupenky.online/form/český', 'https://vstupenky.online/admin/x', 'https://festapp.net/form/x', 'http://127.0.0.1:8000/form/x', 'http://localhost:59801/form/x' );
foreach ( $bad as $i => $input ) { vo_assert( false === VstupenkyOnline\validate_url( $input ), 'reject unsafe URL case ' . $i ); }
$local = 'http://127.0.0.1:59801/form/embedded-synthetic';
vo_assert( false !== VstupenkyOnline\validate_url( $local ), 'explicit local fixture' );
wp_set_current_user( 0 );
$invalid = VstupenkyOnline\render( array( 'url' => $url . '#private' ) );
vo_assert( false === strpos( $invalid, '<iframe' ) && false === strpos( $invalid, 'private' ), 'invalid input never leaked' );
$fixed = VstupenkyOnline\render( array( 'url' => $url, 'title' => '"><img src=x onerror=alert(1)>', 'inheritStyle' => false, 'mode' => 'fixed', 'height' => '4001" onload="bad' ) );
vo_assert( false === strpos( $fixed, '<img' ) && false === strpos( $fixed, ' onload=' ), 'title/height escaping' );
vo_assert( false !== strpos( $fixed, 'height="800"' ) && false === strpos( $fixed, ' data-festapp-embed ' ), 'fixed safe default' );
vo_assert( false !== strpos( $fixed, 'noopener noreferrer' ) && false !== strpos( $fixed, '?embed=1' ), 'safe fallback and embed' );
$block = render_block( array( 'blockName' => 'vstupenky-online/ticket-form', 'attrs' => array( 'url' => $url, 'mode' => 'fixed' ), 'innerBlocks' => array(), 'innerHTML' => '', 'innerContent' => array() ) );
$short = do_shortcode( '[vstupenky_online url="' . $url . '" mode="fixed"]' );
vo_assert( $block === $short, 'block/shortcode share renderer' );
VstupenkyOnline\render( array( 'url' => $url ) );
VstupenkyOnline\render( array( 'url' => $url ) );
$scripts = wp_scripts();
$helpers = array_filter( $scripts->queue, function( $h ) { return 0 === strpos( $h, 'vstupenky-online-helper-' ); } );
vo_assert( 1 === count( $helpers ), 'two instances enqueue one helper' );
ob_start(); wp_footer(); $footer = ob_get_clean();
vo_assert( 1 === substr_count( $footer, 'https://vstupenky.online/embed.js' ), 'late render prints helper once in footer' );
$sub = get_user_by( 'login', 'vo-subscriber' );
wp_set_current_user( $sub->ID );
ob_start(); VstupenkyOnline\admin_page(); $help = ob_get_clean();
vo_assert( '' === $help && ! current_user_can( 'manage_options' ), 'subscriber cannot access help' );
wp_set_current_user( 1 );
ob_start(); VstupenkyOnline\admin_page(); $help = ob_get_clean();
vo_assert( false !== strpos( $help, 'https://vstupenky.online/privacy/' ), 'administrator help and disclosure' );
vo_assert( false === strpos( $help, '<iframe' ) && false === strpos( $help, '<script' ), 'help never connects remote service' );
WP_CLI::success( $checks . ' real WordPress contract assertions; WP ' . get_bloginfo( 'version' ) . ', PHP ' . PHP_VERSION );
