# Spolehlivé plánky a prodej pro akce do 1 000 lidí

> Stav po lokální implementaci a novém auditu 2026-10-20: hotové vlny se neopakují. Pro zbývajících osm Flutter owners, admin/public map průchod, sjednocení s aktuálním main a MCP web consent je autoritativní [plán dokončení](blueprint-mcp-closure-plan-2026-10-20.md) a jeho [exekuční prompt](blueprint-mcp-closure-EXECUTION-PROMPT-2026-10-20.md). Původní rozhodnutí tohoto plánu zůstávají platná. [Výsledek izolované implementace](blueprint-1000-integrity-RESULT-2026-10-20.md) rozlišuje ověřené lokální toky od neprovedené publikace a produkční aktivace.

Datum: 2026-10-20. Stav: připravený plán implementace, opravy nejsou provedeny.
Ověřování: `verification: standard` kvůli veřejným kontraktům, rezervacím,
penězům, migracím a souběhu.

## Výsledek a rozsah

Pořadatel dokáže vytvořit, nastylovat, uložit a znovu otevřít plánek přibližně
1 000 míst. Zákazník na webu i ve Flutteru rezervuje a koupí právě ta místa,
která vidí. Změna vzhledu nepřepíše cenu, rezervaci, identitu ani historickou
vstupenku. Souběžný prodej a administrace nezanechají částečné změny.

Tento plán je autoritativní pro bezpečnost, integritu a kvalifikaci rozsahu
1 000 lidí. Nahrazuje stadionová doporučení z předchozího
[posouzení](../architecture/blueprint-architecture-review-2026-10-20.md).
Nevyžaduje sektorizaci načítání, nový model stadionu, nový rezervační ledger,
obecný CSS systém ani zvýšení současných počtových limitů.

Platná produktová rozhodnutí a úplnou funkční paritu V2 nadále vlastní
[integrační plán B](blueprint-v2-integration-plan-2026-10-19.md) a jeho
[akceptační matice](blueprint-v2-v1-functional-parity-2026-10-19.md).
Tento plán je doplňuje o konkrétní bezpečnostní opravy a měřitelnou kvalifikaci.
Jeho profil 1 000 míst pro toto zadání nahrazuje výkonový profil 5 000 míst z B;
samostatná kvalifikace 5 000 míst není podmínkou dokončení tohoto rozsahu.
Neimplementovat znovu již hotové části B. Pokud B běží v jiném checkoutu,
nejprve sjednotit konkrétní revize a převzít potřebné ověřené části podle
jeho pravidel. Rozpracovaná práce jiného procesu není automaticky naše baseline.

Práce v další implementaci zahrnuje oba repozitáře Festapp a `venue_seat_picker`,
veřejný picker, admin save/read, rezervace, finalize/swap/replace/storno,
stylový a resource kontrakt, setup/copy a relevantní testy. Rozsah 1 000 znamená
kapacitu akce; neznamená automaticky 1 000 souběžných platících zákazníků.

Nynější zadání autorizuje průzkum a plán. Implementace, produkční migrace,
převody skutečných plánků, nasazení, publikace balíčků, commit a push nejsou
provedeny ani zahrnuty do tohoto plánovacího kroku.

## Provedené ověření a pevný bod

Pevný bod průzkumu: Festapp `eb23047248d59bf86345b9e0b79db4a988275231`,
branch `feat/occasion-setup-wizard-20261007`; package HEAD
`c829a33d07de9a8fa376b407658875d22abd246e`. Oba HEAD samy nevystihují
rozpracovaný obsah. Vybrané SHA-256 a výsledky jsou v
[evidence JSON](evidence/blueprint-1000-audit-results-2026-10-20.json).
Jsou to lokální důkazy, nikoli popis aktuální produkce.

