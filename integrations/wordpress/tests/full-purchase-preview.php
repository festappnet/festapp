<?php
if ( ! defined( 'WP_CLI' ) || ! WP_CLI || 'local' !== wp_get_environment_type() ) { exit( 1 ); }
$slug = 'vyzkouset-nakup';
$old = get_page_by_path( $slug );
$content = '<!-- wp:paragraph --><p>Tady si můžete vyzkoušet celý nákup: vyplnit údaje, přidat více vstupenek, zkontrolovat rekapitulaci a odeslat testovací objednávku. Platba je testovací a e-mail se v této lokální ukázce neodesílá.</p><!-- /wp:paragraph -->'
 . '<!-- wp:vstupenky-online/ticket-form {"url":"http://127.0.0.1:59801/form/wordpress-nakup","title":"Vyzkoušet celý nákup vstupenek"} /-->';
$result = wp_insert_post( array( 'ID' => $old ? $old->ID : 0, 'post_type' => 'page', 'post_title' => 'Vyzkoušet celý nákup vstupenek', 'post_name' => $slug, 'post_content' => $content, 'post_status' => 'publish' ), true );
if ( is_wp_error( $result ) ) { WP_CLI::error( $result->get_error_message() ); }
WP_CLI::success( home_url( '/' . $slug . '/' ) );
