const fs = require('node:fs');
const path = require('node:path');
function configureStartupThemes(root, {check = false} = {}) {
    const runtimeSource = ['page_context.js', 'update_policy.js', 'worker_shell.js', 'runtime_state.js'].map(name =>
        fs.readFileSync(path.join(root, 'web_client/src/runtime', name), 'utf8').replace(/^import .*;\n/gm, '').replaceAll('export ', '').trim()).join('\n');
    const source = fs.readFileSync(path.join(root, 'web_client/src/services/theme_preference.js'), 'utf8').trim();
    const script = `<script id="festapp-startup-theme">\n${source}\n</script>`;
    for (const entry of ['web/index.html', 'web_client/index.html']) {
        const file = path.join(root, entry);
        const html = fs.readFileSync(file, 'utf8');
        const withoutScript = html.replace(/\s*<script id="festapp-startup-theme">[\s\S]*?<\/script>/, '');
        if (!/<meta name="color-scheme"[^>]*>/.test(withoutScript)) throw new Error(`Startup theme insertion point missing: ${entry}`);
        let updated = withoutScript.replace(/(<meta name="color-scheme"[^>]*>)/, (_, scheme) => `${scheme}\n${script}`);
        updated = updated.replace(/\s*<script id="festapp-(?:embed-startup|runtime-startup)">[\s\S]*?<\/script>/g, '');
        const bootstrap = `<script id="festapp-runtime-startup">
// Generated from web_client/src/runtime.
(function() {
${runtimeSource}
window.__FESTAPP_CLIENT_RUNTIME__ = '${entry === 'web_client/index.html' ? 'web' : 'flutter'}';
installRuntimeState(window);
${entry === 'web_client/index.html' ? "if (pageContext(window.location) === 'public-embed') document.documentElement.dataset.embedStartup = 'true';" : ''}
})();
</script>`;
        updated = updated.replace(script, `${script}\n${bootstrap}`);
        if (updated !== html) {
            if (check) throw new Error(`Startup bootstrap differs from its sources: ${entry}`);
            fs.writeFileSync(file, updated);
        }
    }
}
module.exports = {configureStartupThemes};
if (require.main === module) configureStartupThemes(path.resolve(process.argv[2] || path.join(__dirname, '../..')));
