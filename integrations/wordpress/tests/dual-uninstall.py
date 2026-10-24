"""Delete/reinstall each installed ZIP on minimum WP; preserve the other plugin and service orders."""
import subprocess,json,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[1]
def wp(*args):
 p=subprocess.run(['node','scripts/environment.mjs','run','tests-cli','wp',*args],cwd=R,text=True,capture_output=True)
 if p.returncode:raise RuntimeError((p.stdout+p.stderr)[-1200:])
 return p.stdout
DB='supabase_db_festapp-vo-wordpress-20261023'
def count():return int(subprocess.check_output(['docker','exec',DB,'psql','-U','postgres','-d','postgres','-Atqc','select count(*) from eshop.orders'],text=True))
before=count();wp('eval-file','/var/www/html/wp-content/plugins/vstupenky-online-tests/dual-seed.php');cases=[]
for slug,missing,remaining,shortcode,page in [('festapp-tickets','FestappTickets','VstupenkyOnline','vstupenky_online','vo-global'),('vstupenky-online','VstupenkyOnline','FestappTickets','festapp_tickets','vo-block')]:
 wp('plugin','uninstall',slug,'--deactivate')
 code=f'''if(function_exists('{missing}\\render') || !function_exists('{remaining}\\render') || !shortcode_exists('{shortcode}')){{WP_CLI::error('Runtime dependency crosses products');}} $p=get_page_by_path('{page}');if(!$p || strpos($p->post_content,'wp:{slug}/ticket-form')===false){{WP_CLI::error('Saved block lost');}} WP_CLI::success('Other plugin operates alone and saved content persists');'''
 wp('eval',code)
 wp('plugin','install',f'/var/www/html/wp-content/vo-artifacts/{slug}-1.0.0.zip','--activate')
 assert count()==before
 cases.append({'plugin':slug,'uninstall_delete':'PASS','other_plugin_independent_in_fresh_request':'PASS','saved_block_preserved':True,'clean_zip_reinstall':'PASS'})
(R/'evidence/dual-uninstall-receipt.json').write_text(json.dumps({'status':'PASS','environment':'minimum WP6.6.4/PHP7.4.33','orders_before':before,'orders_after':count(),'cases':cases},indent=2)+'\n')
print('PASS: actual delete/uninstall + clean ZIP reinstall of both products; independent remaining plugin, saved blocks and service orders preserved')
