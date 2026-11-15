# Slevové kódy pro Festapp Tickets

Datum: 2026-11-15
Stav: Původní etapy nasazeny pro festapptickets ve verzi 0.20.618+1147. Následná oprava prezentace a porovnání potvrzení je popsána na konci plánu.
Ověřování implementace: `standard` - ceny, platby, veřejný kontrakt a migrace
Výchozí revize průzkumu: `a7e52244a`

## Výsledek a rozsah

Pořadatel vytvoří kód, například `TANEC10`, nastaví procentní nebo pevnou slevu,
platnost, limit použití a produkty. Zákazník jej zadá v objednávce, uvidí původní
cenu, slevu a konečnou cenu. Stejnou částku následně požaduje platební metoda,
ukazují potvrzení, faktura, přehled objednávky a reporty.

Stejný přehled otevřený stávajícím tlačítkem z e-mailu ukáže uplatněný kód,
původní cenu, přiznanou slevu a výslednou cenu. Kód se zadává při nákupu;
zobrazení slevy v přehledu neznamená možnost dodatečného uplatnění.

První verze: jedna sleva na objednávku, jedna akce, volitelně vybrané formuláře
a produkty; webový klient i Flutter. Funguje pro běžný nákup a přijetí nabídky
z čekací listiny. Administrativní vytvoření objednávky používá tentýž výpočet.
Hromadně předtištěné vstupenky kódy nepřijímají.

Uživatelem upřesněný požadavek: **Slevové kódy jsou samostatná extra feature
akce**, kterou musí pořadatel výslovně zapnout. Nejde o placený tarif ani
globální zapnutí pro všechny pořadatele. Chybějící nebo vypnutá feature znamená
zákaz nového použití kódu i přes přímé API.

Mimo rozsah: kreditové poukazy, partnerské provize, generování tisíců unikátních
kódů, kombinování kódů, ověřování nároku podle e-mailu a zpětné přidání kódu
k již vytvořené objednávce. Cenové vlny zůstávají funkční; sleva se počítá z ceny
platné v okamžiku potvrzení nákupu.

## Ověřený současný stav

| Fakt a místo | Důsledek pro návrh |
|---|---|
| `supabase/functions/send-ticket-order/index.ts` rozlišuje běžný nákup, administrativní objednávku, výměnu míst a přijetí nabídky. | Prověřit všechny větve; nestačí doplnit jediný formulář. |
| `database/functions/eshop/finalize_ticket_order.sql`, `finalize_ticket_order_internal_v1` sčítá produkty, vytváří platbu a objednávku. | Kanonické uplatnění slevy musí předcházet inicializaci platby. |
| `materialize_ticket_products_internal_v1.sql` ukládá produktové položky a vrací cenu i zálohu. | Sleva potřebuje přesný rozpad na uložené položky. |
| `product_price_changes.sql`, `validate_product_price` respektuje minor units a současnou přesnost `numeric(10,2)`. | Výpočet nesmí slibovat přesnost, kterou databáze neuloží. |
| `lib/components/features/deposit_feature.dart` rozlišuje skutečnou zálohu a pouze zobrazovaný doplatek. | Neměnit ani nezlevňovat vizuální doplatek jako by byl platbou. |
| `docs/architecture/payment-providers.md` zachovává neměnné částky online plateb, registry metod a existující refundovací ledger. | Nevytvářet samostatnou slevovou platební větev. |
| `web_client/src/components/forms/form_measurement_contract.js` a SQL měření mají konverzní kontrakt. | Konverze musí obsahovat skutečně účtované částky. |

Průzkum nenašel doménu kupónů nebo jejich čerpání. Záporné částky ve virtuálním
doplatku nejsou implementací kupónů. Jde o stav zdrojů, nikoli důkaz nasazení.

## Produktová rozhodnutí

