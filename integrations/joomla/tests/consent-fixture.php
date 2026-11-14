<?php
/** Test-only: merge JSON settings into task-owned seeded modules, then purge caches. */
require '/tests/bootstrap.php';
foreach (json_decode($argv[1] ?? '{}', true, 512, JSON_THROW_ON_ERROR) as $id => $changes) {
    $row = $db->setQuery('SELECT params FROM #__modules WHERE id=' . (int) $id . " AND module IN ('mod_vstupenky_online','mod_festapp_tickets')")->loadResult();
    if ($row === null) { throw new RuntimeException('Unknown seeded module ' . (int) $id); }
    $params = array_merge(json_decode($row, true) ?: [], $changes);
    $db->setQuery('UPDATE #__modules SET params=' . $db->quote(json_encode($params)) . ' WHERE id=' . (int) $id)->execute();
}
$factory = $container->get(\Joomla\CMS\Cache\CacheControllerFactoryInterface::class);
foreach (['com_content', 'com_modules', '_system'] as $group) {
    $factory->createCacheController('callback', ['defaultgroup' => $group])->clean();
}
echo "Updated seeded modules\n";
