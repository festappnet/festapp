import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const defaultConfigPath = path.resolve(path.dirname(scriptPath), 'project.conf');

export function parseFlutterVersion(source) {
  const matches = [...source.matchAll(/^FLUTTER_VERSION=([^\r\n#]+)$/gm)];
  if (matches.length !== 1) {
    throw new Error(
      'automation/project.conf must define FLUTTER_VERSION exactly once',
    );
  }
  const version = matches[0][1].trim().replace(/^(['"])(.*)\1$/, '$2');

  if (!/^\d+\.\d+\.\d+$/.test(version)) {
    throw new Error('FLUTTER_VERSION must use an exact semantic version');
  }
  return version;
}

export function readFlutterVersion(configPath = defaultConfigPath) {
  return parseFlutterVersion(fs.readFileSync(configPath, 'utf8'));
}

if (process.argv[1] && path.resolve(process.argv[1]) === scriptPath) {
  process.stdout.write(readFlutterVersion());
}