1. Kódy jsou po oříznutí mezer ASCII `A-Z`, číslice a pomlčka, délka 4-32.
   Zadávání ignoruje velikost písmen; unikátnost je `(occasion, normalized_code)`.
   Použitý kód nelze přejmenovat ani znovu vydat pod stejnou identitou.
2. Procentní sleva je v celých bazických bodech, v rozsahu nad 0 až 100 %.
   Pevná sleva má jedinou uloženou měnu; jiná měna objednávky znamená odmítnutí.
3. Platnost je `[valid_from, valid_until)`, uložená v UTC, editor zobrazuje místní
   čas. Aktivace je explicitní. Vypnutí neovlivní již potvrzené objednávky.
4. Limit počítá úspěšně vytvořené objednávky, nikoli vstupenky ani zobrazení.
   Storno, expirace nebo refundace použití automaticky nevrací. Tím nelze
   opakovaným stornem obcházet limit. Chyba transakce nic nespotřebuje.
5. Jedna objednávka může mít jeden kód; množství způsobilých položek omezuje
   objednávka a produktová pravidla. Nepřidávat slabý limit „jednou na osobu“
   odvozený pouze z libovolně zadaného e-mailu.
6. Kód nelze dodatečně vyměnit. Opravy údajů a storno zachovávají jeho snapshot.
   Změna produktů musí buď zachovat a deterministicky přerozdělit původní
   přiznanou slevu v jejím původním rozsahu, nebo být odmítnuta; viz další oddíl.
7. Bez zapnuté funkce se veřejné pole nezobrazuje. Po zapnutí je sbalené pod
   „Máte slevový kód?“. Neplatný, vyčerpaný či nepříslušný kód má stejnou veřejnou
   chybu; přesný důvod vidí oprávněný pořadatel.

### Zapnutí přes existující systém features

Použít occasion feature s navrženým kódem `discount_codes`, `is_enabled=false`.
Zapojit `lib/components/features/feature_constants.dart`, `feature_metadata.dart`,
factory `feature.dart`, `FeatureService`, editor features v
`lib/components/occasion_settings/` a odpovídající JS konstanty/projekce.
Použít stávající kanonický save a oprávnění features; nevytvářet druhý globální
boolean nebo platební entitlement.

Zapnutí zpřístupní správu a použití kódů; jednotlivé definice mají nadále vlastní
aktivaci a platnost. Formuláře pouze zužují rozsah jednotlivých kódů, nenahrazují
feature akce dalším nezávislým přepínačem. UI po vypnutí ukáže uložené definice
a historii čerpání pro oprávněnou obsluhu jako pozastavené, ale neumožní nová
uplatnění. Opětovné zapnutí zachová limity a stav jednotlivých kódů.

SQL náhled i commit ověřují živou feature. Změna zapnutí a nový nákup musí sdílet
feature/policy fence ve stávajícím pořadí zámků; vypnutí nesmí projít mezi
autorizací a commitem čerpání. Zastaralý náhled vyžaduje nové potvrzení.
Vypnutí neodstraní slevy z objednávek, nezmění částku rozepsané platby a
neblokuje doručení, historii ani refundaci již přiznané slevy.

## Kanonická doména a invarianty

Nová doména `database/functions/eshop_discounts/` vlastní definice, čerpání,
výpočet i projekce. Navržené názvy jsou cílové nové symboly, nikoli existující API.

- `eshop.discount_codes`: rozsah akce/formulářů/produktů, normalizovaný kód,
  typ a hodnota, měna, časová platnost, limit, aktivace, revize a audit autora.
- `eshop.order_discounts`: nejvýše jeden záznam na objednávku, neměnný snapshot
  pravidel a přiznané částky, původní command ID a vazba na kód.
