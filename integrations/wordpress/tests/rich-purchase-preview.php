<?php
// Task-owned local WordPress only.
if ( ! defined( 'WP_CLI' ) || ! WP_CLI || 'local' !== wp_get_environment_type() ) { exit( 1 ); }
$slug = 'podrobny-formular';
$old = get_page_by_path( $slug );
$content = '<!-- wp:paragraph --><p>Rozšířená ukázka obsahuje kontakt, firmu a adresu objednávajícího, více voleb a samostatné jméno, stravování a poznámku pro každou vstupenku. Přidejte více vstupenek a pokračujte do rekapitulace.</p><!-- /wp:paragraph -->'
 . '<!-- wp:vstupenky-online/ticket-form {"url":"http://127.0.0.1:59801/form/wordpress-podrobny","title":"Podrobný formulář s údaji návštěvníků"} /-->';
$id = wp_insert_post( array( 'ID' => $old ? $old->ID : 0, 'post_type' => 'page', 'post_title' => 'Podrobný formulář - více údajů', 'post_name' => $slug, 'post_content' => $content, 'post_status' => 'publish' ), true );
if ( is_wp_error( $id ) ) { WP_CLI::error( $id->get_error_message() ); }
WP_CLI::success( home_url( '/' . $slug . '/' ) );
