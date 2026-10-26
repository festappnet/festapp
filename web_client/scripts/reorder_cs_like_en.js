
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const resolvePath = (relativePath) => path.resolve(__dirname, relativePath);

const PATHS = {
    en: resolvePath('../../assets/translations/en.json'),
    cs: resolvePath('../../assets/translations/cs.json')
};

function readJson(filePath) {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function writeJson(filePath, data) {
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + '\n', 'utf8');
}

function reorderObject(source, target) {
    const reordered = {};
    
    // Add keys in order of source
    for (const key of Object.keys(source)) {
        if (target.hasOwnProperty(key)) {
            if (typeof source[key] === 'object' && source[key] !== null && !Array.isArray(source[key]) &&
                typeof target[key] === 'object' && target[key] !== null && !Array.isArray(target[key])) {
                reordered[key] = reorderObject(source[key], target[key]);
            } else {
                reordered[key] = target[key];
            }
        }
    }

    // Add remaining keys from target that weren't in source
    for (const key of Object.keys(target)) {
        if (!source.hasOwnProperty(key)) {
            reordered[key] = target[key];
        }
    }

    return reordered;
}

function main() {
    console.log('Reading files...');
    const enContent = readJson(PATHS.en);
    const csContent = readJson(PATHS.cs);

    console.log('Reordering CS to match EN structure...');
    const csReordered = reorderObject(enContent, csContent);

    console.log('Writing CS file...');
    writeJson(PATHS.cs, csReordered);
    
    // Also update the web client version to match
    const webCsPath = resolvePath('../public/assets/translations/cs.json');
    console.log(`Updating ${webCsPath}...`);
    writeJson(webCsPath, csReordered);

    console.log('Done.');
}

main();
