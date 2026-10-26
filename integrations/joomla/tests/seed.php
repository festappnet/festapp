<?php
require '/tests/bootstrap.php';
use Joomla\CMS\Table\Table;
use Joomla\CMS\User\User;

function module($element, $title, $position, $params) {
    $row = Table::getInstance('Module', 'JTable');
    $row->bind(['title'=>$title,'module'=>$element,'position'=>$position,'published'=>1,'access'=>1,'showtitle'=>0,'client_id'=>0,'language'=>'*','params'=>json_encode($params)]);
    if (!$row->check() || !$row->store()) { throw new RuntimeException($row->getError()); }
    global $db;
    $db->setQuery('INSERT INTO #__modules_menu (moduleid, menuid) VALUES ('.(int)$row->id.',0)')->execute();
    return (int)$row->id;
}
$db->setQuery("DELETE mm FROM #__modules_menu mm JOIN #__modules m ON m.id=mm.moduleid WHERE m.module IN ('mod_vstupenky_online','mod_festapp_tickets')")->execute();
$db->setQuery("DELETE FROM #__modules WHERE module IN ('mod_vstupenky_online','mod_festapp_tickets')")->execute();
$old = $db->setQuery("SELECT id FROM #__content WHERE alias='ticket-integration'")->loadColumn();
foreach ($old as $id) {
    $row = Table::getInstance('Content', 'JTable');
    $row->delete($id);
}
$ids = [];
foreach (['mod_vstupenky_online'=>'https://vstupenky.online', 'mod_festapp_tickets'=>'https://tickets.festapp.net'] as $element=>$origin) {
    $ids[$element] = module($element, $element, 'sidebar-right', ['url'=>$origin.'/form/embedded-synthetic','cache'=>0]);
}
$articleModule = module('mod_vstupenky_online','Article embed','article-only',['url'=>'https://vstupenky.online/form/embedded-synthetic','cache'=>0]);
$seats = module('mod_festapp_tickets','Seats','seats-only',['url'=>'https://tickets.festapp.net/form/embedded-seats','cache'=>0]);
$article = Table::getInstance('Content', 'JTable');
$article->bind(['title'=>'Ticket integration','alias'=>'ticket-integration','introtext'=>'<p>Ticket integration</p>{loadmoduleid '.$articleModule.'}', 'state'=>1,'featured'=>1,'catid'=>2,'access'=>1,'language'=>'*','created'=>date('Y-m-d H:i:s'),'created_by'=>0,'attribs'=>'{}','metadata'=>'{}']);
if (!$article->check() || !$article->store()) { throw new RuntimeException($article->getError()); }
$db->setQuery('INSERT INTO #__content_frontpage (content_id, ordering) VALUES ('.(int)$article->id.',1)')->execute();
// A real registered user with no backend login/edit privileges.
$existingUser = (int)$db->setQuery("SELECT id FROM #__users WHERE username='viewer'")->loadResult();
$user = new User($existingUser);
$userData = ['name'=>'No module rights','username'=>'viewer','password'=>'OnlyLocalViewer123!','password2'=>'OnlyLocalViewer123!','email'=>'viewer@example.invalid','groups'=>[2],'block'=>0];
$user->bind($userData);
if (!$user->save()) { throw new RuntimeException($user->getError()); }
// Cache globally enabled for render/asset checks; module cache remains disabled.
$config = file_get_contents(JPATH_ROOT.'/configuration.php');
$config = preg_replace('/public \$caching = .*?;/', 'public $caching = 1;', $config);
file_put_contents(JPATH_ROOT.'/configuration.php', $config);
echo json_encode(['modules'=>$ids,'article_module'=>$articleModule,'article'=>(int)$article->id,'seats'=>$seats,'viewer'=>(int)$user->id]), "\n";
