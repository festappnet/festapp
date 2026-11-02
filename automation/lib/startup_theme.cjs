const fs = require('node:fs');
const path = require('node:path');
function configureStartupThemes(root) {
    const source = fs.readFileSync(path.join(root, 'web_client/src/services/theme_preference.js'), 'utf8').trim();
    const script = `<script id="festapp-startup-theme">\n${source}\n</script>`;
    for (const entry of ['web/index.html', 'web_client/index.html']) {
        const file = path.join(root, entry);
        const html = fs.readFileSync(file, 'utf8');
        const withoutScript = html.replace(/\s*<script id="festapp-startup-theme">[\s\S]*?<\/script>/, '');
        if (!/<meta name="color-scheme"[^>]*>/.test(withoutScript)) throw new Error(`Startup theme insertion point missing: ${entry}`);
        const updated = withoutScript.replace(/(<meta name="color-scheme"[^>]*>)/, (_, scheme) => `${scheme}\n${script}`);
        if (updated !== html) fs.writeFileSync(file, updated);
    }
}
module.exports = {configureStartupThemes};
if (require.main === module) configureStartupThemes(path.resolve(process.argv[2] || path.join(__dirname, '../..')));
