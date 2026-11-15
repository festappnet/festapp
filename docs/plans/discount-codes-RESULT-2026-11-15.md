# Slevové kódy - lokální implementace a ověření

Stav lokální etapy k 15. 11. 2026: čtyři etapy implementovány a cíleně lokálně ověřeny
v režimu `verification: standard`. Bez commitu, push, produkční migrace,
release nebo aktivace. Autoritativní rozsah a doložené korekce jsou v
[plánu](discount-codes-plan-2026-11-15.md).

## Implementované chování

- Pořadatel spravuje procentní a pevné kódy u produktů akce: rozsah produktů
  a formulářů, měnu, platnost, limit, pozastavení, čerpání a součty podle měny.
  Ukládání kontroluje oprávnění a revizi; použitý kód nelze přejmenovat.
- Samostatná extra feature `discount_codes` je výchozí vypnutá. SQL vynucuje
  její stav v náhledu i commitu. Vypnutí zachová prodejní snapshot, audit,
  čerpání, původní receipt, přehled i refundaci. Storno nevrací počet použití.
- SQL vlastní výpočet, zaokrouhlení, deterministický rozpad na položky a atomické
  čerpání. Neměnné ceny položek se zapíší před platbou. Zamykání chrání poslední
  použití i závod se změnou feature. Klienti nedopočítávají vlastní slevu.
- Flutter a web mají zadání/odebrání kódu, serverový náhled, chyby, busy stav
  a potvrzení čisté ceny. Změna výběru zneplatní nabídku. Potvrzený nákup drží
  původní snapshot. Retry nejasného výsledku používá tentýž payload, command
  a client identity; při chybějící identitě vyžaduje obnovu, nevyrábí nový nákup.
- Běžné, administrátorské a waitlist objednávky používají společný SQL owner.
  Platba, e-mail, přehled, faktura, report a měření čtou stejné čisté částky.
  Fakturoid využívá stávající leased preparation a obnovu nejasného výsledku.
- Doplněny CZ/EN návody, vyhledávání, kontextové odkazy, Eshop/Forms README,
  ACL manifesty, kanonická registrace a cílené CI registrace.

## Doklady kontrol

Finální databázové kontroly běžely nad neměnným lokálním snapshotem od HEAD
`d26acf952639718658dc9d569bdcff274b577869` se současnými pracovními SQL zdroji.
Tím se zabránilo změně vstupů během bootstrapu, protože v témže pracovním
stromu souběžně vzniká zákaznická samoobsluha. Cizí změny zůstaly zachovány.
Migrační soubory, discount SQL a společný term-move guard byly po testu
porovnány s pracovním stromem a byly shodné.

| Kontrola | Výsledek |
| --- | --- |
| SQL: discount contract, application-only checkout, cash reservations, Stripe create-order | 4 soubory prošly |
| Skutečný víceklientový souběh a populated upgrade rehearsal | 3 testy prošly |
| JS: discount, identity, waitlist a související checkout kontrakty | 103 testů prošlo |
| Edge: command identity, Fakturoid/netto/e-mail a invoice preparation recovery | 25 testů prošlo |
| Flutter: discount cases, desetinný součet a strict recovery identity | 10 testů prošlo |
| CZ/EN browser: skutečné checkout komponenty a retry po 503 | prošlo |
| Help stránky/vyhledávání a security migration kontrakty | 15 testů prošlo |
| Dart analyze nového discount modulu | bez nálezů |
| Dart analyze dotčených checkout/identity souborů | bez chyb; 1 existující immutable warning a 44 style/deprecation info |
| Assembler discount migrations, canonical source contract, diff whitespace | prošlo |

SQL prokazuje zejména zaokrouhlení a měny, rozsah/čas, nulovou cenu, zálohy,
ACL včetně přímého zápisu feature, editace použitých kódů, zakázané cenové
změny a přesun termínu, shodný command s jiným vstupem, rollback bez čerpání,
refundaci skutečného netto a historii po vypnutí. Waitlist test používá guest
capability a opakuje stejný command i po spotřebování nabídky a vypnutí feature.
Souběh prokazuje právě jedno poslední použití, replay ztracené odpovědi,
serializaci skutečného feature writeru, cyklus off/on a bezpečný opakovaný
backfill z historických prodejních dat místo dnešního ceníku.

Použité hlavní příkazy:

```sh
python3 automation/local_db/runtime.py exec -- node web_client/scripts/run_db_tests.js database/tests/eshop_discounts/discount_codes_test.sql database/tests/eshop_orders/application_only_checkout_test.sql database/tests/payment_providers/cash_reservations_test.sql database/tests/eshop/stripe/create_order_test.sql
# Ve stejném vlastněném lokálním DB runtime:
node --test database/tests/eshop_discounts/discount_codes_concurrency.test.mjs
deno test --frozen --lock=supabase/functions/deno.lock --allow-env --allow-net --allow-read supabase/functions/send-ticket-order/commandIdentity_test.ts supabase/functions/send-ticket-order/fakturoid_test.ts supabase/functions/send-ticket-order/fakturoidPreparation_test.ts
python3 automation/ci/resources.py fvm flutter test --concurrency=1 test/sessions/ticket_default_cases.dart test/components/forms/form_total_price_cases.dart test/data_services/client_command_identity_cases.dart --name 'discount_codes|floating .* total keeps|discount recovery' --machine
python3 automation/assemble-discount-codes-migration.py --check
python3 automation/generate_canonical_source_contract.py --check
```

