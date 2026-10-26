import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildCsvInviteAuditSql,
  collectCsvInviteAudit,
  invitationConsistencyFailures,
  participantsToCsv,
} from '../audit_csv_invites.mjs';

const target = {
  projectRef: 'canonicalref',
  organization: 9,
  occasionLink: 'csmostrava2026',
  accessToken: 'secret',
};

test('audit SQL is read-only and scopes the canonical occasion', () => {
  const sql = buildCsvInviteAuditSql(target);
  assert.match(sql, /link = 'csmostrava2026'/);
  assert.match(sql, /organization = 9/);
  assert.match(sql, /SIGN_IN_CODE/);
  assert.doesNotMatch(
    sql,
    /(?:^|;)\s*(?:UPDATE|DELETE|INSERT|ALTER|DROP|GRANT|REVOKE)\b/im,
  );
});

test('audit fails closed when configured occasion is absent', async () => {
  await assert.rejects(
    collectCsvInviteAudit(target, {
      query: async () => [{ result: { target: null, summary: {}, participants: [] } }],
    }),
    /Canonical occasion is absent/,
  );
});

test('audit keeps participant-level send and sign-in evidence', async () => {
  const participant = {
    name: 'Marie',
    surname: 'Vomelová',
    accountEmail: 'shared+1@example.com',
    deliveryEmail: 'shared@example.com',
    invited: true,
    sendCount: 2,
    firstSendAt: '2026-07-29T08:00:00Z',
    lastSendAt: '2026-07-30T08:00:00Z',
    lastSignInAt: '2026-07-30T09:00:00Z',
    signedInAfterFirstSend: true,
  };
  const report = await collectCsvInviteAudit(target, {
    query: async () => [{ result: {
      target: { id: 643, organization: 9, link: target.occasionLink },
      summary: { sentMoreThanOnce: 1 },
      participants: [participant],
    } }],
  });
  assert.equal(report.participants[0].sendCount, 2);
  assert.equal(report.participants[0].signedInAfterFirstSend, true);
});

test('CSV export quotes user data and never includes access credentials', () => {
  const csv = participantsToCsv([{
    name: 'Marie, Jana',
    surname: 'Vomelová',
    accountEmail: 'shared+1@example.com',
    deliveryEmail: 'shared@example.com',
    invited: true,
    sendCount: 2,
  }]);
  assert.match(csv, /^name,surname,account_email/);
  assert.match(csv, /"Marie, Jana"/);
  assert.doesNotMatch(csv, /secret|accessToken|userId/);
});

test('CSV export neutralizes spreadsheet formulas in personal data', () => {
  const csv = participantsToCsv([{
    name: '=HYPERLINK("https://example.test")',
    surname: '+formula',
    accountEmail: 'safe@example.com',
    deliveryEmail: 'safe@example.com',
  }]);
  assert.match(csv, /"'=HYPERLINK/);
  assert.match(csv, /'\+formula/);
});

test('consistency check catches both invitation split-brain directions', () => {
  assert.deepEqual(invitationConsistencyFailures({
    acceptedLogWithoutRecipient: 1339,
    legacyInvitedFlagRows: 2,
  }), [
    '1339 accepted sends lack recipient_user',
    '2 legacy is_invited flags remain',
  ]);
  assert.deepEqual(invitationConsistencyFailures({
    acceptedLogWithoutRecipient: 0,
    legacyInvitedFlagRows: 0,
  }), []);
});
