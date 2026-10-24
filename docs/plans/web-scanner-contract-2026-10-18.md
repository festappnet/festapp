# Webový skener - prováděcí kontrakt a akceptační scénáře

Revize 3, 2026-10-18. Závazná příloha [hlavního plánu](web-scanner-plan-2026-10-18.md), nikoli samostatný návrh. Názvy nových souborů a RPC jsou cílové, nejsou tvrzením, že již existují. Při rozporu opravit oba dokumenty před implementací. Změna kontraktu se zdůvodní konkrétním současným kódem.

## 1. Hranice modulů a routy

| Vlastník | Vstup/výstup a odpovědnost | Co nevlastní |
|---|---|---|
| `components/scan/scan_page.js` | Lifecycle stránky, fokus, zobrazení stavů a příkazy controlleru | SQL pravidla, síťové retry, přímé IDB transakce |
| `scanner_controller.js` ve stejné složce | `loadCode`, `confirm`, `next`, zrušení lookupu, serializace UI událostí | Způsobilost podle ceny/profilu odhadovaná v DOM |
| `scanner_input.js` | Kamera/ruční/HID, normalizovaný payload, explicitní pause/resume/dispose | Potvrzení vstupu a navigace na URL z QR |
| `services/scanner_api.js` | Jediný transport RPC, timeout/error normalizace, nezalogované credentials | Outbox a opakované vytváření operation ID |
| `services/scanner_store.js` | IDB transakce, partition, outbox, aktivní snapshot, lease | Tiše nahrazené úložiště pamětí |
| `services/scanner_sync.js` | Jedna odesílací smyčka, opakování stejného ID, receipt reconciliation | Přepis lokálního údaje na globální pravdu |
| `scanner_settings_page.js` | Sdílená konfigurace, místní preference, konflikt revize a náhled | Nová role nebo nový obecný settings framework |
| `database/functions/scanning/` | Projekce, sessions, snapshots, receipts, admission a audit | Další ticket lifecycle/tabulka osob |

SQL soubory rozdělit podle těchto hranic, ne vytvořit univerzální helpers bez vlastní doménové odpovědnosti. Vite směrovat lazy-loadem na scanner, dekodér lazy-loadem při vstupu do kamery; offline příprava jej stáhne výslovně. Na první otevření katalogu nepřidat download scanner snapshotu či dekodéru.

Kanonické cesty:

- `/scan` - volba uložené akce/session nebo zadání scan kódu. Po výměně kódu se pracovní kontext uloží do IDB; aktivní session nesmí být tajemstvím v URL.
- `/scan/settings`, `/scan/history`, `/scan/offline` - konkrétní scanner podstránky; context zařízení je explicitně zvolený, při více uložených akcích se nesmí odhadnout.
- `/scan/program/<eventId>` - samostatná read-only kontrola přihlášení na program, ověřená vůči přihlášenému uživateli; samotný scan kód akce nestačí.
- `/login-qr` - samostatný přihlašovací scanner příslušného uživatele. Nikdy režim, který v otevřené obsluze automaticky přepne pracovníkův účet.
- `/scan/<historicalCode>` - pouze historický vstup pro exchange. Rezervovaná slova výše mají prioritu; code segment je přesně jeden, dekóduje se jednou. `/#/scan/<code>` a stávající programové deep links mají explicitní jednorázovou normalizaci.

Jeden resolver cesty určuje webové vlastnictví v normálním startu i offline navigaci; testy porovnají jeho chování s generátorem SW a deployment rewrite. Form router a seznam Flutter routes nesmí scanner přebít. Prohlížeč Back/Forward správně mountuje i uklízí komponentu. API domény ani QR text nelze použít jako obecný redirect.

## 2. Obrazovky a pracovní cesty

### Rozměry a priorita informací

Pod 900 CSS px: jeden sloupec s odsazením 16 px, kompaktní hlavička akce/stanoviště (pro běžný text přibližně 56-64 px), jeden stavový řádek „Připojeno · 248 použito“. Pending a konflikty přidat jen při nenulové hodnotě; úplné počty jsou pod rozbalovacím „Přehled“. Offline varování je vždy viditelné a může blok zvětšit. Navigace je jednotně „Skenovat / Historie / Offline“. Hledání podle jména je vedlejší akce režimu „Ručně“, dostupná podle capability; nepotřebuje další hlavní tab.

