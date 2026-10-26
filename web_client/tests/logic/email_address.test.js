import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { isValidEmail } from '../../src/logic/email_address.js';
const cases = JSON.parse(readFileSync(new URL('../../../shared/email/address-cases.json', import.meta.url)));
for (const { email, valid } of cases) test(JSON.stringify(email), () => assert.equal(isValidEmail(email), valid));
