-- Update the stock payment subject while preserving any customized subject.
UPDATE public.email_templates
SET subject = '{{occasionTitle}} - {{orderStatusSubject}} - {{orderSymbol}}'
WHERE code = 'TICKET_ORDER_PAYMENT_DONE'
  AND organization IS NULL AND unit IS NULL AND occasion IS NULL
  AND subject = '{{occasionTitle}} - Přijatá platba - {{orderSymbol}}';
