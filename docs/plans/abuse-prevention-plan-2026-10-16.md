# Festapp: ochrana proti zneužití a fair use

Datum: 2026-10-16
Stav: Lokální implementace existuje; provozní aktivace a zbývající důkazy nejsou dokončené
Ověření: standard - bezpečnost, veřejné kontrakty, souběh a finanční dopady

Aktualizace po implementaci a sjednocení 2026-10-16: lokální realizace tohoto návrhu již existuje. Aktuální stav a výsledky vlastní [implementační přehled](../security/abuse-implementation-2026-10-16.md); následující návrhové formulace zachycují zadání, nikoli tvrzení, že se vše má implementovat znovu. Produkční aktivace není doložena. [Sjednocení bezpečnostních prací](security-work-reconciliation-2026-10-16.md) rozděluje vlastnictví: tento balík vlastní existující aplikační budgety/adaptéry, [serverový plán](server-security-remediation-plan-2026-10-16.md) doplní nevyřešená RPC/ACL/RLS a provozní ochrany. Nepřidávat druhý limiter; retirement neaktivního SQL importeru zachovat. Kritické RPC opravy nemusí čekat na aktivaci tohoto balíku.

Revize 2026-10-16: druhý průchod pokrytím a architekturou. Upřesněny odpovědnosti modulů, transakční sémantika, ochrana samotného limiteru a nezávislá matice bezpečnostních požadavků. Jde o revizi návrhu, ne certifikaci bezpečnosti implementace.

Architektonická revize proti kódu 2026-10-16: ověřeny create/finalize/duplicate, draft bootstrap s rollbackem, legacy facade, registrace s automatickou jednotkou, integrační writer, image copy a e-mailové zámky. Výsledek: návrh sedí jako rozšíření existujících SQL commandů, nikoli jako plošný middleware; konkrétní místa zapojení a výjimky jsou níže. Runtime a skutečné granty nadále nejsou ověřené.

Poslední revize 2026-10-16: explicitně oddělena identita krátkodobého/denního počítadla, omezeny možnosti overrides, ošetřena kapacita pro již přijaté placené závazky a doplněn postup rychlé realizace bez rozšiřování frameworku. Následná implementace už nevychází z další obecné architektonické studie; nové rozhodování vyžaduje konkrétní nový důkaz nebo překážku.

## Výsledek a hranice zadání

Každá externě dostupná operace má doloženou autorizaci, omezení spotřeby, vlastníka a ověření proti obcházení. Útočník nesmí snadno rozesílat poštu cizím lidem, vyčerpat společnou kvótu, blokovat místa, hádat přihlašovací údaje, získat cizí data nebo vyvolávat neomezené placené operace. Legitimní registrace, prodej, odbavení a doručení zaplacených vstupenek musí fungovat i při špičce.

Zadání nyní autorizuje přípravu plánu. Tento dokument neautorizuje implementaci, produkční zásahy, penetrační či zátěžové testování produkce, odesílání zpráv, commit ani push. Následná implementace se provádí až na pokyn uživatele. Úplnost se dokládá pokrytím vstupů a testy; nulové bezpečnostní riziko nelze slíbit.

Rozsah zahrnuje Flutter i JS klienty, Edge Functions, přímé REST/RPC, tabulky/views/RLS/granty, Auth, Storage, Workers/R2/sync, webhooky, cron, administraci, exporty/PDF, integrace, infrastrukturu a dodavatelský řetězec. Zahrnuje anonymního návštěvníka, přihlášeného útočníka, zneužitého editora i kompromitovanou integraci. Frontendové omezení, CORS nebo skrytí tlačítka nejsou serverová ochrana.

Sdílený backend a jeho veřejné domény se inventarizují jako celek. To není povolení vydat všechny tenanty nebo mobilní aplikace. Konkrétní tenant webového vydání se určí před releasem; aktuální pracovní větev ho neurčuje.

## Podklady a jistota závěrů

Průzkum je pouze lokální, bez dotazů do produkce. Výchozí HEAD `eb2304724`, větev `feat/occasion-setup-wizard-20261007`. Pracovní strom obsahuje mnoho rozpracovaných změn včetně bezpečnostních a e-mailových souborů. Závěry proto popisují pracovní zdroje, nikoli nutně main nebo nasazenou verzi. Před realizací zaznamenat cílový main SHA a změny relevantních podkladů; cizí práci nepřepisovat.

| Potvrzený fakt ve zdrojích | Důkaz | Důsledek |
| --- | --- | --- |
| Všechny aplikační e-maily mají používat jedinou frontu a jediného odesílatele | `docs/architecture/ai_context.md`, `docs/backend/edge_functions.md`, `database/functions/emails/email_schema.sql`, `email_queue.sql`, `supabase/functions/process-email-queue/` | Rozšířit existující bránu; nevytvářet druhou frontu ani sender |
| Odesílání má account/region kapacitu, pauzu, klouzavých 24 h, rezervy a fencing; výběr zpráv zohledňuje tenanty a prioritu | `public.email_capacity`, `claim_email`, `begin_email_send` v `email_queue.sql` | Ochrana poskytovatele není sama o sobě limit přijímání práce ani prokázaná fair use po tenantovi |
| Reset hesla má persistentní limity 20 požadavků na zdroj a 3 na účet/organizaci za 900 s; při chybě limiteru vrací 503 | `supabase/functions/send-reset-password-link/index.ts`, `consume_password_reset_rate_limit_v1` | Zachovat anti-enumeraci; prověřit důvěryhodnost IP a sdílený rozpočet s jinými cestami |
| QR login používá `Map` v procesu, limit 30/min a zdroj z `x-forwarded-for` | `supabase/functions/exchange-login-qr/index.ts` | Tento čítač není společný napříč instancemi a zanikne restartem; IP trust je k prověření |
| Google login má SQL rate limiter a pozvánkové kódy atomické použití, expiraci a limit 5 pokusů | `database/functions/users/google_auth.sql`, `sign_in_codes.sql` | Nekopírovat další nezávislé počítání; ověřit všechny přihlašovací i legacy cesty |
| Handler registrace připravuje a enqueueuje zprávu; nemá vlastní zjevný limiter na vstupu | `supabase/functions/register/index.ts` -> `enqueue_account_email` | Kandidát k end-to-end prověření; existence ochrany v nižší vrstvě není tímto průzkumem vyloučena |
| Limit počtu vstupenek jedné objednávky je 20 | `database/functions/eshop/ticket_order_limit.sql` | Není to limit počtu objednávek, nezaplacených rezervací nebo identity nakupujícího |
| Výběr místa zapisuje secret a patnáctiminutovou expiraci | `database/functions/eshop/select_spot.sql` | Prověřit převzetí cizího holdu, souběh a nekonečné obnovování; zatím kandidát, ne prokázaný produkční exploit |
| Existují opětovná vydání zákaznických odkazů a čekací listina | `customer-order-access/index.ts`, `waitlist-commands/index.ts`, `database/functions/eshop_waitlist/` | Nové command UUID nesmí obejít limity příjemce nebo logické operace |
| Image worker už omezuje skutečně načtené upload bajty, rozměry a profily | `workers/image-worker/src/upload-policy.ts` | Zachovat ochrany; doplnit rozpočet frekvence, úložiště a výpočtu, ne duplikovat validaci |
| Public sync worker čte cachovaný veřejný head z R2 bez databáze | `workers/sync-worker/src/index.ts`: `handleRequest`, `canonicalCacheKey` | Zachovat levnou CDN/R2 cestu; nepřidávat SQL admission na cache hit |
| Příprava e-mailu může předcházet enqueue a čekání na přijetí polluje stav po 250 ms až 8 s | `supabase/functions/_shared/emailQueueClient.ts`: `prepareAccountEmail`, `enqueueAndAwaitEmail`, `awaitEmailAccepted`; `email_queue.sql`: `enqueue_email`, `wake_email_worker` | Audit zahrne render, polling a wake amplification, ne jen send frekvenci |
| Starší audit výslovně neověřil všechny živé limity, firewall a všechna RPC; některé přechody zůstávaly otevřené | `docs/operations/security-audit-2026-10-09.md`, `docs/plans/security-remediation-plan-2026-10-09.md`, `workers/image-worker/SECURITY.md` | Navázat na jeho nálezy a ověřit aktuální stav; nepřebírat historické tvrzení o nasazení jako dnešní fakt |
| Draft bootstrap volá creator v záměrně rollbackované subtransakci; finalize zapisuje akci přímo přes interní creator | `occasion_setup/drafts.sql`: `build_occasion_setup_configuration`; `occasion_setup/finalize.sql`: `finalize_occasion_setup_draft` | Počet skutečně vzniklých akcí kontrolovat na doménovém commandu, ne bezpodmínečně na každém volání nízkoúrovňového creatoru |
| Registrace i Google flow mohou automaticky založit jednotku | `users/create_user_from_registration.sql`, `users/google_auth.sql` -> `initialize_registration_unit_v1` | Ochrana samotného `create_unit_and_assign_manager` není úplná |
| Synchronizační zdroj obsahuje samostatný service-only INSERT/UPSERT akcí a následné odstraňování položek mimo snapshot | `synchronization/sync_source_via_http.sql` | Prověřit skutečné nasazení a volající; při aktivní cestě chránit i import a nedovolit pruning po neúplném/omezeném snapshotu |
| Legacy create a duplicate delegují na nové commandy, ale generují si čerstvý UUID | `public_links/legacy_writers.sql`, `others/update_occasion.sql`, `others/duplicate_occasion_client_sync_v1.sql` | Umí sdílet quota enforcement; neumějí samy zaručit replay stejného uživatelského úmyslu mezi dvěma HTTP požadavky |

Reprezentativní tok: veřejný klient -> gateway/router -> Edge nebo přímé RPC -> SQL doménová změna a trvalý e-mailový intent -> `claim_email`/příprava -> `begin_email_send` -> provider. Audit musí sledovat obě varianty vstupu a všechny producenty, včetně GoTrue hooku, cron a webhooku.

## Cílové vlastnictví a pravidla

