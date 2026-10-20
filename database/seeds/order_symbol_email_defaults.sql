-- Canonical global order content. Imported global rows can share a code; keep
-- their IDs, but synchronize every copy so the resolver cannot select stale text.
-- Tenant/unit/occasion overrides and prepared/accepted messages are untouched.
WITH defaults(code, subject, html) AS (VALUES
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
{{balanceReasoning}}
<p>Těšíme se na setkání!</p>
<p>Organizační tým {{occasionTitle}}</p>
<p>Symbol objednávky: <strong>{{orderSymbol}}</strong></p>'),
('TICKET_ORDER_STORNO','{{occasionTitle}} - Storno rezervace','<p>Ahoj,</p>
<p>Tvá objednávka na akci {{occasionTitle}} byla stornována.</p>
<p>&nbsp;</p>
<p>Přejeme pěkný den</p>
<p>Organizační tým {{occasionTitle}}</p>
<p>Symbol objednávky: <strong>{{orderSymbol}}</strong></p>'),
('TICKET_ORDER_CONFIRMATION','{{occasionTitle}} - Potvrzení objednávky','<h3>{{occasionTitle}}</h3>
<p>Ahoj, potvrzujeme Tvou registraci na akci <strong>{{occasionTitle}}</strong>.</p>
{{balanceReasoning}}
{{fullOrder}}
<p>Těšíme se na setkání!</p>
<p>Organizační tým {{occasionTitle}}</p>
')
), canonical AS (
  SELECT code, subject || ' - {{orderSymbol}}' AS subject, html FROM defaults
), updated AS (
  UPDATE public.email_templates e
  SET subject = d.subject, html = d.html
  FROM canonical d
  WHERE e.code = d.code
    AND e.organization IS NULL AND e.unit IS NULL AND e.occasion IS NULL
  RETURNING e.code
)
INSERT INTO public.email_templates(code, subject, html, title)
SELECT d.code, d.subject, d.html, d.code FROM canonical d
WHERE NOT EXISTS (
  SELECT 1 FROM public.email_templates e WHERE e.code = d.code
    AND e.organization IS NULL AND e.unit IS NULL AND e.occasion IS NULL
);
