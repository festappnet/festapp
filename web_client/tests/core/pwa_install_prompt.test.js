import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { JSDOM } from 'jsdom';

const testDirectory = dirname(fileURLToPath(import.meta.url));
const indexTemplate = readFileSync(
    resolve(testDirectory, '../../../web/index.html'),
    'utf8'
);
const installPromptScript = [...indexTemplate.matchAll(/<script>([\s\S]*?)<\/script>/g)]
    .map(match => match[0])
    .find(script => script.includes("window.addEventListener('beforeinstallprompt'"));

function bootInstallPromptBridge() {
    assert.ok(installPromptScript, 'PWA install bridge script must exist');
    const dom = new JSDOM(
        `<!doctype html><html><body>${installPromptScript}</body></html>`,
        { url: 'https://csmostrava.festapp.net/', runScripts: 'dangerously' }
    );
    dom.window.appInstalled = () => {};
    dom.window.appLaunchedAsPWA = () => {};
    dom.window.appLaunchedAsTWA = () => {};
    dom.window.appLaunchedInBrowser = () => {};
    dom.window.hasPrompt = () => {};
    return dom.window;
}

describe('Flutter PWA install bridge', () => {
    test('retains the browser prompt for the in-app install button', () => {
        const window = bootInstallPromptBridge();
        let availabilityNotifications = 0;
        window.hasPrompt = () => { availabilityNotifications += 1; };
        const event = new window.Event('beforeinstallprompt', { cancelable: true });
        event.prompt = async () => {};

        window.dispatchEvent(event);

        assert.equal(event.defaultPrevented, false, 'native installation stays available');
        assert.equal(availabilityNotifications, 1);
    });

    test('opens the prompt immediately from the user action', async () => {
        const window = bootInstallPromptBridge();
        let promptCalls = 0;
        const event = new window.Event('beforeinstallprompt', { cancelable: true });
        event.prompt = async () => { promptCalls += 1; };
        window.dispatchEvent(event);
        window.festappOfflineReady = new Promise(() => {});

        window.promptInstall();
        await Promise.resolve();

        assert.equal(promptCalls, 1);
    });
});