- Rozpad na `order_product_ticket` vázaný ID položky: základ, sleva, čistá cena.
  Nepoužívat falešný záporný produkt. Součet čistých položek je `orders.price`.
  Existující pole ceny převést na jasně zdokumentovaný čistý význam; původní
  cenu držet vedle něj. Neponechat čtenářům dva možné významy stejného pole.
  Rovnost součtu s `orders.price` platí pro aktivní objednávku; současné bankovní
  storno v `cancel_order_domain_internal_v1` cenu nuluje a odpojuje produkty.
  Neměnný prodejní snapshot a rozpad slevy proto musí přežít storno i pozdější
  odstranění produktu nezávisle na aktuálním odkazu na katalog. Audit a refundace
  nesmějí rekonstruovat původní cenu z nulového storna nebo dnešního ceníku.
- `quote_order_discount` vrací pouze serverový náhled pro konkrétní výběr,
  revizi kódu a otisk cen/výběru. Nekonzumuje kapacitu kódu ani místa.
- Soukromý `apply_order_discount_internal` používá stejný čistý výpočet jako
  náhled, ale v transakci objednávky znovu ověří rozsah, čas, revize a limit.
  Změněná cena/nárok znamená 409 a nové potvrzení zákazníkem, ne tiché zdražení.

Výpočet používá desetinná čísla a minor units, nikoli JS `Number` jako autoritu.
Sleva platí na kladné vybrané produktové položky. Procentní částku nejprve
spočítat nad způsobilým součtem, jednou zaokrouhlit na podporovanou přesnost
měny a rozdělit metodou největšího zbytku; shody rozhoduje stabilní pořadí
položek z normalizovaného vstupu. Pevná sleva se zastropuje způsobilým součtem.
Žádná položka ani objednávka neklesne pod nulu. Poplatky platformy a pouze
vizuální doplatky nejsou způsobilé položky.

Skutečnou zálohu první verze nepřepočítává: je-li po slevě čistá cena některého
produktu menší nebo rovna jeho kladné záloze, kód pro daný výběr odmítnout a
v administraci vysvětlit omezení. Nikdy ji tiše nesnížit. Objednávka zlevněná
na nulu bez takové zálohy použije existující no-money větev, bez požadavku na
platbu a bez nové bankovní reference.

Čerpání se zapíše atomicky s objednávkou, s unikátní vazbou na objednávku a
receipt. Pro limit používat zámek řádku kódu a aktuální čerpání, nikoli klientský
čítač. Dodržet zjištěné pořadí společných zámků: platební policy fence, stávající
admission/capacity a produktové zámky, poté řádek kódu před zápisem čerpání.
Editor kódu nesmí po zámku kódu získávat produktové/capacity zámky v opačném
pořadí. Síťová volání nedržet uvnitř transakce.

U objednávek s kódem první verze blokuje cenu/produkty měnící administrativní
operace i výměnu míst, pokud nedokážou zachovat stejný čistý snapshot. Povolit
nadále úpravu kontaktu, nemonetárních odpovědí, doručení, storno a refundaci.
Jde o explicitní omezení této verze, ne tiché odstranění přiznané slevy.

Čerpání neprovádět při zápisu na čekací listinu. Platnost a limit se kontrolují
až při přijetí nabídky. Dílčí přijetí vytvářející samostatnou objednávku je
samostatné použití; další přijetí musí znovu explicitně zadat platný kód.

## Oprávnění a ochrana

Správa kódů používá typed predicate v `database/functions/user_permissions/`
navázaný na skutečně uloženou akci a existující právo editovat objednávky.
Finanční statistiky zůstávají za právem číst objednávky. Nové tabulky mají RLS,
žádné přímé zápisy klientů; všechny funkce jsou v `public` s explicitním
`search_path`. Přidat odpovídající ACL manifesty a bezpečnostní kontrakty.

Veřejné ověření je omezené rychlostí, velikostí vstupu a konkrétním formulářem.
Nezveřejňuje seznam kódů, zbývající počty, zákazníky ani neveřejné produkty.
Raw kód neposílat do URL, obecné analytiky ani chybových logů. Lokální editor
nesmí omylem obnovit deaktivovaný kód uložením zastaralé revize.

