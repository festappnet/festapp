# Doručení vstupenek jako PDF nebo QR v e-mailu

Datum: 2026-10-23  
Stav: Lokálně implementováno a cíleně ověřeno 2026-10-23; bez produkčních změn, commitu a nasazení  
Ověření při implementaci: standard (sdílené doručování a SQL kontrakt)

UI/UX posouzení: subagent `gpt-6-astra`, reasoning `medium`; jeho závěry jsou zapracované níže.

## Výsledek a potvrzená rozhodnutí

Pořadatel vybere pro celou akci způsob doručení vstupenek:

| Hodnota kontraktu | Text v UI | Obsah zprávy se vstupenkami |
|---|---|---|
| `pdf_attachment` | PDF v příloze | Dosavadní PDF pro každou vstupenku |
| `inline_qr` | QR přímo v e-mailu | Jednoduchý QR pro každou vstupenku, bez PDF |
| `both` | QR v e-mailu i PDF v příloze | Jednoduché QR a dosavadní PDF |

**PDF v příloze je výchozí pro stávající i nově vytvořené akce.** Jiná volba vyžaduje výslovné nastavení. Každá vstupenka má vlastní QR. QR v e-mailu i PDF obsahuje stejný `ticket_symbol`, takže společně představují jedinou vstupenku a sdílejí stav kontroly vstupu.

Jde o rozšíření doručení, nikoli nový druh vstupenky. Volba nemění cenu, platbu, rezervaci, kapacitu, převoditelnost, oprávnění ani pravidla vstupu. Žádné nastavení podle produktu, společný QR objednávky, grafická vstupenka v těle e-mailu, nový návrhář, Wallet ani nové veřejné úložiště QR nejsou součástí této práce.

## Výchozí stav a důkazy v repozitáři

| Fakt | Vlastník a důsledek |
|---|---|
| `order_tickets` dnes vytváří PDF, pokud je zapnutá funkce `ticket`. | `supabase/functions/_shared/emailRenderer.ts: renderQueuedEmail`; zde zůstane orchestrace všech tří variant. |
| QR v PDF obsahuje `ticket_symbol`. | `ticketRenderData.ts: normalizeTicketData`, `generateTicket.ts`; nepřidávat jiný kód nebo URL pro inline variantu. |
| Příprava PDF načítá fonty, pozadí a layout, a odmítá čekací vstupenky. | `ticketGeneration.ts: prepareTicketRenderer`; inline větev nesmí potřebovat PDF zdroje ani obejít způsobilost vstupenky. |
| Přílohy nemají metadata pro vložené obrázky; SES je odesílá jako `ATTACHMENT`. | `_shared/emailDelivery.ts: EmailAttachment, PreparedEmail, renderEmail`; `_shared/sesProvider.ts: sesBody`. Metadata je nutné zachovat i v zašifrovaném snapshotu. |
| Připravený e-mail se ukládá a opakovaný pokus jej znovu použije. | `_shared/emailDispatcher.ts`, `_shared/emailPayload.ts`; změna nastavení nepřepisuje již připravenou zprávu. |
| Platnost úmyslu a stav úhrady znovu kontroluje SQL send gate. | `database/functions/emails/email_queue.sql: email_intent_valid, begin_email_send`; všechny varianty musí projít stejnou cestou. |
| Konfigurace vstupenek je součástí `occasions.features`. | `lib/components/features/ticket_feature.dart`; způsob doručení nesmí být další hodnota `ticket_type`, které vybírá PDF šablonu. |
| Nastavení používá existující obrazovka i průvodce založením akce. | `ticket_layout/views/ticket_settings.dart`, `occasion/setup/occasion_setup_page.dart: _ticketSettings`; oba vstupy musí zachovat nový atribut. |
| Finalizace koncertu/plesu dnes vyžaduje PDF layout se společným stylem. | `database/functions/occasion_setup/finalize.sql`; tento předpoklad upravit pro `inline_qr`. |
| Náhled v průvodci dnes zobrazuje potvrzení objednávky. | `database/functions/occasion_setup/email_preview.sql`, `supabase/functions/occasion-setup-email-preview/`; přidat samostatný náhled zprávy se vstupenkami. |
| Šablony a wrapper mají dědičnost akce > pořadatel/unit > organizace. | `lib/components/email_templates/README.md`; zachovat společný resolver a wrapper. |