Kamera nejvýše `min(36dvh, 280px)`, výsledek ji po načtení nahradí. Pro běžně dlouhé údaje na 390 × 844 px musí být bez scrollu vidět stav, jméno, první produkt a hlavní akce. Spodní akční pás má safe-area a rezervu v obsahu. Před potvrzením dominuje „Potvrdit vstup“, sekundárně „Zpět ke skenování“; po dokončení dominuje „Další vstupenka“. Neponechávat velké deaktivované potvrzení jako hlavní ovládací prvek hotového výsledku. Na 320 px, při dlouhých hodnotách a 200% zoom je svislý scroll v pořádku, nesmí zmizet obsah/fokus nebo být překrytý akcí.

Od 900 px: max-width 1200 px, levý sloupec 320 px, mezera 24 px a pružný detail vpravo. Vlevo vstup, připravenost a nejvýše pět nedávných dokončených výsledků. Nastavení je stránka s náhledem, nikoli dlouhý malý modal. Při 200% zoom se layout přeskupí podle skutečné dostupné šířky.

Čtyři vizuální šablony (připraveno/zpracování, povoleno, dokončeno, překážka) pokrývají všechny doménové stavy přes konkrétní text a akce. Nezakládat komponentu pro každou kombinaci stavů. Reuse Futura, ThemeService a stávajících formulářových/button stylů; doplnit jen chybějící sémantické tokeny pro světlý i tmavý motiv. Prázdný stav „Připraveno ke skenování“ s konkrétní akcí.

Vždy viditelné: stav a původ ověření, identifikátor/jméno, platební překážka a účinek CTA. Výchozí profil má nejvýše tři prioritní vlastní údaje, ostatní pod „Další údaje (N)“. Číselný dluh, storno, expired grant ani konflikt nelze schovat do sbalené sekce. Žádná automatická modální okna pro úspěšné scany. Zvuk/vibrace nejsou jediná signalizace a UI je neslibuje, pokud platforma nemá podporu.

### Cesta A - rychlý vstup

1. Obsluha vidí „Hlavní vstup“, správnou akci, „Připojeno“, „Potvrzení vstupu“ a stav úložiště. Kamera vyžádá povolení až po kliknutí.
2. QR přepne UI do `looking_up`; stará CTA se okamžitě deaktivuje a input se pozastaví. Každý lookup má vlastní pořadové číslo, pozdní odpověď starého pořadí se ignoruje.
3. Server vrátí projektovaný ticket a opaque `eligibility_fingerprint`. CTA přesně říká „Potvrdit vstup“, případná neuhrazená částka zůstane viditelná.
4. Kliknutí založí JEDNU operaci. UI přejde do `persisting`, potom do `awaiting_server`. Online úspěch se ukáže až po receipt; během čekání se nezobrazuje falešná zelená.
5. Pokud request doběhne timeoutem, identita operace zůstává. Obsluha může pokračovat pouze přes explicitní lokální uložení při platném offline grantu; při jeho absenci zůstává výsledek nejasný do zjištění receipt.
6. „Další vstupenka“ odemkne nový vstup, nikoli potvrzení předchozího znovu. Lokální pending ticket při dalším načtení ukáže již uloženou operaci.

### Cesta B - výpadek a dvě zařízení

1. A má kompletní balíček z 18:00, platný grant a prázdnou frontu. Výpadek ukáže „Bez internetu. Data z 18:00; změny ostatních zařízení nevidíte.“
2. QR ukáže „Podle uložených dat lze potvrdit vstup“. Po IDB commitu se objeví „Vstup uložen v zařízení - čeká na odeslání“, pending +1, globální počet se nezmění.
3. B potvrdí tentýž ticket na serveru. A o tom offline neví.
4. Po návratu A odešle původní operaci. `already_used` ji přesune do konfliktů, zachová lokální událost a ukáže aktuální autoritativní stav. Ostatní operace pokračují.
5. Vedoucí online označí konflikt za prověřený s důvodem. Nemění ticket ani počty. Pokud člověk fyzicky prošel dvakrát, audit tuto skutečnost nezamaskuje přepsáním jednoho času.

UI rozhodnutí této revize zpracoval Astra Medium. První vydání používá jeden sdílený profil akce, řazení polí tlačítky nahoru/dolů a společné řádky výsledků v historii/frontě. Drag-and-drop framework, grafy a správa živé přítomnosti zařízení se nezavádějí.

Původní smyšlený HTML návrh byl po lokální implementaci odstraněn při [úklidu](repository-size-cleanup-RESULT-2026-10-21.md). Aktuální lokální důkazy a otevřené provozní podmínky uvádí [implementační záznam](web-scanner-implementation-2026-10-18.md).

## 3. Konfigurace a oprávnění

