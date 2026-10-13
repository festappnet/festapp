# Dokončení provozní spolehlivosti BankSync

Datum: 2026-10-08
Stav: Parser Air Bank 0.2.8 je vydaný, nasazený a provozně ověřený. Zálohy jsou uklizené a nová retence je nasazená. Dokončení všech zbývajících vln je nyní výslovně autorizované jako aktivní cíl. Společný kandidát byl sloučen přes chráněný PR #57 do main `8868b37f0ef443b205ff79dd7ed8bc14dabe2356`; další verze se do dokončení a ověření celého kandidáta nevydává. Produkční D1 je nyní na schématu 13 a běží celý nevydaný kandidát z main `9d1e70e` (Worker `e4fb42cd-236e-4846-b48e-8c5ac4a2a41c`). Produkční backup/restore v oddělené D1 je ověřený; běží závěrečná zkrácená observace.
Verification: standard (bankovní fakta, sdílený provoz, migrace a destruktivní úklid).

## Výsledek a rozsah

Sdílený BankSync má dál bezpečně přijímat bankovní fakta a doručovat je současným consumerům. Dokončené výpisy nesmí neomezeně růst, polling nesmí prohledávat jejich celou historii a neopravitelné emaily nesmí opakovat stejnou chybu bez omezení. Uzavření vyžaduje produkční důkaz po nasazení, ne pouze zelené testy.

Implementace vlastní `/Users/miakh/source/banksync`; nasazenou kompozici vlastní `/Users/miakh/source/roman_seznamka/services/banksync`. Tento plán je uložen ve Festappu, odkud vzniklo zadání. Neměnit nesouvisející rozepsané změny ve Festappu nebo Mendeliu. BankSync výchozí implementační HEAD při průzkumu: `a13e4829e88d9baf80cfda6c1f2a38e672e74ef9`, balíček 0.2.7. Před publikací parser PR byla base aktualizována na authoritative main `4e269156fd78710ca332f8da2b036756246f90ff`; parser release cílově 0.2.8.

Uživatel autorizoval opravu parseru Air Bank a bezpečné odstranění starých záloh Festapp Supabase. Pro zbývající provozní změny nejprve požádal o plán, následně výslovně o jeho úplné dokončení a revizi stručného README. Následně výslovně požádal prověřit Fio dokumentaci a pokračovat v práci i plánu: cílový návrh proto nově používá inkrementální `/last`. Opravu parseru dovést přes chráněný release do nasazené instance. Zbývající migrace a změna bankovního kurzoru mají níže konkrétní prováděcí kroky; samotný plán není automatickým finančním replay ani rolloutem dalších tenantů.

## Rozpracovaný kandidát bez vydání

V `/Users/miakh/source/banksync` je větev `fix/complete-banksync-operations` z main `4caff24d81677fec82fba17d58f615e732b7eff8`, stále s package verzí 0.2.8. Migrace 0013 je v kandidátu, byla testována v oddělené D1 a je nyní aplikována také v produkci: přidává partial indexy, stav Fio kurzoru a rozšiřuje email recovery. Test migrace zachovává existující pending důkaz. Email recovery tabulka byla podle explicitního plánu přestavěna v recovery maintenance okně; SHA-256 porovnání původních sloupců všech 8 záznamů potvrdilo jejich přesné zachování. Samotný aditivní partial index byl po stage testu a zachycení Time Travel bookmarku nasazen nezávisle, bez aplikačního vydání.

Kandidát obsahuje bounded cleanup dokončených payloadů (500 záznamů na běh, metadata 7 dní), Fio client pro `/last` a `set-last-id` s textovými ID bez zaokrouhlení a email coordinator se claimy, backoffem 5 minut / 15 minut / 1 hodina / 6 hodin / 1 den a uchováním konfliktních variant v karanténě. Coordinator je připojen k email handleru a scheduleru pro schéma 13, včetně autentizovaných zpráv bez registrovaného účtu (quarantine s nullable FK, nikoliv nekonečná R2 orphan smyčka). Provozní signály jsou připojené k chráněnému statusu a stávajícímu alerteru; produkční ověření kandidáta zůstává otevřené. Nízká vrstva `fioDeltaRecovery.ts` už má durable intent/reset/fetch/spool/commit a atomic fencing všech aliasů. Sdílený bootstrap, chráněné backfill hashů starších tokenů, discovery aliasů a připojení do API/cron/queue vstupů jsou implementované a testované. Existující verified historie se při cutover neopakuje jako nový 90denní import: bootstrap začíná na dosavadním checkpointu minus tři dny; pouze nový/neověřený alias potřebuje plné počáteční okno. Nová fakta mají credential, identity a lease predicate přímo v INSERT; předběžný SELECT sám není bezpečnostní zámek. Lokální kurzorová proof funkce má samostatné testy bankovní hlavičky, neřazených ID a driftu; sdílené lease fencing je nyní použito i ve starém kompatibilním recovery. U schématu 13 aktualizace tokenu zapisuje digest a credential generaci atomicky a zabrání commitu odpovědi starých přihlašovacích údajů. Egress proxy má lokálně doplněný validovaný `set-last-id` (3 Deno testy a typecheck); Proxy je nyní nasazená na správném Supabase hostu. Přímý autentizovaný probe capabilities vrátil 200 a podporu set-last-id, bez autorizace 401 a nebezpečné číselné ID 400. Žádný probe nevolal banku; funkce načetla nový kód bez restartu kontejneru. Důkaz `/tmp/banksync-fio-proxy-deployment-evidence.json`.

README bylo zkráceno z 327 na 30 řádků. Podrobnosti jsou v `docs/guide.md`; oba provozní dokumenty budou součástí npm tarballu. Text výslovně rozlišuje vydaný intervalový Fio polling od rozpracovaného kurzoru a opravuje staré migrační pokyny a tvrzení o karanténě.

Poslední úplné lokální ověření: TypeScript, 629 testů, dual ESM/CJS build, deklarace a package exports prošly (`/tmp/banksync-maintenance-candidate-check.log`). Secrets check prošel. Vstupní integrační test používá stejný skutečný Worker handler pro manual/queue/cron a ověřuje jeden ledger fact a jeden delivery job po opakování. Fresh i původní v9 lokální migrace a Wrangler dry-run prošly; finální nullable orphan FK prošel čerstvým platformním gate na skutečné oddělené D1. Důkaz `/tmp/banksync-final-platform-evidence.json` ověřuje schema, zachovaný pending důkaz, orphan quarantine, bounded purge a odstranění testovací DB.

Provedený stage test ve skutečné Cloudflare D1 `25ddbe03-f065-4dc6-84e0-b5b249cb9099`: migrace zachovala pending cipher a 901 pokusů, schema 13, partial index hledal v 30 tisících completed záznamů s `rows_read=1`. Historický bounded purge vyčistil 500 payloadů a smazal 500 completed metadat; pending zůstal. Soukromý důkaz `/tmp/banksync-stage-d1-evidence.json`. Tato syntetická databáze byla odstraněna; cleanup receipt potvrzuje 404. Také finální platformní test odstranil vlastní dočasnou DB.

Samotný index `idx_bank_recovery_open` je již v produkci. Před změnou byl uložen Time Travel bookmark (`/tmp/banksync-pre-index-time-travel.json`). Přesný dotaz na účet 191 měl před indexem `rows_read=31507`, po změně `rows_read=0`, protože aktuálně nebyl otevřený batch tohoto účtu; `EXPLAIN` používá nový index. Schema zůstává 12 a Worker stále `983a1172-38ab-4293-908c-bc5cf9783fd3`. Důkaz `/tmp/banksync-production-index-evidence.json`; jde o nasazený index, nikoliv vydání kandidáta.

Čerstvá produkční kontrola během implementace: všech osm aktivních Fio účtů má success v posledních 30 minutách. Osm primárních D1 email spoolů je nyní completed; to nedokazuje vyřešení zbylých konfliktních R2 variant, které musí po cutover dostat doloženou karanténu. Krátký chráněný 50sekundový tail zachytil jeden `ok` event bez výjimky; není to důkaz příčiny historických 192 výjimek ani 24hodinový exit. Před cutover mělo nastavení Workeru `observability=null`; od kandidáta jsou Workers Logs zapnuté, historická kauzalita přesto zůstává nedoložená. Kandidát rozlišuje durable retry/quarantine od neošetřených výjimek.

Doplňující obnovovací zkouška po PR #57 odhalila chybné pořadí tabulek při SQL restore (child před parent). Oprava z chráněného PR #58 je sloučena do main `5fbcc39`. Regresní test nyní ověřuje šifrovaný round trip se zapnutými foreign keys, owned account, pending statement/email včetně 901 pokusů, conflict i orphan quarantine a přesné velké textové ID. Stejná obnova mezi dvěma skutečnými D1 zachovala všechny tabulky bez FK porušení; obě testovací DB byly odstraněny. Důkaz `/tmp/banksync-real-backup-restore-evidence.json`. Nový tarball kandidáta má SHA-256 `bf19b740765bf735a9d85ffbd851b86fa5be1d75aed8f1cba6bb3d7f63bd1cf3`.

