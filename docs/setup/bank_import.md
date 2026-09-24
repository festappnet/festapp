# Bank Account Email Import System

This feature allows the system to automatically import bank transactions by
parsing incoming emails from banks (e.g., Fio, AirBank).

## Canonical transaction and pairing contract

Both e-mail and API imports are ingest adapters. They store a transaction and
delegate automatic decisions to `public.match_bank_transaction`; only
`public.apply_transaction_pairing` may change the payment-info link, derived
paid/returned totals, order state, and pairing audit.

Fio fields have fixed meanings:

- `column22` → bank movement `transaction_id`;
- `column17` and Fio e-mail `ID pokynu` → `command_id`;
- `column27` → raw `payer_reference`;
- `column5`, `column7`, `column16`, and `column25` retain VS/reference text.

Never deduplicate on amount, date, payer name, or VS. A transport retry uses
the same `(bank_account_id, external_id)` and an API retry uses the same
`(bank_account_id, transaction_id)`. E-mail/API reconciliation is allowed only
when a provider-issued shared identifier has the same verified meaning. An
e-mail without such an identity is stored but remains unpaired.

Matcher verdicts are `paired`, `already_paired`, `unmatched`, `ambiguous`, and
`ineligible`. Only `paired` changes accounting state. Ambiguous transactions
must be reviewed through the authorized manual UI; do not add a fuzzy fallback.

EUR orders use ISO 11649 references in the form `RF{check digits}{numeric
payment-info id}`. The RF prefix and check digits are mandatory; the payload is
otherwise numeric. Customer activation requires a valid IBAN and explicit legal
`creditor_name` on the bank account. Run the authorized real-bank pilot before
deploying the RF activation migration.

## Documentation Map

- **Architecture**: [AI context](../architecture/ai_context.md).
- **Database**: [Database architecture](../architecture/database.md).
- **Automation**: [Automation reference](../../automation/README.md).

## Setup Guide

### 1. AWS Configuration (SES & SNS)

We use a script to automate the AWS setup. **Prerequisites:** AWS CLI installed
and configured.

**IMPORTANT:** We use a **Subdomain** (`bank.festapp.net`) to avoid breaking
your main email.

1. Run the setup script:
   ```bash
   ./automation/setup_aws_ses.sh
   ```
2. If prompted (or if emails don't arrive), verify the subdomain:
   ```bash
   aws ses verify-domain-identity --domain bank.festapp.net --region eu-central-1
   ```
3. Ensure your DNS **MX Record** for `bank` points to AWS (not your root
   domain).

### 2. DNS Verification

Run the helper script for the subdomain:

```bash
./automation/check_dns_setup.sh bank.festapp.net
```

### 3. Supabase Deployment

Apply the current ordered `supabase/migrations/` set through the approved
database release workflow. The operator-only `instance-install` function is not
a production deployment path. Preserve the required pre-cutover parity across
the self-hosted target and cloud sources `default` and `a`.

**Edge Function:**

```bash
supabase functions deploy bank-mail-parser --project-ref <PROJECT_REF> --no-verify-jwt
```

The runtime must define the exact `AWS_SNS_TOPIC_ARN`. Before canonical
subscription, set the topic to Signature Version 2 and retain the resulting AWS
receipt as cutover evidence:

```bash
aws sns set-topic-attributes --topic-arn <TOPIC_ARN> \
  --attribute-name SignatureVersion --attribute-value 2
```

### 4. Verification Check (Critical)

New SNS subscriptions start in **PendingConfirmation**. They must be confirmed
before AWS sends any emails.

1. Check Status:
   ```bash
   aws sns list-subscriptions-by-topic \
     --topic-arn "arn:aws:sns:<region>:<account-id>:<topic-name>" \
     --region <region>
   ```
2. **If "PendingConfirmation"**:
   - Go to **AWS Console > SNS > Subscriptions**.
   - Select the subscription and click **Request confirmation**.
   - Check **Supabase Edge Function Logs**. The function auto-confirms only
     after the exact-topic Signature Version 2 proof passes; it never logs the
     confirmation URL or token.

## Testing

Run the local parser and pairing integration coverage without live credentials:

```bash
cd workers/image-worker
npx vitest run tests/integration/bank-import.test.ts
cd ../..

deno test --allow-env --allow-net --allow-read \
  supabase/functions/bank-mail-parser/test_parser.ts \
  supabase/functions/bank-mail-parser/test_parser_comprehensive.ts \
  supabase/functions/bank-mail-parser/snsVerification_test.ts
```

### Test with REAL Email (End-to-End)

This script sends an actual email via AWS SES and writes to the configured
canonical database. Run it only as an explicitly authorized production canary;
keep token and service-role values out of shell history and logs.

```bash
node tests/integration/bank_import_real.js --existing-token "YOUR_TOKEN" --from "info@festapp.net"
```

- Requires `aws configure` to be set up.
- `--from` must be a verified sender in your AWS SES.