| ID | Potvrzený fakt | Důkaz a důsledek |
| --- | --- | --- |
| E01 | Anonymní order command přijme spot bez secretu, spot s prošlým holdem i spot z jiného blueprintu stejné akce. Ve všech třech případech vznikne alokace. | Skutečné `SET LOCAL ROLE anon` → `create_ticket_order_client_sync_v1`, nejen přímé volání interní funkce. Zopakováno nad zdrojovými definicemi i již instalovaným místním katalogem. Oprava má prioritu P1. |
| E02 | Cizí secret je odmítnut, opakování stejného order command vrátí stejnou odpověď, nový příkaz na již prodané místo je odmítnut. | Pozitivní/negativní kontroly stejné fixture. Zachovat existující receipts; nepsat druhý order engine. |
| E03 | SVG vložené aktuálním `BlueprintRenderer.renderBackground` spustí handler. | Izolovaný headless Chrome: `foreignObject` s obrázkem z neplatného data URL a `onerror` změnil pouze lokální text na `EXECUTED`. Produkční CSP ani produkční exploit nebyly testovány. |
| E04 | Tentýž SVG payload přes Blob URL v `<img>` se načetl bez spuštění handleru. | Samostatná bezpečná sonda v témže typu izolovaného Chrome. Je to ověřený kandidát řešení, nikoli již opravená aplikace. |
| E05 | 49 cílených core testů stylů a validace prošlo. | `appearance`, `seat_style`, `object_style`, `data_hardening`, `document_equality`. Neprokazují host/SQL integraci. |
| E06 | V2 fixture 1 000 židlí / 1 001 uzlů zachová identity, přesný JSON round-trip a shodu dílčí scény. | Dokument 244 870 B, scéna 2 002 položek s fixture fonty. Teplý Dart VM JIT: medián decode+validate 14,1 ms, celé scény 27,0 ms, jedné židle 0,019 ms. Nejde o prohlížečové frame times ani produkční SLA. |
| E07 | Legacy veřejný reader zvládá vrátit 1 000 míst, ale pro jediný sdílený produkt vrací 1 000 produktových řádků. | Lokální SQL/PG/JSON měření přibližně 5-13 ms v provedených bězích, zhruba 143-146 kB. Bez HTTP, TLS a vykreslení. Deduplikace má konkrétní důvod; distribuovaná infrastruktura zatím ne. |
| E08 | Hold, authoring a preview DB testy prošly. Test order sequence selže na zastaralé fixture odkazu. | Po registraci slugu existujícím `reserve_public_link_internal` projde beze změny readeru. Není to doložená chyba blueprint readeru. Opravit test, nikoli obejít registr odkazů. |
| E09 | Místní instalovaný katalog se od raw zdrojů u finalize/get_blueprint liší. | Finalize má novější reminder/default úpravy, get_blueprint má demo access fence. Oprava/migrace musí zachovat efektivní forward kontrakt a guardy. Prosté nahrání staršího souboru by bylo regresí. |
| E10 | Swap už v aktuálním kódu používá `lock_spot_assignment_scope_internal_v1`. | `swap_spot_tickets.sql:203` a jeho command wrapper. Staré tvrzení plánu B o chybějícím swap locku je neaktuální; ověřit ho testem, ne přidávat další zamykací vrstvu. |
| E11 | V tomto checkoutu host pořád používá grid `BlueprintModel`/`VenueSeatController`; tabulka blueprints nemá nový layout kontrakt. | `blueprint_editor_tab.dart:76,108`, `database/tables/tables.sql:575`. V2 demo není důkaz skutečného uloženého prodeje. |

DB sondy běžely výhradně na místním disposable PostgreSQL `127.0.0.1:55432`.
Definice zdrojů i fixture byly aplikovány uvnitř rollbackované transakce;
nebyly resetovány globální sekvence ani spuštěn bootstrap sdílené DB.
Instalovaný katalog byl ověřen ještě samostatným během bez refresh definic.
Žádná testovací objednávka, receipt ani e-mail z těchto sond nebyly commitnuty.
Obě browser sessions byly zavřeny; globální provider Panerelay byl obejit
vlastním prázdným configem a lokálním headless spuštěním.

## Cílová architektura a invarianty