Browser kontrola používala izolovanou session, light mode a lokální transportní
fixture, nikoli produkční backend. Ověřila i nezměněný payload/command/client
po 503 navzdory následné změně košíku, jedinou rezervaci a úklid history vrstvy.
Vlastní browser/server a dočasný validační checkout byly ukončeny/odstraněny.

## Připravená migrace a pořadí

1. `20261115120000_discount_codes.sql`: schema, backfill, výpočet, writeři,
   ochrany, reporty a příprava fakturace. Obsahuje sdílený kontrakt výběru produktů.
2. `20261115130000_customer_order_policy_foundation.sql`: souběžně připravovaný
   základ zákaznické samoobsluhy. Není vydán touto úlohou, ale je součástí
   společně ověřené migrační sekvence a zavádí závislosti čtenáře přehledu.
3. `20261115140000_discount_code_projections.sql`: aktuální přehled objednávky
   se slevou až po uvedených závislostech. Toto rozdělení nahrazuje předpoklad
   jediné samostatné migrace; nesmí se nasadit pouze první soubor a zapnout UI.

SHA-256 ověřených forwardů:

```text
0a0bc68235931b1c64c7ed9383536e7ae4270bd0c5f8e6f592b2fea3a8a006f9  20261115120000_discount_codes.sql
dc87a62f55bd0b8023ec37fef779cebfb248440e2ccf92c37ee44b12e6dbd98c  20261115130000_customer_order_policy_foundation.sql
09ee1ce0e58e5402dfe1ac718480b210cbcb06459674b29c526b36dc601e5851  20261115140000_discount_code_projections.sql
```

## Omezení a dosud neprovedené kroky

Jeden kód na objednávku, bez kombinování a dodatečného uplatnění. Kód není pro
předtištěné vstupenky. Čistá cena musí být vyšší než kladná záloha; částky
nepodporované existujícím cenovým úložištěm se odmítnou. Sleva při registraci
na čekací listinu se nečerpá a automaticky se nepřenáší do pozdějšího nákupu.
Zlevněné objednávky nelze přecenit, změnit produkty, vyměnit místa nebo přesunout
na jiný termín; nefinanční změny, storno a refundace zůstávají podporované.
Fakturoid zachovává dosavadní adaptér s nulovou DPH; nový daňový engine nevznikl.

Neproběhly plné release lanes ani externí platební/fakturační transakce,
produkční E2E nebo kontrola skutečného produkčního daňového nastavení.
Cílené Flutter testy nenahrazují úplný nativní E2E průchod správy a nákupu.

Po samostatné autorizaci zbývá publikace zdrojů a přesné GitHub lane gates,
ověření cílového backendu a tenant scope, záloha/rehearsal společné migrační
sekvence a koordinované nasazení SQL, Edge a klientů. Feature zůstává vypnutá;
aktivace pro konkrétní akci vyžaduje samostatnou autorizaci. Rollback vypíná
nové čerpání, nemaže audit ani snapshoty a nevrací čtenáře bez podpory netto.

## Navazující autorizovaný rollout

Uživatel následně autorizoval dokončení společné integrace a rollout. Publikace
je připravena z izolované větve nad aktuálním upstreamem. Cílový webový tenant
je pouze `prod/festapptickets` / `vstupenky.online`, organizace 3. Funkce zůstávají
vypnuté do určení konkrétní akce; zákaznická samoobsluha se tímto nezapíná.

Po aktualizaci základu znovu prošlo 8 společných SQL souborů a 9 skutečných
souběhových testů, 54 společných JS testů, 35 Edge testů a 18 CI contract testů.
Původní lokální důkazy pro nezměněné Flutter a browser vstupy zůstávají platné.
Byl zvolen společný nový software generation `0.20.617+1144`, protože build
1143 již byl vydán. GitHub ochrana `main` vyžaduje PR a jedno schválení;
produkční postup dále vyžaduje úspěšné exact-SHA CI gates.

Původní pracovní strom byl zachován. Publikační checkout je
`/Users/miakh/source/festapp-discount-rollout-20261115`; není to dokončené
produkční nasazení. Připravený společný kontrakt zahrnuje samoobsluhu jako
migrační a čtecí závislost, s oběma feature ve výchozím stavu vypnutými.

Provozní příprava navíc doplnila chybějící registraci `customer-order-changes`
do autoritativní production Function bundle policy. Bez ní by endpoint nebyl
vydán v koordinovaném balíku. Existující úplný inventory/bundle kontrakt tuto
registraci ověřuje. Produkční backend identity a dnešní off-host backup byly
read-only ověřeny; migrace 12/13/14 dosud nejsou aplikované.

Publikovaný PR: https://github.com/festappnet/festapp/pull/881. Plné GitHub CI
odhalilo a implementace opravila registraci SQL/native recovery case v obou
inventářích a evidenci tří starších již nasazených migrací (notification unit
groups, wallet collections, order item terminology). Jejich původní SQL bytes
zůstávají shodné s upstreamem; metadata je nyní checksum-pinnují jako historii
a nové definice vlastní explicitní forwardy. Všechny registrované historické
migrace i aktivní forwardy prošly společným `verify_forward()`.
Ochrana main vyžaduje jedno schválení jiným účtem; auto-merge není povolen.
Bez schválení a přesných main CI gates se rollout neprovede.
