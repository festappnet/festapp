# AWS SES Email Forwarding Setup

This guide helps you set up AWS SES to receive emails (e.g.,
`bank.token@festapp.net`) and forward them to your Supabase Edge Function
(`bank-mail-parser`).

## Prerequisites

1. **AWS Account** with permissions to manage SES and SNS.
2. **AWS CLI** installed and configured (if using the automation script).
   - _Mac_: `brew install awscli`
   - _Config_: Run `aws configure` (Provide Key ID, Secret, Region e.g.,
     `eu-central-1`).
3. **Domain Access** (to add DNS records).

---

## Option A: Automated Setup (Recommended)

I have created a script to automate the resource creation.

1. **Install AWS CLI** (if not installed):
   ```bash
   brew install awscli
   aws configure
   ```
2. **Run the Script**:
   ```bash
   ../../automation/setup_aws_ses.sh
   ```
   - You will be asked for your **Edge Function URL**.
   - Deploy your functions first:
     `supabase functions deploy bank-mail-parser --no-verify-jwt`.
   - Set `AWS_SNS_TOPIC_ARN` on the Function and require SNS Signature Version
     2 before pointing the subscription at canonical production:
     `aws sns set-topic-attributes --topic-arn <ARN> --attribute-name SignatureVersion --attribute-value 2`.
   - URL format:
     `https://<project-ref>.supabase.co/functions/v1/bank-mail-parser`.

---

## Option B: Manual Setup (AWS Console)

If you prefer using the web interface:

### 1. Create SNS Topic

1. Go to **Amazon SNS** > **Topics** > **Create topic**.
2. Type: **Standard**.
3. Name: `festapp-bank-emails`.
4. Click **Create topic**.
5. Set the topic message signature version to `2` (SHA-256).

### 2. Subscribe Edge Function

1. In the created topic, click **Create subscription**.
2. Protocol: **HTTPS**.
3. Endpoint: Your Edge Function URL.
4. Click **Create subscription**.
5. _Note:_ The subscription will be "PendingConfirmation". The Edge Function
   code I wrote automatically confirms it when AWS sends the challenge. Refresh
   after a minute.

### 3. Configure SES Domain & Receipt Rule

1. Go to **Amazon SES** > **Configuration** > **Verified identities**.
2. Click **Create identity** > **Domain**.
3. Enter `festapp.net` (or your domain).
4. **IMPORTANT**: Check "Publish DNS records to Route53" (if you use AWS DNS) OR
   copy the **CNAME** and **TXT** records provided.
5. Go to **Email receiving** > **Receipt rule sets**.
6. Create a rule set (e.g., `festapp-rules`) if none exists. Set it as
   **Active**.
7. Create a **Rule**:
   - **Name**: `bank-to-sns`
   - **Recipients**: Leave empty (to match all) OR enter `bank@festapp.net`
     (requires exact match setup) or verify the domain to capture
     subdomain/patterns. _Recommendation: Verify the domain identity._
   - **Actions**: Add **SNS** action -> Choose `festapp-bank-emails`. Encoding:
     `UTF-8`.
   - Save.

---

## Domain Setup (DNS Records)

To receive emails, you **MUST** add these records to your DNS provider (GoDaddy,
Namecheap, Cloudflare, etc.).

### 1. Verification (TXT)

AWS will provide a TXT record to prove ownership.

- **Type**: `TXT`
- **Name**: `_amazonses` (or `_amazonses.festapp.net`)
- **Value**: (Copied from SES Console)

### 2. Receiving Emails (MX)

Point your domain's email traffic to AWS SES.

- **Type**: `MX`
- **Name**: `@` (root)
- **Value**: `10 inbound-smtp.eu-central-1.amazonaws.com`
  - _Note_: The region (`eu-central-1`) must match where you set up SES.
  - _Warning_: This will handle **ALL** incoming email for the domain. If you
    have existing email handling (like Gmail or Outlook), you generally cannot
    mix them easily on the same root domain. Use a **subdomain** (e.g.,
    `bank.festapp.net`) if you want to keep existing email.

#### Using a Subdomain (Recommended for safety)

If you verify `bank.festapp.net`:

- **MX Record**: `bank.festapp.net` ->
  `10 inbound-smtp.eu-central-1.amazonaws.com`
- **Email**: `any-token@bank.festapp.net`.
- You must verify the subdomain identity in SES.
