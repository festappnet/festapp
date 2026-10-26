<?php
// Adversarial content and WordPress integration checks on the installed ZIP.
if ( ! defined( 'WP_CLI' ) || ! WP_CLI ) { exit( 1 ); }
global $n;
$n = 0;
function vo_qa_assert( $ok, $name ) {
 global $n; ++$n;
 if ( ! $ok ) { WP_CLI::error( $name ); }
}
$url = 'https://vstupenky.online/form/qa-final';
foreach ( array( 240, 4000, '240', '4000' ) as $height ) {
 $html = VstupenkyOnline\render( array( 'url' => $url, 'height' => $height, 'mode' => 'fixed' ) );
 vo_qa_assert( false !== strpos( $html, 'height="' . $height . '"' ), 'valid height boundary' );
}
foreach ( array( -1, 0, 239, 4001, PHP_INT_MAX, '240px', '1e3', 'NaN', '', null, array( 240 ), true ) as $height ) {
 $html = VstupenkyOnline\render( array( 'url' => $url, 'height' => $height, 'mode' => 'fixed' ) );
 vo_qa_assert( false !== strpos( $html, 'height="800"' ), 'invalid height safe default' );
}
foreach ( array( array(), array( 'url' => '' ), array( 'url' => array( $url ) ), array( 'url' => str_repeat( 'x', 2049 ) ) ) as $attrs ) {
 $html = VstupenkyOnline\render( $attrs );
 vo_qa_assert( false === strpos( $html, '<iframe' ) && false !== strpos( $html, 'vstupenky-online-error' ), 'incomplete or corrupted content has local fallback' );
}
$bad_urls = array( $url . '?email=person@example.invalid', $url . '#order=private', $url . '%E2%80%AE', $url . '%0D%0A', $url . '%3F', $url . '%23', $url . '%5C', $url . '%ED%A0%80', "https://vstupenky.online\0.evil.invalid/form/x", 'https://VSTUPENKY.ONLINE/form/x' );
foreach ( $bad_urls as $bad ) {
 vo_qa_assert( false === VstupenkyOnline\validate_url( $bad ), 'private/ambiguous URL rejected' );
}
$empty = do_blocks( '<!-- wp:vstupenky-online/ticket-form /-->' );
vo_qa_assert( false !== strpos( $empty, 'vstupenky-online-error' ) && false === strpos( $empty, '<iframe' ), 'empty Gutenberg block renders safely' );
$short = do_shortcode( '[vstupenky_online]' );
vo_qa_assert( false !== strpos( $short, 'vstupenky-online-error' ), 'empty shortcode renders safely' );
$before = array_keys( wp_scripts()->registered );
$fixed = do_shortcode( '[vstupenky_online url="' . $url . '" mode="fixed" height="240" inherit_style="false"]' );
vo_qa_assert( false === strpos( $fixed, ' data-festapp-embed ' ) && ! array_filter( array_diff( array_keys( wp_scripts()->registered ), $before ), function( $h ) { return 0 === strpos( $h, 'vstupenky-online-helper-' ); } ), 'fixed shortcode adds no helper' );
$block = WP_Block_Type_Registry::get_instance()->get_registered( 'vstupenky-online/ticket-form' );
vo_qa_assert( $block && 3 === $block->api_version && false === $block->supports['html'], 'native API v3 block with HTML editing disabled' );
vo_qa_assert( 'en_US' === get_locale() && 'Tickets on your website' === __( 'Tickets on your website', 'vstupenky-online' ), 'bundled PHP translation actually loads' );
$catalogs = glob( WP_PLUGIN_DIR . '/vstupenky-online/languages/*-cs_CZ-*.json' );
vo_qa_assert( 1 === count( $catalogs ) && false !== strpos( file_get_contents( $catalogs[0] ), 'Vstupenky na' ), 'bundled Czech editor catalog present; English source needs no English catalog' );
vo_qa_assert( false === has_action( 'wp_ajax_vstupenky_online' ) && false === has_action( 'rest_api_init', 'VstupenkyOnline\\register' ), 'no extra order/admin write endpoint' );
WP_CLI::success( $n . ' additional tester assertions; WP ' . get_bloginfo( 'version' ) . ', PHP ' . PHP_VERSION );
