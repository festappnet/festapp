# Bezpečnostní opravy Festapp se zachováním funkčnosti

Datum: 2026-10-09
Stav: Balík sloučen a nasazen; konečná evidence a zbývající kompatibilitní brány viz [záznam vydání](../operations/security-release-2026-10-09.md). Uživatel výslovně autorizoval administrátorské sloučení.
Ověření: standard

## Výsledek a rozsah

Tento implementační balík opraví potvrzené NULL bypassy, XSS veřejných formulářů a chybějící objektovou autorizaci vybraných RPC. Zachová platný anonymní scan s tajným kódem, registrace vlastníka/editora/companions, současné formátování formulářů a legitimní administrativní operace. Součástí jsou kanonické SQL zdroje, dopředná migrace a skutečné negativní i pozitivní regresní testy.

Autoritativním podkladem je [ověřený audit](../operations/security-audit-2026-10-09.md) a jeho [evidence](../operations/security-audit-2026-10-09-evidence.json). Uživatel autorizoval sestavení i provedení plánu a práci GPT-6.1 Sol Medium agenta. Navazující požadavek uživatele autorizoval dokončení včetně publikace a nasazení pro festapp. Platí ochrana main s jedním schvalujícím review a původní požadavek nenarušit funkčnost starších klientů.

Sdílený přístup editorů k souborům je dokumentovaný existující kontrakt. Přechod na vlastnictví jednotlivých souborů a nahrazení šestimístných vstupních hesel expirovanými jednorázovými tokeny vyžadují samostatné klientské a datové migrace. Plošné změny těchto kontraktů nejsou součástí tohoto balíku. Přímý UPDATE identity profilu i přímé zápisy účasti už nasazené granty blokují.

## Důkazy a rozhodnutí

| Fakt | Důkaz | Důsledek |
| --- | --- | --- |
| Scan a použití vstupenky propouštějí NULL kód | `scan_ticket.sql`, `update_ticket_to_used.sql`; shodné produkční definice a lokální reprodukce | Použít NULL-safe porovnání a zachovat pozitivní scan bez loginu |
| Starší attendance RPC propouštějí anonymního aktéra | `sign_user_to_event.sql`, `sign_user_out_of_event.sql` | Ověřit aktéra před první změnou členství; zachovat business error codes |
| Nasazená attendance funkce volá autorizovanou membership fasádu, pracovní kanonický zdroj interní helper | Audit dvojího průchodu | Opravu provést v kanonickém zdroji a migraci; testovat autorizaci před vedlejším zápisem |
| HTML builders používají neescapovaná data a vlastní URL filtr je obejitelný | Reálný Chrome reproduktor v auditu | Jeden udržovaný sanitizér pro rich HTML, textové názvy escapovat |
| `anon` smí volat citlivé lookupy, unit membership a bank-user RPC | Katalog a izolované SQL testy | Explicitní kontrola objektu a nejmenší potřebné granty, včetně overloadů |
| Occasion email templates mají vnitřní autorizaci; unit cesta ji postrádá | `get_entity_email_templates` -> `get_all_email_templates` | Zachovat funkční editorové čtení a zabezpečit unit i přímé helper vstupy |
| Přímé veřejné čtení `event_users` vrací UUID, ale starší klienti přes stejnou tabulku počítají účasti | `lib/components/schedule/db_events.dart:198`, `:249` | Neodebírat plošně SELECT v tomto balíku; nejdříve migrovat klientské counts a čtenáře |

## Invarianty a kompatibilita

1. Chybějící identita nebo tajný kód nikdy nezpřístupní chráněnou operaci. Zamítnutí nesmí vytvořit členství ani označit vstupenku jako použitou.
2. Oprávnění se odvozují od cílové jednotky, akce, bankovního účtu nebo uživatele, nikoli od klientem tvrzené role.
3. Platný scan zůstane dostupný přes stávající tajný kód bez povinného loginu. Reset přes scan zachová již opravené ochrany.
4. Attendance zachová stávající návratové kódy, limity, termíny, exclusivity a companions omezené na příslušnou akci.
5. Názvy polí a produktů jsou text; popisy jsou omezené rich HTML. Bezpečné obrázky, odkazy, tabulky a editorové formátování zůstávají funkční.
6. Nové autorizační kontroly zachovají doložené vnitřní/service volání. Případná oprava stávajícího předávání parametrů musí být úzká a testovaná.
7. Migrace nevytváří persistentní aplikační triggery a nemění zákaznická data. Definice jsou v `public` se `search_path = public, extensions`.
8. Nezmění se cizí rozpracované změny. Žádný test nesmí resetovat existující sdílenou testovací databázi nebo používat produkční DATABASE_URL.

