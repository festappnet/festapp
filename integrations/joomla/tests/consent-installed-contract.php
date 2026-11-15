<?php
// Runs in the real installed disposable Joomla, with the runner's temporary
// loopback-only HTTP parser adjustment. No CMP or backend claim is made here.
require '/tests/bootstrap.php';
$origin=getenv('SITE_ORIGIN');
$service=getenv('FESTAPP_CMS_TEST_SERVICE') ?: 'https://vstupenky.online';
$_SERVER['HTTP_HOST']=parse_url($origin,PHP_URL_HOST).':'.parse_url($origin,PHP_URL_PORT);
$_SERVER['REQUEST_URI']='/';$_SERVER['SCRIPT_NAME']='/index.php';
\Joomla\CMS\Uri\Uri::reset();
require_once JPATH_ROOT.'/modules/mod_vstupenky_online/src/Helper/EmbedHelper.php';
require_once JPATH_ROOT.'/modules/mod_vstupenky_online/src/Rule/ConsentexportRule.php';
use Festapp\Module\VstupenkyOnline\Site\Helper\EmbedHelper;
use Festapp\Module\VstupenkyOnline\Site\Rule\ConsentexportRule;
$config=['schemaVersion'=>1,'serviceOrigin'=>$service,'websiteOrigin'=>$origin,'binding'=>['id'=>'11111111-1111-1111-1111-111111111111','version'=>1],'providerConfig'=>['provider'=>'complianz','organization'=>1,'unit'=>1,'consentRevision'=>str_repeat('a',32),'origin'=>$origin,'policyId'=>'1']];
$raw=json_encode($config);$rule=new ConsentexportRule();$field=new SimpleXMLElement('<field name="consent_export"/>');
if (!$rule->test($field,$raw) || $rule->test($field,'{broken')) throw new RuntimeException('Native Joomla form rule valid/malformed');
$foreign=$config;$foreign['websiteOrigin']='https://foreign.example';
if ($rule->test($field,json_encode($foreign))) throw new RuntimeException('Native Joomla form rule accepted foreign origin');
if (EmbedHelper::consent(['consent_enabled'=>0,'consent_export'=>$raw])!==null || !EmbedHelper::consent(['consent_enabled'=>1,'consent_export'=>$raw])) throw new RuntimeException('Joomla on/off state');
$params=['url'=>$service.'/form/embedded-synthetic','display'=>'link','iframe_title'=>'<script>alert(1)</script>','consent_enabled'=>1,'consent_export'=>$raw];
$link=EmbedHelper::render($params);
if (strpos($link,'data-festapp-consent-link')===false || strpos($link,'<script>')!==false) throw new RuntimeException('Joomla marked link or escaping');
$params['consent_enabled']=0;$link=EmbedHelper::render($params);
if (strpos($link,'rel="noopener noreferrer"')===false || strpos($link,'data-festapp-consent-link')!==false) throw new RuntimeException('Joomla off-state link');
echo "PASS real Joomla consent native form rule, on/off, link and escaping\n";
