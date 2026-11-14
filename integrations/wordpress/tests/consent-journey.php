<?php
// Called only by the disposable fixture owner with a real SQL-produced export.
if (!defined('WP_CLI') || !WP_CLI || wp_get_environment_type() !== 'local') { exit(1); }
$raw = file_get_contents(__DIR__ . '/journey-export.json');
$config = json_decode($raw, true);
$settings = VstupenkyOnline\sanitize_consent_settings(['enabled'=>1,'export'=>$raw]);
if (empty($settings['enabled'])) { throw new RuntimeException('Server export import rejected'); }
update_option('vstupenky-online_consent', $settings);
wp_set_current_user(1);
$existing = get_page_by_path('managed-consent-test');
$id = wp_insert_post(['ID'=>$existing ? $existing->ID : 0,'post_title'=>'Ověření přenosu souhlasu','post_name'=>'managed-consent-test',
    'post_content'=>'[vstupenky_online_link url="'.esc_url_raw($config['serviceOrigin'].'/form/embedded-synthetic').'"]Otevřít formulář[/vstupenky_online_link]',
    'post_status'=>'publish','post_type'=>'page'], true);
if (is_wp_error($id)) { throw new RuntimeException('Cannot create fixture page'); }
update_option('permalink_structure','/%postname%/');flush_rewrite_rules();
echo "Prepared real WordPress import and owned form link\n";
