# Shoptet - první adaptér e-shopového konektoru

Historický výzkum a návrh z 29. 10. 2026, začleněný 6. 11. 2026. Nejde o implementaci ani novou autorizaci realizace. Tehdejší záznamy o neodeslání jsou překonané [stavem potvrzeným vlastníkem 1. 11.](../plans/shoptet-partner-onboarding-2026-10-26.md): návrh byl odeslán, čeká se na odpověď a další podání se neposílá.

29. 10. 2026. Stav: připravený provider návrh, implementace ani oprávnění k provozu nejsou hotové. Vlastník vybral společný kapacitní kontrakt varianty A. Nadřazená architektura: [Commerce Connectors](commerce-connectors.md); realizace: [plán](../plans/commerce-connectors-plan-2026-10-29.md).

## Role adaptéru

Shoptet adaptér překládá konkrétní HTTP, autentizaci a podpisy do společného interface. Nevlastní alokaci, order/ticket identity, finanční součty ani rozesílání. Nový e-shop dostane jiný provider adaptér a distribuci extensionu; nedostane kopii těchto doménových pravidel.

Kanonické soubory po implementaci: `supabase/functions/_shared/commerce/providers/shoptet.ts`, `integrations/shoptet/src/` a `integrations/shoptet/manifest.json`. Nemá vzniknout druhý `_shared/shoptet/checkout.ts` s kopií společného orchestrátoru ani `shoptet_orders`/`shoptet_tickets`.

## Překlad provider interface

| Společná operace | Shoptet operace | Nezbytná kontrola |
| --- | --- | --- |
| readCart | GET `/api/shipping-request/{shippingRequestCode}/{shippingGuid}` | Token ověřené instalace; returned shop identity, položky a měna; žádné browserové ceny. |
| publishAuthorization | PUT stejné cesty | Neměnný payload, expires a verificationCode v odpovědi; výsledek nesmí být zapsaný před potvrzením. |
| observeAuthorization | GET stejné cesty + `/status` | pending/acceptedOrder podle validovaných dat. cancelled/open/404 není automaticky provenUnusable. |
| readOrder | GET `/api/orders/{code}` | Stabilní code, line identity, ceny a finanční facts; kontrola vazby na původní nabídku. |
| verifyEvent | Ověření raw webhooku instalačním podpisovým klíčem | VerifiedEvent teprve po validaci; durable generic inbox před ack. |
| revokeAuthorization | Prozatím není prokázaná nevratná provider operace | Browserový invalidate a PUT se starou expirací nejsou bez důkazu synonymem revokace. |

Jde o adaptér pro schválený shipping-addon typ a digitální doručení, nikoli o platební bránu. Rozdíl mezi popisem v průvodci a skutečnou API cestou s shippingGuid řeší pouze adaptér. [Oficiální kontrakt](https://developers.shoptet.com/shipping-addons/), [strojové schéma](../plans/shoptet-direction-evidence-2026-10-29/public-contract.json).

Konkrétní OAuth získání tokenů navazuje na oficiální instalaci. Callback nejprve uloží ověřenou merchant identitu; Festapp unit se nepřevezme z callback query. Propojení provede následná autentizovaná admin operace s důkazem merchant vlastnictví a oprávněním k akci. Credential token je serverový a per-installation. Veřejné browser API nikdy nevrátí Shoptet-Access-Token.

## Provider metadata a normalizace

CheckoutRef = shippingRequestCode, providerMethodRef = shippingGuid. Jedna podporovaná metoda na mapování pro první profil. VerificationCode je providerAuthorizationRef nabídky; chránit jako bearer citlivé pole. App identity + eshopId tvoří stabilní merchant identitu přes reinstall; credential generation určuje oprávnění, nikoli obchodní jedinečnost.

Mapping potřebuje productGuid a neprůhledný variantCode/SKU; měna CZK a explicitní occasion/form/product binding. Aktuální shipping-request schema nedokládá stabilní line ID nebo revizi košíku. Dokud není prokázaný provider kontrakt změn, žádná in-place výměna již zveřejněné nabídky a žádná normalizace array indexu na trvalou identitu položky. Veřejný klient nesmí vložit nevlastněný mapping nebo cizí spot ID.

paid v detailu může být true/false/null a paymentTransactions mají transactionId, amount/status/čas. První testovací metoda musí určit, které přesné hodnoty dokazují plnou úhradu a jak rozlišit ruční paid od automatického provider potvrzení. PENDING/FAILED/UNKNOWN ani libovolný název order statusu nevydávají ticket. Aggregate paid se nesčítá s pohybovými facts jako další úhrada. [Detail](https://api.docs.shoptet.com/shoptet-api/openapi/orders/getorderdetail).

## Konfigurace doručení a profil košíku

Kandidát je označit vstupenky jako atypickou dopravu a jako jedinou odpovídající metodu nakonfigurovat digitální doručení konektoru. Oficiální nápověda uvádí filtrování dopravy touto vlastností. To nenahrazuje test přímého podvržení jiné metody a obnoveného košíku. [Dopravy](https://podpora.shoptet.cz/dopravy/).

Smíšené fyzické zboží není automaticky podporované, protože jeden košík vybírá způsob doručení. Ani samotné pole „bez dopravy zdarma“ nebo dostupnost produktu není důkaz zajištěné rezervace. Serverové ověření všech podporovaných cest je G2. Runtime drift konfigurace pozastaví nové nabídky, ne uvolní existující claims.

## Kdy je adaptér připravený

G1: zpřístupněný provider typ; G2: nabídku nelze obejít; G3: ověřená vazba na obsah/pořadí změn; G4: prokázaná finalita nepřijetí; G5: finanční sémantika konkrétní metody. Důkazy se uloží do manifestu kontraktu a navážou na přesnou testovanou verzi.

Pro vlastní kontrolu jsou připravené [S1-S10](../plans/shoptet-self-verification-2026-10-29.md). Zatím neproběhly. Veřejný frontend checkout kód byl ověřen na commitu `3c10e28c25994039b86c5efd4401fb090b4dda20`: obsahuje vložení verificationCode do inputu a timer invalidace. Neobsahuje důkaz backendové finality. [Evidence](../plans/shoptet-direction-evidence-2026-10-29/frontend-contract.json).

Není důvod posílat samostatný dotaz na každou vlastnost. Nejprve dokumentace a vlastní kontrolovaný sandbox; Shoptet kontaktovat jen v povoleném onboardingu nebo při konkrétním nevyřešeném kontraktu. V této práci je odesílání zakázané.