Celý nevydaný kandidát byl dočasně nasazen přímo z tohoto immutable artefaktu pro produkční ověření, při zachování registry pinu 0.2.8. Nejde o trvalý local override ani npm release; závěrečné vydání a kompozice musí přejít na tentýž chráněný registry artefakt s novou verzí až po exit gates. První deployment `678905f0-5f91-4171-ac35-4c7c2c9b798f` zachoval všechny bindings/vars a health 200 na schema 12. Po nasazení stejného kandidáta s Workers Logs je aktuální version `17bc504c-2921-4865-bdef-fcf688cd63a4`.

Produkční migrace 0013 proběhla 2026-10-08 kolem 00:07 UTC, po přepnutí markeru maintenance, drain všech bank leases, zachycení Time Travel bookmarku a šifrované off-host záloze. Původní export má 102 204 179 bajtů, envelope 136 272 422; R2 kopie `operations/20261008-before-schema13.sql.enc` je ověřena velikostí a SHA-256. Nezávislý obnovovací klíč je chráněn mimo Cloudflare. Lokální obnova plného D1 snapshotu ověřila shodné SHA všech 16 účtů, 538 transakcí, 6 consumerů, 21 subscriptions, 748 jobs a 8 email spoolů. Snapshotový D1 export vytváří část parents až za child INSERT, proto jeho offline load používá následné zapnutí a kontrolu FK; canonical aplikační backup je po PR #58 parent-first a obstojí se zapnutými FK během importu. Chráněné důkazy jsou v `/Users/miakh/.codex/protected/banksync/schema13-20261008/`.

Po migraci byly všechny uvedené původní tabulky porovnány přes SHA původních sloupců a počty; statement counts/cipher bytes byly stejné, FK check čistý, ledger 0013 zapsaný a partial index použitý. Maintenance byla vypnuta v `2026-10-08T00:07:55Z`. První automatické bootstrapy založily 8 durable kurzorů, všech 8 účtů zůstalo fresh bez API error. Inicializace všech 8 kurzorů, durable quarantine, nulový completed ciphertext a skutečný backup/restore jsou již doložené níže. Zbývá závěrečný zkrácený provozní exit.

Migraci email tabulky provádět s `schema_meta.recovery_maintenance=on`: hotový kompatibilní kandidát uchová nové autentizované emaily v R2 a odloží polling/scheduler. Atomic INSERT fence zastaví rozpracované nové ledger zápisy; staré bank leases musí být před DDL drained. Tento marker není změna bankovních údajů ani náhrada databáze. Po migrační kontrole jej explicitně vypnout a ověřit obnovení importů. Tento migrační postup byl proveden a marker je vypnutý. Další npm verze nebo tag se stále nevydává.


## Ověřené výchozí skutečnosti

| Fakt | Důkaz | Důsledek |
|---|---|---|
| Nasazena jedna sdílená instance, D1 schema 12 | Cloudflare deployment `c00dcb30-ff4c-40f4-a1ef-8c4bcfbff292`, version `fbbe8393-e3a7-49a2-842b-c0cb1b3b96b8`; D1 `banksync-db` | Zachovat resource identity a kompatibilní v1/v2 consumer kontrakty. |
| Osm aktivních Fio účtů má čerstvé úspěšné importy; delivery backlog i DLQ jsou prázdné | Živá agregace 2026-10-07 kolem 21:50 UTC | Nezaměnit provozní optimalizaci za nový platební engine nebo hromadný replay. |
| Databáze narostla přibližně z 15 na 100 MB během 4 dnů | D1 storage analytics, denní maxima | Současný růst je přibližně 24-26 MB/den; není to dlouhodobá prognóza ani schválení změny tarifu. |
| Přes 30 tisíc dokončených výpisů drží asi 54,5 MB ciphertextu | Agregace `bank_recovery_batches` | Recovery obsah musí mít konečný životní cyklus. |
| Hledání otevřeného výpisu čte asi 243 z 292 milionů řádků/den | D1 query analytics; živé `EXPLAIN QUERY PLAN`: `SCAN bank_recovery_batches`, pomocné řazení | V první vlně přidat cílený index; produkční primární klíč na `id` tento dotaz nepokrývá. |
| Šest emailových spool záznamů opakovaně selhává | D1 spool a parse_log; `src/cloudflare.ts: processEmail`, scheduled recovery | Rozlišit dočasné selhání, konflikt a nepodporovaná fakta; zachovat původní důkaz. |
| Konkrétní email chyběl parseru kvůli `Datum provedení` u nezaúčtované platby kartou | Omezená diagnostika skutečného emailu, anonymizovaná reprodukce v `src/parser.test.ts` | Neodvozovat datum z doručení nebo dostupného zůstatku. |
| Za 24 h evidováno 192 `scriptThrewException` | Workers analytics | Příčinná souvislost s emailem dosud nepotvrzena; musí se při rolloutu ověřit. |

## Současný a cílový tok

Fio používá `src/bankRecovery.ts: recoverBankAccount` a `src/fio.ts: fetchFioStatement`. První okno je přibližně 89 dní; další začíná tři dny před `api_reconciled_through` a končí aktuálním dnem. `/periods` neposouvá bankovní kurzor. Překryv je úmyslný: opakované pohyby se deduplikují podle ověřených identit. Toto je popis dnešního provozu, nikoliv nově požadovaného cíle. Cílem je `/last` s durable kurzorem a recovery; časové výpisy zůstanou pro bootstrap a samostatnou rekonciliaci.

Statement se pod účtovým a credential lockem uloží zašifrovaný před importem. Import ověří přijímající účet a všechna fakta, pak společně označí batch za dokončený a posune checkpoint. Webhooky se obnovují nezávisle přes durable delivery jobs. Po úspěšném commitnutí statement už není jedinou kopií platebních faktů.

Email projde MIME a autentizací, uloží původní bytes do R2 ještě před D1, potom do D1 spoolu. Obnova nyní každých pět minut zkouší R2 i D1, bez backoffu nebo konečného stavu pro obsahovou chybu. Konflikt stejné identity a jiného obsahu nesmí přepsat původní záznam.

Cílové invarianty:

1. Neúspěšný nebo nedokončený statement nikdy nepruneovat. Úspěšný checkpoint a bankovní fakta musí být zachována, než se odstraní recovery obsah.
2. Polling hledá pouze otevřené batche indexem; práce neroste s počtem dokončených batchů.
3. Identita pohybu, původní částka, měna, datum a směr zůstávají fakty; úklid nezasahuje ledger, webhook payloady, receipt ani platební matching.
4. Pending karta zůstává `observation` a uchovává označení `nezaúčtováno`; nenahrazovat ji potvrzeným bankovním pohybem. Legacy v1 consumer nesmí dostat odchozí pozorování jako kladný kredit.
5. Úspěšný email má jeden dokončený recovery záznam a žádný pending R2 objekt. Konflikty zůstávají doložitelné, ale nejsou v nekonečné automatické smyčce.
6. Nové chybové metriky mají konečné kategorie a neobsahují těla zpráv, tokeny, zákaznické údaje ani bankovní čísla.

## Rozhodnutí a otevřené předpoklady

- **Rozhodnutí po doplnění zadání:** běžný polling přejde na Fio `/last`; třídenní překryv se nebude znovu stahovat při každém ticku. `/periods` slouží pro první import a jednou denně pro kontrolní rekonciliaci. Frekvenci polling ticku tímto neměnit. Před přepnutím musí fungovat durable recovery kurzoru a jedno stahování za každý token pro všechny jeho logické aliasy.
- **Rozhodnutí:** na nově dokončeném statementu atomicky vymazat `cipher` a `key_version` společně s dokončením a checkpointem. Recovery metadata držet 7 dní pro provozní audit a potom po dávkách odstranit. Platební fakta a identitní deduplikaci tento úklid nemění.
- **Rozhodnutí:** dokončené emailové recovery payloady mají stejný životní cyklus. Pending a quarantined důkazy mají vlastní politiku a nesmí se mazat společně s completed.
- **Rozhodnutí:** dočasná chyba dostane exponenciální backoff (5 min, 15 min, 1 h, 6 h, potom nejvýše jednou denně). Obsahový konflikt nebo nepodporované bankovní datum dostane durable quarantine a vyžaduje cílené vyhodnocení; žádný automatický finanční replay.
- **Předpoklad:** batch ve stavu completed již není čten potřebným recovery vstupem. Potvrdit scoped hledáním všech čtenářů `bank_recovery_batches` a zálohovacích/restore cest před odstraněním obsahu.
- **Předpoklad:** změna parseru postačí pro variantu skutečné karty s execution date; jiné chybové zprávy mohou mít odlišnou příčinu. Ověřit konkrétní pending objekty chráněným procesem, nevkládat původní zprávy do git.
- **Otevřeno:** příčina konfliktu těla při stejném Message-ID. Porovnat původní bytes, hlavičky, recipient, Message-ID a envelope pouze v chráněném procesu; nejdříve dokázat, zda jde o opakovanou transportní variantu nebo skutečně odlišnou zprávu. Otisk těla nesmí být ignorován.
- **Otevřeno:** historické terminal delivery jobs (428) pocházejí ze starších období a nejsou dnešní backlog. Rozlišit zachované auditní incidenty od skutečně nedoručených plateb; jejich replay potřebuje vlastní vymezení a autoritu.