## Vlny implementace

### 1 SQL NULL autorizace

Upravit čtyři kanonické funkce ve `database/functions/eshop_orders/` a `database/functions/events/`. Scan použije `IS DISTINCT FROM`; attendance explicitně odmítne chybějícího aktéra a zkontroluje oprávnění před zápisem. Stávající chyby a platné cesty zůstanou zachovány. Doplnit `database/tests/security/scan_attendance_security.mjs` se skutečným `SET ROLE anon/authenticated`, vlastníkem, editorem, companion a cizím uživatelem. Ověřit také beze změny existující deposit, doplatek a overpayment scénáře. Výstup: exploit odmítnutý a pozitivní scénáře zelené.

### 2 HTML a závislosti

GPT-6.1 Sol Medium agent vlastní `web_client/src/utils/html.js`, související field builders, jejich testy a npm manifest/lockfile. Nahradí ruční filtr DOMPurify, odstraní obcházení sanitizace na dotčených vstupech a otestuje skutečné builders. Zachová dosavadní povolené rich formátování při vyloučení event handlerů a nebezpečných URL. Oprava `brace-expansion` bude cílený kompatibilní lockfile update. Výstup: cílené JS testy, web build a izolovaný browser smoke potvrzují blokaci exploitů i funkční formulář.

### 3 Objektová autorizace RPC

GPT-6.1 Sol Medium agent vlastní `add_user_to_unit`, oba kontrakty `get_bank_account_users`, `get_user_id_by_email`, `get_last_sign_in_at`, `get_entity_email_templates` a nutné změny vnitřních čteček. Nejprve dohledá skutečné Flutter, SQL a servisní volající a z nich odvodí matici oprávnění. Unit manager a bank admin/support nejsou zaměnitelné role. Zachovat jména/parametry využívané klientem; odstranit pouze doložené nebezpečné granty a nejednoznačnost overloadů. Přímá vnitřní čtečka nesmí obejít nový obal. `rpc_object_authorization_test.sql` ověří anonymní, cizí tenant, běžného uživatele a všechny povolené role. Výstup: citlivý objekt není přístupný neautorizovanému volajícímu a doložená UI/service cesta funguje.

### 4 Migrace a společné ověření

Koordinátor sestaví dopřednou SQL migraci z finálních kanonických definic a potřebných ACL změn. Žádná duplicitní business implementace ani nový alternativní autorizační mechanismus. Migraci aplikuje v samostatné lokální Supabase databázi vytvořené z repository baseline a migrací. Spustí cílené nové SQL testy, související stávající testy a testy/build frontend agenta; izolovaný browser použije skutečné moduly. Prověří diff proti náhodnému zásahu do rozpracovaných souborů.

Aktualizuje tento plán a audit tak, aby rozlišovaly implementované lokální opravy, zbytková rizika a dosud neprovedené nasazení. Auditní charakterizační reproduktor zůstává historickým důkazem, nikoli regresní bránou přijímající exploit. Nové regresní testy musí na původní zranitelné cestě selhat a na opravě projít.

## Odstranění a ponechané hranice

| Artefakt | Akce | Důkaz |
| --- | --- | --- |
| Vlastní blacklistový HTML sanitizér | Nahradit jedinou udržovanou implementací | Kontrola importů a URL/XSS regresní testy |
| Nebezpečné raw HTML title/description sinks v upravovaných builders | Text escapovat, rich HTML sanitizovat | Test skutečných builders a browser marker |
| NULL-unsafe podmínky ve čtyřech RPC | Odstranit | Negativní SQL testy a cílené hledání |
| Anonymní citlivé RPC / nechráněné overloady | Omezit a testovat včetně vnitřních vstupů | Efektivní ACL a testy rolí |
| Stávající názvy attendance a scan RPC | Ponechat jako podporovanou klientskou hranici | Flutter volání a test návratových kódů |
| Projektové sdílení souborů a starší public attendance counts | Ponechat do samostatného přechodu klientů a metadat | Konkrétní aktivní čtenáři a popsané zbytkové riziko |

