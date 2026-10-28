# Wix Partner Billed - nezávislá kritická kontrola

Datum: 2026-10-28. Výsledek: **3 nálezy P2, billing neaktivovat před opravami**.
Kontrola nenašla P0/P1; nejde o záruku absence dalších vad.

Nezávislý kritik prověřil diff od `176a27aea10f903852a659bb9389432f3e0637ff`
do `a19416796ef394e2f3190b5ff680da30189b9af6`, autoritativní plán, změněné
SQL/JS, testy a důkazy vydání. Produkční funkční zdroj je `94a1288a`; další Wix
commity měnily dokumentaci. Pozdější upstream Make merge nezasáhl kontrolované
Wix/fee soubory. Kontrola neměnila kód, databázi, nasazení ani externí komunikaci.

## WIX-C01 - P2: import může použít již ukončenou smlouvu

Místo: [source.sql](../../database/functions/service_fees/source.sql), řádky 76-89
(a validace data původní objednávky na řádku 115).

`record_service_fee_settlement` načte smlouvu před získáním zámku pořadatele.
Po čekání na zámek ji znovu nenačte. Souběžné ukončení může mezitím změnit její
platnost, ale import pokračuje s původní otevřenou kopií.

Konkrétní pořadí při READ COMMITTED:

1. A ukončí otevřenou smlouvu k datu T a drží necommitnutou transakci i unit lock.
2. B načte ještě původní smlouvu a pro úhradu/službu/objednávku po T čeká na unit lock.
3. A commitne. B získá zámek, ale dál validuje proti staré hodnotě `valid_until`.
4. Úhrada může být zapsána mimo nově potvrzené smluvní období.

Oprava: po získání unit lock znovu načíst aktuální smlouvu, ve stejném zamykacím
pořadí jako ostatní smluvní writery. Potřebný test: dvě PostgreSQL spojení
s uvedeným pořadím musí způsobit odmítnutí B. Současné testy smlouvy ukončují
sekvenčně; souběh ověřují pouze pro delivery claim.

Důkaz je statický rozbor konkrétního zamykání a uložené PL/pgSQL proměnné.
Dvouspojový PostgreSQL reprodukční test nebyl v této kontrole spuštěn.

## WIX-C02 - P2: pozdě vložená refundace mění historický payload

Místo: [prepare.mjs](../../integrations/wix/reporting/prepare.mjs), řádky 69 a 83-89;
source dovoluje import starší refundace na [source.sql](../../database/functions/service_fees/source.sql):93.

Pořadí pro kumulativní zaokrouhlování se pokaždé znovu určuje podle settlement
času a ID. Nově dovezená starší refundace může změnit částky již existujícího,
staged nebo potvrzeného receipt ID.

Nezávislý kritik i primární agent skutečně spustili čistou projekci: charge má
`feeMinor="3"`, FX poměr `1/2`, Wix share `5000`; refundace jedné jednotky z
3. října je spočtena před importem další jednotky z 2. října.

| Stejná refundace z 3. října | Před pozdním importem | Po pozdním importu |
| --- | --- | --- |
| grossRevenue | -0.01 | 0.00 |
| netRevenue | -0.01 | 0.00 |
| wixShare | -0.01 | 0.00 |

Journal správně odmítne změnu pod již použitým klíčem jako
`WIX_DELIVERY_DIGEST_CONFLICT`. Zdroj ale příjem pozdního pohybu dovolil a
projekce mu nedává neměnnou doručitelnou podobu. Příprava po jednotlivých RPC
navíc může před konfliktem uložit některé nové položky. Historické reporty se
proto nesmějí považovat za stabilní jen na základě stejného receipt ID.

Oprava musí stanovit neměnné pořadí/zaokrouhlovací alokaci pro refundace charge,
nebo odmítat vkládání před finalizovanou historii a umožnit explicitní účetní
adjustment. Výpočty USD musí nadále vlastnit jedna projekce. Potřebný test:
potvrdit první payload, vložit starší refundaci, ověřit neměnnost předchozího
payloadu a přesné úplné vyrušení původní částky poslední vratkou.

## WIX-C03 - P2: neúplný reportovatelný záznam trvale blokuje export

Místo: [source.sql](../../database/functions/service_fees/source.sql), řádky 133-135
(import), 163-164 (výběr pro export), a
[prepare.mjs](../../integrations/wix/reporting/prepare.mjs):60.

Import přijímá chybějící nebo nevalidované FX/share údaje. Pokud charge přesto
nese správnou `partnerTermsReference`, má ověřený Wix původ a akvizici, projde do
exportu. Projekce pak odmítne celý report jako `MISSING_FX_EVIDENCE` nebo
`INVALID_SHARE_RATE`. Kontroluje přitom historii ještě před filtrem měsíce.

Spuštěný reprodukční případ: říjnový charge bez FX blokuje přípravu listopadového
reportu chybou `MISSING_FX_EVIDENCE`. Vstup je nevratně zapsaný: opravený replay
má jiný digest a reversal/replacement neodstraní původní nevalidní charge z historie.
To se liší od záměrné karantény bez partner terms, kterou export správně vynechá.

Oprava: atomicky validovat metadata při označení alokace jako reportovatelné,
nebo přidat doložený neměnný enrichment/supersession postup. Potřebný test:
chybějící/poškozené FX nebo share se buď odmítnou před zápisem, nebo zůstanou
opravitelně v karanténě; nesmějí otrávit další měsíce.

SQL přijetí takového vstupu je doložené nullable kontraktem a přímým INSERT.
Chování projekce bylo spuštěné; nový SQL import test se v tomto auditu nespouštěl.

## Provozní podmínka reconciliation

[dispatcher.mjs](../../integrations/wix/billing/dispatcher.mjs):75 posílá HTTP po
asynchronní autorizaci. SQL fencing chrání zápis výsledku do journalu, nikoli
budoucí odeslání starého pozastaveného procesu. Před znovuotevřením unknown pokusu
je potřeba prokázat i zastavení/fencing původního workeru. Samotné potvrzení
provideru, že dosud nic nepřijal, nevylučuje jeho budoucí send. Jde o dodatečnou
provozní podmínku, nikoli čtvrtý samostatně reprodukovaný nález.

## Dopad na vydání

Billing zůstává vypnutý; při posledním produkčním read-only ověření nebyly žádné
fee ani delivery záznamy. Nálezy nevyvracejí nasazení backendové infrastruktury,
klienta ani úspěšné ověření reálného Wix tokenu/CORS/podpisu. Prokazují však,
že před aktivací nestačí pouze dokončit smlouvu.

Osobní podpis, odpověď Wixu k označení OSVČ, ověřená Partner Billed aktivace,
skutečné účetní podklady a marketplace zůstávají dalšími samostatnými podmínkami.
Koncept zprávy zůstal neodeslaný. Audit neznamená schválení k vydání ani opravu
uvedených vad. Další implementace potřebuje cílené regrese pro C01-C03.
