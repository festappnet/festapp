// Disposable WebAuthn ceremony driver. Communicates with the parent over JSON lines;
// credential material must remain in these private pipes, not test logs.
// Start: node tools/festapp/test/webauthn-browser-helper.mjs http://localhost:PORT
// Send: {"id":1,"operation":"create"|"get","options":<WebAuthn JSON options>,"verified":true}
// Receives: {"id":1,"credential":<PublicKeyCredential JSON>} or {"id":1,"error":...}
// Keep the process alive between create and get to retain the virtual credential.
import {createRequire} from 'node:module';
import {createInterface} from 'node:readline';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createHmac} from 'node:crypto';

const origin = new URL(process.argv[2]);
if (!['http:', 'https:'].includes(origin.protocol) || !['127.0.0.1', 'localhost'].includes(origin.hostname) ||
    origin.pathname !== '/' || origin.search || origin.hash || origin.username || origin.password) {
  throw new Error('A disposable localhost origin is required');
}
const require = createRequire(new URL('../../../web_client/package.json', import.meta.url));
const {chromium} = require('playwright');
const browser = await chromium.launch({headless: true, args: ['--mute-audio']});

function ownedHttpOrigin(value) {
  const url = new URL(value);
  if (url.protocol !== 'http:' || !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      url.pathname !== '/' || url.search || url.hash || url.username || url.password) {
    throw new Error('A disposable loopback upstream is required');
  }
  return url.origin;
}

async function qualifyWebClient(page, input) {
  const auth = ownedHttpOrigin(input.auth);
  const rest = ownedHttpOrigin(input.rest);
  const {build} = await import(pathToFileURL(require.resolve('vite')).href);
  const output = await build({
    configFile: false, logLevel: 'silent', root: fileURLToPath(new URL('../../../web_client/', import.meta.url)),
    build: {
      write: false, target: 'es2022',
      lib: {entry: fileURLToPath(new URL('./webauthn-web-client-fixture.mjs', import.meta.url)), formats: ['es']},
      rolldownOptions: {output: {codeSplitting: false}},
    },
  });
  const chunks = output[0].output.filter(item => item.type === 'chunk');
  if (chunks.length !== 1) throw new Error('Expected one web account fixture module');
  const entry = '/__festapp_auth_fixture';
  await page.route('**/*', async route => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.origin !== origin.origin) return route.abort();
    if (url.pathname === entry) return route.fulfill({contentType: 'text/html',
      body: '<!doctype html><script type="module" src="/__festapp_auth_fixture.js"></script>'});
    if (url.pathname === entry + '.js') return route.fulfill({contentType: 'application/javascript', body: chunks[0].code});
    const upstream = url.pathname.startsWith('/auth/v1/') ? auth : url.pathname.startsWith('/rest/v1/') ? rest : null;
    if (!upstream) return route.abort();
    const requestBody = request.postDataBuffer();
    const headers = {...request.headers(), host: new URL(upstream).host};
    // The loopback harness presents both APIs on the fixture page's origin.
    // In deployments, the browser sends Origin on this cross-origin GET.
    if (url.pathname === '/auth/v1/festapp/mfa/channel' && request.method() === 'GET') {
      headers.origin ??= origin.origin;
    }
    delete headers['content-length'];
    const response = await fetch(upstream + url.pathname + url.search, {
      method: request.method(), headers, ...(requestBody && {body: requestBody}), redirect: 'manual',
    });
    const forwarded = Object.fromEntries([...response.headers].filter(([key]) =>
      !['content-encoding', 'content-length', 'transfer-encoding'].includes(key)));
    return route.fulfill({status: response.status, headers: forwarded, body: Buffer.from(await response.arrayBuffer())});
  });
  await page.goto(origin.origin + entry);
  const entryPoint = input.settingsCredentials ? 'mountFestappAccountSecurity'
    : input.recoveryCredentials ? 'mountFestappRecovery'
    : input.heldSession ? 'qualifyFestappGuestCheckout' : 'qualifyFestappPasskey';
  await page.waitForFunction(name => typeof window[name] === 'function', entryPoint);
  try {
    const result = await page.evaluate(({entryPoint, input}) => window[entryPoint](input), {entryPoint, input});
    if (input.recoveryCredentials) return await qualifyAccountRecovery(page, input.recoveryCode);
    return input.settingsCredentials ? await qualifyAccountSecurity(page) : result;
  } finally {
    await page.unroute('**/*');
  }
}