1. **Síťová ochrana:** gateway omezuje objem a velikost požadavků ještě před drahou autentizací, JSON parsováním a DB. Pokrývá Auth, REST/RPC, Storage, Functions i Workers; veřejný origin ani alternativní hostname nesmí umožnit obejití. Nezavádět centrální DB hit pro každý škodlivý paket.
2. **Doménová ochrana:** omezení objednávek, míst, příjemců, exportů a tenantových nákladů vlastní backend příslušné operace. Edge adaptér není jedinou ochranou, pokud lze operaci zavolat přes PostgREST. Doménový stav a rezervace rozpočtu mají atomickou transakční hranici.
3. **Společný mechanismus, konkrétní doménové rozhodnutí:** sdílet úzkou implementaci atomického čerpání časových budgetů, přednostně nad existujícím PostgreSQL pro aplikační operace. Každý doménový modul vlastní své operace, oprávnění, cenu a kapacitní invarianty. Nevytvářet univerzální orchestrátor všech workflow ani nutit různé druhy limitů do jednoho čítače. Síťový limiter zůstává samostatná levná vrstva. Nezavádět Redis ani jinou službu bez doložené potřeby. E-mailový provider gate zůstává samostatným stávajícím vlastníkem account/region kvót.
4. **Důvěryhodný kontext:** actor vychází z ověřeného JWT, tenant/occasion z autorizovaného cílového objektu, nikoli z libovolného body/headeru. IP přijímat pouze ze smluvené proxy, která odstraní podvržené forwarded hlavičky; origin uzavřít proti přímému přístupu. Veřejný anon key ani system secret nejsou neomezená licence ke spotřebě.
5. **Kontrakt rozpočtu:** doménový command ověří actor/tenant/objekt a předá internímu mechanismu pouze serverem vybrané budgety a cenu. Výsledek je allow/defer/deny se stabilním důvodem a retry time. Policy verze slouží auditu; změna konfigurace ani rotace HMAC nesmějí vynulovat spotřebu. Klient neurčuje limit, cenu ani svou roli. Interní rate RPC nejsou veřejným rozhraním pro skládání operací; jejich granty vycházejí z konkrétního execution contextu. Service entrypoint je service-only, veřejný doménový RPC zachová vlastní autorizaci. Použít explicitní granty, NULL-safe ověření a `search_path = public, extensions`.
6. **Souběh a opakování:** atomické čerpání všech příslušných budgetů, stabilní pořadí zámků, žádné čekání na síť pod DB zámkem. Retry stejné dokončené operace nevyvolá nový side effect; každý HTTP pokus stále stojí síťový rozpočet. Nové commandId samo neobnoví recipient/actor budget. Neúspěšné ověření musí zapsat pokus i při následném odmítnutí; výjimka a rollback čítače nesmí obnovit počet pokusů.
7. **Chování při poruše:** nedostupný limiter zastaví nové citlivé a nákladné požadavky kontrolovanou chybou, ne neomezeným fallbackem. Již přijaté placené závazky zůstávají trvalé a obnovitelné. Každá výjimka pro levné veřejné čtení má explicitní omezení a důvod.
8. **Dostupnost:** omezení podle IP je hrubý signál, nikoli jediná identita. Sdílená Wi-Fi/NAT, IPv6, více instancí, restart a více účtů/tenantů patří do návrhu. Nedovolit trvalé uzamčení oběti pouhým zadáváním jejího e-mailu; přidat krátké cooldowny a obnovitelnou cestu pro legitimního držitele.
9. **Pozorovatelnost:** rozhodnutí, backlog, nejstarší čekání, spotřeba tenantů, odklady, provider chyby a limiter outage mají metriky a alerty bez tokenů, adres nebo obsahu zpráv. Klíče příjemců/IP ukládat pseudonymizovaně pomocí serverového HMAC, s verzí klíče, retencí a omezenou kardinalitou. Samotný prostý hash e-mailu nezaručuje anonymitu.
10. **Regrese:** nová veřejná operace bez deklarované politiky nebo zdůvodněné výjimky neprojde kontrolou inventáře. Limit nenahrazuje opravu autorizace, XSS, SSRF ani ochranu tajemství.

## Architektonické rozhodnutí a kritéria čistého návrhu

Preferovaný návrh je rozšíření existujících doménových commandů a e-mailové fronty o malý sdílený mechanismus budgetů. Alternativa „middleware na všechno“ nestačí pro přímé RPC a doménové transakce; samostatná centrální abuse služba by nyní přidala síťovou závislost a distribuované transakce bez prokázaného přínosu. Doménové limity se nesmějí přestěhovat do transportních handlerů jen kvůli sjednocení kódu.

**Produktový scope:** `Organization` je tenant/doména, `Unit` skutečný pořadatel a `Occasion` konkrétní akce. Přidat pořadatelský budget podle `Unit`, nikoli zaměňovat pořadatele za celý tenant. Příslušná hierarchie je actor -> Unit -> případně Occasion -> Organization -> skutečně společná provider kapacita. Scope se odvozují z cílového objektu a vyhodnocují společně podle druhu operace. Přepnutí Unit nevrací actor budget; více editorů jedné Unit sdílí pořadatelský budget. Překročení budgetu jednoho pořadatele nezastaví ostatní, pokud zbývá společná kapacita. Tenantové a provider stropy jsou další ochrana, ne náhrada fair use mezi pořadateli. Podobně férové přidělování e-mailů musí zohlednit `email_messages.unit`, které už schema ukládá, nikoli jen `organization`.

Auth/registrace ještě nemusí mít Unit ani přihlášeného aktéra. Takové operace používají výslovně definovaný identity/recipient/source a organization budget ve své třídě; ne vymyšlenou „výchozí Unit“ a ne neomezenou větev při NULL scope. `user_info` má jednu organization na UUID; více účtů stejného člověka napříč tenanty není nyní prokázaná společná identita. Globální actor budget tedy znamená stejné kanonické UUID, ne automatické propojení lidí podle e-mailu. Sdílené limity a bezpečné onboarding admission řeší nové účty bez zavádění nové person identity databáze.

**Zapojení do existujících commandů**

Tato podsekce není nová implementační vlna; specifikuje místa a transakční pořadí pro vlny 2-4.

| Skutečná cesta | Místo enforcement a zachovaný kontrakt |
| --- | --- |
| `create_occasion_client_sync_v1` -> `create_occasion_domain_command_internal_v1` | po validaci a `begin_unit_client_mutation_v1` s návratem replay, před `update_occasion_internal_v1`; budget a akce commitnou spolu |
| `finalize_occasion_setup_draft` | po ověření přístupu, uloženého finalize výsledku/receipt, revision a payloadu, před materializací; nesmí znovu volat celý create command a vytvářet druhý receipt/fan-out |
| `duplicate_occasion_client_sync_v1` -> `duplicate_occasion_internal_v1` | po autorizaci zdroje i cíle a replay, před SQL kopií; budget odvodit z cílové Unit, nikoli ze source šablony |
| `update_occasion`, `update_occasion_182/_203`, overloady `duplicate_occasion` | ponechat delegaci; nezavádět druhé čerpání ve facade. Každé nové serverem přidělené UUID podléhá témuž create budgetu |
| `create_occasion_setup_draft` a inicializace defaults | před drahým `build_occasion_setup_configuration` kontrolovat draft budget; rollbackový creator nečerpá skutečný create budget. Opakovaná inicializace existujícího draftu nesmí nekonečně platit práci/sekvence ani znovu čerpat dokončený draft |
| `create_unit_and_assign_manager`, registrace a Google | jednotný vnitřní mechanismus jednotkové admission volaný z reálných doménových cest, včetně `initialize_registration_unit_v1`; rozdílná autorizace registrace a ručního create zůstává u jejich vlastníků |
| Service import akcí | po ověření konfigurace zdroje a cíle čerpat budget pro nově vzniklé akce; existující upsert je update, nikoli nové založení. Použít system-source/Unit/tenant scope, nevymýšlet `auth.uid()` za service caller |

Interní admission pro vznik akce má pouze ověřit a atomicky čerpat potřebné budgety. Nesmí sám vytvořit akci, receipt, slug ani sync commit. Tím lze sdílet stejné pravidlo pro tři existující commandy bez slučování jejich odlišných workflow. Není potřeba vytvářet druhý mutation ledger: pro nové commandy použít `client_mutation_receipts` a finalize výsledek v draftu. Usage evidence je úzká evidence spotřeby s vlastním omezeným životním cyklem, ne kopie doménového stavu.

Nepřidávat enforcement do obecného `begin_unit_client_mutation_v1`: helper používají i jiné mutace a nemá znalost výsledného počtu/velikosti akcí. Nepřidávat jej bezpodmínečně do `update_occasion_internal_v1`: používá se také pro update a rollbackový bootstrap. Mechanický trigger by navíc porušil repository pravidla. Všechny skutečné INSERT writery musí být buď uzavřené interní detaily chráněného commandu, nebo výslovně chráněný import s vlastním scope; nikoli seznam nehlídaných výjimek.

**Oprávnění helperu:** existující commandy jsou `SECURITY DEFINER`, ale JWT zůstává uživatelský. Helper vyžadující `auth.role()='service_role'` by tyto legitimní commandy blokoval. Interní quota helper zpřístupnit pouze potřebnému DB vlastníkovi, odebrat EXECUTE `PUBLIC/anon/authenticated` a zajistit minimální práva k usage tabulkám. Doménový command před ním ověřuje `auth.uid()` a cílový objekt; service import má explicitně oddělený ověřený system kontext. Přímé volání helperu obyčejnou rolí musí selhat. Klientský `p_actor`, custom GUC ani údaj z body nejsou důkazem důvěryhodného původu.

**Legacy replay:** staré facade bez commandId zaručují vynucenou kvótu, ne idempotenci mezi HTTP retries. Tuto vlastnost neslibovat zpětně bez změny protokolu. Automatické opakování create/copy směrovat na existující UUID command rozhraní; `ClientCommandTransport` už drží UUID při transportním retry jedné invocation a setup page drží finalize UUID. Nová ruční invocation je nový command a znovu podléhá budgetu. Případné durable obnovení napříč restartem klienta je samostatně ohraničená klientská práce, ne předpokládaná vlastnost současného transportu.