`public.scanner_settings`: PK `occasion_id`, `revision bigint`, verzovaný `config jsonb`, `updated_at`, `updated_by`. Organization/occasion vazbu ověřovat přes canonical occasions, nepřijímat ji pouze od klienta. RLS + grants blokují přímé čtení interní konfigurace anonymem a přímý zápis; každý SECURITY DEFINER RPC má explicitní scope check a repo search_path. Interní primitives nejsou executable přes anon/authenticated.

Příklad konfiguračního dokumentu (identifikátory jsou ilustrativní):

```json
{
  "schema_version": 1,
  "products": {"mode": "selected", "ids": [101, 102], "order": [102, 101]},
  "fields": [
    {"key": "holder_name", "source": "builtin", "default_visible": true},
    {"key": "ticket:55:739", "source": "ticket_field", "form_id": 55,
     "field_id": 739, "label": "Stravovací omezení", "default_visible": true}
  ],
  "manual_search": {"tickets": true, "users": false},
  "sensitive": {"price": false, "hidden_note": false},
  "admission": {"allow_unpaid_online": true, "allow_unpaid_offline": false},
  "offline": {"enabled": true, "max_hours": 12}
}
```

Server validuje existenci každého produktu/formuláře/pole ve stejné akci, unikátní field keys, allowlist builtin keys, rozsah, pořadí i limity velikosti. Výběr typu v UI při uložení rozbalí do konkrétních produktových ID; v režimu selected se tím nově přidaný produkt automaticky nepovolí. Skryté produkty nesmí být odeslané jen proto, aby si je klient mohl později odkrýt. Lokální preference nemění serverový allowlist.

Výchozí unpaid online zůstane povolené jen tam, kde současná politika skutečně umožňuje potvrzení ordered; migrační test doloží zachování. Offline unpaid je pro první vydání vypnuté. Zobrazení dluhu je bezpečnostní minimum pouze pro oprávnění, která mohou s neuhrazeným ticketem pracovat; nepovolené ceny se neprozradí jiným rolím. Online lookups a změny settings vracejí revizi. Při změně omezení oprávnění se serverová authorization epoch zvýší; kosmetické přejmenování nesmí zbytečně vyvolat konflikty admission.

| Schopnost | Sdílený scan-link | Přihlášený pracovník | Vedoucí/správce |
|---|---|---|---|
| Lookup + potvrzení | Jen explicitní link scope | Jen přidělený scope | Jen povolený scope |
| Vyhledávání osob/ticketů | Podle samostatné capability | Podle capability | Podle capability |
| Offline příprava | Jen explicitní grant | Jen explicitní grant | Jen explicitní grant |
| Lokální viditelnost/pořadí | Povolená podmnožina | Povolená podmnožina | Povolená podmnožina |
| Změna sdílených settings | Ne | Ne bez settings capability | Samostatné editor oprávnění |
| Vlastní historie/fronta | Ano ve vlastním scope | Ano ve vlastním scope | Ano ve vlastním scope |
| Historie jiných zařízení | Ne | Ne automaticky | Samostatné audit oprávnění |
| Vypořádání konfliktu | Ne | Ne | Online pod existující editor autoritou |
| Program check | Ne ze samotného scan-linku | Současné approver/event read oprávnění | Totéž podle současné politiky |
| Reset hesla / recepční login | Žádné nové oprávnění | Existující samostatná politika | Existující samostatná politika |

Jde o schopnosti, nikoli nové role „worker/leader“ v databázi. Implementace je namapuje na stávající check/get_is_* guards. Název zařízení „Brána A“ není ověřená identita člověka. U anonymního scan-linku je v auditu device session a `actor_user_id = NULL`.

`update_scanner_settings(p_occasion, p_expected_revision, p_config)` při stale revizi vrátí `settings_changed`; UI nabídne načíst novější konfiguraci a uchová neuložený draft. Na lokální změnu preferencí se společná revize nezvyšuje. Occasion duplicate kopíruje jen validní remapované produkt/field references, nikoli sessions, secrets, outbox či receipts.

## 4. Sessions a Supabase RPC SQL funkce

Veškeré nové serverové rozhraní skenování tvoří Supabase RPC SQL funkce ve schématu `public`, volané přes `supabase.rpc(...)`. Nevzniká vlastní REST server, REST routes, HTTP proxy ani nová Edge Function pro scanner. Termín API v plánu znamená pouze tento RPC kontrakt. Existující recepční `exchange-login-qr` se zachovává jako již existující přihlašovací hranice, nikoli jako nová scanner služba.