## Fio: ověřená dokumentace a přesný cílový protokol

Primární zdroj: [Fio API Bankovnictví, verze 16. 10. 2025](https://www.fio.cz/docs/cz/API_Bankovnictvi.pdf), strany 7-9 a 54. Fio umožňuje `/last/{token}/transactions.json` pro pohyby od posledního stažení a `/set-last-id/{token}/{id}/` nebo `/set-last-date/{token}/{date}/` pro opravu zarážky. Neprázdný `/last` posune zarážku už u banky, nikoliv až po našem DB commitu; prázdná odpověď ji nemění. Stejný token smí mít nejvýše jeden požadavek během 30 sekund, včetně resetu. Toto omezení platí také přes proxy.

**Proč to dnes není zapnuté:** `src/fio.ts: fetchNewTransactions` umí `/last`, ale vrací jen řádky bez hlavičky účtu. Aktivní schema 11/12 větev v `src/cloudflare.ts: runBankApiSync` ho nepoužívá; volá `src/bankRecovery.ts: recoverBankAccount` s `/periods`. Dnešní interval lze po timeoutu opakovat beze změny bankovní zarážky. Obyčejné nahrazení fetch funkce by tuto bezpečnost zrušilo. Proxy `/last` již podporuje jako `op=transactions`; zatím neumí `set-last-id`. Chybějící index a nekonečná retence completed payloadů jsou další nezávislé nedostatky, které změna endpointu sama nevyřeší.

**Jednoznačné vlastnictví kurzoru:** kurzor patří bankovnímu tokenu. Před aktivací doplnit missing `api_token_hash` u dvou aktivních starších účtů (191, 407) chráněným dešifrováním v procesu, bez tokenu v logu. Šest ostatních aktivních účtů má šest různých hashů. Osm účtů versus šest existujících hashů proto není důkaz sdílení tokenu - SQL `COUNT(DISTINCT ...)` ignoruje NULL. Pokud skutečné porovnání odhalí sdílený token, zvolit jednoho poll vlastníka a uložený statement fan-out do všech odpovídajících logických aliasů před potvrzením kurzoru. Dva oddělené `/last` pullery nad jedním tokenem jsou zakázané. Dnes není všech osm účtů pokryto `account_aliases`; samotná existence schema 12 není důkaz hotové identity migrace. Zachovat současné account IDs, pairing codes a consumer subscriptions.

**Bootstrap a cutover:** dokončit otevřené intervalové batche a ověřit účet z hlavičky. První import dál zůstane bounded `/periods`; starší než 90 dní vyžaduje bankovní unlock. Persistovat bootstrap datum a ověřenou generaci přihlašovacích údajů. Po cooldown nastavit zarážku na začátek již importovaného okna přes `set-last-date`, následně použít `/last`. Jednorázové deduplikované přestažení okna pokryje pohyby přidané mezitím nebo zaúčtované zpětně. Nepoužívat maximum ID z časového výpisu jako zkratku: nemusí dokazovat souvisle potvrzený `/last` rozsah.

**Normální polling:** pod současnými credential + physical-account leases vytvořit durable fetch intent obsahující poslední lokálně commitnutý kurzor a generaci tokenu ještě před bankovním requestem. `/last` musí vracet hlavičku i všechny řádky. Ověřit receiving account, měnu a movement ID; odpověď uložit zašifrovanou před importem. Import všech aliasů je idempotentní podle existující identity pohybu. Teprve po úspěšném importu všech řádků společně označit batch completed, persistovat navazující movement kurzor a uvolnit completed ciphertext. Commit musí v téže transakci podmínit stále platným lease tokenem a credential generací; kontrola lease pouze těsně před commitem není dostatečný fencing. Pád při fan-out zopakuje všechny dosud nepotvrzené aliasy, nikdy nepřeskočí druhého consumera. Žádná změna ledgeru nebo webhook kontraktů.

**Ztracená odpověď / pád před spoolingem:** pokud existuje intent bez uložené odpovědi, neopakovat rovnou `/last`. Banka mohla kurzor posunout. Nejdříve po cooldown obnovit `/set-last-id` na poslední lokálně potvrzený pohyb; pokud ještě není žádný potvrzený pohyb, použít uložené bootstrap datum. Reset má vlastní durable stav. Pokud reset odpověď chybí, reset opakovat; pokud uspěl, další bankovní request až v příštím povoleném ticku. Potom zopakovat `/last`. Pokud už ciphertext existuje, obnovit pouze jeho import bez nového bankovního fetch. Toto není nový platební replay, ale dokončení téhož recovery batch s existující deduplikací.

**Kurzor a identita:** movement ID je `column22`, order/command ID je `column17` a nesmí řídit zarážku. ID držet jako decimal text, odmítnout již zaokrouhlené JS number a nenutit jej přes `Number`. `info.idLastDownload` není bezpečně nový kurzor: ukázka JSON `/last` v dokumentaci obsahuje předchozí zarážku a `idFrom/idTo=null`. Dokumentace výslovně označuje `idTo` za poslední pohyb daného výběru. Lokální `fioCursor.ts` používá toto ID pouze tehdy, když patří mezi právě importované řádky; nepoužívá numerické maximum ani pořadí pole. Pokud `/last` vrací `idTo=null`, následující bankovní `idLastDownload` lze potvrdit pouze jako ID z předchozího úspěšně importovaného batch nebo již potvrzený kurzor. Může tedy zůstat o jeden batch pozadu, ale ztracená odpověď pak způsobí jen jednorázové deduplikované přestažení, nikoli pravidelné třídenní výpisy. Uchovávat `last_batch_ids` a diagnostickou `last_reported_movement_id`; neověřená stará zarážka po resetu podle data se nesmí stát recovery kotvou. Cizí neznámá zarážka vyvolá drift a bezpečnou obnovu. Prázdná odpověď může potvrdit dříve importovaný bankou označený pohyb, nikdy nesmí vymyslet novou identitu. Nevalidní hlavička/pohyb nechá recovery otevřené; nesmí zaznamenat úspěch nebo přeskočit vadný řádek.

**Kontrolní rekonciliace:** jednou denně samostatný `/periods` s bounded třídenním překryvem a existující deduplikací. Její checkpoint je oddělen od potvrzeného `/last` kurzoru a její maximum ID jej nikdy neposouvá. Běží pod stejným cooldown/lease jako všechny Fio volání. Delší odstávka vyžaduje samostatné rozdělené intervaly v rámci bankovní dostupnosti; nesmí potichu přeskočit mezeru. Rotace tokenu musí zastavit staré in-flight generace, uložit nový credential hash, zneplatnit starý cursor ownership a provést ověřený bootstrap.

## Implementační vlny

### 1. Parser Air Bank a jeho bezpečné nasazení

Lokálně hotové soubory v BankSync: `src/parser.ts`, `src/parser.test.ts`, `src/index.test.ts`. Čtení execution date při chybějící booking date; booking date má přednost. Odchozí směr z balance-change věty; explicitní záporná částka se podruhé neobrací. Rozporný směr odmítnout. Uchovat pending card type, nic nedopočítávat z času doručení.

Důkaz: reprodukce před opravou měla dva selhávající testy. Po opravě prošlo `pnpm check` (582 testů, typecheck, build, package exports). Zabalený parser správně zpracoval i diagnostický text skutečné chyby. Integrační test ověřuje dokončení D1/R2 spoolu, idempotenci a nulový kredit v1 consumera.

Pro release dodržet `.github/workflows/release.yml`: chráněný nový patch tag, npm trusted publishing, přesný ověřený tarball. Kompozici aktualizovat na tento přesný balíček podle pravidel Mendelia; nepoužít lokální npm link ani neveřejnou náhradu. Před publikací fetch authoritative main, vyřešit rozdíly a relevantní validaci. Nasazení sdíleného Workeru je samostatný produkční krok, žádný rollout Festapp tenant větví.

Exit: nasazená version odpovídá release; podporovaná zpráva dokončí recovery právě jednou, zůstane odchozím pozorováním a negeneruje příchozí kredit. Případné automatické obnovení pending zpráv po nasazení zahrnout do explicitního rollout rozsahu.

### 2. Index otevřených statementů

Přidat novou kompatibilní migraci (aktuálně následuje schema 13; při novější upstream migraci použít další volné číslo). Index:

```sql
CREATE INDEX idx_bank_recovery_open
ON bank_recovery_batches(bank_account_id, created_at, id)
WHERE state <> 'completed';
```

Predicate čtecího dotazu zachovat shodný. Aktualizovat schema version assertion, `src/db.ts`, migrační seznamy testů, `.github/workflows/release.yml` a přesný seznam migračních souborů v release gate. Pořadí musí řešit dnešní striktní schema assertions: nejprve nasadit kompatibilní Worker přijímající současné schema 12 i cílové 13 a zachovávající staré writers; potom aplikovat aditivní migraci, ověřit index a teprve následně zapnout writer vyžadující nové schéma. Po ověření všech vstupů odstranit dočasnou podporu schema 12. Stejný postup použít pro další schema změny email spoolu; žádný starý Worker se nesmí vrátit na databázi se stavy, které neumí bezpečně ignorovat.

Validace: disposable upgrade ze současného schema 12 s alespoň 30 tisíci dokončenými a několika otevřenými batchi. `EXPLAIN QUERY PLAN` musí použít index bez `SCAN bank_recovery_batches` a pomocného řazení. Test správného nejstaršího batch ordering podle účtu. V produkci sledovat rows-read pro tento dotaz, nikoliv jen rychlost na prázdné DB.

Exit: počet čtených řádků pro open lookup se řídí otevřenými batchi, nikoliv celou historií; všechny aktivní účty dál synchronizují.

### 3. Životní cyklus dokončených recovery dat

`src/bankRecovery.ts`: doplnit vymazání ciphertextu do existujícího atomického dokončení batch + checkpoint. Nesmazat před ukončením importu ani při bankovním/account mismatch.

`src/db.ts: pruneRetention` a `src/cloudflare.ts: completeSpool/scheduled`: zavést bounded purge completed metadata starších než 7 dní. D1 email schéma dnes vyžaduje `cipher NOT NULL`; upravit kompatibilní migrací tak, aby completed řádek mohl mít prázdný payload, ale pending měl vždy dostupné obnovitelné bytes. Výslovně otestovat upgrade a restore, neobejít constraint pouhým nesrozumitelným prázdným stringem.

Historické completed statement payloady odstranit po záloze a ověření stavů v malých dávkách. Uchovat pending, spooled, quarantine a chybové důkazy. Rozlišit logickou velikost od fyzické D1 velikosti: uvolněné stránky se mohou znovu používat bez okamžitého zmenšení souboru. Nepřidávat produkční VACUUM bez ověřené podpory a vlastního provozního okna.

Validace: pád před/po atomickém dokončení, restart s pending/spooled batchi, více běhů prune, hranice 7 dní. Důkaz, že ledger a delivery identity/payload hashes se nezměnily. Rozšířit `src/bankRecovery.test.ts`, `src/db.test.ts`, `src/index.test.ts` a `src/backup.test.ts`.

Exit: completed recovery obsah neroste, metadata mají bounded retenci, retry stále obnoví přerušený import bez nové platby nebo ztráty faktů.

### 3b. Inkrementální Fio polling od posledního stažení

Konkrétní změny: `src/fio.ts` přidá hlavičku zachovávající fetch pro `/last` a validovaný `setFioPointerById`; starý rows-only helper nepoužívat v canonical recovery. `src/bankRecovery.ts` dostane durable bootstrap/reset/fetch/spool/commit stavy podle protokolu výše. Navržené persistentní rozhraní: `fio_poll_cursors(credential_hash PRIMARY KEY, generation, last_committed_movement_id TEXT NULL, bootstrap_from_date, last_success_at)` a aditivní `bank_recovery_batches.poll_kind`, `credential_hash`, `credential_generation`, `cursor_before`, `recovery_stage`. `poll_kind` rozlišuje `periods` a `last`; recovery stages jsou `reset_required`, `resetting`, `ready`, `fetching`, `spooled`, `completed`. Existující stavový CHECK se nesmí nekompatibilně rozšířit za běhu starého writeru: dočasně nový protokol držet v aditivním stage sloupci a původní state používat jen jako kompatibilní projekci. Původní intervalové batche dostanou `poll_kind=periods`; nový cursor se z jejich checkpointu nepředstírá. `api_reconciled_through` zůstává výhradně period-reconciliation checkpointem. Finální DDL může upřesnit null constraints podle stagingu, ale musí zachovat oddělené významy a jednu otevřenou recovery operaci za credential generaci. Nepřetěžovat dnešní `api_pointer_initialized`, které dnešní interval writer nastavuje na 1 bez skutečného bankovního resetu. Staré completed intervalové batche se nestanou důkazem potvrzeného `/last` kurzoru.

Kompozice: `supabase/functions/fio-proxy/index.ts` v Mendeliu doplní `op=set-last-id` s validací decimal ID. Nasadit proxy před voláním nové operace, zachovat secret a sanitizované chyby. `services/banksync/wrangler.toml`, README a runbook přestanou popisovat intervalový režim jako běžný polling. Release workflow, schema guards a všechny `['11','12']` capability větve v DB/Worker/delivery přizpůsobit novému schema kontraktu. Zachovat zálohování a ověřený upgrade/restore nové cursor tabulky.

Rollout: nejprve index/retence a kompatibilní schema čtenář, potom aditivní cursor schema, rozšířená proxy, nový recovery engine. Po dokončení všech starých otevřených intervalů aktivovat inkrementální režim pro jeden ověřený nesdílený účet; prokázat bootstrap, prázdný poll, příchozí i odchozí movement, deduplikaci a fresh webhook. Potom rozšířit na zbylé existující účty. Odebrat starou interval-only polling větev; ponechat jediný `/periods` vstup v bootstrap/rekonciliaci. Dočasné přepínače po cutover odstranit. Při rollbacku zakázat další `/last` requesty starého writeru; uložené facts/cursor/spool zachovat a použít kompatibilní recovery nebo bounded periods režim.

Validace: test pádů před requestem, po bankovním posunutí zarážky před uložením odpovědi, během importu a při atomic commit; opakovaný/lost reset; cooldown mezi reset a fetch; prázdná odpověď; chybějící hlavička a špatný účet; předchozí `idLastDownload`; command ID sdílené více pohyby; rotace tokenu během requestu; dva account aliasy se stejným tokenem; průběžné manuální/cron/queue requesty; denní periods nesmí měnit `/last` checkpoint. Ověřit, že následný poll vrátí jen nově dostupné pohyby, nikoliv běžný třídenní replay, a počet facts/delivery se nezmění při recovery.

Exit: všechny aktivní účty mají doložený kurzor a čerstvou synchronizaci, opakované běžné fetch nepřenášejí historické třídenní payloady, ověřená crash recovery neztrácí pohyby a v provozu je jediný poll vlastník za token.

### 4. Jedna řízená emailová obnova, backoff a quarantine

Rozšířit durable stav `authenticated_email_spool` o quarantine, `next_attempt_at`, poslední konečnou chybovou kategorii a čas posledního pokusu. Před změnou stanovit explicitní kompatibilní migraci tabulky s dnešními CHECK/NOT NULL omezeními. Sdílet jednu retry rozhodovací cestu pro R2 a D1 recovery: oba transporty mají sloužit témuž koordinátoru a nemají nezávisle násobit pokusy. R2-first důkaz před D1 zachovat, včetně recovery po D1 outage.

Deterministická chyba se uloží jednou, bez opakovaného velkého `parse_log.raw_data`. Původní i konfliktní tělo zůstanou chráněně uloženy s odkazem a otiskem; žádné přepsání prvního těla. Konfliktní varianta má vlastní durable evidence identitu zahrnující body digest, aby ji scheduler uměl quarantine a neopakoval ji pořád pod původním Message-ID.

Quarantine není delivered bank fact. Ruční nebo autorizované cílené obnovení musí procházet stejnou autentizací, deduplikací a webhook koordinátorem. Žádná nová platební cesta nebo bypass Festapp matcheru. Datum nedopočítávat z dostupného zůstatku ani transportních hlaviček.

Validace: stejný email dvakrát; stejný Message-ID s jiným tělem; pád mezi R2 a D1; pád při dokončení; transient DB/queue fail a následný úspěch; unsupported date; scheduling obou recovery zdrojů; férovost při větší frontě. Testy se stubbed clocks dokazují backoff a nepřítomnost opakovaných trvalých chyb.

Exit: z původních šesti pending D1 případů již tři dokončil parser rollout; zbývající tři mají doložený completed nebo quarantine stav a konečný důvod; počet pokusů a chybových logů už neroste každých pět minut bez možnosti změny výsledku.

### 5. Provozní signály, náklady a dlouhodobý důkaz

Veřejný `/health` ponechat jako hrubý endpoint. Rozšířit chráněný `/status` o open recovery počet/stáří, quarantine počet/stáří, due retry, poslední úspěšnou maintenance a backup, DB velikost/růst a čerstvost polling per účet. Liveness nerovná se finanční end-to-end readiness; `/health/deep` dnes provádí testovací DB zápis a queue komponenta ověřuje pouze binding, nikoliv doručení.

`src/alerter.ts` a aktuální provozní integrace: upozorňovat na chybějící úspěšný běh, růst quarantine, starý otevřený statement, zastavený polling a skutečné stalled delivery. Příčinu 192 výjimek vyhodnotit z chráněných Workers logů bez citlivých payloadů. Historické terminal incidents nesmí bez rozlišení přehlušovat nové selhání.

D1 drahé vedlejší dotazy řešit podle query analytics až po hlavním indexu. Polling frekvenci měnit pouze po samostatném doložení cílové freshness, Fio cooldown a load; v první vlně neměnit.

Validace a exit: zkrácená produkční observace podle následného zadání uživatele (nejvýše 7 hodin) včetně daily maintenance a dohodnuté ukázky obnovy. Všech 8 původně aktivních účtů je fresh, žádný nový nezamýšlený terminal job, žádná ztracená/dvojitá platba, pokles open-query reads a zastavený růst completed ciphertextu. Weekly backup ověřit při nejbližším běhu nebo explicitně autorizovaném řízeném testu; nesimulovat jej posunutím produkčních hodin.

## Zálohy Festapp Supabase

Autorita: `automation/hetzner-supabase/backup/create-online-encrypted-backup.sh`, instalovaná serverová konfigurace a backup manifests. Původní denní sady měly retenci 30 dní. Uživatel následně výslovně zvolil 14 dní denních záloh a čtyři předchozí dokončené týdenní kopie. Nový helper `automation/hetzner-supabase/backup/prune-online-backups.py` ji provádí v prefixu `backups/festapp-supabase-rehearsal-01`. Uživatel nyní dovolil odstranit staré zálohy; výběr omezit na celé dokončené běžné sady mimo zvolenou kombinovanou retenci a ponechat nejméně poslední tři kompletní ověřené sady. Porovnat manifest, čtyři artefakty, velikosti/otisky a úspěšný off-host upload.

Nemazat po jednotlivých souborech podle různých časů uploadu, nedělat purge celého bucketu, nezahrnout migrační, frozen-source a restore-drill důkazy. Nejprve uložit chráněný inventář a přesný deletion manifest, potom mazat jen jeho klíče a ověřit nepřítomnost i zachování posledních sad. R2 graf může mít zpoždění; potvrzení odstranění vychází z object listing.

Inventura, nová politika i ověřené smazání jsou dokončené; výsledky jsou v části Provedeno. Další zkrácení výslovně vybrané politiky vyžaduje nové rozhodnutí. Tato autorita nezahrnuje odstranění special-purpose kopií.

## Deletion ledger a rollback

| Dnešní artefakt/chování | Cílová akce | Důkaz |
|---|---|---|
| Completed statement ciphertext bez konce | Atomické vymazání obsahu, bounded historický purge | Pending/spooled beze změny; completed cipher nulový; idempotentní prune. |
| Full scan open batch | Částečný index se shodným predicate | EXPLAIN + rows read na naplněné DB. |
| Dvě nezávislé neomezené email retry smyčky | Jeden koordinátor s durable backoff/quarantine | Test více zdrojů, konečný error log a férovost. |
| Obsahový konflikt bez terminal recovery stavu | Zachovat oba důkazy, quarantine varianty | Žádné přepsání ani automatický kredit/retry loop. |
| Vybrané běžné backup sady mimo retenci | Smazat pouze klíče z ověřeného manifestu | Object listing po delete; poslední kompletní sady zachovány. |
| Interval-only běžný polling | Nahradit durable `/last`; periods zachovat pouze bootstrap/rekonciliaci | Crash/cooldown/fan-out testy; následný poll obsahuje pouze nové pohyby. |
| Festapp legacy poller / druhý payment engine | Zůstanou nedostupné | Scope vyhledání a aktuální registered routes/jobs. |

Po přechodu na schema 13 nelze jako rollback nasadit vydaný balíček 0.2.8: jeho schema guard verzi 13 odmítá a starý email writer neumí nové message keys. Uchovat kompletní ověřený schema-13 kompatibilní kandidát a při problému zapnout recovery maintenance s durable R2 nebo provést kompatibilní roll-forward opravu. Náhrada živé databáze snapshotem by mohla ztratit nové bankovní fakta a není automatickým rollbackem. Rollback parseru musí počítat s tím, že již přijaté pending-card observations nejdou odvolat novým importem. Neprovádět hromadný replay. Index je aditivní a může zůstat při rollbacku writeru. Odstraněný completed ciphertext neobnovovat jako povinnou live dependency; fakta už byla commitnuta. Nové quarantine stavy musí starší writer bezpečně ignorovat; návrat na starý nekonečný scheduler není vhodný rollback.

## Definition of complete

- [x] Parser release nasazen a ověřen na podporovaných anonymizovaných provider fixtures i chráněném produkčním důkazu.
- [x] Open-batch query používá index; schemata, assertions, release migration gates a restore odpovídají nasazenému kontraktu. Produkční EXPLAIN/rows-read a skutečná schema-13 D1 obnova ověřeny.
- [x] Běžný Fio polling používá `/last` s durable kurzorem a ověřenou obnovou; periods pouze bootstrap/rekonciliace. V 01:25 UTC je od finálního deploymentu 109 běžných last batches a 8 initialized/fresh cursorů; ztracené odpovědi a generace pokrývají cílené integrační testy.
- [x] Recovery obsah i metadata mají bounded životní cyklus; pending data jsou obnovitelná. V 01:25 UTC je 32 168 completed metadata, 0 cipher rows a 0 metadata starších 7 dnů, žádný otevřený statement. Pending/orphan/quarantine restore zachován při skutečné D1 platformní zkoušce.
- [x] Konflikty a nepodporované zprávy mají doložitelnou quarantine, transient chyby mají backoff. Závěrečný read-only audit přesně přiřadil všech 402 původních R2 klíčů ke quarantine s attempts 0 a zachovaným cipher/key; transient delays a fencing pokrývá prošlá emailRecovery integrační sada.
- [x] Žádná změna platebních identit, částek, matcheru, podpisů nebo vedlejší replay. Původní pole byla zachována při migraci; SHA celé aktuální sady 538 faktů, 748 původních delivery jobs a 21 subscriptions souhlasí s ověřenou zálohou. Finanční replay nebyl proveden; poslední runtime kontrola bude zopakovaná při exit.
- [x] Provedená a ověřená autorizovaná backup deletion podle následné retenční volby uživatele.
- [x] Provozní freshness, poslední maintenance/backup a nové incidenty jsou viditelné; zkrácený provozní důkaz potvrzuje pokles zbytečné práce.

## Provedeno v aktuálním tahu

- Parser opraven lokálně, regresní reprodukce před opravou selhala; `pnpm check` prošlo se 582 testy. Přímý běh zabaleného parseru nad chráněným diagnostickým textem potvrdil správné datum, outgoing směr a pending observation. Do repozitáře nebylo vloženo tělo skutečného emailu.
- Parser package 0.2.8 byl publikován a nasazen jako první vlna. Index/migrace, inkrementální Fio cutover, statement purge a nové retry stavy jsou následně dokončené v nevydaném kandidátu; zbývají jeho závěrečné provozní gates.

- Přímá S3 inventura běžného backup prefixu: 32 celých sad, 160 objektů, 45,879606473 GB; rozsah 2026-09-08 až 2026-10-07. Před změnou žádná sada neležela mimo původní 30denní retenci. Poslední serverový backup skončil úspěšně 2026-10-07 02:33:44 UTC.
- Varianta 14 dní denních záloh + 4 předchozí dokončené týdenní kopie byla uživatelem výslovně vybrána jako nová retenční preference. Připravený chráněný manifest `/var/lib/festapp-rehearsal-evidence/banksync-backup-deletion-proposed-20261008.json` vybírá 16 sad / 80 objektů / 23,013748697 GB a zachovává 16 sad včetně týdenní kopie z 2026-09-13. Tento původní návrhový manifest se neprovádí přímo; nový helper sestavuje čerstvý ověřený manifest a před smazáním znovu kontroluje metadata. Lokální tests a serverový dry-run potvrdily výběr 16 sad / 80 objektů / 23,013748697 GB.

- Automatická politika 14 dní + 4 týdenní kopie je nasazena na serveru: checksum runneru `4a53db09cf6b8fa5914d8948400dd2bee71ac84fa1e81fd43d4b1e7de4259a86`, helperu `96b64720c792fae6073522346cb2b4c4e2bed8aa2ef683058e4e03cef1ecb22d`. Předchozí runner odpovídal kanonickému HEAD a jeho kopie je chráněně zachována na serveru. Environment služby nemá překrývající retenční override. Prošly 4 Node testy včetně 5 Python regresních případů a shell syntax checks.

- Produkční úklid dokončen a ověřen: 16 sad / 80 objektů / 23 013 748 697 bajtů odstraněno, 16 úplných sad zachováno. Chráněný výsledek: `/var/lib/festapp-rehearsal-evidence/backup-retention-20261007T221754-1ef4c220.json`, stav `deleted_and_verified`. Kontrola po delete potvrdila nepřítomnost všech vybraných objektů a nezměněnou velikost/mtime všech zachovaných objektů. Běžný backup prefix nyní obsahuje 22,865857776 GB. Celkový účet R2+D1 po odečtení této změny vychází přibližně na 70,66 GB; jde o odhad z předchozího inventáře, grafy mají zpoždění.

- Parser release připraven jako [BankSync PR #56](https://github.com/festappnet/banksync/pull/56), commity `d1f2843` a `10739d0`. Nový CodeQL nález na multiline whitespace byl opraven omezením whitespace na daný řádek; kontrola se znovu spouští. Branch protection vyžaduje PR a status checks bez lidské approving review; CI řídí bezpečné sloučení. `pnpm check` na aktuální base znovu prošlo (31 souborů / 582 testů), secret scan prošel.

- PR #56 sloučen po všech povinných kontrolách včetně CodeQL; authoritative merge `4caff24d81677fec82fba17d58f615e732b7eff8`. Oprava ReDoS prošla novým `pnpm check` (582 testů). Chráněný tag `v0.2.8` publikován pro release workflow.
- Nová agregace 20 R2 bucketů a 3 D1 databází: R2 včetně metadata po odečtení ověřeného smazání vychází na 70,304531955 GB; D1 0,109129728 GB, dohromady přibližně **70,41 GB**. Jde o přesnější současný odhad než dřívější 70,66 GB: mimo tento zásah se změnila také velikost Mendelio backup bucketu. R2 vzorek Festapp backup bucketu je dosud z 22:00 UTC před smazáním, proto je korekce vyznačená, nikoliv prezentovaná jako čerstvý kompletní listing všech bucketů. Velikost KV namespace se v této agregaci neměřila.

- Release 0.2.8 dokončen: [GitHub Actions run 37696866770](https://github.com/festappnet/banksync/actions/runs/37696866770), všechny release gates úspěšné. Registry tarball a GitHub Release jsou byte-identické: SHA-256 `527065d8fa9824e6f2dfece08a86bf91ccfb3bd1ac656ebc36d1eb7f67da6dfa`. `gh attestation verify --repo festappnet/banksync` prošlo. Přechodná npm 404 po publikaci již odezněla. Pin kompozice je 0.2.8, minimum-age výjimka je omezena na tuto přesnou ověřenou verzi. Frozen install i všech 1970 supply-chain policy checks prošly; kompoziční typecheck a unit test prošly. Při instalaci byl odstraněn automaticky vzniklý nesouvisející Expo lockfile churn a původní dirty změny zachovány.

- Produkční parser rollout dokončen: Worker version `983a1172-38ab-4293-908c-bc5cf9783fd3`, deployment `9a02242d-c93e-466e-b2cb-79929c505712`, 100 % provozu. Před i po rollout byly porovnány všechny bindings, plaintext vars a schema 12; žádné změny resource identity. Veřejný i cache-busted `/health` vrátily 200 a `{"ok":true}`. Živá agregace po rollout: 8 aktivních / 8 fresh účtů, 0 account API errors, žádné nové pending delivery jobs; původních 428 historických terminal jobs se nezměnilo.
- První automatická email obnova po nasazení: D1 completed 2 -> 5, pending 6 -> 3, poslední completed `2026-10-07 22:45:59 UTC`. Šest nových Air Bank facts po 22:45 má šest různých bankovních kódů a šest různých external IDs; všechny jsou záporné outgoing observations a nevytvořily žádný webhook delivery job. Od 22:45 vzniklo 9 logů `email_transport_body_conflict`, žádný `email_missing_bank_date`. Transportní konflikt zůstává odlišným otevřeným problémem, nemá se obejít ignorováním digestu.
- Publication state: veřejný BankSync zdroj je sloučený a tagovaný; kompoziční pin/lockfile/README v Mendeliu a Festapp backup/plan source zůstávají lokálně necommitnuté. Serverová retence a Worker parser jsou skutečně nasazené. Mendelio `docs/agents/shared-checkout.md` zakazuje commit před uživatelským potvrzením funkčnosti v prohlížeči; tento backend rollout takové potvrzení nenahrazuje. Nebyly zahrnuty cizí dirty změny ani další tenant release.


## Živý provozní důkaz po cutover

- Všech 8 cursorů je initialized=1; všech 8 původních účtů fresh bez API chyby. Běžné completed batches mají poll_kind=last. Původních 8 email spoolů zůstává completed; 11 konfliktních variant je quarantined s uchovaným cipherem a R2 odkazem, bez dalšího parser retry. Důkaz `/tmp/banksync-schema13-cursor-observation.json`.
- Workers Logs jsou pro stejný kompletní kandidát zapnuté (logs.enabled/persist/invocation_logs true, sampling 1); runtime bindingy zůstaly stejné. Konfigurační zdroj je lokálně v Mendelio `services/banksync/wrangler.toml`. [Cloudflare postup](https://developers.cloudflare.com/workers/observability/logs/workers-logs/).
- Původní observation od `2026-10-08T00:14:26Z` byla po ověřeném nasazení opravy záloh vědomě ukončená; její důkazy jsou zachované jako `before-final-candidate-observation*`. Finální zkrácená observation začala `2026-10-08T01:08:38.920429+00:00`, interval 10 minut, cílový konec `2026-10-08T03:35:00+00:00`. Běžící handle exec `84237`, PID `43380`; nestartovat druhý monitor pouze kvůli timeoutu pozorování. Stav je v chráněném `schema13-20261008/observation-state.json`, vzorky v `observation.jsonl`, program `/tmp/banksync-production-observe.py`.
- První vzorek: schema 13, maintenance off, 8/8 fresh, 0 API errors; historický completed ciphertext už klesl z 56 535 472 na 55 338 324 bajtů. Bounded purge musí doběhnout; fyzická D1 allocation se nemusí při DELETE ihned zmenšit, volné SQLite stránky se znovu použijí.
- Stále otevřené: dořešení historických R2 variant a doložení stability quarantine pokusů, daily maintenance v 03:15 UTC, celá dohodnutá metrická observace a závěrečné jediné registry vydání/pin. Mendelio source zůstává necommitnutý podle konkrétního repo pravidla potvrzení v prohlížeči; provozní autorizace tím není odvolaná.


## Ověřené dokončení záloh a finální kandidát

- Chráněné PR #59 a #60 opravily skutečně reprodukované překročení paměti Workeru při produkční záloze. Samotný rychlejší Base64 převod nestačil; SQL se nyní čte po stránkách, průběžně šifruje a nahrává multipartem. Formát AES-GCM v1 je zachovaný. Backup má vlastněné maintenance okno s 15min expiry, drain bank/email claims a kontrolu vlastnictví před publikací. Tabulkové bounds, počty a sqlite_sequence se zachytí jedním D1 read batchem, obnova zachovává i identity smazaných AUTOINCREMENT řádků. Ztráta vlastnictví abortuje upload.
- Main `9d1e70ecd6407a6518e9906200a897f75a770ea0`: 637 testů / 39 souborů, typecheck, build, package exports, secrets, dependency review a CodeQL prošly. Package stále 0.2.8, žádný nový tag ani npm release. Tarball kandidáta SHA-256 `224157a439bf956296b04fabfec57e15e358b5272d771976b7eabfc432b91c6e` je nasazený na Worker `e4fb42cd-236e-4846-b48e-8c5ac4a2a41c` (100 %); bindings i compatibility flags jsou stejné, health 200. Důkaz `schema13-20261008/final-candidate-deployment.json`.
- Skutečný řízený backup schema 13: R2 `operations/banksync-ops-proof-0a811029c4/banksync-20261008.sql.enc`, 67 484 730 bajtů, encrypted SHA-256 `5b336c76ed709637bb9b75de7cc8e869f027581ab594189c7a6ca0fd88286d42`. Zdroj všech 21 tabulek byl během okna shodný před/po. Stažený objekt prošel kanonickým decrypt skriptem, lokální FK-on obnovou a skutečným importem do oddělené D1. Všech 21 SHA i sqlite_sequence souhlasí, FK violations 0, obnovena maintenance on a allocation disabled. Testovací D1 odstraněna a ověřena 404. Důkazy `operator/backup-evidence.json` a `operator/d1-restore-evidence.json`; nezávislý backup klíč zůstává chráněně mimo Cloudflare. Plaintext odstraněn.
- Dočasný autentizovaný operator Worker byl po důkazu odstraněn a jeho nepřítomnost ověřena 404; jeho tail je zastavený. Skutečný successful backup timestamp je zapsaný do produkčního last_backup_at, bez simulování času či Sunday triggeru.
- Completed recovery ciphertext je nyní 0. Řízený purge použil stejnou produkční bounded funkci: 62 calls, nejvýše 500 řádků na kategorii/call, 30 190 historických payloadů odstraněných; další uklidil scheduler. Metadata/ledger/pending/quarantine tato operace nemaže. Ledger 538 faktů, jobs 320 delivered + 428 historických terminal, bez nového backlogu.
- V 01:09 UTC je 8 primárních email spoolů completed a 124 různých variant quarantined, každá s vlastním digestem a R2 klíčem, attempts=0. Nárůst počtu představuje klasifikaci historické R2 fronty; sám o sobě není opakovaný parser retry. Konečný stav fronty a stabilitu je ještě třeba ověřit.
- GraphQL Workers Analytics je dostupné a ukládá skutečné request/error/status a CPU kvantily. Samostatný metrický collector handle `12021`, PID 31917, běží hodinově přes stejné finální zkrácené okno; kvůli zpoždění metrik zakončí sběr o 15 minut později. Důkazy `worker-metrics-state.json`, `worker-metrics-before.json`, `worker-metrics-observation.jsonl`. Historické uložené logy přes telemetry API zůstávají nedostupné s aktuálními scopes (403); neoznačovat příčinu dřívějších 192 výjimek za doloženou.
- README má 30 řádků místo 327; detailní provozní dokumentace je v docs/guide.md. Použitý veřejný README skill byl přečten z https://github.com/softaworks/agent-toolkit/tree/main/skills/crafting-effective-readmes, bez instalace.


Následné výslovné zadání uživatele ruší 24h čekání: maximum je 7 hodin, ideálně méně. Zachováváme již naměřené období od 01:08:38 UTC, runtime observation končí 08.10. v 03:35 UTC po skutečné daily maintenance 03:15 UTC; GraphQL závěrečný sběr do 03:50 UTC kvůli zpoždění metrik. Nezahajovat nové měřicí období. Collectory byly po ověření živosti řízeně znovu spuštěny pouze pro změnu časové politiky, se zachovanými vzorky i původním začátkem. Tento uživatelský limit má přednost před staršími 24h požadavky výše.


### Přesná inventura historické R2 email fronty

V 2026-10-08 01:16 UTC prefix authenticated-email-pending obsahoval 402 objektů,
3 688 392 bajtů (cca 3,69 MB), uploady od 04.10. do 08.10. v 00:43 UTC.
Ze stejného inventáře je 144 klíčů již durable klasifikovaných, zbývá 258.
Karantény mají šest původních message keys, důvod email_transport_body_conflict
 a max attempts 0. Při stávajícím limitu 10 objektů každých 5 minut zbývá přibližně
130 minut klasifikace; pokračující cursor list nevrací stále první stejné klíče.
To odpovídá dokončení před dohodnutým koncem observace, pokud nepřibudou další
zprávy nebo výpadek. Znovu dokázat konečnou klasifikaci proti všem 402 klíčům.
Důkazy jsou v chráněném r2-inventory/inventory.json a classification-evidence.json.
Dočasný probe měl pouze R2 read operaci, byl autentizovaný s 30min expiry,
po inventuře odstraněn a nepřítomnost ověřena 404. Bankovní facts nebyly replaynuté.

Historické transportní konflikty vytvořily 9 227 parse_log řádků nad pouze šesti různými diagnostickými texty; poslední takový log je z 2026-10-08 00:01:38 UTC. Nová koordinace ukládá každou R2 variantu jednou do durable quarantine, dosavadní pokusy u všech karantén 0. Nezaměňovat diagnostický text po sanitizaci za důkaz shody původních MIME bytes; ty mají různá SHA a zůstávají chráněně zachované.

Scoped production evidence v 01:25 UTC: `schema13-20261008/current-requirements-evidence.json`. Poslední successful backup 01:05:40 UTC; last_maintenance_at zatím chybí a musí jej doložit skutečný daily běh. Ostatní otevřené checkboxy vyžadují doběhnutí R2 klasifikace a závěrečné dohodnuté provozní období; nezaměňovat green testy za dokončený runtime exit.

Finální prerelease preflight: produkční dependency audit hlásí No known vulnerabilities found. Přesný Wrangler migrační loader prošel na prázdné DB i původní v9 fixture do schema 13, bez změny produkce. Důkaz `schema13-20261008/final-migration-gates.json`; současný main zůstává 9d1e70e, nedošlo k nové verzi/tagu.

Retenční zdroj je oddělený do chráněného šestisouborového patch artefaktu `schema13-20261008/festapp-backup-retention-source.patch`, který prošel git apply --cached --check proti aktuálnímu origin/main. Nasazené SHA runneru i helperu jsou shodné se zdrojem. Pracovní checkout je nyní na cizí feat/occasion-setup-wizard-20261007 větvi; backup změny do ní necommitovat. Původní soubory i další dirty změny zůstaly zachované.

V 01:38:51 UTC provedla skutečná recordStorageSample/getOperationsStatus cesta druhý produkční vzorek: D1 size_after 78 712 832 bajtů (78,71 MB), první vzorek 00:16:06 UTC měl 104 779 776 bajtů. Fyzická alokace klesla o 26 066 944 bajtů. Interval je reálně delší než hodina; zobrazovaný přepočet -453 673 298 bajtů/den zachycuje právě provedený úklid, není odhadem ustáleného měsíčního trendu. Metadata sampleru jsou zapsána atomicky jediným D1 příkazem přes API adapter; žádné bankovní údaje ani časy triggerů se neměnily. Status má 0 open recovery, všech 8 účtů fresh a platný last_backup_at, last_maintenance_at stále čeká na daily běh. Důkaz `schema13-20261008/storage-growth-status.json`.

HTTP access boundary ověřená s neplatným X-Admin-Secret: status 401. V této session není načtený platný admin secret; neoznačovat úspěšný HTTP admin probe za provedený. Údaje getStatusData/getOperationsStatus jsou ověřené nad produkční D1 a HTTP dispatcher/role guard pokrývají již prošlé testy. Důkaz `schema13-20261008/operator-http-auth-evidence.json`. Průběžné GraphQL runtime metriky jsou v `worker-metrics-midpoint.json`; vyhodnotit celé dohodnuté okno před exit.

Kontrola finanční neměnnosti v 2026-10-08T01:51:36.225555+00:00: přesné SHA všech polí 538 transaction řádků, 748 webhook_delivery_jobs a 21 webhook_subscriptions jsou shodné s ověřeným produkčním backupem z 2026-10-08T01:05:40.907902+00:00. Nejde jen o shodu počtů; bankovní identity, částky a uložené delivery payloady nebyly změněné. Šlo výhradně o scoped readonly query, bez odeslání webhooků/replay. Důkaz `schema13-20261008/immutable-financial-state-evidence.json`.

Před daily během byla read-only vyhodnocena přesná stávající SQL_PRUNE_TRANSACTIONS podmínka: 0 eligible rows; ledger má 538 řádků, nejstarší created_at 2026-07-06 13:00:05. Nové completed recovery cleanup příkazy transactions vůbec neoslovují. Stávající 90denní politika pro již doručené transaction záznamy (s ochranou nezavřených jobs a nedořešených subscriptions) se tímto cílem neměnila; nelze popisovat všechny tabulky jako bez retenčního limitu. Důkaz `schema13-20261008/daily-retention-preflight.json`.

### Průběžný vzorek 02:12 UTC

GraphQL vzorek od finálního deploymentu 01:08:38 do 02:12:36 UTC obsahuje 156 Worker invocations, 436 subrequests a 0 runtime errors. Jde o průběžná data, nikoli celý exit interval; invocation success neprokazuje HTTP 200 každého endpointu. Důkaz `schema13-20261008/worker-metrics-observation.jsonl`. Přesná kontrola původního inventáře v 02:04 UTC našla 232 z 402 R2 klíčů v durable quarantine, max attempts 0, 170 dosud neklasifikovaných; důkaz `schema13-20261008/r2-inventory/classification-progress.json`. Oba sběrače zůstávají aktivní, začátek a konec observace se neposouvají.

Dnešní pravidelný Festapp backup `20261008T023344Z` skončil v 02:34:52 UTC se systemd Result=success/exit 0. Manifest potvrzuje off_host_verified=true, 14 daily days a 4 weekly copies; čtyři šifrované artefakty mají celkem 1 437 372 366 bajtů. Retenční helper úspěšně vyhodnotil 17 zachovaných sad a nothing_to_delete (0 nových deletion bytes). Jde o skutečný scheduled běh nově nasazené politiky, nikoli další manuální mazání. Důkaz `schema13-20261008/festapp-scheduled-retention-evidence.json`.

Kapacita bounded recovery úklidu byla ověřena proti skutečnému scheduleru: `pruneCompletedRecovery` běží v pětiminutové reconciliation větvi a navíc při daily maintenance. Limit 500 na kategorii tedy umožňuje až 144 000 deletions za den při úspěšných pětiminutových bězích; osm aktivních účtů při minutovém pollingu vytváří přibližně 11 520 completed batches za den. Nejde o limit 500 pouze jednou denně. Kapacitní rezerva nenahrazuje runtime důkaz a monitoring výpadků; aktuální evidence expired completed metadata je 0. Zdroj `src/cloudflare.ts:449`, `src/cloudflare.ts:1681`, `src/db.ts:1009` v kandidátu 9d1e70e.

Jednotky CPU byly ověřené přímo v autentizovaném Cloudflare GraphQL schématu `AccountWorkersInvocationsAdaptiveQuantiles`: cpuTimeP50/cpuTimeP99 jsou v mikrosekundách. Průběžný vzorek 01:08:38-02:12:36 UTC tedy má P50 5,628 ms a P99 257,024 ms. Jde o CPU čas, nikoli celkovou dobu requestu ani velikost paměti; percentily neprokazují celkový billable CPU součet. Důkaz `schema13-20261008/worker-metrics-units.json`.

Skutečný daily BankSync běh nastaveného `15 3 * * *` cronu úspěšně zapsal last_maintenance_at=2026-10-08 03:16:14. Spuštění se zpozdilo proti cron minutě; při prvním readu 03:15:49 marker ještě chyběl, nelze tento mezivýsledek zaměnit za selhání. D1 vzorek má 80 789 504 bajtů v 03:16:14.629 UTC. Read-only kontrola v 03:17:06 potvrdila přesné SHA i počty 538 transactions, 748 delivery jobs a 21 subscriptions proti ověřené záloze, 0 completed cipher rows a 0 expired completed metadata. Inventář má 380/402 klíčů v quarantine (max attempts 0), 22 zbývá. Jeden současně fetching statement je provozní in-flight import; závěrečný audit musí posuzovat stáří otevřených záznamů, nikoli zaměňovat jakýkoli aktivní import za zaseknutí. Důkaz `schema13-20261008/after-daily-evidence.json`. Celé runtime/metrics okno ještě neskončilo.

Provozní observer skončil v 03:35:03 UTC: 17 úspěšných vzorků, 0 collection errors, ve všech 8/8 fresh účtů bez API errors, schema 13 a maintenance off. Původních 8 emailových záznamů zachovalo attempts/state/body digest/last_error, žádné completed cipher bytes ani staré otevřené recovery. Závěrečný read-only audit 03:35:39 má přesné SHA finančních tabulek shodné s backupem, 402/402 původních R2 keys durable quarantined, attempts 0 a zachovaný encrypted content/key, 0 unclassified, 0 open recovery, 0 completed cipher rows a 0 metadata starších 7 dnů. Důkazy `runtime-exit-summary.json`, `final-exit-evidence.json`, `r2-inventory/classification-final.json` v chráněném schema13 adresáři. Poslední ops checkbox čeká pouze na finální GraphQL collection celého okna v 03:50 UTC; nic se nereleaseovalo.

Finální GraphQL sběr skončil úspěšně v 03:50:03 UTC. Celé okno 01:08:38-03:35 UTC: 362 invocations, 1004 subrequests, 0 runtime errors, CPU P50 5,236 ms/P99 251,891 ms. Oba collectory jsou terminal exit 0; nespouštět znovu. Osm provozních acceptance bodů je doloženo. Zbývá publikace zdrojů retence a Mendelio proxy/composition, dodržení jeho commit gate a společný finální registry release/pin. Dokončení runtime důkazu samo o sobě není dokončení celého cíle.

Zdrojová retence publikována v https://github.com/festappnet/festapp/pull/346, head 2ed33fe78715c6499110ef184c350da45381b04e na aktuálním main 0799f8e991ea1782ad59b7441c03d966efbe589c (0 behind). apply_config prošel; full test_all na vlastní aktuální lokální DB: SQL 139, Flutter 1170, Deno 271 a automatizace PASS. Chybějící worker dependencies doplněny a integrační entrypoint zopakován: 27 remote tests dokumentovaně skipped pro local DB. Node backup 4/Python 5 PASS. Testovací DB zastavena, worktree clean, původní feature checkout zachován. PR vyžaduje review. Mendelio commit stále čeká na odpověď na již položenou výjimku z AGENTS.md:104; nic nereleaseovat před tímto gate a finálním registry/pin dokončením.

Uživatel po rychlé kontrole výslovně schválil finální vydání a backendový commit. Kontrola: health 200, 8/8 fresh účtů, 0 API errors a 0 otevřených recovery; 8/8 Fio cursors initialized, posledních 30 minut 214 poll_kind=last batches. SDK PR #61 byl sloučen do main 1216e2fbc16922825a949a5db445f6d93fac0cf7 a tag v0.2.9 byl vydán přes chráněný npm workflow 37747697046: všechny gates SUCCESS včetně audit, fresh/v9 migration, dry-run, attestations a trusted publish. GitHub release https://github.com/festappnet/banksync/releases/tag/v0.2.9 má SHA-256 f27e3567c404c4ada354a5ac3ce8b0a9cec2268d59294eb0a958d6e0015b9687. npm přijal publish v 08:08:40 UTC, ale veřejné metadata/tarball zatím vracejí 404; neoznačovat dostupnost v registru ani finální registry deploy za doložené. Jeden poller /tmp/banksync-wait-registry-029.py, handle 5173, běží max 20 minut a ověří přesnou integritu + SHA. Při timeoutu nespouštět republish stejné verze.

Mendelio source pin 0.2.9 připraven jako commit 6132a29ee8691d415a37ea08c2afdb500a724cc2 v persistentním slot-5, branch fix/banksync-release-0.2.9 na aktuálním origin/main 317082ae8dccd2f4e61cfd18d20e22d68e1fd741. Zachovává InvoiceSync konfiguraci z upstreamu a nesmí publikovat dalších 7 lokálních main commits. Před publikací dokončit standard owning typecheck/quick/verify v slotu; registry 404 dosud blokuje frozen install. Main checkout má připravený owned staged scope 9 souborů a cizí dirty změny zachované. Deploy pouze z main checkoutu po kanonickém installu. Festapp PR #346 zůstává REVIEW_REQUIRED; auto-merge není v repu povolený, neobcházet review.

Finální registry deployment je hotový: @festapp/banksync@0.2.9, Worker e4c6408e-ead9-4bd7-947b-d087bc8db952, registry tarball přesně shodný s GitHub release. npm poller 5173 skončil exit 0 v 08:26:10 UTC; nikdy ho znovu nespouštět. Skutečný post-deploy proof: health 200, 8/8 fresh accounts, 0 API errors, žádné recent events, bindings unchanged. Důkazy release-029-registry-proof.json a release-029-production-proof.json. Zbývá canonical composition source publication po dokončení standard kontroly (handle 81826) a mandatory Festapp PR #346 review. První full gate narazil na nesouvisející test s pevným zářijovým datem po expiraci 28denní retence; test-clock fix je izolovaný commit 6884fe98a, produktové chování nezměněno.


## Aktuální stav po publikaci zdrojů (nahrazuje staré pending údaje)

Mendelio canonical origin/main je f8317411e3db51b7f51097c8df97e004e62e3e3d. Pin SDK 0.2.9, wrapper konfigurace a Fio proxy jsou publikované. Standard gate dokončen ve dvou dávkách: unit a Voice (4709 Python passed) v první; podcast, services, standalone Python, simulated a privacy ve druhé (exit 0). Owning typecheck a composition test prošly. Staré testovací handly jsou terminální; nic neopakovat bez nové změny. Sdílený main byl bezpečně sloučen s upstreamem, owned source soubory jsou čisté a cizí dirty práce i 7 nepublikovaných commits zachované. Slot-5 uvolněn. Důkaz: release-029-source-publication-proof.json.

Produkce již běží na skutečném registry 0.2.9, Worker e4c6408e-ead9-4bd7-947b-d087bc8db952; všech 8 Fio účtů doloženě synchronizovalo po nasazení. Neprovádět další release kvůli dokumentaci. Na žádost uživatele je zestručněný integration guide připraven v BankSync PR #62; čeká pouze chráněné CI/sloučení. Festapp PR #346 stále OPEN/REVIEW_REQUIRED, bez obcházení povinného review.

Dokumentace publikována: BankSync PR #62 MERGED v 09:00:33 UTC, main 437c38bfe88faa975b270267d3e72d524eeef19e. Guide 330 -> 134 řádků, funkční webhook verification/process/receipt příklad, reference operations a optional payment references. Všechny protected CI checks PASS; bez další verze/deploye. Důkaz guide-readability-publication-proof.json. Jediný nedokončený publication gate původního cíle je mandatory review Festapp PR #346.

Na rozšířený požadavek uživatele upraven celý dokumentační celek BankSyncu: README, SECURITY, operations, payment references a security rollout. Staré plány označeny jako historické při zachování důkazů. PR #63 MERGED v 09:07:53 UTC, main ad7f5d1c0f2c7a64493e580333384f6aabc0c6d5; všechny protected CI checks PASS, bez další verze/deploye. Důkaz documentation-suite-publication-proof.json.