## Implementační etapy

### 1. Cenový snapshot a doména kódů

- Přidat kanonické SQL, audit, revize, unikátní čerpání a náhled/aplikaci.
- Zaregistrovat extra feature v existujícím systému, výchozí vypnutí a její
  serverový fence. Kopie akce přebírá běžnou explicitní volbu kopírování features,
  ale nekopíruje čerpání, zákaznické vazby ani aktivní kódy bez samostatné volby;
  v první verzi se definice kódů nekopírují.
- Aditivně doplnit základ/slevu/čistou cenu položek. Existujícím objednávkám
  zachovat částky, backfillovat nulovou slevu bez přepočtu historie.
- Zkontrolovat přesné cenové čtenáře v `eshop_orders/amount_changes.sql`,
  `eshop/product_price_changes.sql`, produktových editorech, reportu a fakturaci.
  Do plánu implementace doplnit výsledný konečný seznam před změnou významu ceny.
- Výstup: součet řádků, sleva, záloha i výsledná cena jsou deterministické;
  současná objednávka bez kódu je beze změny. SQL kontrakt prokáže výpočet a ACL.

### 2. Atomické objednání a platební návaznosti

- Zapojit výpočet do `finalize_ticket_order_internal_v1` před vytvořením platby.
  Provést audit běžné/admin/waitlist větve a Fakturoid přípravy v
  `supabase/functions/send-ticket-order/`; externí faktura musí vzniknout nad
  týmž ověřeným cenovým snapshotem. Při jeho změně přípravu bezpečně opustit.
- Rozšířit command identity o kód a otisk nabídky. Retry stejného commandu nesmí
  spotřebovat druhé použití; stejné ID s jiným vstupem znamená konflikt.
- Online checkout dostává konečnou cenu. Chybu či nejasný výsledek externího
  checkoutu obnovovat stávajícím payment enginem, ne vytvořením další objednávky.
- Odmítnout nepodporované přecenění všech discounted orders ve společném SQL
  owneru, nikoli pouze skrytím tlačítka. Nepřenášet původní kupón automaticky
  do nové náhradní objednávky.
- Výstup: souběh o poslední použití pustí právě jednu objednávku; výpadek po
  commitu vrátí tutéž objednávku, částku i čerpání.

### 3. Správa, nákup a všechny cenové výstupy

- Flutter: správa kódů v administraci akce u produktů, ne samostatný finanční
  systém; seznam, vytvoření/editace, pozastavení, počet použití a součet slev.
- `lib/components/forms/` a `web_client/src/components/forms/`: zadání/odebrání
  kódu, serverový náhled, dostupný busy/error stav a nové potvrzení po změně ceny.
- Aktualizovat `_shared/orderOverview.ts`, zákaznické přehledy, doručovací
  kontext, Fakturoid payload, reporty a SQL konverzní projekce. Faktura musí
  zachovat stejné čisté položky a případné stávající daňové rozdělení.
- Refundace vychází z opravdu zaplacené čisté ceny, nikoli z ceníku.
- Výstup: stejný konkrétní nákup má shodný základ/slevu/netto ve webu, Flutteru,
  potvrzení, platebním požadavku, reportu a fakturačním adaptéru.

### 4. Uzavření kontraktu a příprava nasazení

