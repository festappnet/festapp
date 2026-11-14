<?php
require '/tests/bootstrap.php';
use Joomla\CMS\Language\Text;
use Joomla\CMS\Form\Form;
use Joomla\Registry\Registry;

$count = 0;
function check($condition, $message) {
    global $count;
    if (!$condition) { throw new RuntimeException($message); }
    $count++;
}
$products = [
    ['mod_vstupenky_online', 'VstupenkyOnline', 'https://vstupenky.online'],
    ['mod_festapp_tickets', 'FestappTickets', 'https://tickets.festapp.net'],
];
foreach ($products as [$element, $namespace, $origin]) {
    $app->bootModule($element, 'site');
    $helper = 'Festapp\\Module\\' . $namespace . '\\Site\\Helper\\EmbedHelper';
    check(class_exists($helper), 'Installed module namespace');
    foreach (['sale_2026', rawurlencode('žluťoučký-夜')] as $slug) {
        check($helper::validateUrl($origin . '/form/' . $slug), 'Canonical slug');
    }
    foreach ([null, [], 42, '', 'http://vstupenky.online/form/a', $origin . ':443/form/a', $origin . '@evil.invalid/form/a', $origin . '.evil.invalid/form/a', $origin . '/administrator', $origin . '/form/', $origin . '/form/a/', $origin . '/form/a?embed=1', $origin . '/form/a#x', $origin . '/form/%61', $origin . '/form/%2f', $origin . '/form/%252F', $origin . '/form/..', $origin . '/form/a%00', $origin . '/form/a b', $origin . '/form/ž', $origin . '/form/%c5%be', $origin . '/form/%FF', $origin . '/form/' . str_repeat('x', 2050), 'https://other.invalid/form/a', 'https://sub.' . substr($origin, 8) . '/form/a', "\n" . $origin . '/form/a', $origin . '/form/a" onload="alert(1)'] as $slug) {
        check(!$helper::validateUrl($slug), 'Reject unsafe URL');
        check(!str_contains($helper::render(['url' => $slug]), '<iframe'), 'Invalid value renders no frame');
    }
    $url = $origin . '/form/test';
    foreach (['auto', 'fixed'] as $mode) {
        foreach ([0, 1] as $inherit) {
            $params = ['url'=>$url, 'mode'=>$mode, 'inherit_style'=>$inherit, 'iframe_title'=>'"><script>alert(1)</script>'];
            $s = $helper::settings($params);
            $html = $helper::render($params);
            check(str_contains($html, 'data-festapp-embed-host'), 'Host wrapper');
            check(str_contains($html, 'data-festapp-embed '), 'Frame marker');
            check(str_contains($html, 'data-festapp-height="fixed"') === ($mode === 'fixed'), 'Fixed helper');
            check(!str_contains($html, 'data-festapp-style'), 'Saved form exclusively owns appearance');
            check(!str_contains($html, '<script>') && str_contains($html, '&lt;script&gt;'), 'Escaped title');
            check(str_contains($html, '?embed=1') && str_contains($html, 'rel="noopener noreferrer"'), 'Embed and fallback');
        }
    }
    foreach ([240=>240, 4000=>4000, 239=>800, 4001=>800, -1=>800, 'bad'=>800] as $input=>$expected) {
        check($helper::settings(['url'=>$url, 'height'=>$input])['height'] === $expected, 'Height bounds');
    }
    check($helper::settings(['url'=>$url, 'height'=>[]])['height'] === 800, 'Malformed height');
    foreach (['unit', 'host', 'invalid', ['host']] as $measurement) {
        check(str_contains($helper::render(['url'=>$url, 'measurement'=>$measurement]), 'data-festapp-datalayer') === ($measurement === 'host'), 'Explicit measurement destination');
    }
    $xml = simplexml_load_file(JPATH_ROOT . '/modules/' . $element . '/' . $element . '.xml');
    check((string)$xml->xpath('//fieldset[@name="advanced"]/field[@name="cache"]')[0]['default'] === '0', 'Module cache disabled');
    check((string)$xml->xpath('//field[@name="consent_link"]')[0]['default'] === '0', 'Consent transfer is off by default');
    check((string)$xml->xpath('//field[@name="output"]')[0]['default'] === 'embed', 'Embedded output by default');
    $form = new Form($element);
    $form->load('<form>' . $xml->config->fields->asXML() . '</form>');
    check(!str_contains($helper::render(['url'=>$url]), 'data-festapp-datalayer'), 'Saved module without measurement remains Unit');
    $accepted = $form->validate(new Registry(['params'=>['url'=>$url, 'mode'=>'auto','height'=>800]]));
    if (!$accepted) { foreach ($form->getErrors() as $error) { fwrite(STDERR, (string)$error . PHP_EOL); } }
    check($accepted, 'Actual Joomla form accepts saved URL');
    check(!$form->validate(new Registry(['params'=>['url'=>$origin.'/form/a?x=1']])), 'Actual Joomla rule rejects query');
    // Native Joomla filter + rule on the consent settings, as in the module editor.
    \Joomla\CMS\Factory::getLanguage()->load($element, JPATH_ROOT . '/modules/' . $element, 'en-GB', true);
    $consent = ['url'=>$url,'consent_link'=>'1','consent_provider'=>'cookiebot','consent_organization'=>' 1','consent_unit'=>'2','consent_revision'=>str_repeat('a',32),'consent_cbid'=>'12345678-1234-1234-1234-123456789abc','consent_origin'=>'https://poradatel.example ','consent_valid_from'=>'2026-11-11T00:00:00.000Z','consent_max_age'=>'15552000'];
    $filtered = $form->filter(['params'=>$consent]);
    check($filtered['params']['consent_organization'] === '1' && $filtered['params']['consent_origin'] === 'https://poradatel.example', 'Native filter trims consent settings');
    check($form->validate($filtered), 'Native form accepts complete consent settings');
    check($helper::consent($filtered['params'])['json'] === '{"provider":"cookiebot","organization":1,"unit":2,"consentRevision":"' . str_repeat('a',32) . '","cbid":"12345678-1234-1234-1234-123456789abc","origin":"https://poradatel.example","consentValidFrom":"2026-11-11T00:00:00.000Z","maxAgeSeconds":15552000}', 'Saved settings produce the documented helper JSON');
    foreach ([['consent_cbid'=>'bad'], ['consent_valid_from'=>''], ['consent_origin'=>'']] as $change) {
        $filtered = $form->filter(['params'=>$change + $consent]);
        if (array_values($change) === ['']) { check(($filtered['params'][array_key_first($change)] ?? '') === '', 'Empty value is never filled in'); }
        check(!$form->validate($filtered), 'Native form rejects incomplete consent settings');
        $errors = $form->getErrors();
        $message = (string) end($errors)->getMessage();
        check(str_contains($message, ['consent_cbid'=>'CBID','consent_valid_from'=>'UTC','consent_origin'=>'origin'][array_key_first($change)]) && !str_contains($message, '%s'), 'Native error names the setting: ' . $message);
    }
    check($form->validate($form->filter(['params'=>['consent_link'=>'0','consent_cbid'=>'bad','consent_provider'=>''] + $consent])), 'Disabled consent settings never block saving');
    $cc = ['url'=>$url,'consent_link'=>'1','consent_provider'=>'cookieconsent','consent_organization'=>'1','consent_unit'=>'2','consent_revision'=>str_repeat('a',32),'consent_cc_revision'=>'3'];
    check($form->validate($form->filter(['params'=>$cc])), 'Native form accepts CookieConsent settings with default categories');
    check(!$form->validate($form->filter(['params'=>['consent_cc_marketing'=>'analytics'] + $cc])), 'Native form rejects equal categories');
    $field = $form->getField('consent_valid_from', 'params');
    check($field instanceof \Joomla\CMS\Form\FormField && preg_match('/placeholder="\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z"/', $field->input) === 1 && str_contains($field->input, 'value=""'), 'Empty cutoff shows only a placeholder suggestion');
    foreach (['en-GB', 'cs-CZ'] as $locale) {
        $ini = JPATH_ROOT . '/modules/' . $element . '/language/' . $locale . '/' . $element . '.ini';
        check(is_file($ini), 'Installed translation');
        $strings = parse_ini_file($ini);
        check(is_array($strings), 'Translation INI parses');
        $prefix = strtoupper($element);
        foreach (['CONSENT_TAB','CONSENT_INTRO','CONSENT_LINK','CONSENT_PROVIDER','CONSENT_INVALID','CONSENT_CBID','CONSENT_ORIGIN','CONSENT_VALID_FROM','CONSENT_MAX_AGE','CONSENT_CC_REVISION','CONSENT_CC_CATEGORIES','OUTPUT','OUTPUT_LINK','LINK_DEFAULT','LINK_CLASS','START','ONBOARDING','CENTRAL_APPEARANCE','URL','URL_HELP','TITLE','TITLE_HELP','MODE','AUTO','FIXED','HEIGHT','MEASUREMENT','MEASUREMENT_HELP','MEASUREMENT_UNIT','MEASUREMENT_HOST','CACHE','DEFAULT_TITLE','INVALID_URL','FALLBACK','DISCLOSURE','SERVICE','XML_DESCRIPTION'] as $key) {
            check(isset($strings[$prefix . '_' . $key]) && $strings[$prefix . '_' . $key] !== '', 'Required translation: ' . $key);
        }
        check(!isset($strings[$prefix . '_INHERIT_STYLE']) && !isset($strings[$prefix . '_APPEARANCE']), 'No local appearance override translations');
        $language = \Joomla\CMS\Language\Language::getInstance($locale);
        check($language->load($element, JPATH_ROOT . '/modules/' . $element, $locale, true), 'Joomla loads product locale');
        check($language->_(strtoupper($element).'_START') === $strings[strtoupper($element).'_START'], 'Native localized onboarding');
        check(str_contains($strings[strtoupper($element).'_ONBOARDING'], '{loadmoduleid ID}'), 'Article onboarding');
    }
}
echo json_encode(['assertions'=>$count,'joomla'=>JVERSION,'php'=>PHP_VERSION], JSON_PRETTY_PRINT), "\n";