**Media realita:** `DbOccasions.duplicateOccasion` nejprve commitne SQL, pak `DbImages.createCopyOfImage` stáhne a znovu uploaduje R2 obsah nebo použije starší Storage copy a `add_image_record`. Worker má `/upload`, nikoli prokázaný serverový copy job s receipt. Proto minimální řešení vynucuje upload/Storage bytes a frekvenci na skutečném IO; po file chybě zachová již vytvořenou akci a existující odkazy, jak dělá dnešní klient. Nevymýšlet kvůli limiteru povinný job/saga nebo vracení create kvóty. Silnější jednorázové účtování konkrétních copy child operací by vyžadovalo explicitní nový protokol a migraci obou cest; nelze ho označit za existující schopnost kódu.

**Lock graph:** před implementací zakreslit stávající pořadí pro každou upravovanou transakci: například receipt -> draft/occasion/order -> dedupe/message -> příslušný usage scope. Finalize už drží draft row před receipt; skutečné pořadí je třeba zachovat nebo cíleně sjednotit v dotčených cestách, nikoli slepě vložit budget lock „vždy první“. Queue sender dnes zamyká capacity -> order -> attempt/message; producenti vlastní order -> message a wake obchází capacity lock přes `SKIP LOCKED`. Nepřidat zpětnou hranu přes společný quota řádek. Admission a dispatch používají odlišné budgety/řádky podle fáze. Ověření zahrne dvojici producer/send a dvě create/finalize transakce; síťové volání ani kopie souboru nesmějí běžet pod novým usage zámkem.

**Kanonické SQL zdroje:** některé použité facade/receipt definice jsou dohledatelné v historických migracích (`20260806100000_client_sync_production_hardening.sql`, `20260802234000_client_sync_v1_expansion.sql`), nikoli potvrzené jako samostatné aktuální soubory. Před změnou ověřit výslednou definici po celém migračním pořadí na izolovaném backendu a případně doplnit canonical zdroj jen pro skutečně měněný symbol. Neměnit již aplikované migrace. `automation/assemble_pretty_public_links.py` přepisuje konkrétní historický migration soubor; není to obecný generátor nové abuse migrace. Připravit novou dopřednou migraci a cílený parity důkaz. Komentář `canonical_mutation_source_parity_test.sql` odkazuje na zde nenalezený `automation/client-sync/generate_source_contract.mjs`; nepovažovat tento příkaz bez ověření za funkční gate.

| Modul | Vlastní | Nevlastní |
| --- | --- | --- |
| Ingress a worker routing | objem, metody, body, slow requests, ověřený síťový kontext | rozhodování o držbě místa nebo právech uživatele |
| Sdílený mechanismus časových budgetů | atomické čerpání, čas, expiraci a konzistentní výsledek | Auth, e-mailové šablony, objednávky, poskytovatelské credentials |
| Doménový command | autorizaci, idempotenci, odvození budgetů a atomickou doménovou změnu | HTTP parsování a čekání na poskytovatele v transakci |
| E-mailový modul | admission intentů, fair scheduling, send fence, retry a provider výsledek | náhradu autentizace nebo druhou účetní evidenci objednávek |
| Transportní adaptéry | validaci vstupního formátu a překlad výsledku do kontraktu klienta | vlastní kopii policy a počítadel |

Implementace má povolený seznam konkrétních operací, typované výsledky a explicitní závislosti. Vyhnout se volnému `Record<string, unknown>` jako novému veřejnému kontraktu policy, dynamickému SQL podle názvu operace, plugin registrům a řetězcům konfigurovatelných callbacků. Interní TS typ ani klientský brand sám nezaručuje oprávnění; SQL znovu ověřuje důvěryhodný execution context. Nevytvářet adapter/factory pro hypotetického druhého poskytovatele. Čas a externí IO musí být říditelné v testech přes existující testovací seam; testovat rozhraní skutečného commandu, ne pouze mock volání limiteru.

Pravidla nejsou mechanicky stejná pro všechny zdroje:

| Druh omezení | Vlastnictví a transakční sémantika |
| --- | --- |
| Počet pokusů za čas | síťový nebo autentizační limiter; odmítnutý pokus se započítá a commitne, následný doménový rollback jej nesmí vymazat |
| Budget přijaté operace | deduplikovaná spotřeba se zapíše s doménovým výsledkem; neúspěšný commit nevytvoří ani side effect, ani dokončenou spotřebu |
| Obsazenost a souběh | existující order/ticket/hold nebo worker lease je autorita; žádný paralelní čítač obsazenosti bez transakčně doložené nutnosti |
| Externí send nebo náklad | existující intent/attempt s fencingem; nejistý výsledek zůstává započtený, timeout sám nevrátí permit pro druhé odeslání |

V PostgreSQL se nepoužije představa autonomní transakce uvnitř funkce. Pro odolné počítání pokusů použít krátké samostatné service RPC před commandem, pokud je na této cestě potřeba, nebo explicitní zamítavý návrat, který transakci commitne. Při čistě veřejném RPC se potřebné počítání neúspěšných transportních pokusů vynucuje i na ingressu. Neumožnit klientovi otevřít transakci a rollbackem vracet serverový autentizační budget. Po ověření oprávnění se již dokončený idempotentní command vrátí před novým čerpáním doménového budgetu; nový HTTP pokus stále podléhá ingress limitu. Stejná idempotency identity s odlišným vstupem je konflikt, ne další operace.

Předrenderový preflight omezuje drahou práci, ale není závazným důkazem finálního místa ve frontě. Enqueue musí atomicky provést finální dedupe a admission. Pokud bez rezervace nelze cenu přípravy bezpečně omezit, použít krátce platnou, jednou spotřebovatelnou rezervaci navázanou na ověřený command, scope a cenu, s bounded cleanup; nevytvářet obecnou saga/frontu vedle e-mailové fronty. Pád nebo odpojení klienta nesmí zastavit již přijatý durable command ani neomezeně prodlužovat lease.

Datový návrh používá malé indexované řádky po relevantním scope, konzistentní pořadí zámků, lock/statement timeout a bounded cleanup. Nezamykat jeden globální řádek pro všechny operace a tenanty; singleton `email_capacity` je odůvodněný pouze pro skutečně společnou provider kapacitu. Admission nesmí při každém requestu skenovat historii zpráv nebo všechny holdy. Nový souhrnný údaj jen s explicitním vlastníkem, transakční aktualizací a ověřenou reconciliací. Policy se validuje proti nulovým, záporným a přetékajícím hodnotám; změna limitu má definovaný dopad na existující okno a běžící práci. Algoritmus a dovolený burst se vyberou podle konkrétního rizika a otestují včetně hranice okna, ne podle nejkratší ukázky kódu.

Levné public sync/CDN čtení zůstává bez SQL závislosti. Rozpočty na síťové hranici mohou mít distribuované zpoždění; u každé politiky zaznamenat, zda je hard limit, nebo best-effort ochrana. Nákladový či doménový hard invariant musí vynutit příslušný trvalý vlastník. Samotný provider billing alert není hard spending cap.

## Centrální konfigurace pravidel a mapa operací

Požadavek uživatele: konkrétní limity nesmějí být roztroušené jako konstanty v jednotlivých handlerech. Zřídit jeden typed katalog pravidel v PostgreSQL, společnou mapu logických operací na budgety a jednotné čtení efektivní konfigurace. Jednotná správa neznamená jediný univerzální čítač nebo přesun business logiky do JSON konfigurace. Tabulky a helpery jsou zde návrh pro implementaci, zatím nejsou vytvořené v backendu.

| Navržená tabulka | Obsah a odpovědnost |
| --- | --- |
| `public.abuse_policy_rules` | výchozí pravidla: stabilní `rule_key`, sdílený `budget_key`, scope `actor/unit/occasion/organization`, druh omezení, měrná jednotka, okno, základní limit, burst, povolený základ růstu, přírůstek a pevný strop; verze/revize pro audit |
| `public.abuse_policy_overrides` | cílené parametry existujícího pravidla pro konkrétní Unit nebo Organization; důvod, platnost, autor a revize; přesně jeden typ cíle, nejvýše jedna účinná výjimka pro pravidlo a cíl |
| `public.abuse_budget_usage` | pouze mutable stav časových budgetů: stabilní budget/scope identity, stav příslušného algoritmu, expirace/retence; není zdrojem hodnot limitů, doménové obsazenosti ani kopií email attempts |

Názvy jsou cílový návrh, který může implementace zpřesnit podle výsledku inventáře. Minimálně oddělit konfigurační pravidla od spotřeby. Změny konfigurace evidovat jako neměnné revize nebo explicitní auditní záznamy s předchozí a novou hodnotou; nepřidávat persistentní aplikační trigger. Aktivace více souvisejících změn je atomická. Žádné obecné EAV/key-value úložiště s volnými JSON podmínkami.

Každé pravidlo má validaci podle druhu: kladné celočíselné počty/bajty, povolená okna a burst, `base <= hard_cap`, nezáporný růst a kontrolu přetečení výpočtu. Žádné NULL/0 jako implicitní „neomezeno“. Occupancy pravidlo nepředstírá časové okno; provider quota dál pochází z existujícího `email_capacity`. `growth_basis` je omezený serverem podporovaný výčet, například `none`, `eligible_participants` nebo `existing_orders`; konfigurace nesmí obsahovat SQL, výraz ke spuštění, libovolný název tabulky nebo funkce. Výpočet dynamické hodnoty zůstává u vlastníka důvěryhodných doménových dat.

**Mapa logických operací:** kód obsahuje stabilní povolené přiřazení operace k pravidlům a pravidla příslušné fáze. Číselné hodnoty a povolené scoped výjimky jsou v DB. Jde o nezbytnou vazbu na chování, nikoli o hardcoded limity. Není potřeba druhá tabulka rout přepisující skutečné registrace handlerů.

| Logická operace | Společná rodina budgetů | Důvod |
| --- | --- | --- |
| `occasion.create`, `occasion.duplicate`, `occasion.setup.finalize` | `occasion.creation` pro actor, Unit a Organization | všechny vytvářejí skutečnou akci a nesmějí získat oddělené časové kvóty |
| `occasion.draft.create` a skutečná inicializace konfigurace | `occasion.draft` a omezení přípravné práce | draft není vytvořená akce, ale stojí místo a výpočet |
| přijetí e-mailu podle skutečného druhu zprávy | `email.admission` s konkrétní třídou, recipient a relevantními scopes | jiná cena a účel, společná ochrana příjemce a fronty |
| volání provideru | existující `email_capacity` a send attempt | nelze nahradit konfigurací, která obchází skutečné account/region kvóty |

