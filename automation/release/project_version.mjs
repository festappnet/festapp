#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const releaseDirectory = path.dirname(fileURLToPath(import.meta.url));
const defaultConfigPath = path.resolve(releaseDirectory, '../project.conf');

export function parseProjectVersion(contents) {
  const raw = contents.match(/^VERSION=(?:"([^"]+)"|([^\r\n#]+))$/m)?.slice(1).find((value) => value !== undefined)?.trim();
  const match = raw?.match(/^(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\+(\d+)$/);
  if (!match) {
    throw new Error('VERSION in automation/project.conf must use <version>+<numeric-build>');
  }
  return { full: raw, version: match[1], build: match[2] };
}

export function readProjectVersion(configPath = defaultConfigPath) {
  return parseProjectVersion(fs.readFileSync(configPath, 'utf8'));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const projectVersion = readProjectVersion();
  const option = process.argv[2] ?? '--json';
  if (option === '--version') console.log(projectVersion.version);
  else if (option === '--build') console.log(projectVersion.build);
  else if (option === '--full') console.log(projectVersion.full);
  else if (option === '--json') console.log(JSON.stringify(projectVersion));
  else {
    console.error('Unknown option: ' + option);
    process.exitCode = 2;
  }
}
