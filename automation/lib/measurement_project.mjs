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
