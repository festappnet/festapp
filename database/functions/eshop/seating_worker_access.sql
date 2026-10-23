-- The durable email/PDF worker invokes these enrichers as service_role.
-- Keep client access revoked; no geometry writes are granted.
GRANT SELECT ON eshop.blueprint_seat_bindings, eshop.blueprint_area_bindings TO service_role;
