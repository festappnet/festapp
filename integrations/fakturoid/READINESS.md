# Připravenost Fakturoid konektoru

Datum: 2026-11-12. Rozsah: vstupenky.online, příprava k oficiálnímu zalistování.
Jde o kontrolu aktuálního pracovního stromu, nikoli potvrzení produkčního stavu.

## Co současná implementace dělá

| Chování | Zdroj |
| --- | --- |
| Používá API v3 a OAuth Client Credentials s konfigurací `client_id`, `client_secret`, `slug`, `subject_id`, volitelně `note`. | `supabase/functions/send-ticket-order/fakturoid.ts` |
| Vytváří proformu, předává měnu, částku, bankovní údaje a VS z objednávky. | `supabase/functions/send-ticket-order/fakturoidPayload.ts` |
| Používá jeden souhrnný řádek s `vat_rate: 0` a předem nastavený kontakt; údaje pojmenovaného kupujícího doplňuje na doklad. | Stejné dva soubory. |
| Před vytvořením dohledává doklad přes identitu příkazu; nejednoznačný výsledek odmítá. Emailová fáze další proformu nevytváří. | `fakturoid.ts`, `fakturoid_test.ts` |
| Umí získat PDF existující proformy a podporuje výslovně vyžádané odstranění dokladu při smazání objednávky. | `fakturoid.ts`, `lib/components/eshop/views/order_delete_dialog.dart` |
| Konfigurace je v `eshop.external_services` navázaná na `unit`, tedy pořadatele, ne na jednotlivý formulář. | `database/functions/eshop/get_external_services.sql` |
| Povinná integrace Fakturoidu je v současných pravidlech neslučitelná se Stripe; hotovostní rezervace a předplacené dávky mají vlastní omezení. | `database/functions/eshop_stripe/form_availability.sql`, `database/functions/payment_providers/registry.sql`, `database/functions/eshop_ticket_batches/policy.sql` |

Není doložená automatická evidence úhrady ve Fakturoidu, vystavení konečné
faktury po zaplacení, dobropisy, rozpis produktů a jejich sazeb DPH ani veřejné
samoobslužné připojení. Tyto funkce nepatří do katalogového příslibu.
Existující souhrnná proforma s nulovou sazbou nestačí pro obecný příslib
fakturace libovolného pořadatele.

## Pořadí dokončení

1. Domluvit s Fakturoidem přijetí tohoto typu konektoru, požadované reference,
   podklady a nulové fixní poplatky vydavatele. Dotaz v `submission/` byl
   odeslán 2026-11-13; odpověď zatím není doložená.
2. Zaregistrovat jednu veřejnou OAuth aplikaci. Implementovat Authorization
   Code Flow, souhlas ve Fakturoidu, výběr účtu při více účtech a odpojení.
   Připojení smí spravovat jen oprávněný uživatel příslušného pořadatele.
3. Ukládat a obnovovat tokeny pouze na serveru přes existující chráněné
   úložiště. Svázat OAuth `state` s uživatelem, pořadatelem a jednorázovou
   expirující relací; zabránit záměně pořadatele, opakovanému callbacku
   a souběžnému přepsání obnoveného tokenu. Neposílat tajné hodnoty klientovi,
   do logů ani dokumentace. Návrh oprávnění a ukládání vyžaduje kontrolu
   současných kanonických vlastníků před implementací.
4. Výslovně určit podporovaný účetní rozsah: buď omezená proforma pro
   odpovídající pořadatele, nebo doplněný model kontaktů, položek a DPH.
   Neslibovat plnou fakturaci jen na základě dnešního payloadu.
5. V testovacím účtu ověřit připojení dvou oddělených pořadatelů, obnovu a
   odvolání tokenů, vytvoření a načtení proformy/PDF, zachování VS a obnovu
   po neurčité odpovědi bez duplicitního dokladu. Nepoužívat živé objednávky.
6. Doplnit skutečný český návod podle hotového rozhraní a veřejnou URL,
   schválené reference a případné skutečné snímky v češtině a světlém režimu.
   Teprve poté podat žádost o zařazení a ověřit veřejný katalogový záznam.

Úprava autentizace zasahuje přístupové údaje a fakturaci: vyžaduje standardní
cílené kontroly, tenantovou izolaci a normální publikační brány repozitáře.
Tato příprava neprovádí změnu autentizace, migraci ani nasazení.

## Lokální ověření existujícího základu

```sh
deno test supabase/functions/send-ticket-order/fakturoid_test.ts
```

Sada nahrazuje externí HTTP odpovědi. Ověřuje gateway a payload včetně VS,
opakování, nejednoznačné identity a mazání; nedokládá živé API, produkční
konfiguraci, OAuth připojování ani schválení Fakturoidem.

Výsledek 2026-11-12: **18 testů prošlo, 0 selhalo**. Lokální odkazy všech
pěti připravených souborů byly zkontrolovány bez chyb. Implementační soubory
nebyly v rámci této přípravy měněny.
