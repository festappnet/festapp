import {readRuntimes} from './measurement_runtimes.mjs';

// Project API responses may contain secret bindings. Retain only public metadata
// before the response leaves this process; never print parsing errors or raw data.
try {
  let raw = '';
  for await (const chunk of process.stdin) raw += chunk;
  const data = JSON.parse(raw);
  if (!data.success || !data.result) throw Error();
  if (process.argv[2] === '--deployment') {
    const deployment = data.result;
    if (deployment.id !== process.argv[3] || deployment.environment !== 'production' ||
        deployment.latest_stage?.status !== 'success') throw Error();
    process.exit(0);
  }
  if (process.argv[2] !== '--project' || !process.argv[3]) throw Error();
  const [expected] = await readRuntimes(process.argv[3]);
  const bindings = data.result.deployment_configs?.production?.env_vars;
  const publicValue = key => bindings?.[key]?.type === 'plain_text' ? bindings[key].value : undefined;
  if (publicValue('ORGANIZATION_ID') !== String(expected.organization) ||
      publicValue('UNIT_ID') !== String(expected.unit) ||
      publicValue('FESTAPP_API_URL') !== 'https://api.festapp.net') {
    console.error('Runtime production scope/backend does not match registry');
    process.exit(1);
  }
  const {production_branch, canonical_deployment: active} = data.result;
  console.log(JSON.stringify({success: true, result: {
    production_branch,
    canonical_deployment: active == null ? null : {id: active.id, environment: active.environment,
      latest_stage: {status: active.latest_stage?.status}},
  }}));
} catch {
  console.error('Pages project metadata unavailable');
  process.exitCode = 1;
}
