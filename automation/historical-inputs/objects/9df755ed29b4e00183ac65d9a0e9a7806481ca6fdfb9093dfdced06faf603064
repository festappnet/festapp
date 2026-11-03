-- Forward-only snapshot extension; old attempts keep their original provider body.
ALTER TABLE eshop.stripe_checkout_attempts ADD COLUMN IF NOT EXISTS checkout_locale text NOT NULL DEFAULT 'auto'
  CHECK (checkout_locale IN ('auto','cs','en','de','pl','sk'));
