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

- **Architecture**: `AI_README.md` (See "Split Brain Logic" and "Supabase
  Interactions").
- **Database**: `database/README.md`.
- **Automation**: `automation/README.md`.

## Setup Guide

### 1. AWS Configuration (SES & SNS)

We use a script to automate the AWS setup. **Prerequisites:** AWS CLI installed
and configured.

**IMPORTANT:** We use a **Subdomain** (`bank.festapp.net`) to avoid breaking
your main email.

1. Run the setup script:
   ```bash
   ../../automation/setup_aws_ses.sh
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
../../automation/check_dns_setup.sh bank.festapp.net
```

### 3. Supabase Deployment

**Database:**

- **New Instances**: Managed by `instance-install`.
- **Existing Instances**: Run
  `supabase/migrations/20260124000000_email_sync_columns.sql`.

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
   aws sns list-subscriptions-by-topic --topic-arn "arn:aws:sns:eu-central-1:274371802740:festapp-bank-emails" --region eu-central-1
   ```
2. **If "PendingConfirmation"**:
   - Go to **AWS Console > SNS > Subscriptions**.
   - Select the subscription and click **Request confirmation**.
   - Check **Supabase Edge Function Logs**. The function auto-confirms only
     after the exact-topic Signature Version 2 proof passes; it never logs the
     confirmation URL or token.

## Testing

### Locations

- **Integration Tests**: `tests/integration/`
- **Test Data**: `tests/integration/fixtures/`

### Test with Personal Email (Simulation)

You can simulate an incoming email using your own text file.

1. Create a file `my_email.txt` with the raw email content.
2. Run the test:
   ```bash
   export SUPABASE_URL=...
   export SUPABASE_SERVICE_ROLE_KEY=...
   node tests/integration/bank_import.js --email-file tests/integration/fixtures/fio-sample.txt --token "00000000-0000-0000-0000-00000000TEST"
   ```
   _Replace the file path with your own if needed._

### Test with REAL Email (End-to-End)

This script sends an actual email via AWS SES and waits for it to appear in the
DB.

```bash
node tests/integration/bank_import_real.js --existing-token "YOUR_TOKEN" --from "info@festapp.net"
```

- Requires `aws configure` to be set up.
- `--from` must be a verified sender in your AWS SES.
