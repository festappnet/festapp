-- Product configuration and deletion must use the authorized, receipted
-- domain facades. Direct client DML would bypass product limits and type/layout
-- usage guards, including when the form capacity feature is disabled.
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON eshop.product_types,eshop.products FROM anon,authenticated;
