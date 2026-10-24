<?php
if ( ! defined('WP_CLI') || ! WP_CLI ) { exit(1); }
$before = (int) wp_count_posts('page')->publish;
$subscriber=get_user_by('login','vo-subscriber');
wp_set_current_user($subscriber->ID);
$request=new WP_REST_Request('POST','/wp/v2/pages');
$request->set_param('title','Forbidden subscriber publication');
$request->set_param('status','publish');
$request->set_param('content','<!-- wp:vstupenky-online/ticket-form {"url":"https://vstupenky.online/form/test"} /-->');
$result=rest_do_request($request);
if (403 !== $result->get_status() || current_user_can('activate_plugins')) { WP_CLI::error('Subscriber permissions escaped native WP checks'); }
wp_set_current_user(0);
$result=rest_do_request($request);
if (401 !== $result->get_status() || (int)wp_count_posts('page')->publish !== $before) { WP_CLI::error('Anonymous publication was not denied'); }
WP_CLI::success('Real REST publication denied: subscriber 403, anonymous 401; no page created');
