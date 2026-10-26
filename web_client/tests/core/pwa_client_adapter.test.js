import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { JSDOM } from 'jsdom';

const html = await readFile(
  path.resolve(import.meta.dirname, '../../index.html'),
  'utf8',
);
const moduleSource = [...html.matchAll(
  /<script type="module">([\s\S]*?)<\/script>/g,
)].map((match) => match[1]).find((source) =>
  source.includes('serviceWorker.register'));

test('web client reports before module loading and keeps its worker generation current', async () => {
  assert.ok(moduleSource, 'PWA adapter module is missing');
  const dom = new JSDOM('<!doctype html><body></body>', {
    url: 'https://app.test/',
    runScripts: 'outside-only',
  });
  const { window } = dom;
  const messages = [];
  const registrations = [];
  const controller = {
    postMessage: (message) => messages.push(message),
  };
  const serviceWorker = new window.EventTarget();
  serviceWorker.controller = controller;
  serviceWorker.ready = Promise.resolve({ active: controller });
  serviceWorker.register = async (...args) => {
    registrations.push(args);
    return { active: controller };
  };
  Object.defineProperty(window.navigator, 'serviceWorker', {
    configurable: true,
    value: serviceWorker,
  });
  Object.defineProperty(window.performance, 'getEntriesByType', {
    configurable: true,
    value: () => [],
  });

  const classicSource = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)]
    .map((match) => match[1]).find((source) => source.includes('FESTAPP_CLIENT_VERSION'));
  assert.ok(classicSource, 'generation reporting must be independent of module loading');
  window.eval(classicSource.replace(
    /(window\.__FESTAPP_BUILD_VERSION__\s*=\s*)"[^"]*"/,
    '$1"7.8.9+123"',
  ));
  assert.equal(messages.length, 1, 'cached HTML must report before its first module runs');
  window.eval(moduleSource);
  window.dispatchEvent(new window.Event('load'));
  await window.festappOfflineReady;

  assert.equal(registrations.length, 1);
  assert.equal(registrations[0][0], '/festapp_service_worker.js');
  assert.equal(registrations[0][1].scope, '/');
  assert.equal(registrations[0][1].updateViaCache, 'none');
  assert.equal(messages.at(-1).type, 'FESTAPP_CLIENT_VERSION');
  assert.equal(messages.at(-1).version, '7.8.9+123');

  serviceWorker.dispatchEvent(new window.Event('controllerchange'));
  window.dispatchEvent(new window.Event('focus'));
  const reportRequest = new window.MessageEvent('message', {
    data: { type: 'FESTAPP_REPORT_VERSION' },
  });
  serviceWorker.dispatchEvent(reportRequest);
  assert.equal(messages.length, 5);
  assert.ok(messages.every((message) => message.version === '7.8.9+123'));
  dom.window.close();
});


test('the actual PWA module remains usable when a WebView denies serviceWorker access', async (t) => {
  const dom = new JSDOM('<!doctype html><body></body>', {
    url: 'https://app.test/',
    runScripts: 'outside-only',
  });
  t.after(() => dom.window.close());
  const { window } = dom;
  Object.defineProperty(window.navigator, 'serviceWorker', {
    get() { throw new window.DOMException('Blocked by WebView', 'SecurityError'); },
  });
  assert.doesNotThrow(() => window.eval(moduleSource));
  await window.festappOfflineReady;
});
