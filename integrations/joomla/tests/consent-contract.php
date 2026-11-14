<?php
// Consent transfer settings, generated helper configuration and link markup.
// Real generated module classes; only the few Joomla APIs they touch are stubbed.
namespace Joomla\CMS\Language {
    final class Text {
        public static function _($key) { return $key; }
        public static function sprintf($key, ...$args) { return $key . ':' . implode('|', $args); }
    }
}
namespace Joomla\Registry {
    final class Registry {
        public function __construct(private array $data = []) {}
        public function get($path, $default = null) {
            $value = $this->data;
            foreach (explode('.', $path) as $key) {
                if (!is_array($value) || !array_key_exists($key, $value)) { return $default; }
                $value = $value[$key];
            }
            return $value;
        }
    }
}
namespace Joomla\CMS\Form {
    class Form {}
    abstract class FormRule {}
    interface FormFilterInterface {}
}
namespace Joomla\CMS\Form\Field {
    class TextField {
        public $element; public $value; protected $hint = '';
        protected function getInput() { return ['value' => $this->value, 'hint' => $this->hint]; }
        public function input() { return $this->getInput(); }
    }
}
namespace Joomla\CMS\Uri {
    final class Uri {
        public static string $root = 'https://site.example/';
        public function __construct(private string $url) {}
        public static function root() { return self::$root; }
        public static function getInstance($url) { return new self($url); }
        public function getScheme() { return parse_url($this->url, PHP_URL_SCHEME); }
        public function getHost() { return parse_url($this->url, PHP_URL_HOST); }
        public function getPort() { return parse_url($this->url, PHP_URL_PORT); }
    }
}
namespace {
    define('_JEXEC', 1);
    use Joomla\Registry\Registry;
    use Joomla\CMS\Uri\Uri;