## Nasazení a rollback

Lokální balík není produkční release. Po jeho přijetí se backend nasazuje schválenou cestou z kanonického main; web se vydává pro právě zvoleného tenanta. Požadavek se netýká rolloutů dalších `prod/*` větví. Před produkční migrací ověřit aktivaci, aktuální definice a ACL; po ní provést readback a legitimní smoke. Při regresi opravit konkrétní povolenou cestu, ne plošně obnovit anonymní práva nebo NULL bypass.

## Dokončení a zbytková rizika

- [x] Všechny čtyři NULL cesty jsou opravené v kanonických zdrojích i migraci.
- [x] HTML oprava zachovává doložené formátování a blokuje skutečné payloady.
- [x] Vybraná citlivá RPC mají ověřenou matici oprávnění a žádný retained overload neobchází ochranu.
- [x] Nové testy a dotčené integrační scénáře projdou na izolované databázi po migraci.
- [x] Frontend testy, build a izolovaný smoke projdou; dočasné procesy jsou uklizené.
- [x] Audit a tento plán uvádějí přesný stav nasazení a nedokončené samostatné migrace.

Zbytková práce po tomto balíku: veřejné participant UUID vyžadují převod klientských count čtenářů; soukromé soubory vyžadují klasifikaci a vlastnická metadata; pozvánky vyžadují kompatibilní přechod na jednorázový login; CSP vyžaduje ověření embed a editorových potřeb. Tyto práce nejsou tiše označené za opravené tímto balíkem.

## Výsledek provedení

Balík je v kanonických zdrojích a `supabase/migrations/20261009120000_security_rpc_authorization.sql`. Migrace prošla nad čistou baseline se všemi předchozími migracemi i opakovaným použitím. Nový Node/pg test místo původně plánovaného SQL souboru ověřuje skutečné role a vedlejší efekty v transakci; obsahuje 28 úspěšných kontrol. Sedm SQL sad prošlo: objektová autorizace, dvě sady šablon, companions a tři platební integrační scénáře. Frontend: 40 cílených testů, Vite build a npm audit produkčních závislostí s 0 nálezy. Izolovaný Chrome potvrdil nulové vykonání XSS, odstraněný nebezpečný href, zachované formátování a funkční checkbox.

Opakovatelné lokální DB ověření: `bash database/tests/security/run-local.sh`. Launcher odmítne obsazený taskový projekt, vytvoří vlastní DB na portu 55562 a při ukončení ji uklidí. Nepoužívá produkční URL ani sdílenou testovací DB. Historický auditní reproduktor očekává zranitelný stav a není regresní bránou pro opravenou větev.

Při dohledání volajících byl také uzavřen nepoužívaný `process_token_register`: zůstává dostupný servisní roli, nikoli anonymnímu nebo běžnému klientovi. V Dart/JS/Edge nebyl nalezen aktivní volající. Oba bankovní overloady zůstávají; odstraněn byl nejednoznačný výchozí argument dvouparametrové varianty. Titulky polí se nově zobrazují jako text; rich HTML patří do popisů.

Dočasná DB a izolovaný browser byly uklizeny. Produkční backend, tenantové releasy, commit ani push nebyly provedeny. Dodatečný kandidát `update_email_template` v organizační větvi vyžaduje ověření skutečně nasazené definice a oprávnění; není zde označen za potvrzený ani opravený nález.

## Rozšíření na úplné dokončení

Dne 2026-10-09 uživatel požádal pokračovat bez odkladu. Rozšířený balík vznikl v čistém worktree z aktuálního `origin/main` (výchozí SHA `f6cc023426c74f64707209328fd1b8176204901c`), bez ostatních rozpracovaných změn původní větve.

