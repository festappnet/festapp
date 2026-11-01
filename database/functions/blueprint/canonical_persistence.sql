-- Apply only after the reviewed data cutover. New plans start in the sole
-- canonical representation; old clients/scripts cannot recreate retired state.
ALTER TABLE eshop.blueprints ALTER COLUMN layout SET DEFAULT
 '{"schemaVersion":2,"symbolSetVersion":1,"canvas":{"x":0,"y":0,"width":1120,"height":2080,"fill":"#ffffffff"},"styles":{},"seatingDefaults":{},"textPolicy":{"language":"und","direction":"auto"},"nodes":[]}'::jsonb;
ALTER TABLE eshop.blueprints ADD CONSTRAINT blueprints_canonical_layout_check
 CHECK(coalesce(layout IS NOT NULL AND jsonb_typeof(layout)='object'
 AND layout->'schemaVersion'='2'::jsonb AND layout->'symbolSetVersion'='1'::jsonb
 AND jsonb_typeof(layout->'canvas')='object' AND jsonb_typeof(layout->'nodes')='array'
 AND jsonb_typeof(layout->'styles')='object' AND jsonb_typeof(layout->'seatingDefaults')='object'
 AND jsonb_typeof(layout->'textPolicy')='object',false)) NOT VALID;
ALTER TABLE eshop.blueprints VALIDATE CONSTRAINT blueprints_canonical_layout_check;
ALTER TABLE eshop.blueprints ALTER COLUMN layout SET NOT NULL;
ALTER TABLE eshop.blueprints ADD CONSTRAINT blueprints_retired_geometry_empty_check
 CHECK(configuration IS NULL AND objects IS NULL AND groups IS NULL AND background_svg IS NULL) NOT VALID;
ALTER TABLE eshop.blueprints VALIDATE CONSTRAINT blueprints_retired_geometry_empty_check;
