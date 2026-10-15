-- Ticket details look up seats by their order-product-ticket association.
-- Bound the write-lock wait; apply this small-table index with its ledger row
-- in the same transaction. No RPC or ticket-selection behavior changes.
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '15s';

CREATE INDEX spots_order_product_ticket_idx
  ON eshop.spots (order_product_ticket);