- Potvrzená organizační větev `update_email_template` dovolovala anonymní zápis i v produkčním katalogu. Nová migrace `20261009131500` zavádí objektová oprávnění, skutečnou hierarchii a explicitní granty. Regrese pokrývá odmítnutí i povolený zápis.
- `20261009133000` přidává anonymní agregované počty bez UUID; všechny čtyři přímé Flutter čtečky jsou převedeny. Veřejné čtení staré tabulky zůstává do přechodu instalovaných klientů. Přesný gate: [attendance cutover](../operations/event-attendance-privacy-cutover-2026-10-09.md).
- `20261009143000` přidává samostatné hashované přihlašovací kódy s limitem 10 minut, 5 pokusů a atomickým jednorázovým použitím. Nová registrace aktualizovaného klienta opt-in používá v2; běžná hesla a legacy klienti zůstávají funkční. V2 se při selhání vydání session nesmí opakovaně použít; uživatel potřebuje novou pozvánku nebo reset hesla. Staré slabé password kódy dosud nejsou odvolané. Edge endpoint je v produkčním allowlistu.
- Image worker odmítá privátní AKH upload do veřejného bucketu, sjednocuje kontrolu klíčů a dává `no-store` privátním datům/podepsaným URL. Stávající projektové editorové sdílení zůstává; [vlastnické předpoklady](../../workers/image-worker/SECURITY.md) nelze nahradit odhadem starých klíčů.
- Web dostává kompatibilní základ CSP `base-uri 'self'; object-src 'none'` a `nosniff`. Nejde o dokončenou striktní script CSP.

Ověření rozšířeného balíku: 28 scan/attendance kontrol; 11 SQL sad v čisté oddělené DB včetně skutečné v2 registrace pod service rolí, nezměněné legacy registrace a nezávislosti kódu na hesle; 40 frontend testů a build; 34 worker testů a typecheck; 14 Deno testů. Cílená Dart analýza nemá chyby ani varování, pouze 21 existujících info upozornění.

Zbývající dokončovací podmínky, nikoli hotové opravy:

- [ ] Povinné jedno schvalující review chráněného main, merge a ověřené nasazení backendu/webu/workera. Ochranu neobcházet admin pushem nebo neschváleným produkčním SQL.
- [ ] Aktualizace podporovaných mobilních klientů a evidence ukončení legacy readers před odebráním UUID politiky. Samotný web release mobilní aplikace neaktualizuje.
- [ ] Přechod příjemců pozvánek na v2 a cílené odvolání historických slabých hesel s obnovou účtů. Bez evidence klientské kompatibility by okamžitá změna porušila zadání zachovat funkčnost.
- [ ] Autoritativní klasifikace skutečně soukromých souborů a vlastníků před zužováním dokumentovaného projektového sdílení.

Po review: aplikovat čtyři přesné migrace z main atomicky s ledgerem na ověřený canonical backend, vydat Function bundle s novým endpointem, aktualizovat pouze tenant festapp a worker přes jejich schválené cesty. Ověřit migrační ledger, legitimní readback a skutečnou verzi nasazení. Nenahrazovat produkční smoke fixtures nad zákaznickými daty.

Před publikací byl balík rebased na `c19e10d7b` (upstream změna pouze news page a jejího testu, bez překryvu bezpečnostních změn).

## GitHub security audit

Na výslovnou navazující žádost byl zkontrolován i GitHub security audit: 53 otevřených Dependabot upozornění (19 high, 16 medium, 18 low). Všechna jsou pokryta opravenými verzemi v PR, navíc byl odstraněn jeden další high nález NanoID z lokálního npm auditu. Sedm npm projektů má audit 0 včetně dev dependencies. Podporované aktualizace Wrangler/Fastlane prošly cílenými testy, typechecky, web buildem, čtyřmi Wrangler dry-run balíčky a izolovanou kontrolou Fastlane. Nebyl spuštěn worker deploy, migrace obrázků ani mobile release.

[Přesná mapa všech 53 upozornění a výsledky](../operations/github-security-alerts-2026-10-09.md) odlišuje opravený PR od dosud otevřených upozornění na main. Secret scanning, push protection a automatické Dependabot security updates jsou na GitHubu vypnuté; code scanning neposkytl analýzu. Nastavení GitHubu nebylo při auditu měněno.

První migrace přenechává BEGIN/COMMIT release wrapperu, aby její změny a zápis do ledgeru byly atomické. Neobsahuje vnitřní COMMIT, který by obalový ledger transakční kontrakt předčasně ukončil.