Jedna rodina může mít více pravidel, například krátký burst a rolling 24 h, která se vynucují současně. `rule_key` odlišuje pravidlo, zatímco `budget_key` určuje skutečně sdílenou spotřebu. Žádná registrace dalšího endpointu nesmí sama vytvořit novou nezávislou kvótu stejné operace. Změna `revision`, výjimky, zdroje růstu ani HMAC klíče nesmí změnit identitu budgetu nebo vrátit spotřebu. Oddělené admission/dispatch budgety jsou explicitní, nikoli náhodný vedlejší efekt názvu handleru.

**Identita počítadla:** skutečný usage klíč zahrnuje stabilní `rule_key` uvnitř rodiny, scope kind/identity a podle algoritmu časový bucket. Například krátkodobé `occasion.creation.burst` a denní `occasion.creation.day` jsou dvě oddělená počítadla; create/duplicate/finalize čerpají obě, ne dvakrát tentýž řádek. Policy revision a název transportní routy nejsou součást klíče. Jedna přijatá operace se účtuje jednou do každého příslušného pravidla; všechny jeho scopes se commitnou atomicky, nebo žádný. Kontrola prvního pravidla nesmí mít vedlejší efekt, který zůstane po zamítnutí druhým, kromě záměrně odděleného budgetu pokusů.

Pro první implementaci podporovat jen potřebný krátkodobý burst a rolling objem; nevytvářet katalog zaměnitelných algoritmů. Krátké okno má explicitně omezený burst, rolling 24 h nesmí být pouhé resetování o půlnoci ani fixed window dovolující dvojnásobek přes hranici. Bounded časové buckets lze sčítat konzervativně včetně krajního bucketu; jejich rozlišení, maximální počet a možná délka dřívějšího odmítnutí musí být uvedené v policy. Přesnost nesmí skrývat tolerovaný overshoot hard stropu. Nezapisovat nekonečný event ledger pro každý útočný paket a neskenovat celou historii. Potřebná změna časového okna/algoritmu je změna s migrační sémantikou stavu, nikoli běžný libovolný override.

**Vyhodnocení:** doménový command odvodí skutečné scopes -> načte jednu konzistentní sadu efektivních pravidel -> spočítá serverovou cenu/velikost -> atomicky vyhodnotí všechna příslušná pravidla. Pravidlo pro daný cíl vychází z výchozí konfigurace, případného Organization override a přesnějšího Unit override. Vyšší hierarchické budgety se tím nevypínají: Unit override nemůže odstranit actor/Organization/provider strop. Překrývající se overrides nebo neznámý klíč/povinné chybějící pravidlo jsou chyba konfigurace. Časově ukončený override se vrací na platné výchozí pravidlo, ne na neomezený režim. Snížení limitu neruší přijaté závazky, ale nové čerpání vychází z už existující spotřeby a nového limitu. Dříve vydaná rezervace má krátkou platnost a definovanou politiku při zpřísnění; nepředstavuje trvalou výjimku.

Pro PostgreSQL commandy preferovat čtení malého indexovaného katalogu v téže transakci, bez dalšího HTTP hopu a globálního config locku. Efektivní revizi materializovat jednou pro command, ne opakovaně s různými výsledky uvnitř jeho kroků. Na ingressu a Workers se config používá jen podle jejich vlastního execution modelu: buď validovaný verzovaný snapshot odvozený z autoritativních pravidel s omezenou platností, nebo nativní síťová konfigurace s doloženým vlastníkem. Nepřidávat DB dotaz na každý CDN hit. Bez aktuální konfigurace se citlivá nová práce odmítne podle existující outage policy; nesmí vzniknout tiše použitá velká lokální fallback konstanta. Hodnoty v klientovi slouží pouze zobrazení, nikdy enforcement.

Overrides mění jen výslovně povolené číselné parametry konkrétního scope. Nemění `budget_key`, `rule_key`, fázi, měrnou jednotku, algoritmus, délku okna, scope kind ani logickou mapu operací. Unit override nemůže upravit actor budget sdílený napříč jednotkami, jinak by stejný čítač dostával jiný limit podle vybrané akce. Stejně se neodvozuje globální actor limit od libovolně vybraného tenantového override. Změna základního globálního pravidla je samostatná autorizovaná policy revize. Každá podřízená výjimka je stále omezena všemi nadřazenými budgety a správou stanoveným nepřekročitelným capem.

**Správa:** běžný editor/manager nemá přímý UPDATE/INSERT ani EXECUTE k mutaci policy. Změny provádí chráněný operátorský command s autorizací, validací, auditem a optimistickou revizí. Rozhraní umožní také read-only vyhodnocení efektivního pravidla a spotřeby pro autorizovaného vlastníka Unit, aniž odhalí jiné pořadatele nebo interní detaily Auth ochrany. Admin UI není podmínkou prvního řezu; stejné rozhraní může nejprve obsluhovat schválený operační postup. Pořadatel může požádat o navýšení, nikoli si sám měnit capy.

Číselné výchozí hodnoty vzniknou jako explicitně verzované seed řádky v nové dopředné migraci. Nová operace musí dodat mapování, seed pravidel a behavior test; CI odmítne neznámé/missing mapování. Vlastní politiky nesmějí vytvořit souběžnou kopii limitu v kódu. Bezpečnostní algoritmus a podporované druhy pravidel se mění releasem; běžné schválené nastavení čísel přes operátorský command nevyžaduje přepis handlerů ani rebuild klienta.

## Nezávislá kontrola úplnosti

