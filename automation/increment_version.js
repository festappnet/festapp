const fs = require('fs');
const path = require('path');
const { execFileSync, execSync } = require('child_process');

const projectRoot = path.resolve(__dirname, '../');
const projectConfPath = path.resolve(projectRoot, 'automation/project.conf');

// 1. Check if project.conf is already staged
try {
    const stagedFiles = execSync('git diff --cached --name-only', { encoding: 'utf8' });
    if (stagedFiles.includes('automation/project.conf')) {
        console.log('Version manually updated in this commit. Skipping auto-increment.');
        process.exit(0);
    }
} catch (e) {
    console.error('Error checking staged files:', e);
    process.exit(1);
}

// 2. Read current version
if (!fs.existsSync(projectConfPath)) {
    console.error('Error: automation/project.conf not found');
    process.exit(1);
}

const projectConfContent = fs.readFileSync(projectConfPath, 'utf8');
const versionMatch = projectConfContent.match(/^VERSION=(.+)$/m);

if (!versionMatch) {
    console.error('Error: Could not find VERSION in automation/project.conf');
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

// 3. Update project.conf
const newProjectConfContent = projectConfContent.replace(/^VERSION=.+$/m, `VERSION=${newVersion}`);
fs.writeFileSync(projectConfPath, newProjectConfContent);

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
    'automation/project.conf',
    'pubspec.yaml',
    'web_client/package.json',
    'web_client/package-lock.json',
    'web_client/src/version.js',
    'web/index.html'
];

try {
    execSync(`git add ${filesToStage.join(' ')}`, { cwd: projectRoot });
    console.log('Staged version files for commit.');
} catch (e) {
    console.error('Error staging version files:', e);
    process.exit(1);
}
