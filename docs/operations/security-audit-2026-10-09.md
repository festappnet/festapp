# Bezpečnostní audit Festapp

Druhý průchod potvrdil závažné chyby NULL autorizace a XSS. Dotčené SQL funkce jsou nasazené a mají anonymní EXECUTE granty; jejich zneužití bylo reprodukováno pouze v izolované lokální databázi. Dva původní předpoklady o přímých zápisech jsou vyvrácené: produkční granty chrání účast i identitu profilu. Soukromé soubory používají dokumentovaný společný přístup editorů, jehož změna musí respektovat legitimní sdílení.

Datum: 2026-10-09. Větev: `feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`, s existujícími necommitnutými změnami. Při samotném auditu nebyl aplikační kód ani produkční data změněny. Následně uživatel autorizoval lokální implementaci; její aktuální stav je níže. Původní nálezy a evidence dále popisují stav před opravou.

## Stav navazující opravy

Lokálně opraveny NULL bypassy scan/attendance, XSS formulářů a objektová autorizace vybraných RPC, včetně jejich grantů a bankovních overloadů. Připravena migrace `20261009120000_security_rpc_authorization.sql`. Podrobnosti a zbytkové úkoly jsou v [provedeném plánu](../plans/security-remediation-plan-2026-10-09.md).

Ověření: 28 skutečných scan/attendance kontrol, 11 SQL sad v oddělené DB, 40 frontend testů, Vite build a izolovaný Chrome smoke prošly. Zachovány platné tajné scan kódy, oprávněné role, companions, vlastní přihlášení na otevřenou akci a platební scénáře. Produkční npm audit web klienta po cíleném dependency update hlásí 0 nálezů. Rozšířený balík také chrání zápis emailových šablon, obsahuje přechod na agregační counts a expirované kódy v2, worker opravy a základní CSP. Produkce dosud aktualizována nebyla; veřejné participant UUID, login pozvánky a souborové sdílení potřebují samostatné kompatibilní přechody.

## Rozsah a meze ověření

Průchod zahrnoval kanonické SQL, navazující migrace, RLS, vybrané autentizační a privilegované Edge Functions, veřejné formuláře, image worker, veřejnou synchronizaci a produkční balení funkcí. Lokální ověření přes JSDOM doložilo dvě HTML slabiny. Audit produkčních npm závislostí proběhl pro `web_client`, `image-worker` a `sync-publisher`; hledání tajných klíčů pokrylo vybrané známé vzory v současných verzovaných textových souborech.

Produkční katalog byl při double-checku ověřen read-only přes existující SSH s explicitní cestou k projektovému proxy skriptu. Nebyla změněna konfigurace SSH ani přístupová oprávnění. Cíl odpovídá `prod/festapp`, dokumentu `live.festapp.net/backend-activation.json`, tenantovi `festapp`, generaci 1, organizaci 1, očekávanému hostname a aktivnímu runtime názvu databáze. Původní nesoulad vyplýval z použití generického `WEB_LINK` pracovní větve pro jiného tenanta, nikoli z prokázaného split brain.

Vlastní dočasná Supabase/PostgreSQL databáze byla postavena z baseline a všech migrací do `20261006204500`. Definice všech 11 ověřovaných funkcí jsou přesně stejné jako v produkčním katalogu. Proběhlo 51 SQL kontrol, z toho 19 kontrol minimálního návrhu opravy a 3 existující integrační scénáře. Reálný headless Chrome potvrdil automatické vykonání škodlivého event handleru i vykonání sanitizovaného JavaScript odkazu po kliknutí. Čtyři testy skutečného image-worker routeru ověřily autentizační odmítnutí a sdílený přístup; Supabase a R2 závislosti v těchto worker testech byly mockované.

Produkční dotazy načítaly pouze identitu a katalog, nikoli zákaznické řádky. Kontrolní veřejný HTTP požadavek na getter s neexistujícím ID dostal ne-JSON HTTP 403. Tato odpověď neprokazuje ochranu RPC ani její veřejnou dostupnost pro ostatní klienty; negativní test nesmí libovolnou síťovou chybu vydávat za úspěšnou autorizaci. Exploity nebyly spuštěny nad produkčními objednávkami.

