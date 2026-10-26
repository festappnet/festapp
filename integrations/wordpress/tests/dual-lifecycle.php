<?php
if ( ! defined( 'WP_CLI' ) || ! WP_CLI ) { exit( 1 ); }
foreach(array('vstupenky-online','festapp-tickets') as $slug){
 $path=$slug.'/'.$slug.'.php'; $other=$slug==='vstupenky-online'?'festapp-tickets':'vstupenky-online';
 deactivate_plugins($path);
 if(is_plugin_active($path)||!is_plugin_active($other.'/'.$other.'.php')){WP_CLI::error('Deactivation crossed product boundaries');}
 activate_plugin($path);
 if(!is_plugin_active($path)){WP_CLI::error('Independent reactivation failed');}
}
if((int)$GLOBALS['wpdb']->get_var("SELECT count(*) FROM {$GLOBALS['wpdb']->options} WHERE option_name LIKE 'vstupenky%' OR option_name LIKE 'festapp_tickets%'")!==0){WP_CLI::error('Unexpected plugin-owned account/order state');}
WP_CLI::success('Independent activation lifecycle; no plugin-owned account/order options');
