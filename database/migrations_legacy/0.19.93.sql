-- Complete the inventory spot shape used by the inventory RPCs.
--
-- Some legacy projects received the inventory functions and the pool/resource
-- tables without the corresponding nullable columns on eshop.spots.  Keep this
-- migration additive and idempotent so those projects can be repaired without
-- rewriting existing tickets or allocations.
BEGIN;

ALTER TABLE eshop.spots
  ADD COLUMN IF NOT EXISTS inventory_context BIGINT NULL,
  ADD COLUMN IF NOT EXISTS resource BIGINT NULL,
  ADD COLUMN IF NOT EXISTS resource_slot BIGINT NULL,
  ADD COLUMN IF NOT EXISTS state TEXT NULL;

DO $constraints$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'eshop.spots'::regclass
      AND conname = 'spots_inventory_context_fkey'
  ) THEN
    ALTER TABLE eshop.spots
      ADD CONSTRAINT spots_inventory_context_fkey
      FOREIGN KEY (inventory_context)
      REFERENCES public.inventory_contexts(id)
      ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'eshop.spots'::regclass
      AND conname = 'spots_resource_fkey'
  ) THEN
    ALTER TABLE eshop.spots
      ADD CONSTRAINT spots_resource_fkey
      FOREIGN KEY (resource)
      REFERENCES public.resources(id)
      ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'eshop.spots'::regclass
      AND conname = 'spots_resource_slot_fkey'
  ) THEN
    ALTER TABLE eshop.spots
      ADD CONSTRAINT spots_resource_slot_fkey
      FOREIGN KEY (resource_slot)
      REFERENCES public.resource_slots(id)
      ON DELETE SET NULL;
  END IF;
END
$constraints$;

COMMIT;
