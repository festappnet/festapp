<?php
require '/tests/bootstrap.php';
// Standard Joomla cache purge after changing/removing article-embedded modules.
$factory = $container->get(\Joomla\CMS\Cache\CacheControllerFactoryInterface::class);
foreach (['com_content', 'com_modules', '_system'] as $group) {
    $factory->createCacheController('callback', ['defaultgroup'=>$group])->clean();
}
echo "Cleared disposable CMS caches\n";
