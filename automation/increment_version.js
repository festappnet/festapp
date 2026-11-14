const fs = require('fs');
const path = require('path');
const { execFileSync, execSync } = require('child_process');

const projectRoot = path.resolve(__dirname, '../');
const softwareVersionPath = path.resolve(projectRoot, 'automation/release/software-version.conf');

if (fs.existsSync(path.join(projectRoot, 'automation/tenant-overlay.json'))) {
    console.log('Tenant releases inherit the canonical software version; skipping increment.');
    process.exit(0);
}

// Increment the one software generation, never a tenant counter.
try {
    const stagedFiles = execSync('git diff --cached --name-only', { cwd: projectRoot, encoding: 'utf8' });
    if (stagedFiles.split('\n').includes('automation/release/software-version.conf')) {
        console.log('Canonical software version is already staged. Skipping auto-increment.');
        process.exit(0);
    }
} catch (e) {
    console.error('Error checking staged files:', e);
    process.exit(1);
}

// 2. Read current version
if (!fs.existsSync(softwareVersionPath)) {
    console.error('Error: automation/release/software-version.conf not found');
    process.exit(1);
}

const softwareVersionContent = fs.readFileSync(softwareVersionPath, 'utf8');
const versionMatch = softwareVersionContent.match(/^VERSION=(.+)$/m);

if (!versionMatch) {
    console.error('Error: Could not find the canonical software VERSION');
    process.exit(1);
}

const currentVersion = versionMatch[1].trim();
// Expecting format: x.y.z+build
const parts = currentVersion.split('+');

if (parts.length !== 2) {
    console.warn(`Warning: Version format ${currentVersion} does not match x.y.z+build. Skipping auto-increment.`);
    process.exit(0);
}

const semVer = parts[0];
const buildNum = parseInt(parts[1], 10);

if (isNaN(buildNum)) {
    console.warn(`Warning: Build number ${parts[1]} is not a number. Skipping auto-increment.`);
    process.exit(0);
}

const newBuildNum = buildNum + 1;
const newVersion = `${semVer}+${newBuildNum}`;

console.log(`Auto-incrementing version: ${currentVersion} -> ${newVersion}`);

// 3. Update the main-owned software generation.
const newSoftwareVersionContent = softwareVersionContent.replace(/^VERSION=.+$/m, `VERSION=${newVersion}`);
fs.writeFileSync(softwareVersionPath, newSoftwareVersionContent);

// 4. Run the canonical generator to propagate changes to every version leaf.
try {
    execFileSync(process.execPath, ['automation/configure_version.js', newVersion], {
        cwd: projectRoot,
        stdio: 'inherit',
    });
} catch (e) {
    console.error('Error running configure_version.js:', e);
    process.exit(1);
}

// 5. Stage the modified files
const filesToStage = [
    'automation/release/software-version.conf',
    'automation/project.conf',
    'pubspec.yaml',
    'web_client/package.json',
    'web_client/src/version.js',
    'web/index.html',
    'web_client/index.html'
];

try {
    execSync(`git add ${filesToStage.join(' ')}`, { cwd: projectRoot });
    console.log('Staged version files for commit.');
} catch (e) {
    console.error('Error staging version files:', e);
    process.exit(1);
}
