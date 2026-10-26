-- Fix Sequences for key tables to avoid collision with manually inserted data
-- This is often needed after restoring a dump or manual inserts with fixed IDs

-- Organizations
SELECT setval('organizations_id_seq', COALESCE((SELECT MAX(id) + 1 FROM organizations), 1), false);
-- Units
SELECT setval('units_id_seq', COALESCE((SELECT MAX(id) + 1 FROM units), 1), false);
-- Occasions
SELECT setval('occasions_id_seq', COALESCE((SELECT MAX(id) + 1 FROM occasions), 1), false);
-- Products (eshop schema)
SELECT setval('eshop.products_id_seq', COALESCE((SELECT MAX(id) + 1 FROM eshop.products), 1), false);
-- Product Types (eshop schema)
SELECT setval('eshop.product_types_id_seq', COALESCE((SELECT MAX(id) + 1 FROM eshop.product_types), 1), false);
-- Tickets (eshop schema)
SELECT setval('eshop.tickets_id_seq', COALESCE((SELECT MAX(id) + 1 FROM eshop.tickets), 1), false);
-- Users (if serial, but users is usually uuid in supabase auth, public.user_info is uuid. 
-- Wait, public.user_info ID is foreign key to auth.users (uuid). No sequence usually.
-- But verified bank_account_unlink_test uses 'organizations' and 'units' which likely use serial.

-- Forms (public schema)
SELECT setval('public.forms_id_seq', COALESCE((SELECT MAX(id) + 1 FROM public.forms), 1), false);
-- Secrets (eshop schema)
SELECT setval('eshop.secrets_id_seq', COALESCE((SELECT MAX(id) + 1 FROM eshop.secrets), 1), false);
-- Bank Accounts (eshop schema)
SELECT setval('eshop.bank_accounts_id_seq', COALESCE((SELECT MAX(id) + 1 FROM eshop.bank_accounts), 1), false);
