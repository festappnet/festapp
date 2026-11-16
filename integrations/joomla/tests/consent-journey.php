<?php
// Called inside the wrapper-owned installed Joomla; CMS API and renderer are real.
require '/tests/bootstrap.php';
use Joomla\CMS\Table\Table;
$raw = file_get_contents('/tests/journey-export.json');
$config = json_decode($raw,true);
$db->setQuery("DELETE mm FROM #__modules_menu mm JOIN #__modules m ON m.id=mm.moduleid WHERE m.module='mod_vstupenky_online'")->execute();
$db->setQuery("DELETE FROM #__modules WHERE module='mod_vstupenky_online'")->execute();
$row=Table::getInstance('Module','JTable');
$row->bind(['title'=>'Ověření přenosu souhlasu','module'=>'mod_vstupenky_online','position'=>'sidebar-right','published'=>1,'ordering'=>1,'access'=>1,'showtitle'=>0,'client_id'=>0,'language'=>'*',
    'params'=>json_encode(['url'=>$config['serviceOrigin'].'/form/embedded-synthetic','display'=>'link','cache'=>0,'consent_enabled'=>1,'consent_export'=>$raw])]);
if (!$row->check() || !$row->store()) { throw new RuntimeException($row->getError()); }
$db->setQuery('INSERT INTO #__modules_menu (moduleid,menuid) VALUES ('.(int)$row->id.',0)')->execute();
echo "Prepared real Joomla import and owned form link\n";
