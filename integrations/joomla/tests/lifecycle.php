<?php
/** Destructive lifecycle checks restricted to task-owned disposable Joomla. */
require '/tests/bootstrap.php';
use Joomla\CMS\Installer\Installer;

$element = 'mod_vstupenky_online';
$id = (int)$db->setQuery("SELECT extension_id FROM #__extensions WHERE element='mod_vstupenky_online' AND type='module'")->loadResult();
$other = $db->setQuery("SELECT params FROM #__modules WHERE module='mod_festapp_tickets' ORDER BY id")->loadColumn();
if (!$id || !$other) { throw new RuntimeException('Both installed products required'); }
$installer = new Installer;
$installer->setDatabase($db);
if (!$installer->uninstall('module', $id, 0)) { throw new RuntimeException('Native uninstall failed'); }
if ($db->setQuery("SELECT COUNT(*) FROM #__modules WHERE module='mod_vstupenky_online'")->loadResult() != 0) { throw new RuntimeException('Uninstalled modules remain'); }
if (is_dir(JPATH_ROOT.'/modules/'.$element)) { throw new RuntimeException('Uninstalled module files remain'); }
$after = $db->setQuery("SELECT params FROM #__modules WHERE module='mod_festapp_tickets' ORDER BY id")->loadColumn();
if ($other !== $after || !is_file(JPATH_ROOT.'/modules/mod_festapp_tickets/src/Helper/EmbedHelper.php')) { throw new RuntimeException('Other product changed'); }
echo json_encode(['joomla'=>JVERSION,'uninstalled'=>$element,'other_product_settings_preserved'=>true]), "\n";
