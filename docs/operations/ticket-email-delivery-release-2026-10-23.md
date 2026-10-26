# Vydání doručování vstupenek - 2026-10-23

Dokončeno: na [vstupenky.online](https://vstupenky.online) běží **0.20.368+865**. Pořadatel může uložit doručení jako PDF přílohu, inline QR nebo obojí. Výchozí režim zůstává PDF; inline používá stejnou identitu a stav vstupenky jako PDF a kontrola vstupu.

## Rozsah a revize

| Položka | Hodnota |
| --- | --- |
| Tenant | `prod/festapptickets`, organizace 3 |
| Základ frontendového vydání na main | `c607614bdb8820ac462e2f91f2c646bbdc1ae76d` |
| Nasazený tenant | `39fed12fcff2c902d1c914b15c936e16c6a75eb5` |
| Předchozí tenant | `8a390d70c90f788b897f9ca621fe5e6d0c0a9663` |
| Zdroj backendového bundle | `f7b34bc14867bbbbfb83f39df118e7d710a69dac` |
| Deployment | [0dde3bcf](https://0dde3bcf.vstupenkyonline.pages.dev) |

Vydání zachovalo schválený a ověřený základ `c607614`; během přípravy main pokračoval nesouvisejícími změnami anglického profilu. Základ zůstává předkem main a tenant má jako druhého rodiče předchozí produkční revizi. Další tenanty ani migrace anglického profilu nebyly součástí tohoto vydání. Pozdější změna tohoto dokumentu nevyžaduje nový build.

## Backend a publikace

Aplikována byla pouze migrace `supabase/migrations/20261023231000_ticket_email_delivery.sql`, SHA-256 `8d2a6206847fe577553da8694399db8e1a4e8625dd774e9bb023fb4226aaeaf0`. Atomický záznam migrace a všech devět podpisů funkcí odpovídají otestovanému SQL. Readiness prošla. Fronta byla během údržby pozastavena a vyprázdněna od zpracovávaných úloh, poté vrácena do původního nepozastaveného stavu.

Canonical installer nasadil kompatibilní Function bundle a zachoval router i writer policy. HTTP kontroly bez odesílání potvrdily obsluhu fronty, auth hooku, provider událostí, potvrzovacího capability a náhledů. Nebyl vytvořen testovací e-mailový intent ani odeslán testovací e-mail. Chráněné zálohy, instalační účtenky a původní bundle zůstávají dostupné pro obnovu.

Zdroj byl ověřeně publikován přímo na main s existující administrátorskou výjimkou, bez změny ochrany větve; [PR #572](https://github.com/festappnet/festapp/pull/572) je merged. Tenant byl publikován bez force push. Flutter i web client byly sestaveny lokálně a nasazeny přes `automation/deploy_direct.sh --skip-build --wrangler-oauth` ze schváleného artefaktu. GitHub-hosted produkční build ani Deploy workflow nebyly použity.

## Ověření

- 38 cílených Deno testů a typová kontrola renderování, náhledů a integračního scénáře.
- 36 unikátních Flutter/UI a authoring testů; analyzátor bez chyb a varování.
- Osm SQL sad, včetně fronty, náhledů, nastavení, draftů, finalizace a kontroly vstupu.
- Izolovaný integrační průchod všech tří režimů od zaplacení přes šifrovanou připravenou zprávu a provider stub po post-action; druhé načtení téže vstupenky odmítnuto. Storno po přípravě blokuje odeslání.
- Skutečný lokální průchod přihlášeným průvodcem: uložení všech režimů, náhledy pro jednu a tři vstupenky, odpovídající PNG/PDF, zachování volby po reloadu a mobilní šířka 375 px. Existující obrazovka nastavení je pokryta widget testy.
- Devět Node testů pro zachování překladů a PWA manifest.
- Produkční build, konfigurace obrázků a právních stránek, canonical cutover, drift a kontrola výsledného buildu prošly. `verify_web_deployment.mjs` potvrdil živou verzi, assety a právní stránky třemi souvislými kontrolami.

PWA limity nebyly zvýšeny. Bezztrátová minifikace šesti úplných Flutter katalogů v `build/web/assets/assets/translations` zachovává dekódované hodnoty a šetří 103 531 B. Finální core cache má 24 171 788 / 26 214 400 B, known cache 62 827 265 / 62 914 560 B. Nevyhovující přípravné artefakty byly zachovány odděleně a nebyly publikovány.

## Neověřená kompatibilita poštovních klientů

Uživatel uvedl, že testovací schránky nebude mít. Skutečné doručení do Gmailu, Outlooku, Seznamu a Apple Mail proto není ověřeno. Neověřené zůstává chování těchto klientů při mobilním zobrazení, dark mode, přeposlání a vypnutých obrázcích i skenování z jejich displeje. Lokální náhled, MIME testy a provider stub tyto kontroly nenahrazují.

Podrobnosti implementace a původní požadavky: [archivovaný plán](../archive/plans/ticket-email-delivery-plan-2026-10-23.md).