Kompaktní výsledky a SHA256 definic jsou v [evidenci double-checku](security-audit-2026-10-09-evidence.json). Aktuální regresní ověření spouští `bash database/tests/security/run-local.sh`. Historický [launcher](security-audit-2026-10-09-run-local.sh) a [diagnostika](security-audit-2026-10-09-repro.mjs) zachycují stav před migrací `20261009120000`; jejich očekávání útoků na opravené větvi záměrně neprojdou. Původní evidence zůstává zachována.

Jde o prioritizovaný audit zdrojů, nikoli úplný penetrační test. Nepokrývá celý Git history, všechny závislosti Flutter/Deno, běžící limity Auth, firewall, obnovu záloh ani dostupnost všech RPC z veřejné sítě. Úspěšné cílené testy nejsou zárukou bezchybnosti celé aplikace po budoucích změnách.

## Závažné nálezy

### 1 Skenování propustí chybějící tajný kód

**Vysoká závažnost. Nasazená definice a anonymní EXECUTE potvrzené katalogem; oba exploity reprodukované lokálně pod skutečnou rolí anon.**

- `database/functions/eshop_orders/scan_ticket.sql:124`: `IF scanned_code != expected_scan_code THEN`.
- `database/functions/eshop_orders/update_ticket_to_used.sql:69`: `IF scan_code != expected_scan_code THEN`.

