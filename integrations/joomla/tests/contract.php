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
            check($s['helper'] === ($mode === 'auto' || $inherit === 1), 'Helper conditions');
            check(str_contains($html, 'data-festapp-embed-host'), 'Host wrapper');
            check(str_contains($html, 'data-festapp-embed ') || !$s['helper'], 'Frame marker');
            check(str_contains($html, 'data-festapp-height="fixed"') === ($mode === 'fixed' && $inherit === 1), 'Fixed helper');
            check(str_contains($html, 'data-festapp-style="inherit"') === ($inherit === 1), 'Appearance');
            check(!str_contains($html, '<script>') && str_contains($html, '&lt;script&gt;'), 'Escaped title');
            check(str_contains($html, '?embed=1') && str_contains($html, 'rel="noopener noreferrer"'), 'Embed and fallback');
        }
    }
    foreach ([240=>240, 4000=>4000, 239=>800, 4001=>800, -1=>800, 'bad'=>800] as $input=>$expected) {
        check($helper::settings(['url'=>$url, 'height'=>$input])['height'] === $expected, 'Height bounds');
    }
    check($helper::settings(['url'=>$url, 'height'=>[]])['height'] === 800, 'Malformed height');
    $xml = simplexml_load_file(JPATH_ROOT . '/modules/' . $element . '/' . $element . '.xml');
    check((string)$xml->config->fields->fieldset[1]->field[0]['default'] === '0', 'Module cache disabled');
    $form = new Form($element);
    $form->load('<form>' . $xml->config->fields->asXML() . '</form>');
    $accepted = $form->validate(new Registry(['params'=>['url'=>$url, 'mode'=>'auto','height'=>800,'inherit_style'=>1]]));
    if (!$accepted) { foreach ($form->getErrors() as $error) { fwrite(STDERR, (string)$error . PHP_EOL); } }
    check($accepted, 'Actual Joomla form accepts saved URL');
    check(!$form->validate(new Registry(['params'=>['url'=>$origin.'/form/a?x=1']])), 'Actual Joomla rule rejects query');
    foreach (['en-GB', 'cs-CZ'] as $locale) {
        $ini = JPATH_ROOT . '/modules/' . $element . '/language/' . $locale . '/' . $element . '.ini';
        check(is_file($ini), 'Installed translation');
        $strings = parse_ini_file($ini);
        check(count($strings) === 19, 'All translated strings parse');
        $language = \Joomla\CMS\Language\Language::getInstance($locale);
        check($language->load($element, JPATH_ROOT . '/modules/' . $element, $locale, true), 'Joomla loads product locale');
        check($language->_(strtoupper($element).'_START') === $strings[strtoupper($element).'_START'], 'Native localized onboarding');
        check(str_contains($strings[strtoupper($element).'_ONBOARDING'], '{loadmoduleid ID}'), 'Article onboarding');
    }
}
echo json_encode(['assertions'=>$count,'joomla'=>JVERSION,'php'=>PHP_VERSION], JSON_PRETTY_PRINT), "\n";