Nové RPC SQL funkce pod `public`:

| RPC | Kontrakt |
|---|---|
| `open_scanner_session` | Scan kód nebo existující přihlášené oprávnění -> scope, capabilities, token, server time, epoch a expirace. Silný token přes kryptografický generátor, v DB jen hash. Device ID není důkaz oprávnění. |
| `lookup_scanner_ticket` | Session + normalizovaný symbol nebo podporované user UUID -> minimalizovaný ticket, settings revision, server time, eligibility fingerprint; nemění ticket. |
| `search_scanner_tickets` | Session + query + omezený cursor -> stránka pouze povolených výsledků. Hledání osob je samostatná capability a nekončí neomezeným stažením celé organizace. |
| `prepare_scanner_snapshot` | Session + požadované režimy -> úplný immutable manifest, nikoli průběžně měnící se export. |
| `get_scanner_snapshot_page` | Session + snapshot ID + page index -> přesné payload bytes a digest, pouze vlastník/správný scope. |
| `sync_scanner_operations` | Session + nejvýše min(policy limit, 50) operací a min(policy bytes, 256 KiB) -> receipts po jednotlivých operacích. Jedna položka obslouží i online potvrzení. |
| `get_scanner_receipts` | Aktuálně oprávněný vlastník + omezený seznam operation ID -> uložené výsledky, žádná globální enumerace UUID. |
| `get_scanner_summary` | Session -> konzistentní counts, denominator definition, server time a settings revision. Názvy se neshodují s počtem fyzických přítomných osob. |
| `resolve_scanner_conflict` | Přihlášená editor autorita + operation ID + důvod -> auditované označení jako prověřené; nemění ticket. |

Settings RPC jsou popsané výše. Přidat explicitní revokaci vlastního zařízení; správce může revokovat sessions vlastní akce. Scope, limits, granty a auth failures mají jednotný serverový envelope `code`, strojový `reason`, `data`, `retry_after_ms`, `server_time`. Transportní HTTP 200 se nesmí považovat za doménový úspěch; staré SQL má aplikační code v JSON.

Ticket DTO obsahuje jen `ticket_id`, symbol, povolenou identitu a pole, produkty s ID a popiskem, state, serverem vypočtené `admission_allowed`, `requires_unpaid_confirmation`, případně povolený dluh/místo/skupiny. Eligibility fingerprint je opaque hodnota od serveru, klient ji nepřepočítává ani z ní neodvozuje další oprávnění.

Program check používá současný `get_event_participants_for_edit` jen při odpovídajícím oprávnění; případná užší projekce nesmí rozšířit read scope. Uchovat přihlášené companions a význam „na program přihlášen“, nevytvářet attendance writer. Recepční login respektuje přesný `festapp-login:v1:<occasion>:<secret>` parser s aktuálními délkami a existující AuthService login QR/manual code backend (`lib/data_services/auth_service.dart`: `exchange-login-qr`, payload nebo occasion/manualCode, `setSession` a kontrola aktuální organizace). Token se neukládá do historie scanneru. Úspěšné přihlášení může pokračovat do stávající aplikace, přihlašovací skenování samo proběhne v JS.

## 5. Trvalý model a transakce

Serverové tabulky kromě settings:

- `scanner_sessions`: ID, occasion, původ přístupu, optional actor, token hash, capabilities, epoch, issued/expires/offline_until, revoked_at. Jméno zařízení je pouze popisek. Pro první vydání jediný token s omezenou platností; žádný vlastní refresh-token framework.
- `scanner_snapshots`: immutable manifest a payload pages, session/scope, created_at/retention/expiry, source settings epoch a počty. Fyzické oddělení page tabulky podle velikosti; nemá kopii ticket lifecycle ani vlastní aktualizovatelné guest state.
- `scanner_operations`: unikátní `operation_id`, immutable původní session a scope, ticket, payload hash, rozhodnutí, server commit time, původní fingerprint, případný odkaz na kolidující admission. Receipt je přímo tento řádek, nevytvářet druhou tabulku identických receipts.
- `scanner_conflict_resolutions`: operation ID, rozhodující actor, server time a důvod; oddělené od původního neměnného výsledku. Žádný druhý stav ticketu.