Při předání JSON `null` vznikne SQL `NULL`. Porovnání s očekávaným kódem vrátí `NULL` a odmítací větev `IF` se neprovede. Toto chování odpovídá [sémantice porovnání PostgreSQL](https://www.postgresql.org/docs/15/functions-comparison.html) a [podmínkám PL/pgSQL](https://www.postgresql.org/docs/15/plpgsql-control-structures.html). První funkce při znalosti symbolu vstupenky pokračuje k načtení objednávky a souvisejících údajů. Druhá při znalosti číselného ID pokračuje k označení vstupenky jako použité. UUID fallback první funkce má samostatnou kontrolu přes rovnost; nález se týká cesty přes symbol vstupenky.

Oprava: odmítnout chybějící/prázdný kód a použít `IS DISTINCT FROM`. Přidat skutečné databázové testy s rolí `anon`, nesprávným kódem a `NULL`. V `reset_password_via_scan` už stejný problém řeší migrace `20260906140000_reject_null_scan_password_reset_code.sql`; tato oprava se na dvě uvedené funkce nevztahuje.

### 2 Starší registrace na program obchází kontrolu identity

**Vysoká závažnost. Nasazená definice a anonymní EXECUTE potvrzené; anonymní registrace i odhlášení existujícího účastníka reprodukované lokálně.**

- `database/functions/events/sign_user_to_event.sql:53`.
- `database/functions/events/sign_user_out_of_event.sql:15`.

Obě funkce používají `IF auth.uid() <> usr THEN`. U anonymního volajícího je `auth.uid()` rovno `NULL`, takže se kontrola cizí identity přeskočí. Při ostatních splněných podmínkách může volající zapsat nebo zrušit účast jiného uživatele. Aktuální SQL zdroj registrace navíc volá interní přidání uživatele před kontrolou aktéra. Nasazená definice místo interního helperu volá autorizovanou fasádu `add_user_to_occasion`: druhý průchod ověřil, že nepovolené přidání nového uživatele vyvolá SQL chybu a nevytvoří členství. Původní tvrzení o tomto vedlejším zápisu tedy neplatí pro ověřenou nasazenou cestu. NULL bypass u již existujícího účastníka přesto zůstává.

Flutter tyto názvy stále volá v `lib/components/schedule/db_events.dart:285` a `:768`. Novější `set_event_attendance_client_sync_v1` explicitně odmítá chybějícího aktéra, ale existence této bezpečnější funkce nechrání starší RPC.

Oprava: ověřit identitu a oprávnění před prvním zápisem, odmítnout anonymní volání a převést starší vstupy na autorizovanou kanonickou cestu. Ověřit současné granty a negativní testy mezi uživateli a tenanty.

### 3 Formuláře vykreslují škodlivé HTML

**Vysoká závažnost. Potvrzené automatické vykonání event handleru v izolovaném headless Chromu se skutečným modulem projektu.**

`web_client/src/components/forms/fields/option_builder_helper.js:26`, `:36`, `:91` a `:132` vkládají názvy a popisy polí či produktů přímo do `innerHTML`. Podobná místa obsahují date, checkbox, ID-document a ticket field builders. Veřejné RPC `get_form_by_link` tyto hodnoty vrací z databáze bez HTML sanitizace.

Původní JSDOM kontrola zachování `onerror` byla rozšířena na skutečný Chrome. `buildFieldLabel` dostal poškozený data obrázek s handlerem měnícím pouze lokální marker; prohlížeč ho spustil automaticky bez ručního `eval`. Modely pole a produktu hodnoty před předáním builderu neescapují. Pro uložený útok musí útočník umět změnit příslušný obsah, například přes kompromitovaný účet editora. Dopad může zahrnout změnu platebních instrukcí, čtení údajů vyplňovaných do formuláře a zneužití přihlášené relace na stejném originu.

Oprava: názvy vkládat přes `textContent` nebo escapované šablony; povolené rich HTML vždy sanitizovat jednotnou ověřenou knihovnou. [OWASP doporučuje pro HTML sanitizaci DOMPurify](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html).

### 4 Vlastní HTML sanitizér propouští JavaScript URL

**Vysoká závažnost. Bypass i vykonání JavaScript URL po skutečném kliknutí potvrzené v headless Chromu. Produkční CSP může ovlivnit vykonání.**

`web_client/src/utils/html.js:83` odmítá pouze řetězce začínající doslovným `javascript:` po `trim().toLowerCase()`. Vstup `<a href="java&#x09;script:window.__auditMarker=1">probe</a>` přežije sanitizaci. Po vložení výsledku má DOM odkaz protokol `javascript:`: parser URL tabulátor odstraní, vlastní filtr nikoli.

Tím jsou dotčená i místa, která `sanitizeHtml` používají, například hlavička a popis formuláře. Oprava: nahradit vlastní filtr udržovaným sanitizérem s bezpečnou politikou URL a přidat regresní test obfuskovaného schématu.

### 5 Soukromé soubory nejsou omezené na akci vlastníka

**Potvrzené chování sdíleného editorového kontraktu; závažnost závisí na citlivosti souborů a zamýšleném sdílení. Není automaticky prokázanou chybou oproti specifikaci.**

`workers/image-worker/src/serve-private.ts:62` a `workers/image-worker/src/presigned.ts:53` ověřují `checkIsEditorOnAnyOccasion`, nikoli oprávnění k souboru. Následně přijmou libovolný syntakticky platný klíč `private/...` v příslušném projektovém bucketu. Editor jedné akce tak při znalosti klíče získá soubor jiné akce sdílející tento bucket. Presign navíc dovoluje přístupový odkaz až na 7 dní. Náhodný název souboru není náhradou autorizace.

Stejně široký model má `database/policies/03_storage_buckets.sql` pro `editor-files`; tato starší Storage cesta vyžaduje ověření, zda ještě obsahuje aktivní data. Projektové buckety se rozlišují, ale uvnitř projektu chybí kontrola vlastníka objektu.

Dokumentace `docs/backend/image_worker.md` výslovně popisuje současný projektový kontrakt editorů. Čtyři testy ověřily 401 bez tokenu, 403 bez role a přístup i presign libovolného `private/` klíče s globální editorovou rolí. Supabase odpověď a R2 objekt byly mockované; nešlo o čtení reálného cizího souboru.

Bezpečná náprava: nejprve oddělit projektové sdílené soubory od skutečně soukromých souborů akce, určit vlastníka a migrovat metadata. Teprve u druhé skupiny vynutit vlastnickou kontrolu při čtení a podepisování. Plošný přechod všech `private/` klíčů na occasion kontrolu by mohl rozbít současné sdílení a exporty.

### 6 Privilegované RPC nemají vlastní kontrolu volajícího

**Vysoká závažnost u členství a osobních údajů. Nasazené ACL dovolují anon; skutečné neautorizované operace potvrzené v izolované databázi.**

- `database/functions/users/add_user_to_unit.sql:1`: kontroluje shodu organizací cílového uživatele a jednotky, ale ne oprávnění volajícího měnit členství.
- `database/functions/eshop_bank_accounts/get_bank_account_users.sql:1`: vrací UUID, email, jméno a bankovní role podle ID účtu bez ověření přístupu k účtu. Starší jednoparametrovou variantu vytváří také migrace `20260113165000_add_bank_accounts_management.sql:137`.
- `database/functions/users/get_user_id_by_email.sql:1` a `get_last_sign_in_at.sql:1`: zpřístupňují informace z `auth.users` bez kontroly účelu a vlastníka.
- `database/functions/others/get_entity_email_templates.sql:1`: původní tvrzení bylo příliš široké. Occasion větev chrání volaný `get_all_email_templates`; anonymní pokus byl odmítnut. Unit větev tuto kontrolu nemá a anonymně vrací její metadata a šablony. Nález se vztahuje na unit cestu, nikoli plošně na obě varianty.

Tyto funkce jsou `SECURITY DEFINER` a jejich zdroj neobsahuje cílený `REVOKE`. Katalog potvrzuje anonymní granty všech uvedených funkcí. Lokální test vytvořil členství bez přihlášení, přečetl bankovní uživatele dvouparametrovou variantou a ověřil email/last-sign-in lookup. Jednoparametrové SQL volání `get_bank_account_users` je při přítomnosti overloadu s defaultem nejednoznačné (`42725`); bezpečnější situaci nezajišťuje, protože dvouparametrová cesta funguje. Flutter používá právě oba parametry. PostgreSQL standardně přiděluje novým funkcím EXECUTE pro `PUBLIC`; `CREATE OR REPLACE` zachovává existující oprávnění. [Dokumentace PostgreSQL](https://www.postgresql.org/docs/current/sql-createfunction.html).

Oprava: explicitní autorizace podle cílového objektu, nejmenší nutné granty a omezení interních helperů na servisní roli. `delete_unit_user` nebyl zařazen jako nový nález: novější migrace ho přesměrovává přes autorizovanou synchronizační funkci a omezuje interní variantu.

## Další rizika k ověření a opravě

### 7 Přímý zápis účasti je zakázaný ale vztahy jsou veřejně čitelné

**Původní hypotéza obejití pravidel přímým zápisem byla vyvrácena. Veřejné čtení vztahů je potvrzené; jeho přípustnost závisí na typu programu.**

Produkční granty `authenticated` zakazují INSERT, UPDATE i DELETE na `event_users`. Pokus o přímý INSERT vlastního řádku v identické lokální databázi skončil `42501`. Permisivní RLS policy tedy sama o sobě nevytváří přímou zapisovací cestu. Kvůli této hypotéze nejsou potřeba změny klientských zápisů.

Naopak `anon` má SELECT a policy `USING (true)`; lokální anonymní čtení skutečně vrátilo fixture UUID a event ID. Veřejná synchronizační projekce již poskytuje souhrnné `participantCount`, `savedCount` a `remainingCapacity` místo jednotlivých UUID (`20260802234000_client_sync_v1_expansion.sql:4718`). Před omezením přímého SELECT je nutné najít všechny aktivní čtenáře a zachovat tuto souhrnnou funkcionalitu. Nepředpokládat, že jmenné vztahy u poradenství mají být veřejné.

### 8 Chráněné sloupce profilu nelze přímo měnit

**Vyvrácený nález.**

Produkční `authenticated` nemá UPDATE pro `organization`, `email_readonly` ani `email_delivery`. Přímá změna vlastní organizace byla v identické lokální databázi odmítnuta (`42501`). Samotná policy kontrolující vlastní UUID k úspěšnému UPDATE nestačí. Tato cesta nevyžaduje novou opravu; další profile RPC je stále nutné posuzovat samostatně.

### 9 Přihlašovací kódy se ukládají jako skutečná hesla

**Střední závažnost s možným vysokým dopadem při nedostatečném omezení přihlašovacích pokusů.**

`supabase/functions/register/index.ts:93` a `send-sign-in-code/index.ts:63` generují šest číslic přes `Math.random()`. `database/functions/emails/email_domain.sql:143` a `database/functions/users/reset_user_password.sql` zapisují výsledný kód jako bcrypt heslo do `auth.users`. Expirace emailové zprávy neznamená expiraci takového hesla a běžné přihlášení z něj neudělá jednorázový token. Přímé SQL nastavování hesla také obejde případnou politiku kvality hesel v GoTrue.

Oprava: použít skutečný jednorázový a expirovaný přihlašovací mechanismus, kryptografický generátor a limity pokusů. Ověřit v běžícím Auth životnost kódu a revokaci relací při resetu. Samotné nahrazení `Math.random()` nevyřeší chybějící jednorázovost.

### 10 Frontend nemá viditelnou ochranu CSP

**Střední závažnost jako chybějící další obranná vrstva.**

`web/_headers` a `web_client/public/_headers` neobsahují CSP. HEAD odpověď `https://vstupenky.online` při prvním průchodu a `https://live.festapp.net` při double-checku neobsahovala `Content-Security-Policy`, `X-Frame-Options` ani HSTS; měla `X-Content-Type-Options: nosniff` a `Referrer-Policy: strict-origin-when-cross-origin`. Toto pozorování se vztahuje pouze k testované odpovědi, ne ke všem cestám a tenantům. API Caddy má vlastní bezpečnostní hlavičky, což samo nechrání frontend.

Oprava: zavést kompatibilní CSP nejprve v režimu reportování, následně vynucovat alespoň skripty a `frame-ancestors`; doplnit HSTS po ověření domén. CSP nenahrazuje opravu XSS.

### 11 Zranitelná npm závislost

**Registry uvádí vysokou závažnost; praktický dopad na veřejné formuláře nebyl prokázán.**

`npm audit --omit=dev --json` v `web_client` hlásí jednu zranitelnou tranzitivní závislost `brace-expansion` s několika DoS advisories. [Advisory pro nekontrolovanou rekurzi](https://github.com/advisories/GHSA-qhr7-859c-m2p7). `image-worker` a `sync-publisher` při stejném auditu nehlásily zranitelnosti. Lockfile obsahuje `brace-expansion` 5.0.9 přes `glob`/`minimatch`. Scoped kontrola importů našla `glob` v databázových testovacích skriptech, nikoli ve `web_client/src`. Nález proto zatím znamená závislost nástrojů, ne prokázaný vzdálený DoS veřejných formulářů. Aktualizace lockfile je vhodná, ale má nižší prioritu než potvrzené aplikační exploity.

### 12 Starší migrátor může falešně potvrdit bezpečnostní migraci

**Střední závažnost; aktivní produkční použití nebylo prokázáno.**

`automation/sync_db.js` označuje migraci jako aplikovanou i po chybě rozpoznané širokým porovnáním textu `already exists` nebo `not unique`. Pozdější bezpečnostní příkazy daného souboru nemusely proběhnout. Současné produkční release postupy používají jiné explicitní brány, takže nejde o prokázanou chybu posledního nasazení.

Oprava: starší migrátor vyřadit z použitelných cest nebo zajistit atomické provedení a nezapisovat úspěch při chybě. Ledger nesmí být jediným důkazem nasazených grantů.

## Již přítomné ochrany

Google broker ověřuje podpis, issuer, audience, nonce a časové claims. Reset hesla přes scan už odmítá `NULL` a chrání privilegované účty. Obnova hesla přes email má jednotnou odpověď a serverové limity. HTTP image fetch kontroluje oprávnění a odděluje externí fetch přes `safeFetch`. BankSync používá raw-body HMAC a idempotentní databázový příjem. Produkční bundle explicitně vylučuje `instance-install`, takže jeho neomezené bootstrap chování nebylo označeno za veřejnou produkční SQL injekci.

Omezený scan známých vzorů tajných klíčů neodhalil potvrzený únik. Jediný vzor podobný AWS access key byl falešný nález uvnitř vložených fontových dat. Tento výsledek nenahrazuje audit historie a provozních tajemství.

## Náprava se zachováním funkčnosti

Minimální NULL oprava byla ověřena pouze v izolované transakci. Pro scan nahradila nerovnost za `IS DISTINCT FROM`; anonymní scan s platným tajným kódem zůstal funkční. U účastí odmítla chybějícího aktéra a přesunula stávající kontrolu před přidávání členství. Při platném přihlášení zachovala vlastníka, editora i zapnuté companions. Po dokončení byl celý návrh vrácen přes ROLLBACK. Toto není hotová nasaditelná migrace.

| Oblast | Co musí bezpečnostní oprava zachovat | Co musí odmítnout | Stav ověření |
| --- | --- | --- | --- |
| Scan a použití vstupenky | Platný tajný kód i bez uživatelského přihlášení, obsah objednávky a deposit info | NULL a nesprávný kód, žádná změna stavu při odmítnutí | Minimální návrh lokálně ověřen |
| Účast na programu | Vlastní přihlášení, editor, companion při zapnuté funkci, dosavadní kódy pro duplicitu a kapacitu | Anonymní změna cizí účasti a cizí aktér před prvním zápisem | Minimální návrh lokálně ověřen |
| Platby a scan | Záloha, doplatek na místě a přeplatek | Nové chyby v existujících finančních scénářích | Pod návrhem prošly `full_deposit_flow`, `on_site_surcharge_flow`, `overpayment_flow` |
| HTML | Formátované popisy, bezpečné odkazy a obrázky, povinná pole, checkboxy, produktové ceny | Event handlery a obfuskovaná JavaScript URL | Exploit a současný běžný checkbox ověřeny; nový sanitizér ještě neimplementován |
| Bankovní a uživatelské RPC | Stávající Flutter názvy a parametry, přístup oprávněných editorů/adminů podle objektu | Anonymní přístup a přístup mimo oprávněný účet/tenant | Exploity potvrzeny; kompletní matice oprávnění je podmínkou implementace |
| Soukromé soubory | Výslovně projektové sdílení, exporty a potřebné presign odkazy | Přístup k souboru s occasion/tenant soukromím bez oprávnění | Nejdříve klasifikace souborů a metadata; žádná plošná změna policy |
| Přihlašovací pozvánky | Existující uživatelé a klienti, obnova hesla a doručování | Opakované použití či použití po expiraci u mechanismu označeného jako jednorázový | Vyžaduje samostatný migrační kontrakt; žádná náhlá změna loginu |

Pořadí implementace: NULL kontroly a jejich regresní testy, HTML sanitizace s testy zachování obsahu, objektová autorizace bankovních a uživatelských RPC. Čtení účastníků a vlastnictví souborů zpřísňovat až po mapování aktivních čtenářů a sdílených případů. Chráněné profilové sloupce a přímé zápisy účastí už nové restrikce nepotřebují.

Před nasazením musí být oprava zapsaná do kanonických zdrojů i migrace, projít běžnými cílenými kontrolami a smoke testem skutečného klienta. Produkční ověření po nasazení musí zkontrolovat definice a granty, nikoli jen ledger. Zde ověřené funkční scénáře nezaručují pokrytí každé cesty celé aplikace.
