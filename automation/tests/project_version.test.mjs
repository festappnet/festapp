#!/usr/bin/env node

import assert from 'node:assert/strict';
import test from 'node:test';
import { parseFlutterVersion } from '../flutter_version.mjs';
import { parseProjectVersion } from '../release/project_version.mjs';

test('extracts the canonical build number for App Store tooling', () => {
  assert.deepEqual(parseProjectVersion('APP_NAME=Festapp\nVERSION=1.2.3+456\n'), {
    full: '1.2.3+456',
    version: '1.2.3',
    build: '456',
  });
});

test('accepts a quoted version and rejects a missing numeric build', () => {
  assert.equal(parseProjectVersion('VERSION="2.0.0-beta.1+7"\n').version, '2.0.0-beta.1');
  assert.throws(() => parseProjectVersion('VERSION=2.0.0\n'), /numeric-build/);
});

test('extracts the canonical exact Flutter SDK version', () => {
  assert.equal(parseFlutterVersion('APP_NAME=Festapp\nFLUTTER_VERSION=3.47.2\n'), '3.47.2');
  assert.equal(parseFlutterVersion('FLUTTER_VERSION="3.47.2"\n'), '3.47.2');
  assert.throws(() => parseFlutterVersion('FLUTTER_VERSION=stable\n'), /exact semantic version/);
});