1. **Geometrii a vzhled vlastní `venue_layout_core`.** Jeden verzovaný dokument,
   jeden resolver stylů, jeden scene/hit kontrakt pro Flutter a JS. Výpočet ceny,
   holdů a oprávnění zůstává v hostu a SQL.
2. **Prodej vlastní existující SQL commands.** Veřejný finalize musí pod zámkem
   ověřit otevřený a platný formulář, jeho blueprint, příslušnost spotu, správný
   nenulový secret a neprošlou expiraci, vedle existujících cenových a kapacitních
   kontrol. Platnost se posuzuje aktuálním časem po získání zámků.
3. **Administrativní výjimka je explicitní a serverová.** Oprávněný replace/prodej
   může fungovat bez zákaznického holdu. Nelze jej zapnout polem payloadu, rolí
   pouze v klientovi ani přímou anonymně přístupnou interní funkcí. Cizí aktivní
   hold se při běžné administraci nesmaže potichu.
4. **Identita není souřadnice ani barva.** Node UUID a databázové spot ID zůstávají
   stabilní při posunu, rotaci i změně stylu. Kopie získá nové identity, bez cizího
   ticketu či holdu. Cenová skupina, geometrický parent a atomická výběrová
   jednotka jsou oddělené vztahy.
5. **Styly neřídí prodej.** Pořadí vzhledu je tovární default, uložený vzhled druhu
   objektu, explicitní lokální override, poté serverová/pending/selected presentation.
   Zvýraznění dostupnosti nesmí změnit vlastní uložený styl ani se s ním zaměnit.
   Rozměry a rozestupy jsou geometrická operace, chráněná identitou a kolizemi.
6. **Save je jediný transakční aggregate.** Layout, bindings, skupinové defaulty,
   výjimky a area vazby se uloží společně s očekávanou revizí. Neúspěch nic z toho
   nezmění. Timeout opakuje stejný payload a command ID. Chybějící revize se
   u nového kontraktu odmítne; nepoužije se automaticky aktuální baseline.
7. **Jedna židle se nepřidělí dvěma vstupenkám.** Atomická jednotka se neprodá,
   nedrží, nepřesadí ani nezruší napůl. Stání zůstává množství v existujícím
   inventory. Souběžné kapacitní a finanční přechody používají původní ownery.
8. **Veřejná projekce je veřejná už na serveru.** Neobsahuje kontakty, poznámky,
   cizí objednávky, secrets, soukromé asset reference ani libovolné admin `data`.
   Neukládá soukromí do polí, která se jen lokálně skryjí.
9. **Podklad je obrázek, ne dokument aplikace.** Raw SVG není připojeno přes
   `innerHTML`, `object`, `embed` nebo aktivní iframe. Veřejné resource references
   musí ukazovat na připravený veřejný resource správného tenanta.
10. **Historie vstupenky zůstává faktem.** Cena a označení v prodané objednávce
    se nepřepisují změnou tématu nebo katalogu. Dekorativní label může být jiný
    údaj než obchodní `spot.title`; chráněný obchodní údaj nelze změnit skrytě.
    Nezavádět kvůli tomuto rozsahu nový globální registr fyzických sedadel.

## Rozhodnutí, předpoklady a zbývající mezery

- **D1:** Ponechat JSONB pro layout, relační spoty/bindings/produkty pro obchod.
  Celou scénu, glyphy, zákaznické údaje ani dostupnost neukládat do layoutu.
