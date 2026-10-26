
export async function load(url, context, defaultLoad) {
  if (url.endsWith('.css')) {
    return {
      format: 'module',
      shortCircuit: true,
      source: '',
    };
  }
  return defaultLoad(url, context, defaultLoad);
}