    $count = 0;
    function check($condition, $message) {
        global $count;
        if (!$condition) { throw new RuntimeException($message); }
        $count++;
    }
    $modules = getenv('FESTAPP_JOOMLA_MODULE_ROOT') ?: __DIR__ . '/../build';
    $legacy = getenv('FESTAPP_JOOMLA_LEGACY_HELPER');
    $revision = 'a' . str_repeat('b', 30) . 'c';
    $cookiebot = ['consent_link' => '1', 'consent_provider' => 'cookiebot', 'consent_organization' => '1', 'consent_unit' => '2',
        'consent_revision' => $revision, 'consent_cbid' => '12345678-1234-1234-1234-123456789abc', 'consent_origin' => 'https://poradatel.example',
        'consent_valid_from' => '2026-11-11T00:00:00.000Z', 'consent_max_age' => '15552000'];
    $cookieconsent = ['consent_link' => 1, 'consent_provider' => 'cookieconsent', 'consent_organization' => 1, 'consent_unit' => 2,
        'consent_revision' => $revision, 'consent_cc_revision' => '42', 'consent_cc_analytics' => 'analytics', 'consent_cc_marketing' => 'marketing'];
    foreach ([['mod_vstupenky_online', 'VstupenkyOnline', 'https://vstupenky.online'], ['mod_festapp_tickets', 'FestappTickets', 'https://tickets.festapp.net']] as [$element, $namespace, $origin]) {
        require "$modules/$element/src/Helper/EmbedHelper.php";
        require "$modules/$element/src/Rule/ConsentRule.php";
        require "$modules/$element/src/Filter/ConsentFilter.php";
        require "$modules/$element/src/Field/ConsentsuggestionField.php";
        $helper = "Festapp\\Module\\$namespace\\Site\\Helper\\EmbedHelper";
        $rule = new ("Festapp\\Module\\$namespace\\Site\\Rule\\ConsentRule");
        $filter = new ("Festapp\\Module\\$namespace\\Site\\Filter\\ConsentFilter");
        $url = "$origin/form/ples-2027";

        // Exact helper attribute JSON from the documented examples.
        $c = $helper::consent($cookiebot);
        check($c['provider'] === 'cookiebot', 'Cookiebot provider');
        check($c['json'] === '{"provider":"cookiebot","organization":1,"unit":2,"consentRevision":"' . $revision . '","cbid":"12345678-1234-1234-1234-123456789abc","origin":"https://poradatel.example","consentValidFrom":"2026-11-11T00:00:00.000Z","maxAgeSeconds":15552000}', 'Cookiebot JSON');
        check($c['attributes'] === ['data-cookieconsent' => 'ignore', 'data-festapp-consent' => $c['json']], 'Cookiebot keeps helper outside auto-blocking');
        $c = $helper::consent($cookieconsent);
        check($c['json'] === '{"provider":"cookieconsent","organization":1,"unit":2,"consentRevision":"' . $revision . '","revision":42}', 'CookieConsent JSON with default categories');
        check($c['attributes'] === ['data-festapp-consent' => $c['json']], 'CookieConsent needs no Cookiebot marker');
        check($helper::consent(['consent_cc_analytics' => '', 'consent_cc_marketing' => null] + $cookieconsent)['json'] === $c['json'], 'Empty category names use defaults');
        check($helper::consent(['consent_cc_analytics' => 'statistika', 'consent_cc_marketing' => 'reklama'] + $cookieconsent)['json']
            === '{"provider":"cookieconsent","organization":1,"unit":2,"consentRevision":"' . $revision . '","revision":42,"categories":{"analytics":"statistika","marketing":"reklama"}}', 'Custom categories');
        check($helper::consent(['consent_cc_analytics' => 'měření'] + $cookieconsent)['json'] === '{"provider":"cookieconsent","organization":1,"unit":2,"consentRevision":"' . $revision . '","revision":42,"categories":{"analytics":"měření","marketing":"marketing"}}', 'Unicode category');
        check($helper::consent(['consent_organization' => ' 1 ', 'consent_cbid' => ' 12345678-1234-1234-1234-123456789ABC ', 'consent_origin' => "https://poradatel.example\n", 'consent_valid_from' => "\t2026-11-11T00:00:00.000Z\n"] + $cookiebot)['json']
            === '{"provider":"cookiebot","organization":1,"unit":2,"consentRevision":"' . $revision . '","cbid":"12345678-1234-1234-1234-123456789ABC","origin":"https://poradatel.example","consentValidFrom":"2026-11-11T00:00:00.000Z","maxAgeSeconds":15552000}', 'Trimmed saved values');
        check(str_contains($helper::consent(['consent_origin' => 'https://www.poradatel.example:8443', 'consent_max_age' => 31536000] + $cookiebot)['json'], '"origin":"https://www.poradatel.example:8443","consentValidFrom":"2026-11-11T00:00:00.000Z","maxAgeSeconds":31536000'), 'Port and maximum age');

        // Disabled by default; never configured without the explicit switch.
        foreach ([null, '', '0', 0, false, 'yes', 2, ['1']] as $enabled) {
            $params = ['consent_link' => $enabled] + $cookiebot;
            check(!$helper::consentEnabled($params) && $helper::consent($params) === null && $helper::consentErrors($params) === [], 'Consent transfer is opt-in');
        }
        $missing = $cookiebot;
        unset($missing['consent_link']);
        check($helper::consent($missing) === null, 'Missing switch stays off');

        // Fail closed for everything the service helper would reject.
        $invalid = [
            ['consent_provider' => 'complianz'], ['consent_provider' => 'Cookiebot'], ['consent_provider' => null],
            ['consent_organization' => '0'], ['consent_organization' => '-1'], ['consent_organization' => '1.5'], ['consent_organization' => '01'],
            ['consent_organization' => '9007199254740992'], ['consent_organization' => 1.0], ['consent_unit' => ''], ['consent_unit' => 'x'],
            ['consent_revision' => 'x'], ['consent_revision' => strtoupper($revision)], ['consent_revision' => $revision . 'a'], ['consent_revision' => null],
            ['consent_cbid' => ''], ['consent_cbid' => 'bad'], ['consent_cbid' => '12345678-1234-1234-1234-123456789abcd'],
            ['consent_origin' => ''], ['consent_origin' => 'http://poradatel.example'], ['consent_origin' => 'https://poradatel.example/'],
            ['consent_origin' => 'https://poradatel.example/path'], ['consent_origin' => 'https://Poradatel.example'], ['consent_origin' => 'https://poradatel.example:443'],
            ['consent_origin' => 'https://poradatel.example:0'], ['consent_origin' => 'https://poradatel.example:65536'], ['consent_origin' => 'https://user@poradatel.example'],
            ['consent_origin' => 'https://localhost'], ['consent_origin' => 'https://127.0.0.1'], ['consent_origin' => 'https://poradatel.example?x'],
            ['consent_origin' => 'https://poradatel.example.'], ['consent_origin' => 'https://žluť.example'],
            ['consent_valid_from' => ''], ['consent_valid_from' => '2026-11-11'], ['consent_valid_from' => '2026-11-11T00:00:00Z'],
            ['consent_valid_from' => '2026-02-31T00:00:00.000Z'], ['consent_valid_from' => '2026-11-11T24:00:00.000Z'], ['consent_valid_from' => '2026-11-11T00:00:00.000+01:00'],
            ['consent_valid_from' => '2026-11-11T00:00:00.0000Z'],
            ['consent_max_age' => '0'], ['consent_max_age' => '-1'], ['consent_max_age' => '31536001'], ['consent_max_age' => '1.5'], ['consent_max_age' => ''],
        ];
        foreach ($invalid as $change) {
            $params = $change + $cookiebot;
            check($helper::consent($params) === null && $helper::consentErrors($params) !== [], 'Invalid Cookiebot setting fails closed: ' . json_encode($change));
        }
        foreach ([['consent_cc_revision' => '0'], ['consent_cc_revision' => ''], ['consent_cc_revision' => '-3'], ['consent_cc_revision' => 'v42'],
                  ['consent_cc_analytics' => 'marketing'], ['consent_cc_analytics' => 'same', 'consent_cc_marketing' => 'same'],
                  ['consent_cc_analytics' => str_repeat('a', 129)], ['consent_cc_marketing' => "a\x00"], ['consent_cc_marketing' => "\xff"],
                  ['consent_cc_analytics' => ['analytics']], ['consent_revision' => ''], ['consent_unit' => '0']] as $change) {
            $params = $change + $cookieconsent;
            check($helper::consent($params) === null && $helper::consentErrors($params) !== [], 'Invalid CookieConsent setting fails closed: ' . json_encode($change));
        }
        check($helper::consent(['consent_cc_analytics' => str_repeat('a', 128)] + $cookieconsent) !== null, 'Longest category name');
        check($helper::consent(['consent_cc_analytics' => str_repeat('😀', 65)] + $cookieconsent) === null, 'Category length in UTF-16 units');
        check($helper::consentErrors(['consent_cbid' => 'bad', 'consent_max_age' => '0'] + $cookiebot) === ['CONSENT_CBID', 'CONSENT_MAX_AGE'], 'Named setting errors');
        check($helper::consentErrors(['consent_provider' => ''] + $cookiebot) === ['CONSENT_PROVIDER'], 'Provider must be chosen');

        // Legacy link markup stays byte-identical unless the page helper is configured.
        $base = ['url' => $url];
        foreach ([$base, $base + ['mode' => 'fixed', 'measurement' => 'host'], $base + $cookiebot] as $params) {
            $html = $helper::render($params);
            check(str_contains($html, '<p><a href="' . $url . '" target="_blank" rel="noopener noreferrer">' . strtoupper($element) . '_FALLBACK</a></p></div>'), 'Legacy fallback link');
            check(!str_contains($html, 'data-festapp-consent'), 'Unconfigured link is unmarked');
        }
        if ($legacy) {
            $old = str_replace(['@@NAMESPACE@@', '@@ORIGIN@@', '@@ELEMENT@@', '@@KEY@@'], ['Legacy' . $namespace, $origin, $element, strtoupper($element)], file_get_contents($legacy));
            eval('?>' . $old);
            $oldHelper = "Festapp\\Module\\Legacy$namespace\\Site\\Helper\\EmbedHelper";
            foreach (['auto', 'fixed'] as $mode) {
                foreach (['unit', 'host'] as $measurement) {
                    $params = ['url' => $url, 'mode' => $mode, 'measurement' => $measurement, 'height' => 640, 'iframe_title' => '"<b>'] + $cookiebot;
                    check($helper::render($params) === $oldHelper::render($params), 'Saved modules render exactly as before');
                }
            }
        }
        $html = $helper::render($base + $cookiebot, true);
        check(str_contains($html, '<p><a href="' . $url . '" target="_blank" data-festapp-consent-link>' . strtoupper($element) . '_FALLBACK</a></p>'), 'Configured fallback is marked and keeps its opener');
        check(!str_contains($html, 'noopener') && !str_contains($html, 'noreferrer') && !str_contains($html, 'referrerpolicy'), 'Marked link has no opener or referrer restriction');
        check(str_contains($html, '<iframe data-festapp-embed src="' . $url . '?embed=1"'), 'Marked fallback keeps the embedded form');

        // Link-only output for menus and the home page.
        $link = $helper::render($base + ['output' => 'link']);
        check($link === '<div class="' . $element . ' ' . $element . '-link"><p><a href="' . $url . '" target="_blank" rel="noopener noreferrer">' . strtoupper($element) . '_LINK_DEFAULT</a></p></div>', 'Unmarked link-only output');
        check(!str_contains($link, '<iframe') && !str_contains($link, 'data-festapp-embed'), 'Link-only output has no frame');
        $link = $helper::render($base + ['output' => 'link', 'link_text' => ' Vstupenky <b>2027</b> ', 'link_class' => 'btn btn-primary'], true);
        check($link === '<div class="' . $element . ' ' . $element . '-link"><p><a class="btn btn-primary" href="' . $url . '" target="_blank" data-festapp-consent-link>Vstupenky &lt;b&gt;2027&lt;/b&gt;</a></p></div>', 'Marked link-only button');
        foreach (['btn" onclick="x', 'a<b', str_repeat('a', 201), ['btn']] as $class) {
            check(!str_contains($helper::render($base + ['output' => 'link', 'link_class' => $class]), '<a class='), 'Unsafe link class is dropped');
        }
        foreach ([null, 'embed', 'LINK', ['link'], 'iframe'] as $output) {
            check(str_contains($helper::render($base + ['output' => $output]), '<iframe'), 'Unknown output keeps the embedded form');
        }
        check(str_contains($helper::render($base + ['link_text' => 'Koupit']), '>Koupit</a>'), 'Custom fallback text');
        check(!str_contains($helper::render(['url' => $url . '?x', 'output' => 'link'] + $cookiebot, true), '<a'), 'Invalid URL renders no link');

        // Save-time validation and documented suggestions, never for disabled transfer.
        $input = fn (array $params) => new Registry(['params' => $params]);
        check($rule->test(new SimpleXMLElement('<field name="consent_link"/>'), '0', 'params', $input(['consent_provider' => 'bad'])) === true, 'Disabled transfer saves');
        check($rule->test(new SimpleXMLElement('<field name="consent_link"/>'), '1', 'params', $input($cookiebot)) === true, 'Valid transfer saves');
        try {
            $rule->test(new SimpleXMLElement('<field name="consent_link"/>'), '1', 'params', $input(['consent_cbid' => 'x'] + $cookiebot));
            check(false, 'Invalid transfer must be rejected');
        } catch (UnexpectedValueException $error) {
            check($error->getMessage() === strtoupper($element) . '_CONSENT_INVALID:' . strtoupper($element) . '_CONSENT_CBID', 'Rejected setting is named');
        }
        $field = fn ($name) => new SimpleXMLElement('<field name="' . $name . '"/>');
        $empty = ['consent_origin' => '', 'consent_valid_from' => ''] + $cookiebot;
        // Empty values are never filled in at save; Joomla skips filters for them anyway.
        foreach (['consent_origin', 'consent_valid_from'] as $name) {
            check($filter->filter($field($name), '', 'params', $input($empty)) === '', 'Empty setting stays empty');
            check($helper::consent($empty) === null, 'Empty Cookiebot origin or cutoff fails closed');
        }
        check($filter->filter($field('consent_cbid'), " 12345678-1234-1234-1234-123456789abc\n", 'params', $input($empty)) === '12345678-1234-1234-1234-123456789abc', 'Settings are trimmed');
        check($filter->filter($field('consent_unit'), ['2'], 'params', $input($empty)) === '', 'Non-text setting is discarded');
        // Placeholder suggestions only, from the site address and the current moment.
        $suggest = "Festapp\\Module\\$namespace\\Site\\Field\\ConsentsuggestionField";
        $before = gmdate('Y-m-d\TH:i:s');
        $now = $suggest::suggestion('now');
        check($helper::instant($now) && substr($now, 0, 19) >= $before && strtotime($now) <= time() + 1, 'Cutoff suggestion is the current UTC moment');
        check($suggest::suggestion('origin', 'https://www.example.cz/') === 'https://www.example.cz', 'Origin suggestion from the HTTPS site');
        check($suggest::suggestion('origin', 'https://WWW.Example.cz:8443/joomla/') === 'https://www.example.cz:8443', 'Origin suggestion is serialized exactly');
        check($suggest::suggestion('origin', 'https://www.example.cz:443/') === 'https://www.example.cz', 'Default port omitted');
        foreach (['http://www.example.cz/', 'https://localhost/', 'https://127.0.0.1/'] as $root) {
            check($suggest::suggestion('origin', $root) === '', 'No unsafe origin suggestion: ' . $root);
        }
        check($suggest::suggestion('other', 'https://www.example.cz/') === '', 'Unknown suggestion is empty');
        $box = new $suggest();
        $box->element = $field('consent_valid_from');
        $box->element['suggest'] = 'now';
        $box->value = '';
        check($helper::instant($box->input()['hint']) && $box->input()['value'] === '', 'Empty field shows only a placeholder');
        $box = new $suggest();
        $box->element = $field('consent_valid_from');
        $box->element['suggest'] = 'now';
        $box->value = '2026-01-01T00:00:00.000Z';
        check($box->input() === ['value' => '2026-01-01T00:00:00.000Z', 'hint' => ''], 'Saved value is shown unchanged');
    }
    echo json_encode(['assertions' => $count, 'legacy_comparison' => (bool) $legacy, 'php' => PHP_VERSION]), "\n";
}