Rozhodnutí o reuse: repozitář již má `begin_client_mutation_v1` i `begin_anonymous_client_mutation_v1` (`database/functions/demo_occasions/client_mutation_guards.sql`). Tabulka `client_mutation_receipts` má user/client actor, obecný completed/expired lifecycle a po expiraci odstraněný response (`supabase/migrations/20260806100000_client_sync_production_hardening.sql`). Scanner používá vlastní úzce vymezený `scanner_operations` jako jediný registry scanner receipts: jeho autorizační identita je session a nevypořádané offline události nesmějí automaticky ztratit svůj výsledek. Obecné mutation receipts/retenci a sync materializaci nerozšiřovat. Reuse existujících guards, zámků a vzoru claim/hash/finish; nekopírovat obecný Client Sync framework. Táž scanner operace se nezapisuje do obou registrů. Změnit toto rozhodnutí lze pouze doloženým jednodušším návrhem se stejnou autoritou a retencí, aktualizovaným v hlavním plánu i příloze.

Ilustrace položky požadavku; hodnoty se nikdy nevytvářejí z dat DOM:

```json
{
  "operation_id": "5d45393c-9abe-4c2a-805a-471ed99d3a20",
  "action": "admit_ticket",
  "ticket_id": 482,
  "origin_session_id": "8c773bef-82e1-4f8d-8fda-503ad2901e09",
  "snapshot_id": null,
  "settings_revision": 7,
  "eligibility_fingerprint": "opaque-server-issued-value",
  "confirm_unpaid": false,
  "captured_at": "2026-10-18T16:42:00Z"
}
```

Lookup online používá `snapshot_id = null`, offline konkrétní uložený snapshot; fingerprint je povinný v obou případech. Origin session/occasion se musí shodovat s prokázaným access contextem. Hash server počítá z kanonického JSONB dokumentu stabilních významových polí, ne z klientského hash parametru. Bearer token a retry metadata nejsou součástí identity operace.

Accepted receipt obsahuje `operation_id`, `outcome=accepted`, `reason=admitted`, `committed_at`, `ticket_id` a fingerprint použitého rozhodnutí. Conflict/rejected má strojový reason a bezpečnou projekci vysvětlení. Opakovaný přenos přidává transportní `replayed=true` mimo neměnný uložený výsledek. Aktuální summary/current ticket se případně vrací vedle receipt, nikdy přepsáním historického receipt.

### Přesné pořadí admission

1. Ověřit autentizaci session, scope a limity; operation ID je global unique UUID a payload hash zahrnuje původní scope/session/ticket/action/snapshot/fingerprint/unpaid confirmation. Při retry stejného ID a jiného hash vrátit `operation_payload_mismatch`.
2. Transakčně rezervovat operation ID. Souběžný totožný request počká na commit prvního nebo bezpečně retry; nesmí přečíst trvale nedokončený „success“ řádek. Oprávněný identický retry již uložené operace vrátí historický receipt bez dalšího ticket write.
3. Před ticket lockem získat scope zámky `lock_order_capacity_scope_internal` pro související orders, poté orders v kanonickém pořadí, pak ticket. Použít současné order/ticket mutability guards bez obráceného zamknutí. Pokud se během předběžného čtení změnily vazby, po zámku je znovu ověřit a bezpečně retry; nevěřit původnímu order ID.
4. Znovu ověřit current state, symbol, occasion writable, order eligibility, platnost session a epochu. Při revokaci souběžné s potvrzením musí obě cesty serializovat společnou session/epoch hranici. Žádný serverový úsudek podle klientského času.
5. Porovnat eligibility fingerprint z lookupu/snapshotu s aktuálním. Zahrnuje ticket ID/state/updated_at, příslušnou order eligibility a verzi admission policy. Nezahrnuje název produktu, zvolenou barvu ani lokální pořadí polí. Změna paid/sent bez nové překážky může vrátit čerstvý lookup; automatické potvrzení při nesouladu se neprovede.
6. Pokud je vstup povolen, provést ticket state=used a receipt v jedné transakci. Pokud jde o očekávanou doménovou překážku, uložit odmítnutý/conflict receipt bez ticket write. Rate limit/DB timeout/neočekávané 5xx jsou retryable, nesmějí natrvalo spotřebovat operation ID jako zamítnutý ticket.
7. Výsledky dávky poslat až po úspěšném commitu. Očekávaný konflikt jedné položky neblokuje další. Nečekaná DB chyba může shodit celou HTTP transakci; klient opakuje stejná ID, předchozí samostatně commitnuté dávky zůstávají bezpečné.

Staré nativní scan a admin used wrappers musí přesunout zámky před ticket-first SELECT; podpis a semantiku odpovědi zachovat. Nevnucovat scan receipt režim nesouvisejícím order mutations, jen sdílet doménové zámky a eligibility.

### Vrácení ticketu na nepoužito a historické receipts