async function qualifyAccountRecovery(page, recoveryCode) {
  const panel = page.locator('account-recovery-panel');
  const method = panel.getByLabel('Replacement verification method');
  await method.selectOption('webauthn');
  const code = panel.getByLabel('Recovery code');
  const start = panel.getByRole('button', {name: 'Set up replacement'});
  await code.fill('z'.repeat(43));
  await start.click();
  await panel.getByRole('alert').filter({hasText: 'Verification failed.'}).waitFor({state: 'visible'});
  if (await code.inputValue()) throw new Error('The recovery form retained a rejected code');
  await code.fill(recoveryCode);
  await start.click();
  await panel.getByRole('status').filter({hasText: 'Your replacement method is verified.'}).waitFor({state: 'visible'});
  if (await code.count()) throw new Error('The confirmed recovery form retained a code input');
  return {access_token: await page.evaluate(() => window.festappRecoveryProof())};
}

async function qualifyAccountSecurity(page) {
  const panel = page.locator('.account-security');
  const failures = [];
  const recordFailure = response => {
    const pathname = new URL(response.url()).pathname;
    if (response.status() >= 400 && (pathname.startsWith('/auth/') || pathname.startsWith('/rest/'))) {
      failures.push(`${response.status()} ${pathname}`);
    }
  };
  page.on('response', recordFailure);
  try {
    return await walkAccountSecurity(panel, page);
  } catch (error) {
    const waiting = String(error.message).split('\n').find(line => line.includes('waiting for'));
    throw new Error([`Account security: ${String(error.message).split('\n')[0]}`, waiting, ...failures].filter(Boolean).join(' | '));
  } finally {
    page.off('response', recordFailure);
  }
}

async function walkAccountSecurity(panel, page) {
  const button = name => panel.getByRole('button', {name, exact: true});
  const status = text => panel.getByRole('status').filter({hasText: text}).waitFor({state: 'visible'});
  const idle = () => panel.and(page.locator('[aria-busy="false"]')).waitFor({state: 'visible'});
  await button('Add authenticator app').click();
  const qr = panel.getByRole('img', {name: 'Authenticator setup QR code'});
  await qr.waitFor({state: 'visible'});
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const secret = await panel.locator('code').textContent();
  const bits = [...secret.replace(/=+$/, '')]
    .map(character => alphabet.indexOf(character).toString(2).padStart(5, '0')).join('');
  const key = Buffer.from(bits.match(/.{8}/g).map(byte => Number.parseInt(byte, 2)));
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30000)));
  const mac = createHmac('sha1', key).update(counter).digest();
  const code = String((mac.readUInt32BE(mac.at(-1) & 15) & 0x7fffffff) % 1000000).padStart(6, '0');
  await panel.locator('input[autocomplete="one-time-code"]').fill(code);
  await panel.locator('button[type="submit"]').click();
  await status('Sign-in method added.');
  if (await panel.locator('code').count()) throw new Error('Confirmed TOTP setup still exposes a setup key');

  await button('Add security key').click();
  await status('Sign-in method added.');
  await idle();
  await button('Add passkey').click();
  await status('Sign-in method added.');
  await idle();
  const passkey = panel.getByText('Passkey', {exact: true}).locator('..');
  await passkey.getByRole('button', {name: 'Edit', exact: true}).click();
  await passkey.getByLabel('Passkey name', {exact: true}).fill('Travel passkey');
  await passkey.getByRole('button', {name: 'Save', exact: true}).click();
  await panel.getByText('Travel passkey', {exact: true}).waitFor({state: 'visible'});

  const totp = panel.getByText(/^Authenticator app · [A-Z2-7]{6}$/).locator('..');
  await totp.getByRole('button', {name: 'Remove', exact: true}).click();
  await totp.getByRole('button', {name: 'Remove', exact: true}).click();
  await status('Verification factor removed.');
  const webAuthn = panel.getByText(/^Security key · [A-Z2-7]{6}$/).locator('..');
  await webAuthn.getByRole('button', {name: 'Remove', exact: true}).click();
  const disable = button('Turn off two-factor authentication');
  await disable.waitFor({state: 'visible'});
  if (!await page.evaluate(() => window.festappSettingsSession())) {
    throw new Error('Opening the last-factor confirmation ended the session');
  }
  await disable.click();
  await idle();
  await page.waitForFunction(async () => !await window.festappSettingsSession());
  return {accountSettingsAgainstPinnedAuth: true};
}

