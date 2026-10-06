BEGIN;
-- Global default order templates only. Tenant/unit/occasion overrides and
-- previously prepared/accepted messages remain unchanged. Keep original design.
INSERT INTO public.email_templates(code,subject,html,title)
SELECT d.code,d.subject,d.html,d.code FROM (VALUES
('TICKET_ORDER_UPDATE','{{occasionTitle}} - Změna objednávky','<p>Ahoj,</p>
<p>Tvá objednávka na akci {{occasionTitle}} byla změněna.</p>
{{changeOverview}}
{{balanceReasoning}}
{{fullOrder}}
<p>&nbsp;</p>
<p>Přejeme pěkný den</p>
<p>Organizační tým {{occasionTitle}}</p>'),
('TICKET_ORDER_REMINDER','{{occasionTitle}} - Připomínka objednávky','<p>Ahoj,</p>
{{balanceReasoning}}
{{fullOrder}}
<p>Přejeme pěkný den</p>
<p>Organizační tým {{occasionTitle}}</p>'),
('TICKET_ORDER_PAYMENT_DONE','{{occasionTitle}} - Přijatá platba','<h3>Tvá platba na akci {{occasionTitle}} dorazila</h3>
<p>Ahoj,<br>
potvrzujeme přijetí platby za Tvou registraci na akci {{occasionTitle}}.</p>
<p>&nbsp;</p>
<p>Těšíme se na setkání!</p>
<p>Organizační tým {{occasionTitle}}</p>'),
('TICKET_ORDER_STORNO','{{occasionTitle}} - Storno rezervace','<p>Ahoj,</p>
<p>Tvá objednávka na akci {{occasionTitle}} byla stornována.</p>
<p>&nbsp;</p>
<p>Přejeme pěkný den</p>
<p>Organizační tým {{occasionTitle}}</p>'),
('TICKET_ORDER_CONFIRMATION','{{occasionTitle}} - Potvrzení objednávky','<h3>{{occasionTitle}}</h3>
Ahoj, potvrzujeme Tvou registraci na akci <strong>{{occasionTitle}}</strong>.
{{balanceReasoning}}
{{fullOrder}}
<p>Těšíme se na setkání!</p>
<p>Organizační tým {{occasionTitle}}</p>
')
) AS d(code,subject,html)
WHERE NOT EXISTS(SELECT 1 FROM public.email_templates e WHERE e.code=d.code AND e.organization IS NULL AND e.unit IS NULL AND e.occasion IS NULL);

UPDATE public.email_templates
SET subject=CASE WHEN subject LIKE '%{{orderSymbol}}%' THEN subject ELSE subject || ' - {{orderSymbol}}' END,
    html=CASE WHEN html LIKE '%{{orderSymbol}}%' OR html LIKE '%{{fullOrder}}%' THEN html
        ELSE html || '<p>Symbol objednávky: <strong>{{orderSymbol}}</strong></p>' END
WHERE organization IS NULL AND unit IS NULL AND occasion IS NULL
    AND code IN ('TICKET_ORDER_CONFIRMATION','TICKET_ORDER_UPDATE','TICKET_ORDER_STORNO','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER');

COMMIT;
