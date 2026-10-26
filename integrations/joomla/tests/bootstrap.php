<?php
/** Test-only bootstrap, mounted outside the document root. */
$_SERVER['HTTP_HOST'] = 'localhost';
$_SERVER['REQUEST_URI'] = '/';
$_SERVER['SCRIPT_NAME'] = '/index.php';
define('_JEXEC', 1);
define('JPATH_BASE', '/var/www/html');
require JPATH_BASE . '/includes/defines.php';
require JPATH_BASE . '/includes/framework.php';
$container = \Joomla\CMS\Factory::getContainer();
$container->alias('session.web', 'session.web.site')->alias('session', 'session.web.site')->alias('JSession', 'session.web.site')->alias(\Joomla\CMS\Session\Session::class, 'session.web.site')->alias(\Joomla\Session\SessionInterface::class, 'session.web.site');
$app = $container->get(\Joomla\CMS\Application\SiteApplication::class);
\Joomla\CMS\Factory::$application = $app;
$app->createExtensionNamespaceMap();
$app->loadLanguage();
$db = $container->get(\Joomla\Database\DatabaseInterface::class);