`update_ticket_to_unused_ws` nadále znamená oprávněnou novou možnost použití, ne smazání historického admission. Mění current state/timestamp; čerstvý lookup tedy vrátí nový fingerprint. Offline operace vytvořená podle staré generace musí skončit `eligibility_changed` i tehdy, když je ticket nyní opět sent.

Retry dávného accepted ID vrátí PŮVODNÍ accepted receipt s časem původního commitu a samostatným aktuálním stavem, pokud ho caller smí číst. Nesmí znovu nastavit used, znovu zvýšit počty ani přepsat novější snapshot starým used overlayem. Nový platný vstup po oprávněném unused má nový operation ID a čerstvý fingerprint. Pokud změněný writer negarantuje aktualizaci fingerprint source, opravit ho v rozsahu admission; nezavádět závislost na nezjištěném generickém updated_at triggeru.

## 6. Snapshot a lokální stav

Snapshot materializovat z JEDNOHO konzistentního SQL statement snapshotu (například `WITH ... MATERIALIZED` pro řádky/projekci/page grouping a manifest). Několik stránkovaných SELECTů nad živými tickets není konzistentní snapshot. Před materializací zamknout session/policy hranici, aby revize manifestu odpovídala autorizovaným datům. Dostupnost a velikost omezit existující abuse policy; opakovaná příprava má serverový limit a TTL cleanup.

Každá stránka vrací přesný `payload_text` v UTF-8 a SHA-256 těchto bajtů. JS ověřuje přes TextEncoder původní text, nikoli JSON.stringify znovu naparsovaného objektu. Manifest má seřazené page indexes/digests, počet ticketů a byte count. Po ověření všech stránek klient v transakci přepne active snapshot pointer. V půlce přípravy zůstává aktivní předchozí úplný balíček. Digest chrání úplnost/proti poškození; není to samostatný důkaz oprávnění nebo podpis offline licence.

IDB partition: canonical backend generation + origin/organization + occasion + session. Lokální stores `sessions`, `snapshots`, `tickets`, `outbox`, `receipts`, `preferences`, `sync_leases`. Outbox záznam obsahuje nezměněný původní payload, attempt count, next_attempt_at, stav a last error; citlivý guest DTO do něj neukládat celý. Vyhledávací index obsahuje jen povolené údaje, je přestavitelný ze snapshotu a není druhá autorita.

Datové a UI stavy jsou oddělené:

| Stav | Význam | Povolené pokračování |
|---|---|---|
| `persisting` (UI) | IDB ještě nepotvrdila commit | Žádný úspěch ani nový submit |
| `pending` | Trvale uloženo, server výsledek neznámý | Sync; další ticket jen podle platného offline grantu |
| `sending` | Request může být in flight nebo po crashi nejasný | Receipt lookup/retry stejného ID |
| `blocked_auth` | Transport zastaven pro session/epoch | Zachovat payload a vyžádat oprávněné obnovení |
| `accepted` | Historický autoritativní receipt | Zobrazit výsledek, nikdy znovu zapisovat |
| `conflict` | Známý výsledek kolize/změněné eligibility | Přehled konfliktů/vedoucí |
| `rejected` | Známé definitivní odmítnutí této operace | Nový lookup, žádné automatické opakování jako nová akce |

Klientský lease má holder UUID, expiry, fencing generation; read/update v jedné IDB transakci. Expired lease lze převzít, pozdní odpověď starého holdera nesmí zhoršit terminal state. `BroadcastChannel` je pomocná signalizace, nikoli podmínka korektnosti. Pending overlay je odvozený z outboxu a nemůže udělat z unknown ticketu platný ticket.

Opakování: timeout například 10 s; backoff 1, 2, 4, 8 až max 30 s s jitter; respektovat delší server `Retry-After`. Po odložení záložky žádný slib přesných intervalů. Nejprve reconcile receipts a odešli pending, pak stáhni nový snapshot a summary. Konflikt jedné operace nezastavuje frontu, 401/epoch blokuje scope, 429 pozastaví podle serveru. Retry count nemění původní request hash.

Nově prodaný/změněný ticket může v offline snapshotu chybět; takový případ ukázat jako neověřitelný offline. Online číst čerstvou projekci. Offline provoz nelze zapnout až po prvním výpadku bez předchozích dat. Samotný funkční internet bez trvalého outboxu dovolí čtení, nikoli potvrzení; tím nevzniká druhá paměťová write cesta.

