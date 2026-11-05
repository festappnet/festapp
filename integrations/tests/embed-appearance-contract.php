<?php
// Real adapter renderers with only the CMS APIs stubbed. No network or CMS state.
namespace Joomla\CMS\Language {
    final class Text {
        public static function _($key) { return $key; }
    }
}
namespace {
    define('ABSPATH', '/');
    define('_JEXEC', true);
    function wp_get_environment_type() { return 'production'; }
    function wp_strip_all_tags($value) { return strip_tags($value); }
    function esc_attr($value) { return htmlspecialchars($value, ENT_QUOTES, 'UTF-8'); }
    function esc_html__($value, $domain) { return esc_attr($value); }
    function esc_url($value) { return esc_attr($value); }
    function __($value, $domain) { return $value; }
    function wp_enqueue_style($handle) {}
    function wp_enqueue_script($handle, $url, ...$args) { $GLOBALS['helpers'][] = $url; }
    function shortcode_atts($defaults, $attributes, $name) { return array_intersect_key($attributes, $defaults) + $defaults; }
    function check($condition, $message) {
        if (!$condition) throw new \RuntimeException($message);
    }
    $root = dirname(__DIR__);
    $count = 0;
    foreach ([['vstupenky-online', 'VstupenkyOnline', 'https://vstupenky.online'],
              ['festapp-tickets', 'FestappTickets', 'https://tickets.festapp.net']] as [$product, $namespace, $origin]) {
        require "$root/wordpress/$product/includes/embed.php";
        $module = 'mod_' . str_replace('-', '_', $product);
        require "$root/joomla/build/$module/src/Helper/EmbedHelper.php";
        $joomla = 'Festapp\\Module\\' . $namespace . '\\Site\\Helper\\EmbedHelper';
        $wordpress = $namespace . '\\render';
        foreach (['auto', 'fixed'] as $mode) {
            foreach ([false, true] as $obsoletePreference) {
                $GLOBALS['helpers'] = [];
                $url = "$origin/form/ples-2027";
                $attrs = ['url' => $url, 'mode' => $mode, 'inheritStyle' => $obsoletePreference,
                          'inherit_style' => $obsoletePreference ? 'true' : 'false'];
                $outputs = [$wordpress($attrs), $joomla::render($attrs)];
                check($GLOBALS['helpers'] === ["$origin/embed.js"], 'WordPress always loads shared helper');
                foreach ($outputs as $html) {
                    check(str_contains($html, 'data-festapp-embed-host'), 'Shared host wrapper');
                    check(str_contains($html, '<iframe data-festapp-embed '), 'Shared protocol');
                    check(!str_contains($html, 'data-festapp-style'), 'No local appearance authority');
                    check(str_contains($html, 'data-festapp-height="fixed"') === ($mode === 'fixed'), 'Height is independent of appearance');
                    check(str_contains($html, "$url?embed=1"), 'Saved public form address');
                    $count++;
                }
            }
        }
    }
    echo "PASS $count WordPress/Joomla renderer cases (CMS APIs stubbed)\n";
}
