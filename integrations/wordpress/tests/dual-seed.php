<?php
if ( ! defined( 'WP_CLI' ) || ! WP_CLI || 'local' !== wp_get_environment_type() ) { exit( 1 ); }
$pages = array(
 'vo-global' => '<!-- wp:festapp-tickets/ticket-form {"url":"http://127.0.0.1:59804/form/embedded-synthetic","title":"Global event tickets"} /-->',
 'vo-global-fixed' => '[festapp_tickets url="http://127.0.0.1:59804/form/embedded-synthetic" mode="fixed" height="800"]',
 'vo-global-seats' => '<!-- wp:festapp-tickets/ticket-form {"url":"http://127.0.0.1:59804/form/embedded-seats","title":"Global reserved seats"} /-->',
 'vo-dual' => '<!-- wp:vstupenky-online/ticket-form {"url":"http://127.0.0.1:59801/form/embedded-synthetic","title":"Czech event tickets"} /--><!-- wp:festapp-tickets/ticket-form {"url":"http://127.0.0.1:59804/form/embedded-seats","title":"Global reserved seats"} /-->',
 'vo-global-invalid' => '[festapp_tickets url="https://vstupenky.online/form/private#capability"]',
);
foreach ( $pages as $slug => $content ) {
 $old=get_page_by_path($slug);
 $result=wp_insert_post(array('ID'=>$old ? $old->ID : 0,'post_type'=>'page','post_title'=>$slug,'post_name'=>$slug,'post_content'=>$content,'post_status'=>'publish'),true);
 if(is_wp_error($result)){WP_CLI::error($result->get_error_message());}
}
WP_CLI::success('Five dual-product fixture pages prepared');