Grant expiry se lokálně posuzuje podle server-time anchor + monotonic elapsed během otevřené stránky. Po restartu je nutná kontrola plausibility uloženého času, zpětný skok hodin blokuje nové offline přijetí do online ověření. Prohlížeč bez důvěryhodného času nedává bezpečnostní důkaz; server i tak znovu autorizuje každý replay. Podvržený klientský čas nemůže prodloužit serverový grant.

Při vypršení se fronta uchová a po nové autorizaci stejného scope se pouze zjistí již existující receipts. Dosud necommitnuté operace ze zneplatněného grantu se automaticky nepřevedou do nové session. Vedoucí je může online prověřit; první vydání nevytváří obecné „force accept offline history“ API. Pokud je dnes ticket stále použitelný, vedoucí může zvolit existující aktuální autorizovanou admission akci a auditně ji navázat na původní konflikt, nikdy nahradit jeho identitu.

## 7. Počty, historie, audit a provoz

Summary nese `eligible_total`, `used_current`, `unused_eligible`, `unpaid_conditional`, `server_time`, `definition_version`. Celková platná množina pro headline je used + aktuálně způsobilé nepoužité, nikoli počet účtenek. Storno/waitlisted nejsou eligible, nezaplacené podmíněné jsou oddělené. `used_current` zahrnuje i administrativně označené used, proto label „Použité vstupenky“; auditované fyzické potvrzení pouze label „Potvrzení skenerem“. Nevydávat historické used za prokázaný příchod člověka.

Summary se vypočítá v jednom snapshotu; `used_current + unused_eligible = eligible_total` v definovaném scope. Reálné počty se mohou snížit při oprávněném unused nebo stornu; UI je nesmí držet monotónně. Lokální pending počítá unikátní otevřené operace/tickety podle uvedeného labelu, conflict count jen nevypořádané konflikty. Filtr produktů detailu summary scope nezmění. Součet peněz se neodvozuje z vybraných produktů.

Historie odděluje „Toto zařízení“ a oprávněný „Přehled akce“. U každého potvrzení uvádí původ (online/offline), client captured time jako údaj zařízení, server committed time a outcome; anonymního operátora nejmenuje. Původní příjmy po offline výpadku se neztratí ani při conflict resolution. Receipt TTL musí přesáhnout přípustné období retry; pro první vydání se receipts automaticky nemažou, dokud není definovaná a otestovaná retenční politika. Snapshot rows mají krátký TTL a cleanup bez aplikačních triggerů.

Provozní start: vybrat správnou akci, pojmenovat zařízení, připravit data, ověřit kameru/čtečku a grant do konce směny. Handover směny: zobrazit pending/conflicts, odeslat nebo výslovně předat uzamčené zařízení; logout nesmí smazat frontu. Při výpadku storage použít jiné připravené zařízení. Při delším výpadku za offline grant nové přijetí zastavit, stávající záznamy zachovat. Žádný obecný export guest seznamu do nechráněného CSV jako automatický fallback.

Telemetrie bez PII: čas a verze aplikace, hash/pseudonym scope, velikost fronty, nejstarší pending, kód chyby a sync latency. Nikdy ticket symbol, QR, scan token, session token, jméno ani poznámky. Bez sítě zobrazuje zařízení své zdravotní metriky, neposkytuje předstíraný centrální dohled.

## 8. Matice ověření a implementační balíčky

Pro pořadí prvního vertikálního řezu a provozní rozpočty platí část „Efektivita implementace a provozu“ hlavního plánu. UI gate zahrnuje jeden cílený izolovaný průchod mobilním a desktopovým výsledkem, offline konfliktem a storage failure, s obrázky klíčových stavů. Funkční accessibility tree nenahrazuje vizuální kontrolu hierarchie. HTML demo nepoužívat jako produkční CSS ani důkaz offline persistence.

