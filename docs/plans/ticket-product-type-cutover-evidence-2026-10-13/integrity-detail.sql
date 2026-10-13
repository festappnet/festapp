BEGIN READ ONLY;
SELECT jsonb_build_object('kind','missing_product_detail','null_product',opt.product IS NULL,'ticket_state',t.state,'rows',count(*)) FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id=opt.ticket JOIN public.occasions o ON o.id=t.occasion LEFT JOIN eshop.products p ON p.id=opt.product WHERE o.organization=3 AND p.id IS NULL GROUP BY opt.product IS NULL,t.state ORDER BY 1;
COMMIT;
