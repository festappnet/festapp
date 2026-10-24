<?php
if ( ! defined( 'WP_CLI' ) || ! WP_CLI ) { exit(1); }
$slug = 'vstupenky-online/vstupenky-online.php';
$id = get_page_by_path('vo-block')->ID;
$before = get_post_field('post_content',$id);
$tables = $GLOBALS['wpdb']->get_col('SHOW TABLES');
$options = $GLOBALS['wpdb']->get_col("SELECT option_name FROM {$GLOBALS['wpdb']->options} WHERE option_name LIKE 'vstupenky%'");
deactivate_plugins($slug);
if ( is_plugin_active($slug) ) { WP_CLI::error('Deactivation failed'); }
activate_plugin($slug);
if ( ! is_plugin_active($slug) || $before !== get_post_field('post_content',$id) ) { WP_CLI::error('Reactivation changed saved content'); }
if ( $tables !== $GLOBALS['wpdb']->get_col('SHOW TABLES') || $options !== array() ) { WP_CLI::error('Unexpected plugin-owned persistence'); }
WP_CLI::success('Deactivation/reactivation preserves saved blocks, no plugin tables/options');