| ID / scénář | Minimální důkaz | Vlastník / vlna |
|---|---|---|
| C01 kamera/ručně/HID stejného symbolu | Shodná projekce; Enter HID pouze lookup | Controller/input, 3 |
| C02 dvojklik a opakované video snímky | Jedno operation ID, jeden přechod | Controller + SQL, 2-3 |
| C03 server commit + ztracená odpověď + restart | Retry vrátí stejný receipt, počet se nezvýší | SQL/store/sync, 2/4 |
| C04 dvě spojení potvrdí stejný ticket | Jeden accepted, druhý already_used | DB concurrency, 2 |
| C05 potvrzení proti současnému storno/payment | Konzistentní serializace, žádný obrácený lock order | DB concurrency, 2 |
| C06 offline A, accepted B, sync A | Viditelný konflikt, zachovaná lokální historie | Sync/browser, 4 |
| C07 accepted -> admin unused -> starý retry | Historický receipt neprovede nový write | SQL + store overlay, 2/4 |
| C08 starý snapshot -> unused/reopened -> nová lokální operace | eligibility_changed, nikoli tiché nové použití | SQL, 2 |
| C09 přerušené stažení/digest mismatch | Starý snapshot funkční; nový není ready | Store/browser, 4 |
| C10 quota před potvrzením / crash po IDB commit | První bez úspěchu, druhý s obnovenou operací | IDB/browser, 4 |
| C11 session revoke/expiry v půlce fronty | Scope blokován, terminal receipts zůstávají, nic se nepřeznačí novou session | Auth/sync, 2/4 |
| C12 role/cizí tenant/přímý RPC | Settings/cizí snapshot/cizí receipts odmítnuty i bez UI | SQL ACL, 1-2 |
| C13 all/none/selected + cizí field ID + duplikace akce | Přesná projekce, žádný leak a validní remap | Settings SQL/JS, 1/3 |
| C14 přímý/hash start a Back/Forward bez sítě | JS scanner shell; žádné Flutter asset requests | Routing/PWA, 5 |
| C15 dvojice záložek a expired lease | Jeden sender; pozdní odpověď nezhorší terminal state | Store/sync, 4 |
| C16 app update + outbox staršího schema | Fronta přežije, nekompatibilita blokuje bezpečně | IDB/PWA, 4-5 |
| C17 program a recepční credential ve špatném režimu | Žádný ticket write ani změna účtu obsluhy | Domain adapters, 3 |
| C18 320 px/200% zoom/klávesnice/dlouhé texty | Dostupná CTA, fokus a bezpečnostní stav | Jediný kombinovaný UX průchod, 3/5 |

Nové test suites seskupit podle seam: `web_client/tests/scan/{controller,settings,store,sync,routing}.test.js`, SQL `database/tests/scanning/{settings,admission,snapshot,authorization}_test.sql`; konkrétní multi-connection harness nesmí spoléhat na jedinou rollback SQL transaction. SQL runner filtruje názvy jako substring a při nulové shodě končí úspěchem, proto validation musí doložit nenulový počet provedených testů. Před spuštěním runneru explicitně nastavit izolovanou lokální DATABASE_URL, nikdy se nespoléhat na `.env.local` jako důkaz lokálního cíle.

Každá vlna je ucelený reviewovatelný balíček: 1 konfigurace+projekce, 2 server admission+ACL+konkurenční důkaz, 3 online pracovní cesta+nastavení+ostatní skenery, 4 persistentní offline+recovery, 5 routing cutover+absence legacy web entry, 6 runbook+autorizovaný release. Backend lze připravit aditivně před klientem, ale jako hotový výsledek se neoznačí neúplná online-only náhrada.

První vydání obsahuje všechna C01-C18. Další analytika, volitelný automatický rychlý režim, více sdílených profilů stanovišť, delta snapshots a produktové čerpání nejsou podmínkou ani skrytým dluhem této implementace. Trvalost fronty, truthful UX, replay a autorizační scope nejsou odložitelné „polish“.

## Implementovaný doplněk kontraktu

Lokální realizace revize 3 je doložena v [implementačním záznamu](web-scanner-implementation-2026-10-18.md). Ticketová odpověď se čte z kanonického `eshop.tickets.data.fields` vytvořeného `extract_ticket_answers_internal`; order pole z order data. Root JS shell řeší legacy hash dříve, než router provede běžný forced-home handoff, protože hash nemůže vidět HTTP/SW resolver. Obě změny jsou současně zaznamenány v hlavním plánu.

Úzké pomocné RPC: `search_scanner_users` (samostatná capability, occasion-scoped minimální projekce a stránkování), `preview_scanner_ticket` (editor + validovaný draft), `get_scanner_event_history` (editor audit, omezená stránka), `reset_scanner_password` (session scope + delegace na existující reset_password_via_scan bez rozšíření target oprávnění), `revoke_scanner_session` (vlastní token nebo stávající editor). Nové endpointy jsou výhradně public Supabase RPC.

Lokální outbox schéma 1 se nemaže při nekompatibilní operaci: future schema má stav `blocked_schema`, zachová payload a neodesílá se. `blocked_auth` se může pouze reconciliovat na existující receipt; automatická změna origin session není povolena. Příprava navíc žádá existující PWA worker o úplnost matching shellu zprávou `FESTAPP_SCANNER_SHELL_STATUS`.