- **D2:** Pro raw legacy SVG zvolit bezpečný image context, s transformací a rozměry
  odpovídajícími dosavadnímu podkladu. V2 používá existující host resource provider.
  Tato volba odstraňuje aktivní DOM cestu a nepotřebuje vlastní SVG sanitizer.
  [MDN popisuje omezení SVG v image contextu](https://developer.mozilla.org/en-US/docs/Web/SVG/Guides/SVG_as_an_image).
  Externí fonty/odkazy v podkladu mohou potřebovat při importu vložit zdroje do
  obrázku nebo odmítnout; nikdy je neopravovat návratem k aktivnímu DOM.
- **D3:** Nezvyšovat počtové limity ani nepřidávat sektorový backend pro 1 000 míst.
  Nejprve odstranit duplicitu produktů a zbytečné kompletní přepočty, pokud měření
  konkrétního host toku potvrdí jejich cenu.
- **D4:** Nový save vyžaduje revizi. Staré mobilní DTO mohou zůstat jen na pojmenované
  vnější kompatibilní hranici s původním formátem; nesmějí tiše zapsat V2 layout
  nebo obejít nové obchodní guardy. Přesný seznam vydaných writerů doložit ve vlně 0.
- **A1:** Základ kvalifikace je 1 000 prodejných míst, až 100 otevřených zákaznických
  relací a vlna 20 současných mutací. Je to zvolený testovací profil, nikoli
  prokázaná produkční kapacita nebo požadavek pro stadion.
- **A2:** Host dostane V2 bindings/revision podle plánu B. Je-li to stále nedokončené,
  je to zbývající implementační závislost, ne důvod označit demo za hotový prodej.
- **Mezery ověření:** Nebyl proveden skutečný dvousession závod finalize/hold,
  zatížení HTTP/Edge s 20 klienty, kompletní V2 host E2E ani produkční readback.
  Tyto body mají níže povinné exit brány. Dosavadní výsledky je nenahrazují.

## Implementační vlny

### 0. Sjednocení baseline a reprodukovatelných důkazů

**Cíl:** opravit skutečně výsledný kontrakt, ne přepsat novější guardy starším SQL.

- Zapsat HEAD a scoped dirty manifest obou repozitářů; ověřit package resolver
  a skutečný stav integrace B. Nezahrnout cizí změny ani nechat testovat jiný package
  než ten, který se bude distribuovat. Zachovat požadavky B na vlastníka nového UI.
- Ověřit efektivní definice po všech forward migracích. Zvlášť uchovat demo fence
  v get_blueprint a aktuální reminder/default kontrakt finalize. Použít existující
  source-contract/generační workflow; neodvozovat referenční hashe z produkční DB.
- Zabezpečit výlučně task-owned DB pro integrační/souběhové testy. Stávající DB
  na portu 55432 neresetovat jen proto, že je lokální. Nové testy musí mít lokální
  target guard a odmítnout neověřený vzdálený endpoint.
- V `database/tests/eshop/get_blueprint_order_sequence_test.sql` opravit fixture
  registrací slugu kanonickým allocatorem; neměnit kvůli ní produkční resolver.

**Kontrola/exit:** známé zdroje a izolovaná DB; tři původní passing SQL kontroly
a opravený sequence test procházejí. Před opravou lze E01/E03 reprodukovat.
Výsledek sondy zobrazující chybu se nevydává za passing security regression.

### 1. Uzavření veřejné rezervace a aktivního SVG

**Změny a získaný invariant:**

- `database/functions/eshop/finalize_ticket_order.sql`: veřejná větev kontroluje
  všechny podmínky invariantu 2 včetně nenulového secretu, expirace a vazby na
  form blueprint. Zkontrolovat duplicitní spoty v jednom payloadu. Vše běží pod
  zámky; po konfliktu se necommitne ticket, payment info, allocation ani e-mail.
- `create_ticket_order.sql`, `eshop_orders/create_ticket_order_client_sync_v1.sql`,
  replace/confirm a waitlist accept: všechny vstupy používají tentýž invariant;
  admin výjimka vychází z ověřené identity a pravomoci. Zachovat legální běžný
  nákup bez konkrétního spotu a existující množstevní produkty.
- Zapsat jedno pořadí parent/seat locků podle skutečných callerů. Použít existující
  scope helpery; checkout nezamyká seat teprve při posledním UPDATE po nechráněném
  ověření. Zachovat pořadí form/order parent → produkt → blueprint → potřebné
  inventory parenty → spoty v ID pořadí. Buyer advisory lock z holdů bez důvodu
  nepřenášet do editoru. Případný retry serializace musí použít stejný command ID.
- `web_client/src/components/blueprint/blueprint_renderer.js` a `svg_utils.js`:
  odebrat raw SVG → `innerHTML`. Image-context adaptér má odvolání Blob URL při
  výměně/destroy, omezení velikosti a bezpečný error stav. Obrázkový podklad se
  nemá změnit na aktivní HTML ani při parser error. Udržet viewBox, crop a fit.
- Prověřit stejnou hranici u package JS asset resolveru a host importu podkladu;
  aktivní payload nesmí projít alternativním viewerem. Neuvolňovat script CSP.

**Migrace/kompatibilita:** nová forward migrace navazující na aktuální řadu;
kanonické zdroje a migrace musí dávat stejný výsledný kontrakt včetně dalších
guardů. Neměnit historické migrace jako jedinou opravu. Existující SVG zůstane
zobrazitelné jako obrázek; případně nepodporované externí zdroje se ohlásí.

**Validace:** nový `database/tests/eshop/blueprint_reservation_integrity_test.sql`
pokryje valid hold, NULL/absent/wrong/expired secret, foreign blueprint/occasion,
closed/scheduled form, replay, druhý command na prodaný spot a oprávněný admin
replace bez veřejného holdu. SQL test používá skutečné anon/authenticated role.
Nový `web_client/tests/components/blueprint_background_security.test.js` a
headless kontrola skutečného rendereru prokážou, že E03 už nefunguje a bezpečný
SVG i raster podklad se zobrazují. Zachovat denied přímé interní RPC.

**Exit:** tři případy E01 vracejí rejection bez side effects; validní veřejný nákup,
admin tok a replay fungují. SVG handler se nespustí a není přítomen v DOM hosta.

### 2. Datový save/read, styly a obchodní identita

**Cíl:** uložený V2 dokument a jeho obchodní vazby nejsou dvě nezávislé pravdy.

- Převzít nebo dokončit potřebnou část vlny 1 B: `eshop.blueprints.layout`,
  revize, node-to-spot bindings, skupinové produktové defaulty a area bindings.
  Vše přes `update_blueprint_client_sync_v1`, ne přímými tabulkovými zápisy.
- Serverová validace kontroluje uzavřený strukturální kontrakt: verzi, počty,
  bytes/hloubku, typy a rozsahy geometrických/stylových hodnot, povolené klíče,
  UUID/ref/parent integritu, resource references a zakázaná business pole.
  Nepřepisovat prostorové algoritmy či rendering do SQL. Sdílet verzovanou
  specifikaci a pozitivní/negativní corpus s core validátorem, aby se rozsahy,
  styly a povolená pole nerozcházely. Nezávislá klientská validace není oprávnění.
- Rejection po jakémkoli částečném INSERT/UPDATE musí rollbacknout celý aggregate
  před dokončením receipt. Testovat i chybu posledního prvku a limit response;
  aggregate vstup má nyní 8 MiB, result data 4 MiB a receipt 8 MiB.
- Držené/prodané místo nelze smazat, změnit na dekoraci, přepojit na jiný produkt
  či nedělitelnou jednotku, nebo skrytě přejmenovat jeho obchodní označení.
  Samotný posun/rotace/vzhled a čistě dekorativní label jsou odlišné operace.
  Zachovat historické spot title a cenu v objednávce. Případná explicitní obchodní
  změna používá existující order owner a historii, ne style save.
- Zákaznická projekce používá povolený seznam polí; oddělit admin metadata.
  V `get_blueprint.sql` deduplikovat produkty podle ID. Neodstraňovat pole `data`
  naslepo: nejdřív dohledat skutečné čtení a veřejná potřebná pole explicitně promítnout.
- Ve V2 mají nové writers povinnou očekávanou revizi. Starý adapter smí zůstat
  jen dle inventury vydaných klientů a nesmí zapsat nový layout bez této ochrany.
- Setup/copy/import nesmí kopírovat occupancy, command identity či zákaznická
  data; převod stávajícího plánku zachová spot ID a obchodní údaje. Žádný hromadný
  převod produkčních plánků v této implementaci.

**Validace:** rozšířit B `blueprint_layout_test.sql` o invalid style keys/NaN-like
nečíselné vstupy, neznámé schéma, cizí binding/resource, stale/missing revision,
alokovanou židli, částečný zápis a oddělení veřejných/admin dat. Corpus round-trip
v core a SQL strukturální kontroly se porovnají na stejných fixtures.
Save → read → reopen 1 000 míst zachová bindings i explicitní overrides.

**Exit:** jediný zdroj geometrie a stylu, jednoznačné spot vazby, žádné změny
objednávek přes vizuální save. Pro jeden produkt je ve veřejném DTO jeden řádek.

### 3. Oba klienti, expirace a pravdivá obnova stavu

**Cíl:** vizuální výběr odpovídá potvrzenému serverovému stavu i při chybě.

- V `DbOrders.selectSpot` a JS `DbForms.selectSpot` předat typovaný výsledek
  s `expiresAt`; Flutter dnes redukuje odpověď na bool. Stav relace musí znát
  skutečnou expiraci serveru, ne vytvořit nový plný timeout při reloadu.
- `seat_reservation_widget.dart`, `blueprint_selector.js`, `form_session.js`
  a jejich V2 nástupci: odmítnutý hold obnoví picker i form payload; submit počká
  na pending hold operace. Ztracená odpověď vyvolá ověření autority, ne automatické
  tvrzení, že hold neexistuje. Retry holdu neprodlužuje původní deadline.
- Při reopenu nepřepsat spot na `selected_by_me` jen podle starého lokálního
  výběru. Server má přednost po expiraci, převzetí místa i po změně oprávnění.
  U klientů se stejným buyer secretem řešit obnovu a release bez duplikace ticketu.
- Nemazat výběr při presentation patchi ani při změně tématu. Undo/redo layoutu
  nevrací a znovu neposílá již potvrzenou objednávku. Permission change během draftu
  blokuje save; poslední potvrzený dokument zůstává dostupný.
- Fonty a pozadí projdou stávajícím host resource providerem. Chybějící font/asset
  vrátí viditelný error, nikoli prázdný plánek, ztracený dokument nebo náhradní cenu.

**Validace:** skutečně registrované Flutter suites `shared_czech_test.dart`
a `shared_default_2_test.dart`, nové scénáře v příslušných `*_cases.dart`;
kontrolovat počty a jména vykonaných testů. JS session/picker testy pokryjí
pending submit, rollback payloadu, reload, expiraci a opožděnou odpověď.
Package reservation identity a style/context testy pokryjí apply/undo/redo.

**Exit:** úspěch, konflikt, expirace i timeout končí shodnými ID/stavy/cenami
v obou klientech a v DB. Žádná větev nenahradí serverový stav lokálním odhadem.

### 4. Skutečný souběh a kvalifikace 1 000 míst

**Cíl:** dokázat vlastnosti výsledného řešení, které sériová sonda nedokazuje.

- Přidat `database/tests/eshop/blueprint_reservation_concurrency.test.mjs` se
  dvěma a více skutečnými PG spojeními. Deterministické barriers, konečný
  statement/lock timeout, commit/rollback a kontrola všech výsledných vztahů.
  Žádné pouhé `sleep` a žádný test jen opakování jednoho command ID.
- Povinné závody: dva buyers na jednu židli; valid finalize proti re-hold po
  expiraci; hold proti smazání/změně produktu; dva editoři jedné revize;
  finalize proti swap/replace/storno a cenové změně; stání na poslední kapacitu;
  celá atomická jednotka proti částečnému výběru. U prohraného příkazu žádný
  ticket/payment/history/email side effect; použitý hold nesmí zůstat nabízený.
  Zopakovat závod přes dva formuláře stejné akce nad sdíleným plánkem i přes
  různé produkty, aby výsledek nestál pouze na náhodné serializaci jednoho formu
  nebo produktu. Ověřit i přerušené spojení těsně před a po commitu.
- Fixtures: 1 000 židlí v řadách; 100 stolů po 10 židlích s lokálními výjimkami;
  kombinace se stáním, gaučem, rotací a podkladem. Cenové a prodejní stavy
  available/held/selected/ordered/used/blocked. Vyzkoušet uložené font resources.
- Vlastní izolovaný full-app backend podle `festapp-local-e2e`, bez providerů
  plateb/e-mailů. Skutečný admin → save → reopen → veřejný picker → hold → order
  → admin stav, včetně sítě a skutečných SQL commands. JS a Flutter používají
  odpovídající buildy a stejná fixture ID. Mock package demo tuto bránu nenahradí.
- Změřit zvolený profil 100 otevřených sessions / 20 souběžných mutací.
  Počítat očekávané konflikty odděleně od timeoutů, deadlocků a interních chyb.
  Nezvyšovat plošně anti-abuse limity, aby test prošel; doložit efektivní politiku
  a případný odůvodněný limit konkrétní akce. Buyer UUID není identita člověka.

**Rozpočty kvalifikace, ne dosavadní výsledky:** na zaznamenané lokální sestavě
po zahřátí assets plánek do 2 s použitelný; lokální odezva výběru p95 do 100 ms;
hold odpověď p95 do 1 s při 20 mutacích bez umělé WAN latence; celá save/reopen
operace do 2 s. Každou metriku rozdělit na klient/transport/SQL a měřit stejnou
fixture, viewport, renderer a build režim. Při nesplnění profilovat konkrétního
ownera a opravit ho, nikoli změnit práh bez evidence. VM benchmark 27 ms není
tvrzení o 60 FPS ani mobilním vykreslení.

**Exit:** žádná dvojí alokace, porušená cena, poloviční jednotka nebo částečný
save; všechny uvedené závody mají důkaz. Reálný host tok pro 1 000 lidí splňuje
rozpočty. Paměť a počet handlerů/Blob URL se po deseti mount/dispose cyklech
nehromadí. Zaznamenat Chrome a jeden mobilní/touch profil; emulace není fyzický telefon.

### 5. Odstranění nahrazených cest a příprava aktivace

- Ve výsledné větvi zrušit starý interní renderer/style save, který byl V2
  skutečně nahrazen, v souladu s deletion ledgerem B. Dokumentaci aktualizovat
  podle výsledného kontraktu; neudržovat dva aktivní editory téže akce.
- Legacy sloupce a vnější mobilní adaptéry ponechat jen do odděleně autorizované
  aktivace a ověřené migrace jejich spot identit. Pojmenovat přesné konzumenty,
  podporované DTO a podmínku odstranění; nezavést trvalý fallback na starou geometrii.
- `_v1` v client-sync RPC je verze command protokolu, nikoli důkaz starého
  rendereru. Nerušit receipts, order commands ani kompatibilní ticket identity.
- Zapsat finální source/migration/build hashe a výsledky kontrol. Nenasazovat
  z neověřeného lokálního package override. Produkční kroky zůstanou neprovedené.

**Exit:** konkrétní ověřený release kandidát, jeden cílový kontrakt a přesný
seznam dosud neaplikovaných provozních kroků. Označení „připraveno lokálně“
se nezaměňuje za „aktivní v produkci“.

## Ledger odstranění a kompatibility

| Cesta | Výsledek | Důkaz |
| --- | --- | --- |
| Raw SVG → `innerHTML` a fallback na původní markup | Odstranit ve vlně 1 | Stejný škodlivý fixture v obou veřejných rendererech nespustí handler |
| Veřejný finalize jen s kontrolou rovnosti secretu | Nahradit úplným invariantem; staré fasády vedou do stejné domény | Anon negativní testy přes dostupná veřejná RPC |
| V2 save bez očekávané revize | Odmítnout | Missing/stale revision test beze změn DB |
| Lokální stale výběr jako autorita dostupnosti | Odstranit | Reload/expiry/pending/network testy |
| V1 interní renderer a obchodní editace nahrazené V2 | Odstranit podle B při přechodu callerů | Scoped imports/callers + test skutečných entrypointů |
| Legacy DB sloupce a vydaní mobilní konzumenti | Ohraničeně ponechat do aktivace/migrace | Explicitní seznam callerů a guard proti zápisu V2 starým DTO |
| Receipts, původní order/inventory engine a historické cenové snapshoty | Zachovat jako kanonickou autoritu | Replay, souběh, finanční a identity testy |

## Ověřování při implementaci

DB runner spouštět jen na prokázaně task-owned DB s explicitním `DATABASE_URL`.
Zvolení nula souborů není úspěch; kontrolovat count/summary. Po zdrojové změně
ověřit nový forward katalog, ne jen ručně nahrané funkce. Relevantní příkazy:

```bash
node web_client/scripts/run_db_tests.js database/tests/eshop/blueprint_reservation_integrity_test.sql database/tests/eshop/blueprint_layout_test.sql
node --test database/tests/eshop/blueprint_reservation_concurrency.test.mjs
python3 automation/generate_canonical_source_contract.py --check
```

`DATABASE_URL` musí být nastaven z izolované fixture, nikdy převzat bez kontroly
z `.env.local`. Source/migration parity má odpovídat platnému manifestu projektu.

Pro klientské změny použít příslušné testy a session roots. Před každým Flutter
úkolem ověřit volný workstation slot; nejvýše jeden úkol, vždy concurrency 1.

```bash
fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart test/sessions/shared_default_2_test.dart
```

V package core po souvisejících změnách spustit relevantní testy přes `fvm dart test
--concurrency=1`; při finální změně sdíleného kontraktu celé core. V `web_client`
spustit odpovídající explicitní `node --test` soubory včetně session/picker/security.
V package web použít jeho `npm test` a parity kontrolu společného kernelu, pokud
se měnil scene/resource kontrakt. Analyzer jen na dotčené Dart moduly.
Passing kontroly neopakovat bez změny vstupů. Finální E2E musí odpovídat finálním
zdrojům. U nových testů ověřit discovery, nikoli jen existenci souboru.

## Rollout a návrat

Lokálně: reprodukce → bezpečnostní opravy → schema expanze → kanonický writer
a readers → callers → kvalifikace → odstranění nahrazených interních cest.
Schéma musí existovat před novým klientem. Migraci ověřit jak na nové DB,
tak na fixture s prodanými místy, starými objednávkami a aktivními holds.

Produkce je samostatně autorizovaný krok pro jediného vybraného tenanta:
read-only inventura skutečných plánků/klientů, záloha, dry-run s nezměněnými
spot ID, bezpečnostní forward migrace a expanze, ověřený klient, readback.
Bez autorizace se nic z toho nespustí a žádné jiné `prod/*` větve se nemění.
Pozdější deployment má dodržet lokální direct release workflow a delegaci
rutinního provedení podle AGENTS.md, nikoli automatický GitHub dispatch.

Návrat klienta je dovolen jen na build kompatibilní s expanzí a opravenými guardy.
Neobnovovat kvůli rollbacku nechráněný finalize, aktivní SVG ani writer, který
by zahodil V2 layout. Historické spoty a objednávky se nemažou. Schema contraction
počká na prokázané odstranění vnějších konzumentů.

## Hotovo znamená

- E01 a E03 jsou opravené a mají negativní regresní důkaz přes skutečný vstup.
- Tři fixture třídy s 1 000 místy projdou save/read/reopen a oběma zákaznickými
  toky se stejnými identitami, cenami a pravdivými stavy.
- Server odmítá neplatný/cizí dokument a bindings, souběžnou stale revizi,
  změny chráněných obchodních údajů a poloviční atomickou jednotku bez side effects.
- Souběh, replay, expirace a timeout jsou ověřené na skutečném PostgreSQL;
  výkon hosta má zaznamenané výsledky podle vlny 4, nikoli jen VM benchmark.
- Každá nahrazená cesta je odstraněna nebo má konkrétní omezenou vnější hranici.
  Platné požadavky parity B nebyly potichu vyřazeny.
- Finální zdroje, migrace a testy jsou dohledatelné; stav produkční aktivace je
  výslovně neprovedený, dokud neproběhne samostatně autorizované nasazení.
