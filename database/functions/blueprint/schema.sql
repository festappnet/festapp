-- Host commercial state is separate from the portable geometry.
ALTER TABLE eshop.blueprints ADD COLUMN IF NOT EXISTS layout jsonb;
ALTER TABLE eshop.blueprints ADD COLUMN IF NOT EXISTS layout_revision bigint NOT NULL DEFAULT 0 CHECK (layout_revision >= 0);
CREATE TABLE IF NOT EXISTS eshop.blueprint_seat_bindings (
 blueprint bigint NOT NULL REFERENCES eshop.blueprints(id) ON DELETE CASCADE,
 node_id uuid NOT NULL, spot bigint NOT NULL UNIQUE REFERENCES eshop.spots(id),
 selection_unit uuid, group_node uuid, blocked boolean NOT NULL DEFAULT false,
 PRIMARY KEY(blueprint,node_id)
);
CREATE INDEX IF NOT EXISTS blueprint_seat_selection_unit_idx ON eshop.blueprint_seat_bindings(blueprint,selection_unit);
CREATE TABLE IF NOT EXISTS eshop.blueprint_group_products (
 blueprint bigint NOT NULL REFERENCES eshop.blueprints(id) ON DELETE CASCADE,
 group_node uuid NOT NULL, product bigint NOT NULL REFERENCES eshop.products(id), PRIMARY KEY(blueprint,group_node)
);
CREATE TABLE IF NOT EXISTS eshop.blueprint_area_bindings (
 blueprint bigint NOT NULL REFERENCES eshop.blueprints(id) ON DELETE CASCADE,
 node_id uuid NOT NULL, inventory_context bigint NOT NULL REFERENCES public.inventory_contexts(id),
 product bigint NOT NULL REFERENCES eshop.products(id), PRIMARY KEY(blueprint,node_id), UNIQUE(blueprint,inventory_context)
);
ALTER TABLE eshop.blueprint_seat_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.blueprint_group_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.blueprint_area_bindings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.blueprint_seat_bindings,eshop.blueprint_group_products,eshop.blueprint_area_bindings FROM PUBLIC,anon,authenticated;

-- Existing canonical SECURITY DEFINER writers (including occasion copy) retain
-- the postgres owner across CREATE OR REPLACE. Application roles stay revoked.
ALTER TABLE eshop.blueprint_seat_bindings OWNER TO postgres;
ALTER TABLE eshop.blueprint_group_products OWNER TO postgres;
ALTER TABLE eshop.blueprint_area_bindings OWNER TO postgres;
