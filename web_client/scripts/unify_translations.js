import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Helper to resolve paths relative to this script
const resolvePath = (relativePath) => path.resolve(__dirname, relativePath);

// Paths configuration
const PATHS = {
    flutter: {
        en: resolvePath('../../assets/translations/en.json'),
        cs: resolvePath('../../assets/translations/cs.json')
    },
    web: {
        en: resolvePath('../public/assets/translations/en.json'),
        cs: resolvePath('../public/assets/translations/cs.json')
    }
};

function readJson(filePath) {
    if (!fs.existsSync(filePath)) {
        console.warn(`Warning: File not found at ${filePath}`);
        return {};
    }
    try {
        const content = fs.readFileSync(filePath, 'utf8');
        return JSON.parse(content);
    } catch (error) {
        console.error(`Error reading ${filePath}:`, error.message);
        return {};
    }
}

function writeJson(filePath, data) {
    try {
        const content = JSON.stringify(data, null, 2) + '\n';
        fs.writeFileSync(filePath, content, 'utf8');
        console.log(`Updated: ${filePath}`);
    } catch (error) {
        console.error(`Error writing ${filePath}:`, error.message);
    }
}

function mergeTranslations(lang) {
    console.log(`\nUnifying ${lang.toUpperCase()} translations...`);

    const flutterPath = PATHS.flutter[lang];
    const webPath = PATHS.web[lang];

    console.log(`\nUnifying ${lang.toUpperCase()} translations for ${path.basename(flutterPath)}...`);
    
    // Read files
    let flutterContent = readJson(flutterPath);
    let webContent = readJson(webPath);

    const flutterKeys = Object.keys(flutterContent).length;
    const webKeys = Object.keys(webContent).length;

    console.log(`Flutter keys: ${flutterKeys}`);
    console.log(`Web keys:     ${webKeys}`);

    // Merge: Web + Flutter (Flutter takes precedence for conflicts, but Union of keys)
    // Deep Clone to avoid mutation side effects during merge
    const merged = JSON.parse(JSON.stringify(webContent));
    
    // Custom Deep Merge: 
    // We iterate Flutter keys. If key exists in Web and IS object, recurse. 
    // If not object, overwrite. 
    // If doesn't exist, add.
    
    function recursiveMerge(base, override) {
        for (const key in override) {
            if (Object.prototype.hasOwnProperty.call(override, key)) {
                if (
                    typeof override[key] === 'object' && 
                    override[key] !== null && 
                    !Array.isArray(override[key]) &&
                    typeof base[key] === 'object' && 
                    base[key] !== null &&
                    !Array.isArray(base[key])
                ) {
                    recursiveMerge(base[key], override[key]);
                } else {
                    base[key] = override[key];
                }
            }
        }
    }

    recursiveMerge(merged, flutterContent);

    const mergedKeys = Object.keys(merged).length;
    console.log(`Merged keys:  ${mergedKeys}`);

    // Write back to both
    writeJson(flutterPath, merged);
    writeJson(webPath, merged);
}

function main() {
    try {
        mergeTranslations('en');
        mergeTranslations('cs');
        console.log('\nTranslation unification complete.');
    } catch (error) {
        console.error('Fatal error unifying translations:', error);
        process.exit(1);
    }
}

main();
