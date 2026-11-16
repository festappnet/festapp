<?php
// Simulate a co-installed earlier copy owning one existing parser entrypoint.
namespace Festapp\CmsConsent {
    function parse_export($input, array $allowed_origins, string $website_origin): ?array { return null; }
}
namespace {
    require dirname(__DIR__) . '/measurement/consent-export.php';
    require dirname(__DIR__) . '/measurement/consent-export.php';
    if (\Festapp\CmsConsent\origin_from_url('https://organizer.example/site/') !== 'https://organizer.example') {
        throw new \RuntimeException('Co-installed parser prevented origin helper installation');
    }
    if (!\Festapp\CmsConsent\positive_integer(1) || !\Festapp\CmsConsent\origin('https://organizer.example')) {
        throw new \RuntimeException('Co-installed parser prevented envelope helper installation');
    }
    echo "PASS shared CMS mixed parser load preserves installed helpers\n";
}
