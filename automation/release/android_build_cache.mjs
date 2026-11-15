import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const toolchainFiles = new Set([
  '.fvmrc', 'android/settings.gradle', 'android/gradle.properties',
  'android/gradle/wrapper/gradle-wrapper.properties',
  'android/gradle/wrapper/gradle-wrapper.jar',
]);
const selected = name => toolchainFiles.has(name) ||
  ['pubspec.lock', 'android/build.gradle', 'android/app/build.gradle'].includes(name) ||
  name.startsWith('packages/super_native_extensions/') ||
  name.startsWith('packages/irondash_engine_context/');

// CargoKit artifacts contain generic native libraries. Tenant application IDs
// affect final packaging, while every other app build setting stays in the key.
function nativeInput(name, content) {
  if (name !== 'android/app/build.gradle') return content;
  return content.toString().replace(
    /^(\s*(?:namespace|applicationId)\s*(?:=\s*)?)["'][^"']+["'];?\s*$/gm,
    '$1"<tenant>"',
  );
}

export function androidBuildCacheKeys(files, runtime) {
  for (const field of ['os', 'arch', 'image', 'rustc']) {
    if (!runtime[field]) throw new Error(`Missing build cache runtime ${field}`);
  }
  for (const name of [...toolchainFiles, 'android/app/build.gradle', 'pubspec.lock']) {
    if (!Object.hasOwn(files, name)) throw new Error(`Missing build cache input ${name}`);
  }
  const digest = (names, environment, normalize = false) => {
    const hash = crypto.createHash('sha256').update(JSON.stringify(environment));
    for (const name of names.sort()) {
      hash.update('\0' + name + '\0');
      hash.update(normalize ? nativeInput(name, files[name]) : files[name]);
    }
    return hash.digest('hex');
  };
  const gradle = digest([...toolchainFiles], {
    os: runtime.os, arch: runtime.arch, image: runtime.image,
  });
  const native = digest(Object.keys(files).filter(selected), runtime, true);
  return { gradle: `android-gradle-v1-${gradle}`, native: `android-native-v1-${native}` };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  // The trusted helper is copied outside the immutable tenant checkout.
  const root = process.cwd();
  const tracked = execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8' });
  const files = Object.fromEntries(tracked.split('\0').filter(name => name && selected(name))
    .map(name => [name, fs.readFileSync(path.join(root, name))]));
  const keys = androidBuildCacheKeys(files, {
    os: process.env.RUNNER_OS, arch: process.env.RUNNER_ARCH,
    image: `${process.env.ImageOS ?? 'unknown'}:${process.env.ImageVersion ?? 'unknown'}`,
    rustc: process.env.FESTAPP_CACHE_RUSTC_VERSION,
  });
  console.log(`gradle=${keys.gradle}\nnative=${keys.native}`);
}