SES podporuje `ContentDisposition: INLINE` a `ContentId` s HTML odkazem `cid:`: [oficiální dokumentace](https://docs.aws.amazon.com/ses/latest/APIReference-V2/API_Attachment.html). To potvrzuje transportní možnost, nikoli kompatibilitu všech poštovních klientů; ta má vlastní ověřovací bránu níže.

## Cílový kontrakt a invarianty

- Jediný atribut `delivery_mode` uvnitř feature `ticket`; přípustné hodnoty odpovídají tabulce. Chybějící atribut znamená `pdf_attachment`, explicitní neplatná hodnota se odmítne. Neprovádět plošný backfill jen kvůli doplnění defaultu.
- Nová akce bez explicitní volby i starý draft bez atributu použijí PDF. Výslovné kopírování nastavení existující akce může převzít její uložený režim; převzatá volba musí být viditelná v rekapitulaci.
- SQL vlastní validaci uloženého režimu. Dart a TypeScript používají odpovídající uzavřený kontrakt a stejný default. Přidat atribut do serializace a relevantních draft/copy/save cest, nikoli do PDF layout JSON nebo appearance patch.
- Funkce `ticket.is_enabled` zůstává hlavní branou. Volba režimu ji automaticky nezapíná. Vypnutá funkce nevytváří nové QR ani PDF; její dosavadní e-mailové chování se zachová.
- Inline QR vzniká jako PNG v procesu přípravy e-mailu. Nepoužívat veřejnou URL obsahující symbol, externí QR službu, SVG ani HTML obrázek s `data:` jako produkční doručení.
- Všechny varianty sdílejí pravidla výběru vydatelných vstupenek. Storno a čekací listina nesmí získat platný QR jinou větví. Zachovat kontrolu příslušnosti ke správné akci a stavové kontroly úhrady v SQL.
- E-mail s QR je jedna atomická připravená zpráva. Chyba generování jednoho QR/přílohy nezpůsobí částečné odeslání ani označení některých vstupenek jako odeslaných.
- Režim se vyhodnotí při první úspěšné přípravě zprávy a zůstane součástí jejího šifrovaného snapshotu. Retry použije tentýž obsah. Nový explicitní resend může použít aktuální nastavení, ale nesmí vystavit nové identity vstupenek.
- Uložení režimu samo o sobě neposílá staré vstupenky znovu. Zachovat existující události, deduplikaci, fencing, potlačení adres a globální limity fronty. Neměnit význam stavu přijetí poskytovatelem na potvrzení doručení do schránky.

## UX a obsah

Ovládání umístit nahoru do existujícího nastavení vstupenek, před nastavení kontroly a PDF. V průvodci vytvořením akce patří stejný znovupoužitelný selector do Komunikace nad náhledy, pouze pro akce se vstupenkami; v jeho vloženém editoru Vzhled selector skrýt, aby nebyl dvakrát. Použít jednu skupinu tří vzájemně výlučných voleb s krátkým vysvětlením a náhledem výsledku. PDF bude první a výchozí volba. Nezavádět druhé nezávislé nastavení v editoru e-mailových šablon; může pouze odkazovat do nastavení vstupenek. U vypnuté funkce volby skrýt nebo zobrazit jako neaktivní a uloženou volbu zachovat.

Pomocný text vysvětlí, že volba platí pro všechny vstupenky akce a nemění již odeslané e-maily. U již připravených zpráv platí pravidlo snapshotu; formulace nesmí slibovat, že změna upraví zprávu již čekající na retry.

**Upřesnění uživatele:** v těle e-mailu bude pouze jednoduchý QR pro každou vstupenku. Žádná grafická karta, obrázek celé vstupenky ani automatický souhrn názvu akce, data, místa, produktu, sedadla nebo držitele kolem QR. Tyto informace patří do běžného textu e-mailové šablony. Nevytvářet zjednodušený druhý návrhář vstupenek.

QR je tmavý na pevném světlém podkladu s ochranným okrajem, bez loga a dekorací. Více QR zobrazit pod sebou ve stabilním pořadí, u více vstupenek pouze s krátkým rozlišením „QR 1 z 3“; bez rámečku, vypsaného symbolu nebo dalších údajů vstupenky. Na mobilu nesmí vzniknout vodorovný posuv. U `both` stručně vysvětlit, že QR v e-mailu a PDF patří ke stejné vstupence.

U volby způsobu doručení použít stručné popisy, které pořadateli vyjasní výsledek:

- **PDF v příloze:** „Vstupenky odešleme jako PDF v příloze e-mailu.“
- **QR přímo v e-mailu:** „Do těla e-mailu vložíme pouze QR kódy, bez grafické vstupenky a bez PDF.“
- **QR v e-mailu i PDF v příloze:** „V e-mailu budou jednoduché QR kódy a v příloze PDF vstupenky.“

Výchozí zůstává PDF v příloze. Náhled odpovídá přesně vybrané variantě.

Náhled ukazuje samostatně zprávu se vstupenkami v aktuálním režimu, včetně seznamu PDF příloh. Umí jednu i několik ukázkových vstupenek a používá neplatné ukázkové QR. Potvrzení objednávky ani jeho náhled se nesmí omylem změnit na vydání vstupenky. Náhled nic nezařazuje do fronty, nevytváří objednávku a neodesílá poštu.

V režimu `inline_qr` není PDF editor součástí povinného průchodu. Uložený návrh se nemaže; jeho úprava může zůstat jako vedlejší akce „Upravit PDF pro tisk“. Návrat k PDF obnoví existující návrh; případnou chybějící/neplatnou konfiguraci musí pořadatel opravit před použitím. Inline doručení nesmí načítat PDF fonty či pozadí a nesmí selhat kvůli jejich nedostupnosti.

Blok jednoduchých QR generuje systém; pozice `{{tickets}}` zůstává stejná a neznamená grafickou vstupenku. Šablona `TICKET_ORDER_PAYMENT_DONE` může určit jeho pozici jedním vyhrazeným blokem `{{tickets}}`; pokud jej stará nebo zděděná šablona nemá, renderer vloží blok na konec obsahu před wrapper. Opakovaný blok se odmítne v editoru a renderer zajistí, že každý QR bude ve výsledku pouze jednou. U PDF režimu je tento blok prázdný. HTML interpolované z dat musí být escapované; technické CID se odvodí bezpečně a jednoznačně, ne vložením neověřeného textu do HTML atributů.

Výchozí text šablony upravit tak, aby netvrdil, že PDF vždy existuje. U vlastních šablon obsah automaticky nepřepisovat. Při přepnutí ze samotného PDF ukázat výsledný náhled a stručné upozornění, aby pořadatel zkontroloval text o přílohách. Technickou syntaxi CID neukazovat uživateli editoru.

Při vypnutých obrázcích zůstává běžný text šablony a krátký alternativní popis obrázku. QR vyžaduje zobrazení obrázků; netvrdit, že je v takovém stavu dostupný nebo že je zaručen ruční vstup. Nepřidávat automaticky textový kód, nezapínat `canScanManually` a nezavádět nový veřejný odkaz jako další závislost této verze.

## Implementační kroky

### 1. Konfigurace a uložení

**Změny:** Rozšířit `TicketFeature`, konstanty feature a serializaci o `delivery_mode`. Přidat malý SQL validátor kontraktu a zapojit jej do relevantních create/update/finalize cest: zejména `others/update_occasion.sql`, `others/save_occasion_domain_command_internal_v1.sql`, `occasion_setup/finalize.sql`. Ověřit zachování atributu v `duplicate_occasion.sql`, načtení kopie v průvodci a merge layoutu. Nepřidávat nový veřejný write RPC, pokud postačí stávající oprávněný save.

Pro `inline_qr` odstranit závislost finalizace na povinném PDF layoutu a jeho společném stylu. Pokud layout zůstává uložen, zachovat jeho strukturální/referenční validaci. Pro PDF a `both` zachovat dosavadní požadavky. Zkontrolovat, že změna samotného režimu nespustí vedlejší `enqueue_paid_order_tickets` v `update_occasion.sql`.

**Migrace:** Autorské SQL a případná repo migration mění pouze kontrakt funkcí; žádné přepisování existujících režimů nebo objednávek. Oprávnění a explicitní `search_path` podle pravidel repozitáře.

**Ověření a výstup:** Cílené modelové a SQL testy pro default nových/starých akcí a draftů, tři hodnoty, odmítnutí neplatných hodnot, oprávnění, save/copy roundtrip, inline finalizaci bez PDF a absenci resend při změně nastavení. Uložená volba se neztrácí žádným podporovaným vstupem.

### 2. Společná příprava zprávy a inline transport

**Změny:** V `_shared/emailRenderer.ts` vybrat režim a společnou sadu vydatelných vstupenek. Oddělit výběr symbolů a ověření způsobilosti od PDF rendereru; nové malé pomocníky držet v `_shared/`, například `ticketEmail.ts` a `ticketDelivery.ts`. QR payload zůstává `ticket_symbol`; znovu využít existující závislost `qrcode` a odpovídající korekci chyb. PDF generovat jen pro PDF a `both`.

Rozšířit `EmailAttachment` a `PreparedEmail` o volitelnou dispozici a CID; propagovat přes `renderEmail`, šifrování/dešifrování snapshotu až do `sesBody`. Chybějící metadata znamenají dosavadní `ATTACHMENT`, aby staré připravené zprávy zůstaly čitelné. Inline obrázek musí mít odpovídající CID v HTML. Zachovat Reply-To, odesílatele, tracking policy a post-actions. Žádné nové provider credentials ani přímé odesílání mimo worker.

Blok jednoduchých QR vložit na jediné hranici kompozice obsahu před wrapperem a jen pro zprávu se vstupenkami. Zachovat tříúrovňovou dědičnost. Výchozí šablony a editor bloků upravit bez duplicitního generování HTML.

**Selhání:** Nepřepínat automaticky na PDF ani nevynechávat QR při chybě. Velikost zprávy počítat včetně PNG a base64; zachovat existující velikostní limit a diagnostiku bez logování QR/symbolů. Žádné tiché zkracování počtu vstupenek, dělení objednávky do dalších zpráv ani automatické přepnutí režimu.

**Ověření a výstup:** Deno testy s provider stubem pro počet/typ příloh a QR ve všech režimech, shodu QR symbolu s PDF, CID vazby, escapování, filtr způsobilosti, přesah velikosti, chybu jedné položky a inline větev bez volání PDF zdrojů. Rozšířit `_shared/canonicalEmail_test.ts` o metadata a seal/open roundtrip včetně starých snapshotů. Retry používá identický snapshot a neprovádí druhou přípravu.

### 3. Nastavení, náhled a průvodce

**Změny:** Sdílené ovládání v `ticket_layout/views/ticket_settings.dart` a `occasion/setup/occasion_setup_communication_settings.dart`, lokalizace přes `*_strings.dart`, integrace do `_ticketSettings` v `occasion_setup_page.dart`, rekapitulace a draft. Selector v průvodci zapisuje do téhož `ticketDraft`, nikoli do konfigurace formuláře nebo šablony. Po změně v Komunikaci synchronizovat nebo invalidovat cache `_ticketFeature`, aby pozdější úprava PDF nepřepsala režim starou hodnotou. Oddělit načítání PDF zdrojů od renderu volby doručení. Přepnutí režimu zachovává rozpracovaný PDF návrh a stávající draft/save/conflict mechaniku.

Rozšířit autorizovaný draft preview (`occasion_setup/email_preview.sql`, `occasion-setup-email-preview/handler.ts` a `content.ts`) o výslovný výběr podporovaného typu zprávy; default zůstane dnešní potvrzení objednávky. Server odvozuje tenant/unit/occasion ze schváleného kontextu a kontroluje revizi. Náhled pro existující akci napojit na již používaný oprávněný preview vstup editoru; pokud takový vstup neposkytuje serverový render, rozšířit tento vstup, nikoli přidat nechráněný renderer.

Produkční HTML s `cid:` musí náhled převést na lokální bezpečné reprezentace obrázků pouze pro zobrazení. Existující `OccasionSetupCommunicationSettings._safePreview` odstraňuje všechny obrázky, SVG i inline styly: doplnit úzce omezenou projekci důvěryhodných ukázkových QR, nikoli plošně povolit obrázky a libovolné zdroje v šablonách. Znovu použít stejnou kompozici bloku QR a wrapper; nezavádět zvláštní přibližnou Flutter kresbu e-mailu. Náhled musí respektovat aktuální neuloženou volbu, bez odeslání a bez vydání platných QR. Zachovat loading, chybu a opakování načtení.

**Ověření a výstup:** Rozšířit `test/components/occasion/occasion_setup_settings_test.dart`, související gallery/draft testy a `occasion-setup-email-preview/preview_test.ts`. Ověřit všechny režimy, default, vypnutou funkci, návrat k PDF, neuložené změny, běžné potvrzení versus zprávu se vstupenkami, revizi a zamítnutí cizího kontextu. UI/UX návrh a případné změny nechat projít subagentem `gpt-6-astra`, reasoning `medium`, jak požaduje uživatel.

### 4. Integrované ověření a dokumentace

**Změny:** Doplnit stručný kontrakt do README email templates a ticket layout, popsat default, systémový blok a snapshot/resend chování. Zachovat dosavadní PDF renderer, šablony, tisk a download; mění se pouze výběr příloh v doručování. Odstranit pouze nové duplicitní předpoklady „každé vydání vyžaduje PDF“, nikoli související tiskové funkce.

**Ověření a výstup:** Na izolovaných datech provést zaplacení -> fronta -> připravená zpráva -> provider stub -> post-action a kontrolu vstupu. Stejná vstupenka načtená z e-mailu a poté PDF musí být při druhém načtení již použitá. Ověřit storno mezi přípravou a odesláním přes stávající SQL gate. Žádné skutečné platby, hromadné rozesílání nebo produkční změny.

Před povolením inline režimu v produkci provést skutečné doručení do výslovně schválených testovacích schránek Gmail, Outlook, Seznam a Apple Mail. Ověřit mobilní zobrazení, dark mode, přeposlání, vypnuté obrázky, skenovatelnost z displeje a objednávku s více QR. Testovací odeslání vyžaduje samostatné oprávnění; tento plán jej neposkytuje. Pokud nejsou schránky k dispozici, uvést přesně neověřené klienty jako otevřenou release bránu.

## Proporční ověřování při implementaci

Plán sám nevyžaduje spouštění testů. Při implementaci batchem pokrýt změněný kontrakt, nikoli po každé úpravě opakovat celou sadu:

- Cílené Deno testy pro email delivery, canonical SES transport a preview; používat frozen lock `supabase/functions/deno.lock` a repo oprávnění jako v `automation/test_all.sh`.
- Cílené SQL testy přes `pnpm exec node scripts/run_db_tests.js ../database/tests/<konkrétní-test>.sql` z `web_client`, po ověření konfigurace výhradně izolované testovací DB. Nezaměňovat `.env.local` s oprávněním k produkci.
- `fvm dart analyze <změněné-dart-soubory>` a relevantní Flutter testy přes `fvm flutter test --concurrency=1 <cílené-testy>`. Před každým Flutter úkolem ověřit, že na stanici neběží jiný Flutter úkol, a případně počkat.
- UI kontrola v izolované headless browser session; pro plný průchod použít repo local-E2E workflow. Poštovní klienti mají samostatnou bránu výše.

Přesný seznam testovacích souborů doplní implementující agent podle vzniklých změn. Široké release gate spouštět jen pro samostatně autorizované vydání.

## Nasazení, kompatibilita a návrat

Původní plán autorizoval pouze návrh; uživatel následně výslovně zadal lokální implementaci execution promptu. Lokální implementace je dokončena. V původním kroku nebyly produkční operace autorizovány; následná žádost o dokončení rozšířila rozsah na přípravu publikace a vydání. Stav a zbývající povinné repo brány jsou níže. Neměnit aktuální rozpracované změny uživatele ani přepínat jeho větev; společný kód při implementaci patří na canonical `main` podle repo pravidel, případně v izolovaném checkoutu.

Při později autorizovaném vydání nejprve nasadit SQL validaci a čtení defaultu, potom worker podporující všechny režimy a staré snapshoty, a teprve následně UI umožňující uložit inline/both. Prověřit i ostatní zapisující klienty a jejich zachování atributu, aby starý save nevracel vědomě zvolený režim na PDF. Neměnit jiné tenant větve ani je nestavět bez výslovného rozsahu. Rutinní deployment a live ověření delegovat podle repo pravidel levnějšímu subagentovi; neočekávané technické problémy vrátit hlavnímu agentovi.

Rollback nesmí nasadit worker bez podpory již připravených inline snapshotů nebo uložených režimů. Nejprve uzavřít nové volby v UI a případně použít existující globální pause fronty; obnovit kompatibilní opravený worker. Již odeslané e-maily se změnou nastavení neodvolají. Nepřepisovat všechny akce na PDF jako automatický rollback.

## Předpoklady, rizika a hotovo

- Předpoklad: cílové zakázky běžně obsahují počet vstupenek, který se vejde do jedné zprávy. Před realizací zjistit podporovanou maximální velikost objednávky a zvolit rozměr/kompresi PNG tak, aby reprezentativní horní mez měla rezervu pod limitem. Pokud to nejde, výslovně řešit samostatné produktové rozhodnutí; žádné skryté vynechávání QR.
- Riziko: vlastní zděděná šablona může zmiňovat PDF. Náhled a upozornění jsou povinné; automatické přepisování cizího textu není součástí plánu.
- Riziko: e-mailový klient může blokovat i inline obrázek a dlouhé zprávy krátit. Ověřit reálné klienty; samotná podpora SES není důkaz použitelnosti.
- Hotovo znamená: výchozí PDF pro nové i staré záznamy, konzistentně uložená explicitní volba, tři správné varianty doručení, jeden symbol a stav vstupu, inline bez PDF závislostí, bezpečné náhledy, zachované frontové brány a prošlé cílené testy. Lokálně dokončená implementace a živé nasazení se vykazují odděleně.


## Dokončení nad aktuálním canonical main

Původní lokální implementace vznikla ve staré rozpracované větvi. Pro publikaci byla změna samostatně přenesena na aktuální `origin/main` (`c8e70c6e7`), bez převzetí cizích změn a bez odstranění novějších funkcí. Aktuální průvodce řídí vstupenky podle viditelného ticket pole formuláře a validaci společného stylu vlastní `normalize_occasion_setup_appearance_internal`. Inline výjimka je proto implementována v tomto vlastníkovi, nikoli starým přepisem finalizeru.

Zachovány jsou nové typované autorizace, read-only a scanning nastavení, kontext náhledu, povinné/autorské odkazy, katalog pěti e-mailových šablon a draft overrides. Nový náhled rozšiřuje původní dvouargumentový SQL kontrakt; default stále vrací potvrzení a katalog. Explicitní `order_tickets` vrací CID PNG a seznam PDF. Náhled pro existující akci používá stejné oprávněné rozhraní a `can_read_ticket_layout`.

- Default PDF, tři hodnoty, serializace a zachování vědomé volby při starších zápisech jsou implementovány v SQL/Dartu/TypeScriptu. Změna nastavení znovu nezařazuje paid objednávky.
- Inline používá stávající symboly bez PDF zdrojů. Snapshoty zachovávají CID a disposition; staré snapshoty zůstávají kompatibilní. Renderer, globální fronta, send fencing a admission stav zůstávají společné.
- Vzhled PDF, tisk a download se nemění. Přepnutí na inline zachová uložený návrh včetně jeho stylu. Nový selector sdílejí nastavení a Komunikace.
- `{{tickets}}` je rezervovaný nerepetovatelný rich block. SQL chrání i draft overrides. V PDF a payment-notice zprávách je prázdný. Staré šablony bez markeru dostanou QR před wrapperem; vlastní text se nepřepisuje.
- Pro běžný obsah ticket zprávy se znovu využívá aktuální `orderEmailPresentation.ts` a `generateFullOrder`, bez dalšího payment rendereru. Globální seed už netvrdí, že PDF vždy existuje.
- Funkční migrace `20261023230000_ticket_email_delivery.sql` se generuje přes `automation/assemble-ticket-email-migration.py` pouze z dotčených definic. Nemění data ani cizí helpery/oprávnění.

### Cílené ověření canonical portu

- 37 Deno testů: ticket delivery, SES/snapshoty, existující email delivery a oba druhy preview. Typecheck skutečného worker rendereru, preview endpointu a rehearsal adapteru prošel.
- 36 unikátních UI testů: 25 Flutter widget testů a 11 core authoring testů; relevantních osm widget testů po doplnění invalidace kontextu opět prošlo. Analyzer nemá chyby ani varování. UI/UX implementoval a posoudil `gpt-6-astra`, medium; design detector vrací prázdný seznam.
- Osm cílených SQL souborů (draft/finalize/preview/ticket settings, nový kontrakt, fronta/post-actions a scanner) prošlo v samostatné lokální kopii `festapp_ticket_email_canonical_20261023`. Stávající preview test načítá SQL jako vlastník funkcí `supabase_admin`; ostatní běží jako místní `postgres` a testují skutečné authenticated hranice.
- Integrovaný rollback-only rehearsal prošel pro PDF, inline i obojí: SQL paid transition -> canonical queue -> šifrovaná příprava -> SES stub -> post-actions -> sken 200/409. Storno po přípravě zabránilo send gate. Deno adapter nemá síťové oprávnění; reálná platba ani pošta nevznikla.

Reprodukce (s explicitním lokálním `DATABASE_URL`, z `web_client`):

```sh
pnpm exec node scripts/run_db_tests.js occasion_setup/ticket_delivery_test.sql \
  occasion_setup/email_preview_test.sql occasion_setup/finalize_test.sql \
  occasion_setup/drafts_test.sql ticket_layout_settings_test.sql \
  emails/order_ticket_intents_test.sql emails/canonical_email_queue_test.sql scanning/admission_test.sql
pnpm exec node ../automation/email-delivery/rehearse-ticket-delivery.mjs
```

Logy: `/tmp/festapp-ticket-canonical-deno-final.log`, `/tmp/festapp-ticket-canonical-{sql,preview-sql,sql-extra,integration}.log`, `/tmp/ticket-canonical-{analyze,context-analyze,flutter,context-flutter,core-test}.log`.

### Stav publikace a omezení

Uživatel následně zadal dokončení včetně přípravy publikace/nasazení a uvedl, že testovací schránky nebude mít. Gmail, Outlook, Seznam a Apple Mail proto nejsou skutečně ověřeny; mobilní poštovní klienty, dark mode, přeposlání, vypnuté obrázky a skenovatelnost z těchto klientů nelze vykazovat jako prošlé. Kompatibilita transportu a lokální náhled nenahrazují toto zjištění.

Ochrana canonical `main` vyžaduje jedno schválení pull requestu. Připravená a ověřená změna musí projít tímto schválením před publikací a produkčními kroky. Po merge je pořadí SQL -> kompatibilní Function bundle -> jediný tenant `prod/festapptickets` / `vstupenky.online`, s lokálním buildem, canonical drift gate a ověřením živé verze. Žádná produkční změna ani skutečný e-mail dosud neproběhly.
