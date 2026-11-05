# Vydání detailu objednávky - 2026-11-02

Nasazeno a ověřeno na https://vstupenky.online, verze **0.20.481+987**.
Pouze tenant `festapptickets`; žádná další produkční větev nebyla nasazena.

- PR: https://github.com/festappnet/festapp/pull/693
- Kanonický main: `f37babbf2d8155ee6dcb73723ba982d4a616f8b2`.
- Tenant commit: `90fc68b5bab3dc8d41aa855d32f9c2bf9769b36e`.
- Předchozí prod tip `accd791bc222ee37a40a2ff8324d33d3b984109c`
  zůstává předkem. Overlay vychází z přesného main výše; main-owned drift prošel.
- Pages deployment: https://0dc753eb.vstupenkyonline.pages.dev

## Funkční změna

Flutter detail objednávky má pět záložek, propojení uloženého plánku se
vstupenkami a původní vlastníky produktů, transakcí, kontaktu a storna.
Upravitelné odpovědi mají pravou tužku a společné uložení/zahození; e-mail se
upravuje inline přes existující contact owner. Šířka panelu se ukládá místně.
Neviditelný HTML slider již nepřepisuje nativní resize kurzor. Obchodní akce
používají v češtině Stornovat/storno; dismiss a zahození úprav zůstávají Zrušit.

## Ověření a autorizace

Uživatel výslovně povolil produkční nasazení i administrátorský merge PR #693
po odmítnutí běžného merge kvůli review. Ochrana větve nebyla změněna.
Před první publikací i před mergem byl načten a porovnán aktuální upstream.
Všech pět GitHub kontrol prošlo na schváleném headu
`834b34a1d4c327f854698c8d280484b332543084`.

Časově závislá notifikační fixture nyní používá svůj pevný snapshot místo
aktuálního dne; nejde o změnu formátování času v aplikaci. Přesná CI sada
prošla 64/64. Další ověření: 12/12 notifikačních/retained-route scénářů,
40/40 grid/presentation/public SDK kontrol a oba SQL regresní testy.
Podrobnější skutečné lokální scénáře jsou v
[local review](../../plans/evidence/order-detail-local-review.md).

Lokální Flutter + web-client build prošel `verify_web_build`.
Přímé nasazení přes `automation/deploy_direct.sh` s již kvalifikovaným buildem
prošlo `verify_web_deployment`: tři po sobě shodné kontroly verze, buildu
načtených assetů a právních stránek. GitHub produkční build/deploy workflow
nebyl použit; samostatný provisioning workflow pouze přenesl existující
chráněný release manifest beze změn mimo repozitář.

Po nasazení byl samostatně načten skutečný produkční český katalog a ověřeno:
`Stornovat objednávku`, `Stornovat vstupenku`, obchodní `Stornovat`
a obecné `Zrušit`. Lokální browser před vydáním otevřel a bezpečně zavřel
storno dialog a ověřil inline editaci/zahození bez datových zápisů.

## Backend

Live aktivace: `festapptickets`, generation 1, canonical organizace 3.
Protected SSH profil, hostname a runtime databáze byly ověřeny před operací.
Z přesného main byly v jediné transakci aplikovány a zapsány do ledgeru:

- `20261101210000_order_admin_detail.sql`, SHA-256
  `3ccb80d6a4d13a03afdc2c44f0ddd3834be39a2e1edce21830a53c0545d1f5c4`.
- `20261101220000_order_detail_responses.sql`, SHA-256
  `e450e74015ad71921c347920eecf960fbfdff60e0b2d8311922c143afc7d8aef`.

PostgREST byl notifikován. Read-only kontrola potvrdila shodu obou digestů,
všech devět kontrol nových grants a zachování vlastníků i ACL dvanácti
existujících e-mailových čteček. Záloha původních definic zůstává v soukromém
workdir s režimem 0600. Zákaznické objednávky, platby ani kontakty nebyly při
produkčním vydání měněny. Functions kontejnery ani provider konfigurace se
nerestartovaly; žádná produkční testovací zpráva nebo platba nebyla vytvořena.

Lokální uživatelská aplikace na portu 58631 a lokální Supabase zůstávají běžet.

Soukromé provozní záznamy zůstávají na pracovní stanici: build
`/tmp/festapptickets-cloudflare-build.log`, nasazení
`/tmp/festapptickets-deploy-direct.log`. Kvalifikovaný tenant worktree je
`/Users/miakh/source/festapp-festapptickets-order-detail-release-20261102`.
