<?php
require '/tests/bootstrap.php';
use Joomla\CMS\Table\Table;
$origin = getenv('SITE_ORIGIN');
$service = getenv('FESTAPP_CMS_TEST_SERVICE') ?: 'https://vstupenky.online';
$db->setQuery("DELETE mm FROM #__modules_menu mm JOIN #__modules m ON m.id=mm.moduleid WHERE m.module='mod_vstupenky_online'")->execute();
$db->setQuery("DELETE FROM #__modules WHERE module='mod_vstupenky_online'")->execute();
$export = ['schemaVersion'=>1,'serviceOrigin'=>$service,'websiteOrigin'=>$origin,'binding'=>['id'=>'11111111-1111-1111-1111-111111111111','version'=>1],'providerConfig'=>['provider'=>'complianz','organization'=>1,'unit'=>1,'consentRevision'=>str_repeat('a',32),'origin'=>$origin,'policyId'=>'1']];
foreach ([false,true] as $index=>$enabled) {
 $value=$export; if (getenv('CONFLICT') && $index===0) { $enabled=true; $value['binding']['version']=2; }
 $row=Table::getInstance('Module','JTable');
 $row->bind(['title'=>'Consent '.$index,'module'=>'mod_vstupenky_online','position'=>'sidebar-right','published'=>1,'ordering'=>$index+1,'access'=>1,'showtitle'=>0,'client_id'=>0,'language'=>'*','params'=>json_encode(['url'=>$service.'/form/embedded-synthetic','cache'=>0,'consent_enabled'=>$enabled ? 1 : 0,'consent_export'=>json_encode($value)])]);
 if (!$row->check() || !$row->store()) throw new RuntimeException($row->getError());
 $db->setQuery('INSERT INTO #__modules_menu (moduleid,menuid) VALUES ('.(int)$row->id.',0)')->execute();
}
