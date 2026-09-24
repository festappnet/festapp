
const fs = require('fs');
const path = require('path');

// Arguments: [node, script, projectRoot, fontFamilyBase, commaSeparatedFontFiles]
const projectRoot = process.argv[2];
let fontFamilyBase = process.argv[3] || 'Futura'; // Default
const configuredFiles = process.argv[4] || '';

if (!projectRoot) {
    console.error("Usage: node configure_fonts.js <projectRoot> [fontFamilyBase] [fontFiles]");
    process.exit(1);
}

const fontSourceDir = path.join(projectRoot, 'automation/fonts');
const flutterFontDir = path.join(projectRoot, 'fonts');
const webFontDir = path.join(projectRoot, 'web_client/src/assets/fonts');
const pubspecPath = path.join(projectRoot, 'pubspec.yaml');
const webThemePath = path.join(projectRoot, 'web_client/src/theme_config.css');
const dartThemePath = path.join(projectRoot, 'lib/theme_config.dart');

// Ensure dests exist
if (!fs.existsSync(flutterFontDir)) fs.mkdirSync(flutterFontDir, { recursive: true });
if (!fs.existsSync(webFontDir)) fs.mkdirSync(webFontDir, { recursive: true });

// 1. Scan and Classify Fonts
const fonts = [];
let fontSources;
if (configuredFiles) {
    const files = configuredFiles.split(',').map(file => file.trim());
    if (files.some(file => !/^fonts\/[^/,]+\.(ttf|otf)$/i.test(file)) ||
        new Set(files).size !== files.length ||
        new Set(files.map(file => path.basename(file).replace(/\s+/g, ''))).size !== files.length) {
        throw new Error('FONT_FILES must list distinct .ttf/.otf files directly under fonts/ with unique web filenames');
    }
    const allowedDir = fs.realpathSync(flutterFontDir);
    fontSources = files.map(file => {
        const source = path.join(projectRoot, file);
        if (!fs.existsSync(source) ||
            path.dirname(fs.realpathSync(source)) !== allowedDir ||
            !fs.statSync(source).isFile()) {
            throw new Error(`Configured font is missing or outside fonts/: ${file}`);
        }
        return { file: path.basename(file), source };
    });
} else {
    if (!fs.existsSync(fontSourceDir)) {
        throw new Error(`Font source directory not found: ${fontSourceDir}`);
    }
    fontSources = fs.readdirSync(fontSourceDir)
        .filter(file => /\.(ttf|otf)$/i.test(file))
        .map(file => ({ file, source: path.join(fontSourceDir, file) }));
}
const validFiles = fontSources.map(font => font.file);

if (validFiles.length === 0) {
    throw new Error('No .ttf/.otf fonts found in automation/fonts');
}

// Auto-Detect Family Name
function detectFamilyName(fileList) {
    if (!fileList || fileList.length === 0) return null;
    let common = fileList[0].replace(/\.[^/.]+$/, ""); 
    fileList.forEach(f => {
        const name = f.replace(/\.[^/.]+$/, "");
        let i = 0;
        while(i < common.length && common[i] === name[i]) i++;
        common = common.substring(0, i);
    });
    common = common.replace(/[-_]$/, '');
    if (common.length < 2) return null; 
    return common.replace(/-/g, ' ').replace(/_/g, ' ').trim();
}

const detectedFamily = configuredFiles ? null : detectFamilyName(validFiles);
if (detectedFamily && detectedFamily !== 'Futura') {
    // If the user provided a specific env var override, maybe respect it?
    // But typically auto-detect is preferred if files are provided.
    // If the arg passed is "Futura" (default), we definitely override.
    if (fontFamilyBase === 'Futura') {
        fontFamilyBase = detectedFamily;
        console.log(`Auto-detected Font Family: "${fontFamilyBase}"`);
    } else {
         console.log(`Using Configured Font Family: "${fontFamilyBase}" (Detected: ${detectedFamily})`);
    }
}


console.log(`Scanning fonts...`);

