<?php
/** Actual Joomla updater/HTTP transport/installer against an explicitly local feed. */
require '/tests/bootstrap.php';
use Joomla\CMS\Installer\Installer;
use Joomla\CMS\Installer\InstallerHelper;
use Joomla\CMS\Updater\Updater;

$expectedVersion = $argv[1];
$expectedSha = $argv[2];
$base = $argv[3];
$element = 'mod_vstupenky_online';
$eid = (int)$db->setQuery("SELECT extension_id FROM #__extensions WHERE type='module' AND element='mod_vstupenky_online'")->loadResult();
$site = $db->setQuery("SELECT us.update_site_id,us.location FROM #__update_sites us JOIN #__update_sites_extensions ue ON ue.update_site_id=us.update_site_id WHERE ue.extension_id=".$eid)->loadObject();
$publicFeed = 'https://raw.githubusercontent.com/festappnet/festapp/main/integrations/joomla/updates/vstupenky-online.xml';
if (!$site || $site->location !== $publicFeed) { throw new RuntimeException('Distributed manifest did not register the expected public update site'); }
$before = $db->setQuery("SELECT params FROM #__modules WHERE module='mod_vstupenky_online' ORDER BY id")->loadColumn();
$cache = json_decode($db->setQuery('SELECT manifest_cache FROM #__extensions WHERE extension_id='.$eid)->loadResult(),true);
$originalCache = $cache;
// Deliberately synthetic older-version metadata, not a historical release claim.
$cache['version'] = '1.0.0';
$db->setQuery('UPDATE #__extensions SET manifest_cache='.$db->quote(json_encode($cache)).' WHERE extension_id='.$eid)->execute();
$db->setQuery('UPDATE #__update_sites SET location='.$db->quote($base.'/updates.xml').',last_check_timestamp=0 WHERE update_site_id='.(int)$site->update_site_id)->execute();
try {
    $probe = \Joomla\CMS\Http\HttpFactory::getHttp()->get($base.'/updates.xml');
    if ($probe->code !== 200) { throw new RuntimeException('Local updater transport HTTP '.$probe->code.' '.substr($probe->body,0,160)); }
    Updater::getInstance()->findUpdates($eid, 0, Updater::STABILITY_STABLE);
    $update = $db->setQuery('SELECT version,detailsurl FROM #__updates WHERE extension_id='.$eid)->loadObject();
    if (!$update || $update->version !== $expectedVersion) { fwrite(STDERR,json_encode($app->getMessageQueue()).PHP_EOL); throw new RuntimeException('Native updater did not discover the local transport fixture'); }
    $definition = new \Joomla\CMS\Updater\Update;
    $definition->loadFromXml($update->detailsurl, Updater::STABILITY_STABLE);
    $download = $definition->get('downloadurl')->_data;
    $hash = $definition->get('sha256')->_data;
    if ($download !== $base.'/vstupenky.online.zip' || $hash !== $expectedSha) { throw new RuntimeException('Updater parsed different package or checksum'); }
    $downloaded = InstallerHelper::downloadPackage($download);
    $file = $app->get('tmp_path').'/'.$downloaded;
    if (!$downloaded || hash_file('sha256',$file) !== $expectedSha) { throw new RuntimeException('Downloaded package checksum mismatch'); }
    $unpacked = InstallerHelper::unpack($file, true);
    $installer = new Installer;
    $installer->setDatabase($db);
    if (!$installer->update($unpacked['extractdir'])) { throw new RuntimeException('Native Joomla package update failed'); }
    InstallerHelper::cleanupInstall($file,$unpacked['extractdir']);
    $installed = json_decode($db->setQuery('SELECT manifest_cache FROM #__extensions WHERE extension_id='.$eid)->loadResult(),true);
    if ($installed['version'] !== $expectedVersion) { throw new RuntimeException('Updated version not persisted'); }
    $after = $db->setQuery("SELECT params FROM #__modules WHERE module='mod_vstupenky_online' ORDER BY id")->loadColumn();
    if ($before !== $after) { throw new RuntimeException('Module settings changed during native update'); }
    echo json_encode(['joomla'=>JVERSION,'php'=>PHP_VERSION,'version'=>$expectedVersion,'sha256'=>$expectedSha,'manifest_registers_public_update_url'=>true,'native_discovery_download_checksum_install'=>true,'settings_preserved'=>true,'boundary'=>'local HTTP feed with same version/checksum/package bytes, synthetic older-version metadata; public URLs require publication readback']), "\n";
} finally {
    $db->setQuery('UPDATE #__update_sites SET location='.$db->quote($publicFeed).',last_check_timestamp=0 WHERE update_site_id='.(int)$site->update_site_id)->execute();
    $db->setQuery('UPDATE #__extensions SET manifest_cache='.$db->quote(json_encode($originalCache)).' WHERE extension_id='.$eid)->execute();
    $db->setQuery('DELETE FROM #__updates WHERE extension_id='.$eid)->execute();
}
