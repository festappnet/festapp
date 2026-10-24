<?php
// Task-owned disposable WordPress only; invoked with WP-CLI, not HTTP.
if ( ! defined( 'WP_CLI' ) || ! WP_CLI || 'local' !== wp_get_environment_type() ) {
	exit( 1 );
}
// Keep the disposable WP database aligned after wp-env restores pinned core.
require_once ABSPATH . 'wp-admin/includes/upgrade.php';
wp_upgrade();
$pages = array(
	'vo-block' => '<!-- wp:vstupenky-online/ticket-form {"url":"http://127.0.0.1:59801/form/embedded-synthetic","title":"Testovací vstupenky"} /-->',
	'vo-shortcode' => '<!-- wp:shortcode -->[vstupenky_online url="http://127.0.0.1:59801/form/embedded-synthetic" mode="fixed" height="800"]<!-- /wp:shortcode -->',
	'vo-seats' => '<!-- wp:vstupenky-online/ticket-form {"url":"http://127.0.0.1:59801/form/embedded-seats","title":"Testovací sedadla"} /-->',
	'vo-two' => '<!-- wp:vstupenky-online/ticket-form {"url":"http://127.0.0.1:59801/form/embedded-synthetic"} /--><!-- wp:shortcode -->[vstupenky_online url="http://127.0.0.1:59801/form/embedded-seats"]<!-- /wp:shortcode -->',
	'vo-invalid' => '<!-- wp:shortcode -->[vstupenky_online url="https://evil.invalid/form/test"]<!-- /wp:shortcode -->',
);
foreach ( $pages as $slug => $content ) {
	$existing = get_page_by_path( $slug );
	$id = wp_insert_post( array( 'ID' => $existing ? $existing->ID : 0, 'post_type' => 'page', 'post_title' => $slug, 'post_name' => $slug, 'post_content' => $content, 'post_status' => 'publish' ), true );
	if ( is_wp_error( $id ) ) {
		WP_CLI::error( $id->get_error_message() );
	}
}
$password = wp_generate_password( 28, false );
wp_set_password( $password, 1 );
update_option( 'blogname', 'vstupenky.online - izolované ověření' );
update_option( 'permalink_structure', '/%postname%/' );
flush_rewrite_rules();
$subscriber = get_user_by( 'login', 'vo-subscriber' );
if ( ! $subscriber ) {
	wp_insert_user( array( 'user_login' => 'vo-subscriber', 'user_pass' => wp_generate_password( 32 ), 'user_email' => 'subscriber@example.invalid', 'role' => 'subscriber' ) );
}
echo 'VO_CREDENTIALS=' . wp_json_encode( array( 'username' => 'admin', 'password' => $password, 'url' => home_url( '/wp-login.php' ) ) ) . "\n";
