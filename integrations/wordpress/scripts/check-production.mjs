import {spawnSync} from 'node:child_process';
const run=(...args)=>{const r=spawnSync('node',['scripts/environment.mjs','run','tests-cli','wp',...args],{encoding:'utf8'});if(r.status)throw Error(r.stderr+r.stdout);return r.stdout};
try {
 run('config','set','WP_ENVIRONMENT_TYPE','production');
 console.log(run('eval-file','/var/www/html/wp-content/plugins/vstupenky-online-tests/production-gate.php'));
} finally {run('config','set','WP_ENVIRONMENT_TYPE','local');}