- Povinně aktualizovat uživatelskou nápovědu, nikoli jen vývojářské README.
  Kanonické veřejné návody jsou v `automation/release/help/` s anglickými
  protějšky v `en/`, katalogem `pages.json` a existujícím vyhledáváním.
  Doplnit nastavení extra feature, vytvoření kódu, procentní/pevnou slevu,
  rozsah, platnost, limity, pozastavení a zachování historie po vypnutí.
  Zákaznická část popíše zadání při nákupu, chybu kódu a zobrazení slevy
  v přehledu otevřeném tlačítkem z e-mailu. Výslovně uvést omezení záloh,
  nekombinování kódů, zákaz dodatečného uplatnění a pravidla refundace/čerpání.
  Rozšířit existující tematické návody a jejich navigaci; nový článek přidat
  jen pokud rozsah vyžaduje samostatný postup, a zaregistrovat jej do katalogu.
  Zachovat konzistentní českou a anglickou nápovědu, skutečné názvy ovládání
  a kontextové odkazy z UI. Neuvádět funkci jako živou před jejím nasazením.
  Potřebné nové screenshoty po implementaci pořídit v light mode s UI i daty
  v jazyce návodu, podle `automation/help_capture/README.md` a pravidel repo.
- Aktualizovat runtime bundle/modely, ACL manifesty a dokumentaci Eshop/Forms.
  Neregistrovat druhou kalkulačku v klientu. Odstranit dočasné migrační helpery
  a testovací zkratky; zachovat pouze původní podporované veřejné podpisy RPC.
- Připravit migraci a lokální rehearsal; nové sloupce/schema před writery,
  poté enginy, čtenáři a UI. Funkce je ve výchozím stavu vypnutá.
- Výstup: žádný známý vstup neumí snížit částku mimo kanonický owner a žádný
  výstup nepřičítá slevu podruhé. Produkční aktivace zůstává samostatným krokem.

## Ověření při implementaci

V plánovací fázi se testy nespouštějí. Implementace má přidat cílené kontrakty
do `database/tests/eshop_discounts/`, Edge testy identity/Fakturoid payloadu,
webové testy objednávky a Flutter cases registrované v příslušné session.

- SQL: měna, zaokrouhlení a rozpad, nula/100 %, zálohy, hranice času, scope,
  vypnutý kód, limit a dvousession souběh, rollback, retry, ACL a zakázaná editace.
- Feature: missing/off/on/off/on, přímé API při vypnutí, závod vypnutí s commitem,
  zachování historické slevy, čerpání a refund recovery po vypnutí.
- Toky: běžná/admin/waitlist objednávka, bank/cash/instalovaný online connector,
  chyba externí fakturace, zrušení/expirace a refundace bez obnovy limitu.
- Projekce: historická objednávka bez kódu, konverze, e-mail a report nezmění
  částku ani po pozdější editaci či deaktivaci definice kódu.
- Příkazy: `node web_client/scripts/run_db_tests.js database/tests/eshop_discounts/discount_codes_test.sql`
  po vytvoření tohoto kontraktu; cílené Deno testy dle oprávnění okolních testů;
  v `web_client` přes `pnpm exec node --test` vybrané nové `.test.js` soubory.
  Flutter přes `fvm flutter test --concurrency=1` příslušné session, až je volný
  jediný workstation Flutter slot. Přesné session určit podle registrace cases.
  Před publikací změn navíc povinné cílené kontroly dle `CONTRIBUTING.md`.
- Nápověda: ověřit existujícími cílenými kontrolami veřejných help stránek
  odkazy, katalog, vyhledatelnost a CZ/EN protějšky. Po dokončení funkce porovnat
  postup se skutečným UI; nekopírovat neimplementované kroky z návrhu.

## Předpoklady, rizika a odstranění

- Návrhová rozhodnutí o limitech a nekombinování jsou doporučený výchozí rozsah,
  nikoli zjištěná stávající pravidla Festappu.
- Produkční schéma, aktivace jednotlivých platebních metod a skutečný daňový
  režim nebyly ověřeny. Implementátor ověří lokální schema a fakturační adapter;
  při nevyjádřitelném daňovém rozpadu nepovolí kódy danému checkoutu a uvede
  konkrétní blokaci. Nezavádět vlastní daňový engine.
- Není co plošně migrovat z legacy kupónů. Zachovat cenové vlny, virtuální
  doplatky a existující platební ledgery; odstranit pouze případné dočasné
  kalkulačky/aliasy vytvořené při této implementaci.
