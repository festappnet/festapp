# Propojení vstupenky.online s Fakturoidem

Pracovní podklad k návodu, 2026-11-12. Veřejné samoobslužné připojení zatím
není doložené; tento dokument není oznámením dostupnosti ani návodem ke
klikání v hotovém rozhraní.

## K čemu propojení slouží

Propojení umožňuje při přípravě objednávky vstupenek vytvořit ve Fakturoidu
proformu. Doklad dostane variabilní symbol objednávky. Existující napojení
pracuje s nastavením pořadatele, které může ovlivnit více jeho akcí.

## Co si předem ujasnit

- Jaký účet Fakturoidu a který pořadatel budou propojeni.
- Zda účet a jeho tarif umožňují potřebné použití API.
- Zda Vám vyhovuje proforma s jedním souhrnným řádkem a nulovou sazbou DPH.
  Vhodnost účetního postupu ověřte se svou účetní.
- Jaké platební metody potřebujete. Současné propojení má omezení pro Stripe,
  hotovostní rezervace a předplacené dávky; dostupnost musí potvrdit nastavení
  konkrétního způsobu prodeje.

Automatické označování dokladů jako uhrazených, vystavení konečné faktury
a dobropisů nejsou v tomto rozsahu doložené.

## Bezpečné připojení

Pro veřejný konektor připravujeme připojení s udělením souhlasu přímo ve
Fakturoidu. Tento postup ještě není připravený k použití. Hesla ani přístupové
klíče neposílejte e-mailem.

Před zveřejněním sem patří skutečné kroky hotového rozhraní: připojení účtu,
volba pořadatele a účtu Fakturoidu, kontrolní objednávka, ověření proformy
a odpojení. Postup musí být ověřený na testovacích datech a odpovídat
skutečně nasazené verzi.

Technický stav a podmínky zařazení: [příprava konektoru](../../integrations/fakturoid/README.md).
