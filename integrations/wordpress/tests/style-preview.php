<?php
// Local visual comparison using the actual plugin and disposable checkout.
if ( ! defined( 'WP_CLI' ) || ! WP_CLI || 'local' !== wp_get_environment_type() ) { exit( 1 ); }
$content = '<!-- wp:paragraph --><p>Stejný formulář ve dvou režimech. Vyzkoušejte pole, výběr vstupenek a pokračování objednávky. Jde o testovací data.</p><!-- /wp:paragraph -->'
 . '<!-- wp:heading --><h2 class="wp-block-heading">Převzít styl stránky - zapnuto</h2><!-- /wp:heading -->'
 . '<!-- wp:vstupenky-online/ticket-form {"url":"http://127.0.0.1:59801/form/embedded-seats","title":"Vstupenky ve vzhledu webu","inheritStyle":true} /-->'
 . '<!-- wp:heading --><h2 class="wp-block-heading">Původní vzhled formuláře</h2><!-- /wp:heading -->'
 . '<!-- wp:vstupenky-online/ticket-form {"url":"http://127.0.0.1:59801/form/embedded-seats","title":"Vstupenky v původním vzhledu","inheritStyle":false} /-->';
$old = get_page_by_path( 'ukazka-vzhledu' );
$result = wp_insert_post( array( 'ID' => $old ? $old->ID : 0, 'post_type' => 'page', 'post_title' => 'Vstupenky ve vzhledu vašeho webu', 'post_name' => 'ukazka-vzhledu', 'post_content' => $content, 'post_status' => 'publish' ), true );
if ( is_wp_error( $result ) ) { WP_CLI::error( $result->get_error_message() ); }
WP_CLI::success( home_url( '/ukazka-vzhledu/' ) );
