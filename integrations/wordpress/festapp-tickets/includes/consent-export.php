<?php
/** Shared CMS envelope parser. Provider semantics belong to the service adapter. */
namespace Festapp\CmsConsent;
if (!function_exists(__NAMESPACE__ . '\\parse_export')) {
    function parse_export($input, array $allowed_origins, string $website_origin): ?array {
        if (!is_string($input) || strlen($input) > 16384 || $input === '') { return null; }
        $v = json_decode($input, true, 16);
        if (!is_array($v) || ($v['schemaVersion'] ?? null) !== 1 ||
            !in_array($v['serviceOrigin'] ?? null, $allowed_origins, true) ||
            ($v['websiteOrigin'] ?? null) !== $website_origin || !origin($website_origin) ||
            !is_array($v['binding'] ?? null) || !is_string($v['binding']['id'] ?? null) ||
            !preg_match('/\A[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}\z/D', $v['binding']['id']) ||
            !positive_integer($v['binding']['version'] ?? null)) { return null; }
        $c = $v['providerConfig'] ?? null;
        if (!is_array($c) || !in_array($c['provider'] ?? null, ['complianz','cookiebot','cookieconsent','wix'], true) ||
            !positive_integer($c['organization'] ?? null) || !positive_integer($c['unit'] ?? null) ||
            !is_string($c['consentRevision'] ?? null) || !preg_match('/\A[a-f0-9]{32}\z/D', $c['consentRevision']) ||
            ($c['origin'] ?? null) !== $website_origin) { return null; }
        return ['schemaVersion'=>1,'serviceOrigin'=>$v['serviceOrigin'],'websiteOrigin'=>$website_origin,
            'binding'=>['id'=>$v['binding']['id'],'version'=>$v['binding']['version']],'providerConfig'=>$c];
    }
}
if (!function_exists(__NAMESPACE__ . '\\origin_from_url')) {
    // CMS installation paths are not part of a website origin.
    function origin_from_url(string $url): string {
        $p = parse_url($url);
        if (!is_array($p) || ($p['scheme'] ?? '') !== 'https' || isset($p['user']) || isset($p['pass'])) { return ''; }
        $value = 'https://' . strtolower($p['host'] ?? '');
        if (isset($p['port']) && $p['port'] !== 443) { $value .= ':' . $p['port']; }
        return origin($value) ? $value : '';
    }
}
if (!function_exists(__NAMESPACE__ . '\\positive_integer')) {
    function positive_integer($value): bool { return is_int($value) && $value > 0 && $value <= 9007199254740991; }
}
if (!function_exists(__NAMESPACE__ . '\\origin')) {
    function origin(string $value): bool {
        $p = parse_url($value);
        return is_array($p) && ($p['scheme'] ?? '') === 'https' && !isset($p['user'],$p['pass']) &&
            !isset($p['path']) && !isset($p['query']) && !isset($p['fragment']) &&
            preg_match('/\Ahttps:\/\/[a-z0-9.-]+(?::[0-9]+)?\z/D', $value) === 1;
    }
}
