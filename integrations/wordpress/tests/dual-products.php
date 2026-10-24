<?php
// Both independently installed ZIPs must coexist without sharing a runtime owner.
if ( ! defined( 'WP_CLI' ) || ! WP_CLI ) { exit( 1 ); }
global $dual_checks; $dual_checks = 0;
function dual_assert( $ok, $name ) { global $dual_checks; ++$dual_checks; if ( ! $ok ) { WP_CLI::error( $name ); } }
$products = array(
 array( 'vstupenky-online', 'vstupenky_online', 'VstupenkyOnline', 'https://vstupenky.online', 'http://127.0.0.1:59801' ),
 array( 'festapp-tickets', 'festapp_tickets', 'FestappTickets', 'https://tickets.festapp.net', 'http://127.0.0.1:59804' ),
);
foreach ( $products as $i => $p ) {
 list( $slug, $shortcode, $ns, $origin, $local ) = $p;
 $validate = $ns . '\\validate_url'; $render = $ns . '\\render';
 dual_assert( is_plugin_active( $slug . '/' . $slug . '.php' ), 'independent ZIP active: ' . $slug );
 dual_assert( false !== $validate( $origin . '/form/test' ), 'own production origin accepted' );
 dual_assert( false !== $validate( $local . '/form/test' ), 'own explicit fixture accepted' );
 dual_assert( false === $validate( $products[1-$i][3] . '/form/test' ), 'other production brand rejected' );
 dual_assert( false === $validate( $products[1-$i][4] . '/form/test' ), 'other local brand rejected' );
 foreach ( array( '?email=private', '#token=private', '/..', '%2Fadmin', '%252Fadmin', '%0A', '@evil.invalid', '/extra' ) as $suffix ) { dual_assert( false === $validate( $origin . '/form/test' . $suffix ), 'unsafe URL rejected for ' . $slug ); }
 $a = array( 'url' => $origin . '/form/test', 'mode' => 'fixed', 'height' => 240 );
 $block = render_block( array( 'blockName' => $slug . '/ticket-form', 'attrs' => $a, 'innerBlocks' => array(), 'innerHTML' => '', 'innerContent' => array() ) );
 $short = do_shortcode( '[' . $shortcode . ' url="' . $a['url'] . '" mode="fixed" height="240"]' );
 dual_assert( false !== strpos( $block, 'data-festapp-embed-host' ), 'native price host is declared without moving the iframe' );
 dual_assert( $block === $short && false !== strpos( $short, 'height="240"' ), 'native block/shortcode use the same renderer' );
 dual_assert( false !== strpos( $short, 'class="' . $slug . '"' ) && false !== strpos( $short, $origin ), 'output retains product identity' );
 $styled = $a; $styled['inheritStyle'] = true;
 $styled_block = render_block( array( 'blockName' => $slug . '/ticket-form', 'attrs' => $styled, 'innerBlocks' => array(), 'innerHTML' => '', 'innerContent' => array() ) );
 $styled_short = do_shortcode( '[' . $shortcode . ' url="' . $a['url'] . '" mode="fixed" height="240" inherit_style="true"]' );
 dual_assert( $styled_block === $styled_short && false !== strpos( $styled_short, 'data-festapp-style="inherit"' ) && false !== strpos( $styled_short, 'data-festapp-height="fixed"' ), 'opt-in style shares renderer and preserves fixed height' );
 dual_assert( false !== strpos( $short, 'data-festapp-style="inherit"' ), 'website appearance is the default' );
 $plain = $a; $plain['inheritStyle'] = false;
 $plain_block = render_block( array( 'blockName' => $slug . '/ticket-form', 'attrs' => $plain, 'innerBlocks' => array(), 'innerHTML' => '', 'innerContent' => array() ) );
 $plain_short = do_shortcode( '[' . $shortcode . ' url="' . $a['url'] . '" mode="fixed" height="240" inherit_style="false"]' );
 dual_assert( $plain_block === $plain_short && false === strpos( $plain_short, ' data-festapp-embed ' ), 'explicit opt-out matches block and shortcode without helper' );
 $render( array( 'url' => $origin . '/form/test' ) ); $render( array( 'url' => $origin . '/form/test' ) );
 $helpers = array_filter( wp_scripts()->queue, function( $h ) use ( $slug ) { return 0 === strpos( $h, $slug . '-helper-' ); } );
 dual_assert( 1 === count( $helpers ), 'one helper per product origin' );
 dual_assert( wp_script_is( $slug . '-editor', 'registered' ) && wp_style_is( $slug, 'registered' ), 'distinct script/style handles' );
 wp_set_current_user( 1 ); ob_start(); call_user_func( $ns . '\\admin_page' ); $help = ob_get_clean();
 dual_assert( false !== strpos( $help, $origin . '/login' ) && false !== strpos( $help, '1. Prepare your form' ), 'first-account onboarding is present' );
 dual_assert( false === strpos( $help, '<iframe' ) && false === strpos( $help, '<script' ), 'local help never embeds a service admin' );
 wp_set_current_user( 0 ); ob_start(); call_user_func( $ns . '\\admin_page' ); $help = ob_get_clean(); dual_assert( '' === $help, 'anonymous help access denied' );
}
WP_CLI::success( $dual_checks . ' dual-product coexistence/security assertions; WP ' . get_bloginfo( 'version' ) . ', PHP ' . PHP_VERSION );
