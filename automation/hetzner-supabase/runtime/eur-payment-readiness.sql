-- Read-only preflight for the canonical self-hosted EUR reference rollout.
-- Returns counts and booleans only; no account details or credentials.
WITH required_versions(version) AS (
  VALUES ('20260806001000'), ('20260806002000')
),
migration_state AS (
  SELECT jsonb_object_agg(
    r.version,
    EXISTS (
      SELECT 1 FROM supabase_migrations.schema_migrations m
      WHERE m.version = r.version
    )
  ) AS applied
  FROM required_versions r
),
eur_accounts AS (
  SELECT u.organization,
    count(DISTINCT ba.id) AS eur_account_count,
    count(DISTINCT ba.id) FILTER (
      WHERE nullif(trim(to_jsonb(ba)->>'creditor_name'), '') IS NOT NULL
    ) AS with_creditor_name_count,
    count(DISTINCT ba.id) FILTER (
      WHERE upper(regexp_replace(coalesce(ba.account_number, ''), '[[:space:]]', '', 'g'))
        ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'
    ) AS iban_shape_count
  FROM eshop.bank_accounts ba
  JOIN eshop.unit_bank_accounts uba ON uba.bank_account = ba.id
  JOIN public.units u ON u.id = uba.unit
  WHERE 'EUR' = ANY(ba.supported_currencies)
  GROUP BY u.organization
),
eur_account_usage AS (
  SELECT DISTINCT ba.id AS bank_account_id,
    u.organization,
    o.title AS organization_title,
    coalesce((
      SELECT count(*) FROM eshop.payment_info pi
      WHERE pi.bank_account = ba.id AND pi.currency_code = 'EUR'
    ), 0) AS eur_payment_info_count,
    coalesce((
      SELECT count(*) FROM eshop.payment_info pi
      WHERE pi.bank_account = ba.id AND pi.currency_code = 'EUR'
        AND pi.created_at >= now() - interval '30 days'
    ), 0) AS eur_payment_info_30d_count,
    coalesce((
      SELECT count(*) FROM eshop.payment_info pi
      WHERE pi.bank_account = ba.id AND pi.currency_code = 'EUR'
        AND pi.creditor_reference IS NOT NULL
    ), 0) AS eur_payment_info_with_reference_count,
    coalesce((
      SELECT count(*) FROM public.forms f
      WHERE f.bank_account = ba.id AND f.is_open
    ), 0) AS open_form_count
  FROM eshop.bank_accounts ba
  JOIN eshop.unit_bank_accounts uba ON uba.bank_account = ba.id
  JOIN public.units u ON u.id = uba.unit
  JOIN public.organizations o ON o.id = u.organization
  WHERE 'EUR' = ANY(ba.supported_currencies)
)
SELECT current_database() AS database_name,
  (SELECT applied FROM migration_state) AS migrations_applied,
  EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'eshop' AND table_name = 'payment_info'
      AND column_name = 'creditor_reference'
  ) AS creditor_reference_column_present,
  to_regprocedure('public.generate_creditor_reference(bigint)') IS NOT NULL
    AS generate_reference_function_present,
  to_regprocedure('public.is_valid_iban(text)') IS NOT NULL
    AS iban_validation_function_present,
  EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'create_ticket_order_internal_v1'
      AND pg_get_functiondef(p.oid) LIKE '%EUR_CREDITOR_NAME_REQUIRED%'
  ) AS live_order_creditor_name_guard_present,
  coalesce((SELECT jsonb_agg(to_jsonb(eur_accounts) ORDER BY organization)
    FROM eur_accounts), '[]'::jsonb) AS eur_accounts_by_organization,
  coalesce((SELECT jsonb_agg(to_jsonb(eur_account_usage)
    ORDER BY organization, bank_account_id) FROM eur_account_usage),
    '[]'::jsonb) AS eur_account_usage;