try {
  async function virtualAuthenticator(userVerification) {
    const context = await browser.newContext();
    const page = await context.newPage();
    const cdp = await context.newCDPSession(page);
    await cdp.send('WebAuthn.enable');
    const {authenticatorId} = await cdp.send('WebAuthn.addVirtualAuthenticator', {options: {
      protocol: 'ctap2', transport: 'internal', hasResidentKey: true,
      hasUserVerification: userVerification, isUserVerified: userVerification,
    }});
    // For the HTTPS fixture Chromium signs a real secure origin. Serve the
    // empty page within this context without provisioning a local TLS trust root.
    if (origin.protocol === 'https:') {
      await page.route(origin.href, route => route.fulfill({contentType: 'text/html', body: '<!doctype html>'}));
    }
    await page.goto(origin.origin, {waitUntil: 'domcontentloaded'});
    return {page, cdp, authenticatorId};
  }
  const primary = await virtualAuthenticator(true);
  const withoutVerification = await virtualAuthenticator(false);
  const copiedFixtureCredentials = new Set();
  process.stdout.write(JSON.stringify({ready: true}) + '\n');
  for await (const line of createInterface({input: process.stdin, crlfDelay: Infinity})) {
    let request;
    try {
      request = JSON.parse(line);
      if (request.operation === 'client_sign_in') {
        const result = await qualifyWebClient(primary.page, request.options);
        process.stdout.write(JSON.stringify({id: request.id, credential: result}) + '\n');
        continue;
      }
      if (!['create', 'get'].includes(request.operation) || !request.options ||
          typeof request.options !== 'object') throw new Error('Invalid ceremony request');
      const authenticator = request.verified === false ? withoutVerification : primary;
      if (request.verified === false && request.operation === 'create') {
        // Registration must use a clean fixture authenticator so the normal
        // excludeCredentials check does not stop the browser first.
        await withoutVerification.cdp.send('WebAuthn.clearCredentials', {
          authenticatorId: withoutVerification.authenticatorId,
        });
        copiedFixtureCredentials.clear();
      }
      if (request.verified === false && request.operation === 'get') {
        // Use the same ephemeral fixture credential to exercise the server
        // rejection on a device without UV. The key stays in the test process.
        const {credentials} = await primary.cdp.send('WebAuthn.getCredentials', {
          authenticatorId: primary.authenticatorId,
        });
        for (const credential of credentials) {
          if (copiedFixtureCredentials.has(credential.credentialId)) continue;
          await withoutVerification.cdp.send('WebAuthn.addCredential', {
            authenticatorId: withoutVerification.authenticatorId, credential,
          });
          copiedFixtureCredentials.add(credential.credentialId);
        }
      }
      const credential = await authenticator.page.evaluate(async ({operation, options, verified}) => {
        const publicKey = operation === 'create'
          ? PublicKeyCredential.parseCreationOptionsFromJSON(options)
          : PublicKeyCredential.parseRequestOptionsFromJSON(options);
        if (verified === false) {
          // Exercise a standard ceremony which does not request local UV.
          if (operation === 'create') {
            publicKey.authenticatorSelection = {
              ...publicKey.authenticatorSelection,
              userVerification: 'discouraged',
              residentKey: 'discouraged',
              requireResidentKey: false,
            };
          } else {
            publicKey.userVerification = 'discouraged';
          }
        }
        const result = await navigator.credentials[operation]({publicKey});
        if (!result) throw new Error('No credential returned');
        return result.toJSON();
      }, request);
      process.stdout.write(JSON.stringify({id: request.id, credential}) + '\n');
    } catch (error) {
      process.stdout.write(JSON.stringify({id: request?.id, error: String(error.message)}) + '\n');
    }
  }
} finally {
  await browser.close();
}