fontSources.forEach(({ file, source: srcPath }) => {
    let weight = 400;
    let style = 'normal';
    const lowerName = file.toLowerCase();

    // Heuristic for Weight
    if (lowerName.includes('bold') || lowerName.includes('700')) weight = 700;
    else if (lowerName.includes('medium') || lowerName.includes('500')) weight = 500;
    else if (lowerName.includes('light') || lowerName.includes('300')) weight = 300;
    
    // Heuristic for Style
    if (lowerName.includes('italic')) style = 'italic';

    // File copying prep
    // Remove spacess for web
    const webFilename = file.replace(/\s+/g, '');
    
    fonts.push({
        appFilename: file, 
        webFilename: webFilename,
        weight: weight,
        style: style,
        srcPath: srcPath
    });
});

// 2. Clear and Copy Files
console.log(`Found ${fonts.length} fonts. Syncing...`);
fonts.forEach(font => {
    const flutterTarget = path.join(flutterFontDir, font.appFilename);
    if (font.srcPath !== flutterTarget) fs.copyFileSync(font.srcPath, flutterTarget);
    fs.copyFileSync(font.srcPath, path.join(webFontDir, font.webFilename));
});

// 3. Update pubspec.yaml
console.log(`Updating pubspec.yaml with family "${fontFamilyBase}"...`);
if (fs.existsSync(pubspecPath)) {
    let pubspec = fs.readFileSync(pubspecPath, 'utf8');
    
    let newFontSection = `  fonts:\n    - family: ${fontFamilyBase}\n      fonts:\n`;
    
    fonts.forEach(font => {
        newFontSection += `        - asset: fonts/${font.appFilename}\n`;
        newFontSection += `          weight: ${font.weight}\n`;
        if (font.style !== 'normal') newFontSection += `          style: ${font.style}\n`;
    });
    
    const fontsRegex = /  fonts:\n(\s{4}- family:[\s\S]*?)(?=\n\s{2}[a-z]|\nflutter:|$)/;
    
    if (pubspec.match(fontsRegex)) {
        pubspec = pubspec.replace(fontsRegex, newFontSection.trimEnd());
        fs.writeFileSync(pubspecPath, pubspec);
        console.log("✔ pubspec.yaml updated.");
    } else {
        console.warn("⚠ Could not find '  fonts:' section to replace.");
    }
}

// 4. Update theme_config.css
console.log("Updating theme_config.css...");
if (fs.existsSync(webThemePath)) {
    let css = fs.readFileSync(webThemePath, 'utf8');
    let newCssRules = "";
    fonts.forEach(font => {
        const ext = path.extname(font.webFilename).toLowerCase();
        const format = ext === '.otf' ? 'opentype' : 'truetype';
        
        newCssRules += `@font-face {\n`;
        newCssRules += `    font-family: '${fontFamilyBase}';\n`;
        newCssRules += `    src: url('./assets/fonts/${font.webFilename}') format('${format}');\n`;
        newCssRules += `    font-weight: ${font.weight};\n`; 
        newCssRules += `    font-style: ${font.style};\n`;
        newCssRules += `}\n\n`;
    });

    const fontFaceRegex = /@font-face\s?\{[^}]+\}/g;
    if (css.match(fontFaceRegex)) {
        css = css.replace(fontFaceRegex, '');
        css = css.replace(/^\s+/g, ''); 
        css = newCssRules + css;
    } else {
        css = newCssRules + css;
    }

    // Also update body { font-family: ... }
    const bodyFontRegex = /body\s*\{[\s\S]*?font-family:\s*['"]?([^'"]+)['"]?/;
    if (css.match(bodyFontRegex)) {
         css = css.replace(bodyFontRegex, (match, currentFont) => {
             return match.replace(currentFont, fontFamilyBase);
         });
    }

    fs.writeFileSync(webThemePath, css);
    console.log("✔ theme_config.css updated.");
}

// 5. Update lib/theme_config.dart
console.log("Updating lib/theme_config.dart...");
if (fs.existsSync(dartThemePath)) {
    let dart = fs.readFileSync(dartThemePath, 'utf8');
    // Regex to find: static final fontFamily = "Something";
    const dartRegex = /static final fontFamily = ".*";/;
    
    if (dart.match(dartRegex)) {
        dart = dart.replace(dartRegex, `static final fontFamily = "${fontFamilyBase}";`);
        fs.writeFileSync(dartThemePath, dart);
        console.log("✔ lib/theme_config.dart updated.");
    } else {
         console.warn("⚠ Could not find 'static final fontFamily' in theme_config.dart.");
    }
}

console.log("Dynamic Font Configuration Complete.");