Inventář endpointů odhalí nepokryté cesty, ale ne chybějící vlastnosti uvnitř jinak známé cesty. Proto vlna 1 vytvoří také matici scénářů proti [OWASP ASVS](https://owasp.org/projects/asvs), se zaznamenanou verzí a zvoleným rozsahem. Každý aplikovatelný požadavek má důkaz/test nebo otevřený nález; `N/A` potřebuje konkrétní zdůvodnění. Nejde o tvrzení o ASVS certifikaci. Pro omezení spotřeby a zneužití legitimních operací použít [OWASP API4](https://api-security.owasp.org/editions/2023/en/0xa4-unrestricted-resource-consumption/), [API6](https://api-security.owasp.org/editions/2023/en/0xa6-unrestricted-access-to-sensitive-business-flows/) a [DoS Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Denial_of_Service_Cheat_Sheet.html): odlišují spotřebu infrastruktury, externí náklady a škodlivou automatizaci business flow.

Do matice výslovně patří následující scénáře; jejich provedení vlastní uvedené vlny:

- **Identity a session (2, 5):** změna role/tenanta během operace, revokace JWT versus refresh, password spraying napříč účty, opakovaná registrace a vytváření tenantů kvůli obnovení kvót. Resend nesmí cizímu člověku umožnit nekonečně rušit platný login proof oběti. Ověřit redirekty, cookies, CSRF a login/account-linking CSRF tam, kde se používají browser credentials.
- **Vstupy a oprávnění (4, 5):** mass assignment chráněných polí, duplicitní a neznámé parametry, SQL/function overloady, `SECURITY DEFINER`, views a vlastnictví RLS, mutable JWT metadata, účetní částky a serverem ověřený tenant. Speciálně odlišit právo „editor“ od oprávnění cílové operace.
- **Amplifikace a limity (2, 3, 5):** jedna dávka s mnoha adresáty/položkami, JSON hloubka a velikost polí, komprimované/dekódované vstupy a výstupy, slowloris a timeout čtení, náhodné cesty/cache miss, generování milionů limiter klíčů, opakované wake/poll/cron a časové souběhy při recovery. Body limit se vztahuje na skutečně zpracovaná data.
- **Cache, soubory a odkazy (5):** cache poisoning a klíče ovlivněné Host/query/headerem, cache hit versus miss, ukradená/revokovaná capability, MIME/content sniffing, SVG/HTML aktivní obsah, path traversal, přepsání cizího klíče a únik přes referer/log/export. Response a metriky nesmějí zveřejnit existenci oběti ani obsah soukromého objektu.
- **Externí poskytovatelé a provoz (3, 5, 6):** pevné cíle nebo egress allowlist, DNS/redirect/SSRF, nedůvěryhodná odpověď poskytovatele, signing-key rotace a replay, actual spending caps versus pouze alarmy, izolace credentials, omezený přístup k administraci a CI, obnova záloh a incidentní odvolání kompromitovaného přístupu.

Pro každou mitigaci testovat i její zneužití proti oběti: vyčerpání recipient budgetu, uzamčení účtu, zaplnění fronty, metrik nebo cleanupu. Challenge/CAPTCHA je možný navazující krok jen po zdůvodnění, s přístupnou alternativou a kontrolou nákladů; není výchozí náhradou za limity ani souhlasem zapnout placeného dodavatele.

## Fair use: co se musí nastavit a vynucovat

Politika bude centrálně verzovaná. Pořadatel uvidí přidělené limity, spotřebu, čekání a způsob navýšení; nemůže si sám zvýšit backendový strop. Text fair use musí odpovídat skutečně vynucovaným pravidlům. Ceník, pokuty a automatické účtování nejsou součástí zadání.

Upřesnění uživatele: limity mají mít přiměřenou rezervu, nikoli nadměrné paušální kvóty. Mají se přizpůsobovat velikosti akce a legitimnímu provozu. Návrh nesmí vyžadovat ruční navýšení pro každou běžnou prodejní nebo odbavovací špičku, ale nesmí se automaticky uvolňovat jen proto, že přichází více požadavků.

Pro vhodné objemové limity použít konkrétní pravidlo `min(přidělený strop, základ + přírůstek * relevantní velikost akce)`. Základ, přírůstek a strop musí vlna 1 uvést číselně pro každou takovou operaci a zdůvodnit běžným scénářem včetně rezervy. Relevantní velikost jsou serverem doložené údaje pro danou operaci: například skuteční účastníci pro informační rozesílku nebo existující objednávky pro transakční komunikaci. Počítat unikátní příjemce/účasti, ne součet session, ticket položek či opakovaných registrací téže osoby. Organizátorem nastavená kapacita sama neuděluje neomezený nárok; vždy ji omezuje přidělený pořadatelský (`Unit`), tenantový a společný strop. Scope příjemce u jednotlivé zprávy a legitimní opakovaná účast na různých akcích zůstávají rozlišitelné; jeden globální DISTINCT příjemců není náhrada účtování skutečně vytvořených intentů. Nezapočítávat tutéž operaci znovu přes více akcí do pořadatelského nebo tenantového budgetu.

Počet přihlášených uživatelů může pomoci odhadnout potřebný souběh obsluhy, ale není sám o sobě důvodem zvýšit e-mailovou kvótu nebo ochranné limity pokusů. Samotné ověření e-mailu také není důkazem legitimního růstu. Nové účty, tenanty a neověřené registrace nesmějí automaticky vytvářet další společnou kapacitu. Růst příslušného budgetu má řízené tempo a horní mez; při poklesu velikosti akce nesmí zpětně rušit přijaté závazky. Účast na velké akci nezvyšuje počet povolených pokusů o stejný OTP ani recipient cooldown.

Dynamické výpočty zůstávají malé a předvídatelné: verzovaná formule/tabulka nad existujícími doménovými daty, žádný samoučící model ani drahý přepočet všech účastníků při každém requestu. Pro rozesílky odlišit jednu oprávněnou zprávu každému účastníkovi od opakovaného posílání téže osobě. Špičku absorbovat omezeným burstem, řízeným souběhem a frontou; nezvyšovat kvůli ní pevný denní provider strop. Vlna 1 doloží konkrétní příklady malé, střední a velké akce, včetně anonymních nakupujících a sdílené Wi-Fi, a jejich dopad na kvóty i náklady. Pokud pro číselné nastavení chybí evidence, označit návrh k ověření místo vydávání libovolného násobku za bezpečnou kapacitu.

| Oblast | Rozpočty a jednotky | Reakce a ochrana legitimního provozu |
| --- | --- | --- |
| Registrace/Auth/reset/pozvánky/QR/Google | krátkodobé bursty, pokusy na proof/účet, zdroj, tenant a globální vznik identit; příjemce také napříč typy zpráv a tenanty | generická odpověď bez existence účtu, omezená platnost, cooldown, jeden aktivní proof; ochrana proti zneužití lockoutu |
| E-maily | enqueue intentů, pending počet i bajty, skuteční příjemci včetně CC/BCC, actor/Unit/occasion/tenant, příjemce, rolling den a společný account/region send budget | bulk odložit před renderingem, auth a placené vstupenky mají vyhrazený podíl a omezené čekání; ani priorita nepřekročí provider strop |
| Objednávky/místa/waitlist | aktivní nezaplacené objednávky, držená místa, vydané nabídky, počet obnov, trvání holdu od prvního vzniku, pokusy o capability | atomické limity s expirací; změna secret/UUID nesmí nekonečně prodlužovat držení; nabídky zachovají pořadí a dostupnou kapacitu |
| Zakládání a kopírování akcí | společný burst a rolling 24 h pro create/duplicate/finalize, per actor napříč jednotkami, per Unit napříč editory a per tenant; počet uložených akcí a rozpracovaných draftů; cena kopírovaných dat a souborů | atomická kontrola před založením/kopií, serverem přidělený strop nezávislý na počtu právě založených akcí; smazání ani nová jednotka nevrací časový budget |
| PDF, export, kopie akce, hromadné operace | počet položek, řádků/stran, bajty, CPU čas, souběh a cena operace | autorizace a admission před tvorbou; velké úlohy jen přes existující nebo odůvodněný řízený job; omezený výsledek |
| Upload/download/transformace | request/objekt/tenant bajty, pixely, disková kvóta, transformace, souběh a egress | streamovaný strop i bez Content-Length, omezené varianty, TTL odkazů, privátní cache a tenant izolace |
| Čtení/search/sync/realtime | stránkování, velikost bundle, rozsah query, timeout, frekvence refresh, kanály a fan-out | drahé parametry mají serverové maximum; cache klíče respektují práva, veřejné čtení nedostane privátní data |
| Webhook/cron/integrace/push | ověřené podpisy, čerstvost/replay podle kontraktu, inbox idempotence, retry/backoff, fan-out a vnější účty | neplatný podpis před side effect; legitimní retry nespotřebuje druhý doménový budget; strop i pro interní producenty |

Konkrétní nové číselné stropy zatím nejsou vydané produktové rozhodnutí. Vlna 1 vytvoří tabulku pro každou operaci: měrná jednotka, klíče, burst, okno, souběh, denní budget, pending budget, rezervovaný podíl, chování při výpadku a maximální čekání. Uvede hard/best-effort záruku, zdroj času, algoritmus a chování při změně policy. Hodnoty vycházejí z read-only provozních metrik, skutečných provider kvót a doložené běžné akce; chybějící data nahradit explicitně označeným konzervativním návrhem. Finální tabulka musí být konkrétní před aktivací, ne s hodnotou „doplnit“. Zachovat stávající ověřené limity do vědomého přechodu.

Do e-mailových pravidel zahrnout potlačení bounce/complaint, platnost a účel zprávy, oprávněnost adresáta, četnost opakovaného zaslání a hromadné kampaně. Právní texty a jejich případné posouzení jsou samostatné; technický plán netvrdí právní soulad. Distribuovaný útočník nesmí sám vyčerpat budget oběti, a jeden tenant nesmí globální recipient politikou trvale zablokovat jinému nutné transakční doručení; určit prioritizaci a operátorskou obnovu bez obcházení stropů.

## Postup rychlé realizace

Požadavek uživatele je rychlá, efektivní implementace bez zbytečných odboček. Rozsah auditu zůstává celý systém, ale úplný audit není sériová blokace první doložené ochrany. Šest vln níže popisuje pokrytí a závislosti; nejsou to šest velkých studií nebo nutnost šestkrát vydat celou aplikaci.

1. **Jeden průzkum a třídění:** použít tento call graph, doplnit chybějící runtime/ACL důkazy a konkrétní policy pro nejbližší řez. U již prověřených cest neopakovat obecný architektonický průzkum. Inventář a matice jsou pracovní evidence, ne samostatný reportovací projekt. Potvrzené kritické opravy mají přednost před obecnou abstrakcí.
2. **První funkční celek:** malý chráněný policy katalog + overrides + usage, seed konkrétních hodnot, operátorský write/read kontrakt, create/duplicate/finalize + draft a relevantní vznik Unit. Dodat společně doménové změny, dopřednou migraci a cílené behavior/ACL/souběhové testy. Bez admin UI, nové služby, message brokeru a obecného workflow enginu. Převod všech historických helperů není podmínkou tohoto dokončeného řezu; jejich současné ochrany zůstávají do vlastního přechodu účinné.
3. **Druhý funkční celek:** e-mailové admission, recipient/Unit fairness, backlog a zachování paid intentů; následně doložené vstupní mezery Auth/QR. Použít stejný katalog, odlišné budgety a existující sender. Nevytvářet další frontu ani pro jistotu přestavovat celé šablony/PDF. Již potvrzený kritický Auth nález se opraví dříve, bez čekání na tento pořadník.
4. **Dokončení pokrytí:** zbývající objednávky/holdy, aktivní integrace, upload/egress a další řádky inventáře; CI mapování a provozní důkazy přidávat k právě změněným cestám. Uzavření předchozích nezávislých bezpečnostních migrací a celého auditu evidovat zvlášť od hotového limiter řezu. Menší dílčí release není tvrzení, že je celý program hotový.

Běžná SQL operace má přidat jeden konzistentní lookup malého katalogu a bounded práci nad konkrétními usage klíči uvnitř existujícího RPC, ne další síťové kolečko, globální zámek nebo opakovaný přepočet všech uživatelů. Přínos nevyčíslovat bez měření; na lokální fixture ověřit použité indexy, počet nových DB/HTTP volání a nepřítomnost růstu práce s celou historií. CDN hit nemění svou DB nezávislost. Nová infrastruktura je přípustná pouze při doložené překážce současného řešení.

Po každém souvislém implementačním celku spustit jednu cílenou validační dávku odpovídající riziku: SQL behavior/ACL + dotčené integrační scénáře, Deno/JS jen pokud se měnily a konkrétní klientské adaptéry podle potřeby. Zachovat passing evidence pro nezměněné vstupy. Nespouštět kompletní build/test všeho po každém souboru; povinné repository a release gates tím nejsou zrušené. Neprovádět další nezávislou architektonickou revizi nebo audit subagentem bez nového požadavku; konkrétní selhání řešit cíleně. Použít zásady skillu `focused-development` pro implementaci, nikoli jako záminku přidat nové přípravné fáze.

Rozpracované bezpečnostní nálezy nelze schovat za označení „optimalizace“. Počet uzavřených vstupů, výsledky testů a skutečný runtime stav mají přednost před počtem vytvořených dokumentů, helperů nebo konfiguračních možností. Tento plán a krátký execution prompt jsou autoritativní; nevytvářet další souběžný plán stejné práce.

## Vlny realizace

### 1. Úplný inventář, model hrozeb a návrh limitů

**Změny:** založit `docs/security/abuse-surface-inventory.json`, `docs/security/fair-use-policy.md` a `docs/security/security-requirements-matrix.md` podle nezávislé matice výše. Vstup pro Functions je `automation/hetzner-supabase/merge/runtime-writer-policy.json`, `supabase/config.toml`, skutečné registrace handlerů a router/bundle. Pro SQL se zdroji porovnat katalog efektivních EXECUTE grantů (včetně PUBLIC, dědění a overloadů), tabulek, views, RLS, Storage a PostgREST exposed schemas. Dohledat `.rpc`, přímé `.from`, Auth SDK, dynamická volání, cron/pg_net, DB webhooky, worker routy, veřejné hosty a aktivní legacy/mobile klienty. Nepovažovat function inventory za úplný inventář API.

Každý řádek: metoda/cesta nebo přesná SQL signatura, deployment host, actor, potřebné oprávnění a tenant boundary, side effects, cena/fan-out, skutečná ochrana a vlastník, přímý bypass, související test, stav `ověřeno / chybí / neověřeno / zdůvodněná výjimka`. Inventář zahrne nové worktree změny, historické přechody z auditu 9. října a bootstrap `instance-install`, který nesmí být v produkčním bundle. Kandidáty reprodukovat izolovaně; potvrzené incidentní riziko eskalovat konkrétním nálezem.

**Migrace/odstranění:** žádné. Označit nevyužité vstupy k odstranění až po důkazu o konzumentech. Read-only katalog produkce vyžaduje příslušný backend-access workflow, ověření canonical aktivace/identity a autorizovaný navazující rozsah.

**Ověření:** porovnání inventáře s runtime policy, source registracemi a získaným katalogem; u každé kategorie anonymní, vlastní a cizí tenant a privilegovaný aktér. Neověřený runtime údaj nesmí být označen „chráněno“.

**Výstup:** každý nalezený vstup a aplikovatelný bezpečnostní požadavek má stav, vlastníka a testovací cestu; seznam P0/P1/P2 má důkazy, závislosti a konkrétní číselný návrh policy. Produkčně neověřené položky jsou výslovně otevřené. Potvrzený P0/P1 nález s izolovanou opravou a regresním testem řešit před čekáním na obecný limiter nebo dokončení celého inventáře; produkční containment je samostatně autorizovaný krok. Rozšíření abstrakce nesmí oddálit odstranění známého bypassu.

### 2. Důvěryhodná síťová hranice a společné admission

**Změny:** po výsledku inventáře upravit skutečný canonical ingress/router a jeho repository generátory; související runtime konfigurace jsou v `automation/hetzner-supabase/runtime/`. Definovat důvěryhodné IP/proxy hlavičky, uzavření originu, route-specific metody, streamované body stropy, timeouty a souběh. Prověřit živé GoTrue limity včetně přímého password login, signup, OTP/reset a refresh; nevnucovat aplikaci nový paralelní Auth systém. Limity refresh respektují počet klientů a nesmějí způsobit hromadné odhlášení.

Doplnit canonical SQL policy/usage mechanismus v novém `database/functions/abuse/`, pokud inventář nepotvrdí použitelný existující vlastník. Doménové commandy skrývají výběr budgetů před klientem; `_shared/abusePolicy.ts` přidat jen pro skutečně společný transportní překlad nebo service pokusovou ochranu, ne jako povinný průchod každého RPC. Policy klíče odvozovat na serveru. Oddělit commit pokusů, commit přijaté operace a existující occupancy/lease podle architektonické tabulky. Omezení pro přímo dostupné RPC a tabulkové zápisy řešit na jejich skutečné hranici; případné přesunutí za Edge vyžaduje migraci klientů a odebrání původních grantů. DB gateway context nesmí být klientem padělatelný. Expirace čítačů, omezený cleanup, maximální počet nových klíčů, indexy a pořadí zámků jsou součást návrhu. Nezavádět DB dotazy na cached public sync cestu.

Realizovat tabulky pravidel/overrides/usage a mapu podle části „Centrální konfigurace pravidel a mapa operací“. Přidat operátorský write command a autorizované čtení efektivní policy; seed výchozích čísel, validace, audit změny a převod existujících reset/Google konstant jsou součást jedné autority. RLS a granty nesmějí dovolit běžnému klientovi upravit policy nebo čítače. Aktivační transakce konfigurace nesmí resetovat usage ani vyžadovat přepis všech producentů.

První průchozí implementační řez je SQL admission pro create/finalize/duplicate akce se společným actor/Unit/organization budgetem a zachováním receipts. Ověřit jej včetně bootstrap draftu dříve, než se sdílené rozhraní rozšíří na ostatní domény. Je to omezený pilot mechanismu v existujících commandech, ne nový framework. Při tom nepřidávat service-only JWT podmínku do uživatelské SQL cesty a nepřestavovat receipt helper. Následný převod reset/Google se řídí jejich odlišnou commit sémantikou pokusů, nikoli slepým použitím pilotního business budgetu.

**Migrace/odstranění:** dopředná migrace nejprve přidá chráněná data/kontrakt; poté převést QR `Map` a doložené reset/Google adaptéry. Staré veřejné názvy potřebné pro klienty mohou zůstat jako tenké adaptéry bez druhého čítače. Neměnit application flow persistentními triggery.

**Ověření:** izolované SQL/Deno testy souběžného čerpání malého počtu permitů, NULL vstupů, nedůvěryhodných IP, dvou instancí, restartu, hranice okna, limiter outage, commit odmítnutých pokusů a bounded cleanup. Doplnit rollback doménového commandu, pokus vrátit spotřebu rollbackem, idempotency conflict, změnu policy/HMAC bez resetu budgetu a izolaci nezávislých tenantů bez globálního zámku. Testy body bez Content-Length, chunked/dekódovaných vstupů a ochrany proti slow requests. Plán dotazu/indexy ověřit nad lokální malou fixture, ne kapacitním testem e-mailů.

Konfigurační testy ověří chybějící pravidlo, neplatné/overflow hodnoty, pořadí a expiraci overrides, zachování vyšších capů, odmítnutí změny běžným editorem, konkurentní update revize a policy změnu u již spotřebovaného budgetu. Behavior test načte změněné číselné pravidlo a prokáže změnu rozhodnutí beze změny handleru i zachování sdílené create/duplicate/finalize spotřeby.

**Výstup:** změna instance, hlavičky, přímá RPC cesta ani nové UUID neobnoví relevantní budget; veřejná operace nedokáže měnit policy.

Regresní testy musí navíc rozlišit krátké a denní pravidlo: volné krátké okno s vyčerpaným denním limitem operaci zamítne, krátkodobý reset nevrátí denní spotřebu a zamítnutí posledním pravidlem neodečte business kapacitu z předchozích. Ověřit dvě různě nakonfigurované Unit pod stejným actor budgetem, bez možnosti změnit actor limit přepnutím cíle. Testovat skutečný výsledný stav, nikoli jen pořadí zavolání helperů.

### 3. E-maily: admission, férovost a ochrana příjemců

**Změny:** `database/functions/emails/email_queue.sql`, `email_schema.sql`, `email_domain.sql`, producenti `register`, `send-sign-in-code`, `send-reset-password-link`, `send-custom-email`, `send-tickets`, `send-app-links`, account deletion, GoTrue hook, order/waitlist reissue a automatické reminders. Pro každého producenta doložit přijetí intentu před drahým renderingem a bezpečné zachování transakce doménové operace. Příprava nesmí neomezeně ukládat snapshoty před kontrolou budgetu.

Navázat admission a backlog stropy na stávající `public.email_messages`; `claim_email` dostane doložené přidělení pořadatelského (`unit`), tenantového a prioritního podílu, `begin_email_send` zůstane poslední globální fence. Fairness se vyhodnocuje mezi pořadateli i tenanty uvnitř příslušné třídy; rezervovaný auth/paid podíl nesmí obejít nekonečný proud priority z kompromitovaného pořadatele/tenanta ani stárnutí bulk zpráv. Auth intenty bez Unit používají vlastní omezenou třídu podle pravidel výše. Podíl není slib doručení při vyčerpané provider kvótě. Expirovaný OTP a neplatná nabídka se neodesílají pozdě ani automaticky znovu nevytvářejí.

Opětovná zpráva pro stejný účel musí mít recipient cooldown nezávislý na commandId. Dedupe se ověří před novým čerpáním doménového budgetu, avšak transportní pokusy zůstávají omezené. Započítat velikost příloh, všechny skutečné adresáty, retry a nejasný provider výsledek; `unknown` automaticky neposílat znovu. Pending strop zahrnuje i budoucí, blokované, připravované a nejasné intenty, nejen aktuálně due zprávy. Ověřit izolaci credentials pouze u senderu a skutečný přidělený rozpočet, zejména pokud account sdílí jiný produkt.

Prověřit `wake_email_worker`, `awaitEmailAccepted`, `process-email-queue` a recovery cron proti opakovanému spouštění při každém requestu. Wake může být sloučený a worker/polling mají omezený souběh i celkovou dobu; neudržovat HTTP request otevřený po celé čekání na denní kvótu. Zachovat klientský kontrakt: accepted intent není `sent`; pokud API nově vrací pending/202, doložit migraci klientů a oddělený status lookup s anti-enumerací. Změna adresy nebo práv mezi přípravou a sendem musí znovu projít stávající `email_intent_valid` a doménovými podmínkami.

**Selhání/kompatibilita:** nezahazovat zaplacenou objednávku ani její intent kvůli momentálně naplněnému send limitu. Odklad doručení je trvalý a viditelný; ochrana přijímání nových veřejných objednávek může zasáhnout před jejich závazným vytvořením. Provider callback a hook musí na přetížení odpovídat způsobem umožňujícím jejich doložený retry. Nesmí vzniknout retry smyčka nebo povolení poslat mimo frontu.

Odlišit běžný backlog budget pro nové/discretionary požadavky od omezené rezervy na již přijaté transakční závazky. `enqueue_paid_order_tickets` dnes běží v platební transakci; přidání stejného zamítavého bulk admission do této větve by mohlo zabránit zaznamenání legitimního zaplacení. Rezervu a zastavení nového příjmu odvodit i od existujících dosud nezaplacených objednávek, které ještě mohou přejít do paid; pouhé upřednostnění při `claim_email` tento problém neřeší. Již dříve přijatý závazek se doloží existující objednávkou a její verzí, nikoli klientským příznakem `priority` nebo `paid`.

Takový závazek používá stejnou durable frontu a send fence; nevytvářet nouzového sendera nebo další queue. Opakovaný intent se coalescuje přes existující dedupe, rezerva není neomezená výjimka. Při skutečném storage/DB selhání vrátit retryable neúspěch podle existujícího BankSync inbox kontraktu a vyvolat alarm, nikdy falešný úspěch bez commitu. Před aktivací dokázat, že nově nastavená policy neblokuje platbu dříve vytvořené objednávky jen kvůli vyčerpané běžné mail kvótě. Žádný příslib neomezeného doručování při vyčerpané provider kapacitě.

**Migrace/odstranění:** doplnit policy/usage a potřebné indexy; odstranit bypassy, nikoli doručovací historii. Zachovat jeden sender a existující fencing. Datovou retenci navrhnout odděleně od mazání auditních důkazů.

**Ověření:** rozšířit cílené `database/tests/emails/` a Deno producentní testy. Prokázat odmítnutí před drahou prací a správnou vazbu doménového commitu/intentů. Historický e-mailový plán zakazuje kapacitní testy a syntetické dávky včetně stub varianty: tento plán je neobnovuje. Žádné testovací e-maily ani zjišťování SES kvóty odesíláním; férovost doložit policy, omezenými stavovými testy a read-only provozními metrikami.

Stavové ověření zahrne opakovaný stejný command bez dvojího účtování, odlišný payload se stejným klíčem, preflight/finální enqueue race, pád během přípravy, expirovanou rezervaci, `unknown` bez vrácení send permitu a změnu adresy/práv. Fronta ani limiter nesmějí odhalovat aktivitu jiných tenantů. Tyto malé transakční scénáře nejsou syntetickou e-mailovou dávkou.

Na existující izolované `database/tests/emails/account_intent_atomicity_test.sql`, `order_ticket_intents_test.sql` a relevantní BankSync testy navázat scénářem: běžný backlog je vyčerpaný, dříve přijatá objednávka přejde do paid, její oprávněný intent se uloží jednou a provider send zůstane odložený pod globálním stropem. Nová ruční bulk zpráva nesmí tvrzením o prioritě čerpat rezervu závazků. Skutečný DB failure nezíská úspěšný inbox receipt. Stačí malý stavový scénář bez externího odesílání.

**Výstup:** každý producent sdílí admission/recipient/tenant policy a stávající provider gate. Bulk nemůže vytlačit auth a placené transakční doručení; přípustné čekání má metriku a alarm.

### 4. Objednávky, rezervace, capabilities a placené integrace

**Změny:** `database/functions/eshop/select_spot.sql`, `create_ticket_order.sql`, `eshop_orders/create_ticket_order_client_sync_v1.sql`, `eshop_waitlist/`, `send-ticket-order`, `customer-order-access`, `waitlist-commands` a navazující integrační adaptéry. Ověřit skutečnou držbu místa, maximální životnost a počet aktivních holdů, nepřevzetí cizího secretu a souběžnou změnu objednávky. Prověřit jednu operaci přes všechny overloady a klienty, nejen jeden handler.

**Výslovný požadavek: zakládání akcí.** Použít pilot z vlny 2 a konkrétní call graph z architektonické části. Chránit `database/functions/others/create_occasion_domain_command_internal_v1.sql`, veřejnou create facade `create_occasion_client_sync_v1` (dohledaná v migration `20260806100000`), `occasion_setup/finalize.sql`, `occasion_setup/drafts.sql`, `duplicate_occasion_client_sync_v1.sql`, `duplicate_occasion.sql`, `public_links/legacy_writers.sql` a všechny další skutečné INSERT writery. Finalize je vlastní cesta, nikoli wrapper veřejného create commandu. V lokálních zdrojích jsou create a duplicate samostatné commandy s existující autorizací a mutation receipts; tento průzkum nepotvrdil společnou create kvótu. Zkontrolovat skutečný call graph a granty, ne jen přidat kontrolu do průvodce ve Flutteru.

Založení, dokončení draftu, kopie existující akce a použití šablony spotřebují tentýž budget vzniku nové akce. Ověření actor/tenant a replay receipt proběhne před čerpáním; nová akce a spotřeba vzniknou atomicky před drahým kopírováním/fan-out. Finalizace draftu se účtuje jednou; draft má vlastní limit vzniku, uloženého počtu i bajtů, aby nešel používat jako neomezené úložiště. Vedle burstu a rolling 24 h definovat počet existujících akcí včetně skrytých/testovacích/archivovaných, případně samostatný nižší limit aktivních akcí. Každá skutečně uchovávaná varianta musí patřit do konkrétního resource budgetu; přepnutí stavu není bezplatné uvolnění diskové kapacity. Číselné stropy musí být samostatné řádky policy z vlny 1, nikoli pouze obecná položka „hromadné operace“.

Actor budget platí napříč jednotkami přístupnými témuž kanonickému uživateli, Unit budget napříč jejími editory a tenant budget napříč jeho pořadateli; vyhodnotí se konzistentně. `create_unit_and_assign_manager`, `initialize_registration_unit_v1` v registraci/Google a případný dostupný vznik organizace mají vlastní admission, aby přes nové jednotky, tenanty, pozvánky a nové účty nešlo obnovovat společnou kvótu. Zdroj `create_unit_and_assign_manager` dnes ověřuje JWT a organization feature flag; existence flagu není početní kvóta. Společný strop pro vznik akcí a přidělená tenantová kvóta nesmějí automaticky růst počtem vytvořených akcí, draftů nebo přidaných účtů. Nový či nedůvěryhodný pořadatel má omezenou základní kapacitu; navýšení musí vycházet z doloženého legitimního užívání nebo operátorem přidělené policy, ne ze samotného zaplnění limitu.

Kopie se počítá jako nová akce a má navíc limit položek/bajtů a souběhu pro následné kopírování souborů přes klient/worker. Úspěšná SQL kopie není oprávnění neomezeně opakovat file IO; minimální řešení chrání skutečný upload/Storage copy a autorizovaný cíl podle media kontraktu výše. Dnešní child operace nemají prokázaný společný receipt/job protokol. Nepřidávat druhou business implementaci kopírování. Smazání a opětovné založení nesníží rolling počet vytvoření; případné uvolnění storage budgetu až podle skutečné reclaim evidence. Usage evidence pro rolling budget se nesmí mazat kaskádou při smazání doménové akce/jednotky; retenční životnost je explicitní a omezená.

Prověřit skutečnou runtime registraci `synchronization/sync_source_via_http.sql`. Je-li cesta aktivní, zahrnout cron i ruční service volání: budget nových akcí proti cílové Unit/organization, bounded odpověď zdroje, síťový timeout a vlastní budget synchronizační práce. Existující UPSERT nespotřebuje další create slot, ale stále stojí update/IO práci. Síťový fetch musí předcházet novému quota locku. Při částečné odpovědi, překročeném limitu nebo přerušené synchronizaci nikdy nespustit mazání lokálních akcí podle neúplného seznamu. Vybrat explicitně atomické odmítnutí importu nebo durable pokračování se zákazem pruning do kompletního ověřeného snapshotu; nepřidávat druhý sync engine. Pokud je starý writer mrtvý, odstranit registraci/zdroj v rozsahu doložených volajících místo stavby limiteru pro něj.

Zahrnout scan i brute force scan tajemství, stornování, změny cen/produktů, refunds a existující Fakturoid/BankSync operace: oprávnění, signed částky, replay, atomická idempotence a omezení externích callů. Omezení nesmí zablokovat zaznamenání skutečné zaplacené transakce. Kapacitu dál vlastní existující tickets/order model, ne nový ledger osob.

**Migrace/odstranění:** chráněné hold/usage údaje a přechod aktivních rezervací s explicitní expirací; bez plošného stornování zákaznických objednávek. Nechráněné alternativní writery odebrat až po migraci volajících.

**Ověření:** izolované scénáře dvou kupujících na stejném místě, stejné identity s novým UUID, opakovaného obnovení, dvou tenantů a podpisově platného replay webhooku. Pozitivní nákup, zaplacení, nabídka a scan mají regresní scénář; test nezakládá skutečnou fakturu ani bankovní požadavek.

Pro vznik akcí prokázat souběžné vytvoření posledního dostupného slotu, create versus duplicate versus draft finalize, starší facade a přímý SQL vstup, nový commandId, přepnutí jednotky, druhého editora stejné Unit, nezávislého pořadatele ve stejném tenantu, skrytí/archivaci, smazání a nové založení. Ověřit, že stejný receipt nevytvoří ani nezaúčtuje druhou akci a SQL zamítnutí neponechá částečné produkty, členství ani slug. Bootstrap draftu nesmí spotřebovat create slot, musí ale podléhat draft admission; změna UUID nesmí obejít limit draftů. Po chybě pozdějšího file IO existující akce zůstane viditelná a opakování nevytváří novou akci. Pro aktivní import testovat update bez nového create slotu a limit/částečný snapshot bez pruning. Pozitivní scénář musí zachovat běžné založení i kopii oprávněným pořadatelem.

Navázat na konkrétní existující sady `database/tests/occasion_setup/drafts_test.sql`, `duplicate_occasion_target_unit_test.sql`, `duplicate_occasion_creator_editor_test.sql`, `public_links/public_links_test.sql` a dotčené source parity testy. Přidat behavior testy budgetu na veřejném commandu a runtime ACL negativní test helperu; pouhý mock, který ověří zavolání limiteru, nestačí. Dopřednou migraci ověřit vůči skutečnému výsledku celé baseline, ne přepsáním historického SQL souboru.

**Výstup:** kapacitu nelze držet bez omezení, duplikovat ani převzít; dokončený payment nebo retry nepřinese druhý side effect.

### 5. Zbylé plochy: data, výpočet, soubory a provoz

**Změny:** dokončit každý zbývající řádek inventáře. `workers/image-worker/` a `sync-worker/` dostanou příslušné admission/egress limity, `fetch-http-data` SSRF a redirect/DNS ověření, PDF/download/export limity vstupů a výstupů. Rozšířit kontrolu na přímé tabulky/views, Storage listing, signed URL, sync artefakty, cache, realtime a administrativní hromadné operace. Tajný odkaz je omezená capability, ne všeobecné přihlášení.

Dokončit nebo přesně ohraničit otevřené přechody předchozího auditu: participant UUID, legacy slabé pozvánky, vlastnictví privátních objektů a CSP/embed kontrakty. Neodvozovat vlastnictví ze segmentu filename a nerušit zdokumentované sdílení bez migrace. Prověřit XSS/injection, IDOR/cross-tenant přístup, únik tajemství/PII v chybách a logu, vendor permissions, deployment/debug/admin endpoints, povrch závislostí a CI credentials. Pouhý rate limit neuzavírá takový nález.

Provozní část zahrne retenci/cleanup a zaplnění disku/logů, DB connection/query stropy, zálohování a doloženou obnovu na izolovaném cíli, minimální IAM/SSH práva a dosažitelnost administrace. Metriky nepoužívají raw IP, recipient nebo commandId jako neomezené labels; odmítnuté pokusy mají sampling/agregaci. U poskytovatelů doložit účtované jednotky, skutečné capy, alarmy a kdo reaguje, včetně limitu R2 egress/transformací a push fan-out. Výsledkem je runbook konkrétního tenanta/operace, pauza bulk/producenta, omezená časová výjimka v policy s auditem a postup obnovy; žádné tlačítko na vypnutí globálního stropu.

**Migrace/odstranění:** přesné datové/klientské přechody pro ownership/legacy zdokumentovat před vynucením. Odstranit mrtvé endpointy a nepotřebná provider oprávnění; sdílené služby jiných aplikací neomezovat bez vlastní scope evidence.

**Ověření:** objektové a cross-tenant regresní testy, skutečné bounded stream čtení, timeout/cancellation, privátní cache, podepsané URL a pozitivní kompatibilní upload/sync. `workers/image-worker` pouze lokální unit/typecheck; jeho remote integration suite vytváří reálná data a není lokální náhrada.

**Výstup:** žádný řádek inventáře nezůstane nevyřízený; odložené kompatibilní migrace mají konkrétního vlastníka a brání označení celého programu za dokončený.

### 6. Průběžná brána, rollout a důkaz dokončení

**Změny:** doplnit stávající kontrolu `automation/tests/edge_function_test_coverage.test.mjs`, `supabase/functions/test-coverage.json` a `_shared/edgeEntrypoints_test.ts` o mapování na abuse policy; přidat analogickou kontrolu pro veřejné SQL a worker routy z inventáře. Výjimky mají důvod, vlastníka a datum revize. Přidat konzistentní chyby/odklady do skutečných Flutter a JS call sites, bez automatických nekonečných retry. Při login/reset zachovat anti-enumeraci; jiné route mohou použít 429/Retry-After v souladu s kontraktem, odložená přijatá operace vrací durable identitu.

Požadavek bez vlastního časového budgetu může být legitimní, má-li odpovídající jinou ochranu; CI nemá nutit DB limiter na každou routu. Samotné vyplnění inventáře neprokazuje vynucování: testovat veřejné rozhraní a neexistenci bypassu. Doklady v requirements matici musí mířit na současné testy nebo provozní pozorování a rozlišovat fakt, předpoklad a otevřený nález.

**Rollout:** nejprve schema/policy, potom producenti a enforcement, následně klientské úpravy a odebrání starých grantů/čítačů. U nových číselných limitů lze krátce měřit shadow rozhodnutí bez bypassu stávající ochrany; potvrzené autorizační chyby se do shadow režimu nedávají. Aktivaci provést jen s číselnou policy, alerty, rollbackem a explicitním vybraným tenantem.

**Ověření a výstup:** sestavit balík důkazů se source SHA, policy verzí, migračním ledgerem, runtime konfigurací bez secrets, výsledkem cílených testů a stavem každého řádku. Lokální implementace, merge, aplikace migrace a živá ochrana jsou čtyři různé stavy. Ochrana produkce vyžaduje readback a omezené neškodné canaries schválenou cestou, nikoli objemové útoky.

## Evidence odstranění a kompatibility

| Artefakt | Cílová akce | Důkaz |
| --- | --- | --- |
| QR procesová `attempts Map` | převést na sdílené enforcement a odstranit lokální autoritu | více instancí a cílené hledání |
| Nezávislé reset/Google rate čítače | po migraci jediný canonical policy owner; existující názvy jen pokud potřebné pro kompatibilitu | call graph, granty, test původních vstupů |
| Případní přímí mail sendeři/credentials mimo worker | odstranit, pokud inventář potvrdí; nesmí vzniknout v implementaci | zdrojový i deployment credential inventář |
| Veřejné alternativní write RPC/granty nebo hosty obcházející ochranu | uzavřít po migraci doložených volajících | efektivní ACL, síťová dosažitelnost, negativní test |
| `instance-install` a debug/bootstrap routy | zachovat jen mimo canonical produkci | bundle/router manifest |
| Legacy klienti, pozvánky, attendance a object sharing | evidence kompatibility a cílený přechod; ne tvrzení, že již odstraněno | nasazené verze, migrační readback a pozitivní scénáře |
| Shadow flagy a dočasné výjimky | po vyhodnocení odstranit nebo ponechat časově omezené s vlastníkem | finální policy a kontrola konfigurace |

## Ověření a provozní autorita

Plánování nespouští testy aplikace. Při implementaci použít cílené repository testy v disposable lokální DB; vždy explicitně dodat lokální `DATABASE_URL` a izolované Supabase endpointy, ne implicitní `.env.local`. Reuse vzoru `database/tests/security/run-local.sh` musí mít vlastní taskový projekt/port a nesmí resetovat cizí DB. SQL testy spouštět přes `node web_client/scripts/run_db_tests.js <konkrétní test>` až po kontrole lokálního cíle. Deno použije běžnou repository konfiguraci a konkrétní test soubor; nové behavioral testy zapsat do coverage matrix. Workery ověřit jejich lokálními unit a typecheck skripty; změněné klientské chování cílenými JS testy a `fvm dart analyze <soubor>`, případně relevantním klientským testem. Release gate určuje repository workflow až při autorizovaném releasu.

Backend release používá kanonické SQL a schválený self-hosted bundle přes protected access, po kontrole backend aktivace. Web build lokálně a `automation/deploy_direct.sh` pouze pro zvolený tenant. Nespouštět GitHub-hosted deploy bez výslovného zadání. Při publikaci respektovat aktuální main a skutečná branch protection/review pravidla; dřívější historické svolení v jiném plánu se na tento úkol nepřenáší.

Rollback vrací konkrétní kompatibilní cestu nebo policy hodnotu, ne autorizační bypass, přímé AWS credentials ani neomezené odesílání. Schema nejprve ponechat jako bezpečný superset; destruktivní contraction až po důkazu migrace klientů a dat. Existující paid intents, dedupe a auditní záznamy zachovat.

## Předpoklady a otevřené rozhodovací body

- Sdílená DB může být vhodný vlastník aplikačních budgetů; vlna 1 ověří frekvenci a náklady bez zátěžových testů. Pokud nestačí, změnu autority zdůvodnit v plánu před implementací, nepřidávat druhý konkurenční limiter.
- Skutečný proxy trust chain, veřejná dosažitelnost originu, živé GoTrue/SES kvóty, sdílení účtu a stav předchozích migrací nejsou nyní ověřené. Patří do read-only provozního ověření před aktivací; nejsou překážkou lokálního auditu.
- Číselné fair use hodnoty a vybraný tenant releasu nejsou schválené. Připravit konkrétní návrh s dopady a vyřešit před enforcement/produkčním rolloutem, nikoli začít s libovolnými čísly.
- Absolutní ochranu proti distribuovanému útoku nelze doložit jen aplikačními testy. Zůstává závislost na síťové kapacitě, provider limitech, reakcích obsluhy a budoucích změnách; ty mají mít průběžnou kontrolu a alerty.

## Definice dokončení

- [ ] Inventář zdrojů, deployovaných cest a efektivních DB oprávnění je reconciliovaný; každá cesta má policy nebo zdůvodněnou výjimku.
- [ ] Nezávislá bezpečnostní matice má u každého aplikovatelného požadavku aktuální důkaz a žádný nevyřízený nález; zdůvodněné N/A jsou konkrétní.
- [ ] Rozhraní modulů zachovávají doménové vlastnictví; pokusy, přijaté operace, occupancy a provider attempt mají odlišnou doloženou transakční sémantiku.
- [ ] Limiter, cleanup, polling, metriky ani cache miss samy neumožňují neomezenou spotřebu; cached public sync zůstává bez DB závislosti.
- [ ] Potvrzené mezery v autorizaci, integritě a izolaci tenantů jsou opravené, ne pouze zpomalené limiterem.
- [ ] Limity nelze obejít jinou instancí, restarty, přímým API, podvrženou IP, jiným tenantem nebo novým commandId.
- [ ] E-mailové admission, příjemce, backlog a tenantové podíly fungují přes všechny producenty; jeden sender zachovává globální provider fence.
- [ ] Legitimní nákup, auth, odbavení a paid delivery mají pozitivní důkaz; funguje odklad, obnova i porucha limiteru bez ztráty závazků.
- [ ] Fair use má konkrétní hodnoty, odpovídá implementaci a dává pořadateli srozumitelnou informaci o omezení a navýšení.
- [ ] Objemové limity mají přiměřenou rezervu a doložené škálování pro malou, střední a velkou akci; nové účty/session ani útočný provoz samy nezvyšují společný strop a bezpečnostní limity proofů.
- [ ] Vznik akcí přes create, duplicate, šablonu i finalize draftu sdílí atomickou kvótu; nové jednotky/editorské účty, smazání nebo změna stavu ji neobcházejí. Drafty, uložené akce a kopírování souborů mají vlastní omezenou spotřebu.
- [ ] Fair use odlišuje Unit/pořadatele od Organization/tenanta; automatický vznik jednotek a případný aktivní import akcí nemají neomezenou alternativní cestu. Bootstrap draftu nečerpá skutečný create slot a neúplný import neodstraňuje lokální akce.
- [ ] Číselná policy je v jednom chráněném katalogu s mapou operací, cílenými overrides, konzistentní revizí a auditem; upravené handlery neobsahují vlastní konkurenční limity. Změna policy nemění identitu ani minulou spotřebu budgetu.
- [ ] Krátkodobé a denní čítače jsou oddělené, ale všechny alternativní create routy je sdílejí; selhání dalšího pravidla neponechá částečnou business spotřebu. Scoped override nemění globální actor pravidlo podle zvoleného cíle.
- [ ] Vyčerpaná běžná e-mailová kvóta neblokuje zaznamenání platby dříve přijaté objednávky; omezená rezerva závazků a stejná fronta zachovávají provider fence a retryable failure při skutečné poruše.
- [ ] Staré čítače, bypassy, nepotřebné granty a dočasné cesty jsou odstraněné nebo explicitně ohraničené; kompatibilní bezpečnostní migrace nejsou nevyřízené.
- [ ] CI hlídá nové vstupy; metriky, alerty, incidentní pauzy, cleanup a obnovovací runbook mají vlastníka.
- [ ] Případný autorizovaný rollout má doložené SHA, runtime policy, migrace, vybraný tenant a skutečný živý stav. Bez něj je výsledek označen pouze jako lokálně připravený.