- Zapnutí v produkci vyžaduje zvláštní autorizaci a ověření aktuálního backendu,
  rehearsal, zálohu a případnou webovou release gate. Rollback vypne nové
  čerpání; nemaže přiznané slevy a nesmí vrátit staré čtenáře neznající netto.

## Hotovo znamená

Všechny nákupní větve používají jediný SQL owner, limity obstojí v souběhu,
částky souhlasí napříč platebním a účetním výstupem a cílené kontroly projdou.
Součástí dokončení je aktualizovaná uživatelská nápověda v podporovaných
jazycích s funkčními odkazy a postupem odpovídajícím skutečné implementaci.
Součástí předání je přesný seznam omezení, migrační postup a oddělený stav
lokální implementace, nasazení a produkční aktivace. Tento dokument samotné
provedení implementace ani produkční operace neautorizuje.


## Upřesnění podle implementačního průzkumu 2026-11-15

- Cenou položky je dnes `orders.data.tickets[].products[].price`, nikoli sloupec
  na `order_product_ticket`. Nové sloupce `base_price`, `discount_amount` a
  `net_price` jsou aditivní; JSON `price` má u nové zlevněné objednávky jednoznačně
  čistý význam. Historii backfill čte pouze z uloženého prodeje, ne z katalogu.
- Konečný audit cenových cest: materializace a finalizace objednávky; produktové
  editace `update_ticket_products_ws`; výměny `swap_spot_tickets` a
  `confirm_blueprint_order_change`; storno `cancel_order_domain_internal_v1`
  a `storno_tickets_bulk`; čtení `get_order_admin_detail`, `get_orders`,
  `get_order_details_for_email`, `get_ticket_details_for_generating`,
  `get_tickets_with_details`, zákaznický `eshop_waitlist/order_overview`,
  `operator_orders`, `amount_changes`, `get_report_ws`, `form_datalayer`,
  Flutter `OrderDataProductModel` a klientské rekapitulace, Edge `orderOverview`
  a `fakturoidPayload`. Katalogová cena v `get_orders` je dostupná nabídka,
  není cenou prodané položky. PDF i konverze už čtou uložené JSON ceny.
- Běžný command hashuje celý vstup, tedy i `discount`. Není nutný druhý hash
  nebo druhý receipt. Původní command UUID interně doplní SQL wrapper a waitlist
  owner; klient neurčuje identitu čerpání.
- Zjištěný existující `lock_blueprint_scope_internal` serializuje celý obchodní
  scope akce, včetně kanonického save features. Sdílený fence pro vypnutí je
  tento owner, nikoli další přepínač nebo nezávislý zámkový protokol. Následuje
  platební policy fence, admission/produkty a řádek kódu.
- Fakturoid ve stávajícím kódu připravuje fakturu až po SQL commitu. Zlevněné
  objednávky použijí existující lease/recovery přípravu faktury s týmž receipt,
  čisté prodané řádky a stávající nulovou DPH adaptéru. Nevzniká nový daňový
  engine ani faktura z nezávazného náhledu.
- Součet slev procentního kódu musí být členěný podle měny; součet CZK a EUR
  není finanční metrika. Počet použití zůstává přes všechny měny dohromady.
- Přehled po stornu může ukazovat aktuální nulovou částku objednávky i původní
  přiznaný prodejní rozpad. Snapshot musí zůstat označený jako původní prodej,
  ne aktuální požadavek na zaplacení.

- Během souběžné implementace vznikl společný
  `eshop/product_selection_contract.sql`; aktuální materializace jej již volá.
  Forward slev jej proto načítá před materializací. Jde o původní admission
  pravidla, ne druhou cenovou cestu.
