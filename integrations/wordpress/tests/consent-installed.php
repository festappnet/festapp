<?php
// Run inside each disposable, real WordPress installation with both products active.
$website = 'https://organizer.example';
add_filter('home_url', static function () use ($website) { return $website . '/subdirectory'; });
wp_set_current_user(1);
$checks = 0;
foreach ([['vstupenky-online','VstupenkyOnline','vstupenky_online','https://vstupenky.online'], ['festapp-tickets','FestappTickets','festapp_tickets','https://tickets.festapp.net']] as [$slug,$namespace,$shortcode,$service]) {
    $allowed = $namespace . '\\allowed_origins'; $service = $allowed()[0];
    $config = ['schemaVersion'=>1, 'serviceOrigin'=>$service, 'websiteOrigin'=>$website, 'binding'=>['id'=>'11111111-1111-1111-1111-111111111111','version'=>1], 'providerConfig'=>['provider'=>'complianz','organization'=>1,'unit'=>1,'consentRevision'=>str_repeat('a',32),'origin'=>$website,'policyId'=>'1']];
    $sanitize = $namespace . '\\sanitize_consent_settings';
    $raw = wp_json_encode($config);
    $valid = $sanitize(['enabled'=>1, 'export'=>$raw]);
    if (empty($valid['enabled'])) throw new RuntimeException("$slug valid import rejected");
    $foreign = $config; $foreign['websiteOrigin'] = 'https://foreign.example';
    foreach (['{broken', wp_json_encode($foreign)] as $bad) {
        if (!empty($sanitize(['enabled'=>1, 'export'=>$bad])['enabled'])) throw new RuntimeException("$slug invalid import accepted");
    }
    update_option($slug.'_consent', $valid);
    $url = $service.'/form/embedded-synthetic';
    $link = do_shortcode('['.$shortcode.'_link url="'.$url.'"]Visit[/'.$shortcode.'_link]');
    if (strpos($link,'data-festapp-consent-link') === false) throw new RuntimeException("$slug marked link missing");
    do_shortcode('['.$shortcode.' url="'.$url.'"]');
    do_shortcode('['.$shortcode.' url="'.$url.'"]');
    $handle = $namespace . '\\helper_handle';
    $name = $handle($service);
    if (count(array_keys(wp_scripts()->queue, $name, true)) !== 1) throw new RuntimeException("$slug duplicate helper");
    $callback = $namespace . '\\consent_script_attributes';
    $attrs = apply_filters('wp_script_attributes', ['id'=>$name.'-js']);
    if (!isset($attrs['data-festapp-consent'])) throw new RuntimeException("$slug consent script callback missing");
    $valid['enabled']=false; update_option($slug.'_consent', $valid);
    if (strpos(do_shortcode('['.$shortcode.'_link url="'.$url.'"]Visit[/'.$shortcode.'_link]'),'data-festapp-consent-link') !== false) throw new RuntimeException("$slug disabled link marked");
    // Manual links remain controlled by their author, including explicit rel.
    $manual='<a href="https://example.invalid/" rel="noopener noreferrer">Manual</a>';
    if (strpos(apply_filters('the_content', $manual), 'rel="noopener noreferrer"') === false) throw new RuntimeException("$slug altered a manual link");
    $malicious=$config; $malicious['providerConfig']['payload']='</script><script>alert(1)</script>';
    $escaped=$sanitize(['enabled'=>1,'export'=>wp_json_encode($malicious)]);
    update_option($slug.'_consent',$escaped);
    $attrs=apply_filters('wp_script_attributes',['id'=>$name.'-js','src'=>$service.'/embed.js']);
    if (strpos(wp_get_script_tag($attrs), '</script><script>alert(1)') !== false) throw new RuntimeException("$slug script attribute injection");
    $render=$namespace.'\\admin_page';
    if (function_exists($render)) {
        ob_start();$render();$admin=ob_get_clean();
        if (strpos($admin, 'name="_wpnonce"') === false || strpos($admin,'</textarea><script>') !== false) throw new RuntimeException("$slug settings nonce/escaping");
    }
    if (!defined('WP_UNINSTALL_PLUGIN')) define('WP_UNINSTALL_PLUGIN',true);
    include WP_PLUGIN_DIR.'/'.$slug.'/uninstall.php';
    if (get_option($slug.'_consent',null) !== null) throw new RuntimeException("$slug uninstall left consent setting");
    $checks++;
}
echo "PASS real WordPress consent imports and helper registration: $checks products\n";
