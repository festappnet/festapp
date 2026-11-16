<?php
// Shared envelope security only, never an assertion of server approval or live CMP.
$wordpress = ($argv[1] ?? '') === '--wordpress';
if ($wordpress) {
    define('ABSPATH', '/');
    $GLOBALS['wp_parse_url_calls'] = 0;
    function wp_parse_url($url) {
        $GLOBALS['wp_parse_url_calls']++;
        return parse_url($url);
    }
    require dirname(__DIR__) . '/wordpress/vstupenky-online/includes/consent-export.php';
} else {
    require dirname(__DIR__) . '/measurement/consent-export.php';
}
use function Festapp\CmsConsent\parse_export;
function check($ok, $message) { if (!$ok) { throw new RuntimeException($message); } }
$origin = 'https://organizer.example'; $service = 'https://tickets.example';
$value = ['schemaVersion'=>1,'serviceOrigin'=>$service,'websiteOrigin'=>$origin,
    'binding'=>['id'=>'11111111-1111-1111-1111-111111111111','version'=>7],
    'providerConfig'=>['provider'=>'cookieconsent','organization'=>1,'unit'=>2,'consentRevision'=>str_repeat('a',32),'origin'=>$origin,
        'revision'=>42,'categories'=>['analytics'=>'statistika návštěv','marketing'=>'<script>reklama</script>']]];
$raw = json_encode($value, JSON_UNESCAPED_UNICODE);
check(parse_export($raw,[$service],$origin) === $value, 'Unicode envelope preserved without competing provider validation');
foreach (['complianz','cookiebot','cookieconsent','wix'] as $provider) {
    $v=$value;
    $v['providerConfig']=['provider'=>$provider,'organization'=>1,'unit'=>2,'consentRevision'=>str_repeat('a',32),'origin'=>$origin];
    check(parse_export(json_encode($v),[$service],$origin) === $v, 'Provider-only export accepted');
}
foreach (['{','null','[]',str_repeat(' ',16385)] as $bad) { check(parse_export($bad,[$service],$origin) === null,'malformed/oversized rejected'); }
foreach (['schemaVersion'=>2,'serviceOrigin'=>'https://foreign.example','websiteOrigin'=>'https://foreign.example','binding'=>['id'=>'wrong','version'=>7]] as $key=>$bad) {
    $v=$value;$v[$key]=$bad;check(parse_export(json_encode($v),[$service],$origin) === null,'foreign/version/binding rejected');
}
foreach ([0,1.5,'7',null,9007199254740992] as $bad) {
    $v=$value;$v['binding']['version']=$bad;check(parse_export(json_encode($v),[$service],$origin) === null,'invalid numeric version rejected');
}
check(\Festapp\CmsConsent\origin_from_url('https://Organizer.Example:443/subdirectory/') === $origin, 'CMS installation path and default port normalize to origin');
check(\Festapp\CmsConsent\origin_from_url('https://organizer.example:8443/subdirectory/') === 'https://organizer.example:8443', 'non-default port retained');
check(\Festapp\CmsConsent\origin_from_url('https://user@organizer.example/') === '', 'credentialed CMS URL rejected');
echo "PASS shared CMS export envelope security (21 cases)\n";

if ($wordpress) { check($GLOBALS['wp_parse_url_calls'] > 0, 'Generated WordPress adapter uses its CMS URL API'); echo "PASS generated WordPress URL API binding\n"; }