- Veřejný quote obsahuje také whitelisted rozpad pouze vybraných veřejných
  produktů (ID, základ, sleva, netto a měna). Klientské `begin_checkout` a
  `add_payment_info` používají tyto SQL částky, nikoli katalogový součet před
  slevou. Revize definice, audit, scope, limity a zákazníci nejsou veřejnou
  projekcí. Finální konverze nadále vlastní SQL.

- Zákaznický SQL přehled byl souběžně rozšířen o policy projekci samoobsluhy.
  Jeho finální slevová projekce proto patří do forwardu
  `20261115140000_discount_code_projections.sql`, za společné ownery ve forwardu
  `20261115130000_customer_order_policy_foundation.sql`. Základní schema a cenový
  owner zůstávají ve `20261115120000_discount_codes.sql`. Čtenář se nesmí dostat
  před své závislosti, ani když je samotná slevová feature vypnutá. Při nasazení
  se použije celé ověřené pořadí migrací před aktualizací UI a jakoukoli aktivací.

- Souběžně vznikl další writer přesunu termínu v
  `customer_order_changes/move.sql`. Preview i commit nyní volají stejný
  `assert_order_discount_unchanged_internal`; nepoužívají detekci přítomnosti
  funkce ani tichou volitelnou cenovou cestu. První verze zlevněné objednávky
  nepřesouvá na jiné produkty/termíny ani při shodné katalogové ceně.

- Klientské opakování po nejasném výsledku musí obejít nový quote: poslední
  použití už může být spotřebované původní potvrzenou objednávkou. Oba klienty
  proto nabízejí opakování zmrazeného původního payloadu a vyžadují existující
  pending command/client identity. Chybějící identita ani změna aktéra nesmí
  automaticky vytvořit nový command. Flutter drží potvrzený snapshot odděleně
  od editovaného draftu, takže asynchronní invalidace nesmí potichu odstranit kód.

- Důkaz z plného CI při přípravě rollout: společný occasion writer je součástí
  existujícího ticket-layout readiness otisku. Je nutné spustit kanonický
  `generate_ticket_layout_write_contract.py` a nasadit jeho aktualizovaný owner
  ve forwardu 14 po společné foundation. Původní contract-refresh migrace zůstává
  neměnná. Přesný ACL regression zároveň eviduje nové soukromé tabulky, sloupce
  a explicitní revokace veřejného přístupu; nejde o povolení nové autority.

## Oprava podle produkčního ověření 15. 11. 2026

Objednávka s přiznanou slevou mohla ihned zobrazit zastaralé potvrzení, i když
uložená historie i aktuální cena souhlasily. Důkaz vyvrátil předpoklad, že
porovnání volitelných názvů míst je již normalizované: historický chybějící
`spot_group_title` se lišil od obohacené prázdné hodnoty. Etapa projekcí proto
normalizuje pouze NULL/prázdné názvy místa a skupiny v kanonickém SQL porovnání.
Skutečné změny názvů a cen stále vyvolají upozornění. Forward
`20261115180000_discount_confirmation_consistency.sql` nemění objednávky ani
finanční engine. Regrese ověřuje také skutečný `get_products_for_ticket`.

Správa kódů používá kompaktní standardní dialog a standardní patičku editoru.
Po uložení načte serverový seznam před zavřením editoru; zobrazuje i nulové
čerpání. Webová rekapitulace odděluje kód, původní cenu, slevu a výslednou
částku; tlačítka mají responzivní rozestupy. Historie ukazuje kód a částky
z neměnného historického snapshotu i při vypnuté funkci.

Ověření následné opravy: 7 cílených Flutter testů (včetně skutečného RPC
transportu uložení/obnovení při šířkách 390 a 1000), 27 JS testů, SQL
regrese potvrzení a slev, 3 testy souběhu/retry a 8 testů forward ownerů.
Izolovaná kontrola prohlížeče pokrývá CZ/EN mobil i desktop, rozestupy a
zarovnání částek. Nedotýká se produkčních objednávek, aktivace ani e-mailů.
