# Wix Partner Billed - výsledek realizace

Aktuální stav: source je na `main`, DB/backend a klient `prod/festapptickets` jsou
nasazené jako `0.20.444+949`. Vlastník osobně podepsal dodatek a DocuSign potvrdil
dokončení všemi stranami. [Doklad a odeslaná žádost o aktivaci](../../integrations/wix/evidence/addendum-completion-20261028.json)
jsou uložené; Erel byl informován ve stávajícím vlákně. Billing zůstává vypnutý.
Wix nyní blokuje podání požadavkem na external billing permission a payouts.
Produkční hosting nového widgetu a marketplace submission nejsou dokončené.
Nezávislá [kritická kontrola](wix-partner-billing-CRITIC-2026-10-28.md) následně
našla tři P2 vady. Všechny jsou opravené, kritikem znovu ověřené a nasazené
[migrací 20261028160000](../operations/releases/festapptickets-wix-critic-fix-2026-10-28.json).
Následující původní části zachovávají historii před nasazením; aktuální receipt je
[produkční foundation release](../operations/releases/festapptickets-wix-foundation-2026-10-28.json).

## Architektura a implementace

Na následný výslovný pokyn uživatele vznikl společný
[zdroj servisních příjmů](../architecture/service-fees.md) v `public.service_fee_*`,
oddělený od peněz pořadatelů v `eshop`. Existující `authoring/finance.sql` spravuje
banky a refundace pořadatelů; ticket-order Fakturoid zajišťuje jejich kupující
faktury. Ani jedno není příjmovou knihou Festapp.

Nový zdroj vlastní individuální smluvní procento a jeho časové verze, nezávislý
akviziční důkaz, skutečnou úhradu nebo vratku servisní faktury a přesnou alokaci
k původním objednávkám. Import je jen servisní RPC s povinnými referencemi na
reálnou fakturu, úhradu a alokaci. Sazba nemá default; peníze se nepočítají z
plateb za vstupenky. Nejednoznačná nebo neúplná alokace se odmítne.

Wix adaptér čte tento zdroj. Zachovává původní `prepare.mjs` jako jediný výpočet
CSV/API v USD. Původ objednávky bere z uloženého serverového důkazu a zvlášť
vyžaduje Wix akvizici nejpozději při vzniku objednávky. Refundace dědí původní
instalaci, kurz a smluvní údaje. Zdroj uchovává původní provenance snapshot i po
smazání kupující objednávky, bez tokenů nebo podepsaných URL.

[Dispatcher a operátorská obnova](../../integrations/wix/billing/DELIVERY.md)
používají OAuth konkrétní instalace a ověřují token-info před billing POST.
SQL journal odděluje prepared/sending/confirmed/rejected/unknown, atomicky
přiděluje pokusy a blokuje změnu digestu i souběžný send. Expirovaný pokus,
5xx, timeout, ztracená nebo neplatná odpověď zůstávají unknown. Opakování dovolí
jen doložená reconciliation pod stejnou identitou. Její audit zůstává zachován.
Aktivace je v nové migraci vypnutá a nemá veřejný aktivační endpoint.

Nová migrace: `20261028150000_service_fees_wix_delivery.sql`. Kanonické SQL
ověřuje `python3 automation/assemble-service-fees-migration.py --check`.
Původní replay oprava ani checkout/payment hranice nebyly touto realizací změněny.

## Skutečné ověření

- Čerstvá izolovaná Supabase PG15 DB `festapp-wix-billing-20261028`, loopback
  port 60222: baseline a forward migrace včetně obou Wix migrací prošly.
  Finální nová migrace byla po úpravě period smluv aplikována také atomicky
  přes `psql --single-transaction` na této disposable DB.
- Wix suite: 31/31, včetně PostgreSQL/executor testu bez skipu. Po poslední změně
  smluvního časového scope znovu prošly 3 dotčené dispatcher/source testy;
  zbývajících 28 testů mělo nezměněné vstupy.
- Executor používá skutečné RPC nad PostgreSQL a falešný provider přes skutečný
  OAuth/HTTP adaptér. Ověřuje import -> projekci charge/partial/full refund,
  restart s již commitnutým unknown, souběh dvou DB spojení, expiraci claimu,
  reconciliation fencing, nesprávnou instalaci, response decoding, role,
  nedoloženou sazbu, překryv smluv a neměnnost akvizice.
- Web replay/provenance: 13/13. Edge identity/handler/entrypoints: 77/77.
  Coverage inventory: pass, 45 produkčních funkcí bez nepokrytého endpointu.
- Existující SQL regrese: checkout origin, client-sync runtime a Stripe order
  creation, 3/3. Wix build a sealed package prošly. `git diff --check` a shoda
  kanonické migrace prošly.
- Policy suite `node --test automation/tests/abuse_policy_coverage.test.mjs`:
  5/6; trvá známý nesoulad `/occasion-lifecycle` v inventáři image Workeru.
  Tento gate není zelený a nebyl obejit ani upraven kvůli releasu.

Simulovaný provider není důkazem živého Wix tokenu ani skutečné billing události.
Proveden také izolovaný headless read-only test zveřejněného Harmony QA webu.
Skutečný token přiřazené aplikace z nativní host odpovědi prošel přímo
`verifyWixIdentity` proti živému Wix token-info. Instance
`5ebf65f5-1d62-43a1-a7f6-f04b06f22354` a site
`60fac33a-8ef8-4122-a754-2b6b98a7428b` odpovídají QA instalaci.
Produkční Festapp domény byly blokované síťovými pravidly; nebyl proveden
nákup, hold ani billing. Token se nevypisoval a soukromá raw host odpověď byla
po ověření odstraněna. Tato kontrola neprokazuje celý nový widget/proof flow;
po lokálním síťovém override bundle se požadavek na checkout context neobjevil.
Browser byl zavřen. Flutter build nebyl proveden.
Tato evidence není produkční release attestace.

## Produkce a externí stav

Přečteno existující Gmail vlákno `1a18198a75444077`: poslední zpráva při kontrole
je odeslaný dotaz `1a18267de29c3241`, odpověď na OSVČ dosud chybí. Písemné fee-only
potvrzení a nulové samostatné publisher poplatky zůstávají platným nalezeným
podkladem; nebyl přijat nový závazek.

Read-only SSH ověřilo hostname, aktivní runtime DB, `current_database()` a
organizaci 3 `vstupenky.online`. Živý `backend-activation.json` odpovídá
`festapptickets`, canonical, generation 1. V produkčním migration ledgeru není
ani `20261028130000`, ani `20261028150000`; checkout origins, zdroj servisních
příjmů i delivery journal tam neexistují. Žádná produkční data nebyla načtena
nad rámec identity organizace a katalogu migrací/tabulek.

Native portál nebyl v tomto běhu znovu autentizovaně otevřen. Poslední zachovaná
native evidence uvádí unlisted 1.1, DYNAMIC Custom plán, external billing false,
bez podpisu a marketplace submission. Aktuální review/publication stav tedy
není nově ověřený a nesmí být označen jako publikováno nebo review pending.

## Historický seznam před rolloutem (aktuální stav viz úvod)

1. Dodat skutečné individuální smlouvy, úhrady vlastních servisních faktur,
   případné vratky, FX/smlouvu s Wixem a akviziční důkazy do nového zdroje.
   V tomto běhu nebyl připojen žádný skutečný účetní účet ani naplněna reálná data.
2. Dostat správný dodatek pro OSVČ, skutečně jej dokončit a doložit aktivaci
   Partner Billed i odpovídající oprávnění. Poslední e-mail není podpis.
3. Vyřešit policy inventory gate s vlastníkem a prokázat celý nový hosted widget/proof flow. Samostatný
   serverový verifier už se skutečným Wix host tokenem prošel. Zachovat všechny ostatní povinné release gates.
4. Izolovat přesný Wix diff od cizí práce, publikovat ověřené main/tenant revize,
   nasadit DB -> backend s chráněným email restartem -> klient
   `prod/festapptickets` lokálním buildem/direct deploy -> widget. Rutinní deploy
   delegovat podle AGENTS.md. Reálné verze ověřit read-only.
5. Po splnění podmínek podat marketplace submission a doložit native receipt,
   následné review a skutečnou publikaci. Testovací produkční nákupy, holdy nebo
   smyšlené billing události nejsou autorizovány a nebyly použity.

Rozpracované Make/admin/Flutter změny zůstaly zachovány. Nebyl vytvořen commit
ani push, které by je přibalily do neověřeného produkčního vydání.

## Pokračování po potvrzení OSVČ uživatelem

- ARES ověřil Michael Bujnovský, IČO 06455361, právní forma 101. Úplné údaje
  sídla jsou uložené pouze v ignorované `.private/` a byly použity v existující
  DocuSign obálce. Vyplněno šest nepodpisových polí: dvě identifikace podnikatele,
  sídlo, název a popis aplikace a role `Sole trader / owner`. Použito `Finish Later`;
  po opětovném otevření jsou identifikace, aplikace a role skutečně uložené.
  Podpis ani `Finish` nebyly použity. Pole země založení korporace zůstává prázdné;
  pevné znění `corporation` stále vyžaduje opravu Wixu. Odpověď ve vlákně nepřišla.
- Bezpečnostní inventář byl doplněn o skutečný `/occasion-lifecycle` route a jeho
  existující testy. Policy suite nyní 6/6; lifecycle testy 5/5. Nejde o výjimku
  z gate ani změnu produkčního oprávnění.
- Nový bundle v opravdu izolovaném headless browseru prokazatelně vystavil
  `accessTokenListener` a přes skutečný Wix SDK odeslal token i `x-wix-linguist`.
  Požadavek byl odchycen bez produkčního zápisu. Kanonický handler ověřil token
  u živého Wixu a SQL v disposable DB vydalo skutečně validní podepsaný kontext.
  Browser mock preflight neumožnil následné načtení iframe; tento celý tok tedy
  zatím není označen jako úspěšný. Zjištěná chybějící hlavička `x-wix-linguist`
  byla doplněna v CORS a cílený preflight regresní test prošel; Edge suite 78/78.
- Aktuální upstream `176a27aea10f903852a659bb9389432f3e0637ff` už obsahuje
  migraci `20261028130000_notification_personal_read_batches.sql`. Wix původ byl
  před publikací přesunut na `20261028140000_wix_checkout_origin.sql`. Historické
  údaje výše popisují dřívější stav, nikoli nově použitelnou migrační identitu.
- Čistá pracovní větev `/private/tmp/festapp-wix-partner-billing-20261028` odděluje
  tento task od Make/admin/Flutter změn. Čerstvá disposable DB z aktuálního main
  prokazuje správné tři samostatné ledger záznamy `130000` notification,
  `140000` Wix origin a `150000` service fees/delivery. Prošel source/executor
  test 3/3 bez skipu, web 13/13, SQL regrese 3/3, policy 6/6 a build/package.

Nová účetní hranice a dispatcher zůstávají prázdné a deaktivované. Žádné skutečné
úhrady ani akviziční důkazy se nevymýšlejí. Následný technický rollout může nasadit
kompatibilní infrastrukturu s vypnutým billingem; podpis, aktivace a marketplace
zůstávají oddělené skutečné kroky. Podepsání smlouvy provede osobně uživatel.

## Publikace zdrojů a doplněná native evidence

Ověřená implementace je publikovaná přímo na autoritativním `main` jako
`94a1288a341b5eb39c275ff51f4686c2c39e9e14` (commit implementace
`3444137d48932fc7e29072085e25390afc2bff9a`, následně pouze normalizace whitespace
SQL a zachování oficiálních CRLF bajtů report CSV). Před push byl znovu načten
upstream a ověřena návaznost na `176a27aea10f903852a659bb9389432f3e0637ff`.
Původní pracovní strom zůstává nedotčený včetně cizí práce.

Po samostatném ověření reálného host tokenu, kanonického handleru a SQL podpisu
prošel widget na zveřejněném Wix hostu s fixture transportem odpovědi do stejného
originu: oba iframe i přímé odkazy dvou lokálně připojených widgetů nesou kontext;
přidání druhého widgetu zachová první iframe a změna titulku prvního zachová druhý.
Produkční Festapp domény byly blokované a nebyla vytvořena objednávka ani hold.
Tato transportní adaptace nepředstírá browser kvalifikaci produkčního CORS;
nový source preflight test skutečnou hlavičku SDK ověřuje. Viz
`integrations/wix/evidence/native-origin-proof-20261028.json`.

Rutinní backend a web rollout převzal levnější deployment agent. Source zůstává
zmrazený na uvedené revizi; použit je oddělený čistý klon s větví `main`, nikoli
přepnutí nebo vyčištění původního pracovního stromu. Existující chráněný schema-2
release manifest byl nalezen z předchozího schváleného přenosu a nevyrábí se nový.
Přesný výsledek produkčního nasazení musí doložit závěrečný receipt, nikoli tento
záznam o přípravě. Billing aktivace, podpis a marketplace zůstávají neprovedené.

## Ověřený produkční výsledek

Zdroj `main 94a1288a341b5eb39c275ff51f4686c2c39e9e14` a tenant
`5b5f69900ad5d33774c10834b210b2aa5b740e16`, verze `0.20.444+949`, jsou nasazené
v autorizovaném scope. Ledger obsahuje Wix origin `20261028140000` a service
fees/delivery `20261028150000`; upstream notification `20261028130000` zůstalo
samostatné a beze změn. Functions bundle byl nasazen kanonickým installerem.
Email se během restartu pauzoval a vyprázdnil, kontrolní JSON požadavek na worker
vrátil 401, po obnovení je `paused=false`, `producer_access_ok=true`, bez alertů.
Klient prošel main-owned tenant drift, existujícím chráněným schema-2 manifestem,
lokálním Flutter/web buildem a direct deploy. Živá verze, assety a právní stránky
prošly třemi souvislými kontrolami.

Samostatný skutečný browser test na vlastním zveřejněném Wix hostu nyní prokázal
produkční CORS `OPTIONS 200` a `POST 200` s reálným tokenem Wix SDK a existujícím
veřejným non-demo formulářem organizace 3. Nový widget byl přepsaný pouze uvnitř
izolovaného browseru, nikoli na hostingu. Iframe i přímý odkaz nesly skutečný
kontext vydaný produkčním endpointem; read-only SQL potvrdilo platnost podpisu.
Produkční dokument formuláře a order endpoint byly síťově blokované. Po testu
zůstalo 0 checkout origin záznamů, 0 fee settlements a 0 delivery záznamů;
billing byl vypnutý. Tento pozdější probe nahrazuje předchozí otevřený CORS bod.
Browsery byly ukončené a raw token/capability podklady odstraněné.

Zbývá oprava pevného označení `corporation` ze strany Wixu a osobní podpis
uživatelem, následně doložená Partner Billed aktivace a skutečné vydání widgetu
s marketplace submission/review/publication. Účetní import musí při prvním
skutečném servisním příjmu obsahovat skutečné smluvní, platební a akviziční podklady.
Žádný takový pohyb ani jeho absence nejsou nahrazovány syntetickými reporty.

## Podpis a pokračování k App Marketu

Vlastník osobně dokončil podpis. DocuSign zpráva `1a183562faa939fa` potvrzuje
dokončení všemi stranami a obsahuje podepsané PDF; soukromá kopie je archivována
mimo Git. Zpráva `1a18358487893fcd` byla odeslána Erelovi ve stávajícím vlákně
a přečtení Gmailu potvrdilo `SENT`. Obsah výslovně uvádí OSVČ a žádá potvrzení
dostatečnosti a aktivaci Partner Billed. Žádný obecný účetní příjem nebyl domyšlen.

Nativní portál stále uvádí verzi 1.1, plán Ticketing service a dva blockery:
`Set up payouts` a `Request external billing permission`; tlačítko Submit App je
vypnuté. Payouts vede na samostatný Partner Program a jeho další podmínky.
Ty nebyly přijaty a bankovní údaje nebyly vymyšleny. Vyřešení activation/payout
požadavků a zbývající qualification/release gates zůstávají podmínkou publikace.

Nový widget je připraven na samostatné testovací Cloudflare Pages adrese
`https://600abe03.festapp-wix.pages.dev` pro source `f0fed2a0b`.
[Hosting receipt](../../integrations/wix/evidence/hosting-preview-20261028.json)
dokládá přesnou shodu se zapečetěným balíčkem, HTTP/content types/CORS a funkční
`/settings` a `/help`. Hash stabilního widgetu zůstal před i po nasazení stejný.
Nativní registrace se nezměnila. Release check zůstává záměrně blokovaný chybějící
aktivací, aktuálními editor receipts, billing implementation receipt a ověřením
store assets; žádná podmínka nebyla oslabena.

## BI ověření požadované Wixem 29. října

Erelova zpráva `1a186cc331d539c7` požaduje doručení jedné BI události a následné
upozornění pro jeho kontrolu. Přístup přes existující `wixBillingProvider` již
prošel skutečným OAuth i token-info (HTTP200, správná aplikace a vlastní QA
instalace, typ APP). Token ani app secret nebyly uloženy do evidence.

[Příprava ověření](../../integrations/wix/evidence/bi-verification-preparation-20261029.json)
obsahuje návrh jedné qualification-only CHARGE s gross/net/share USD0. Kritická
kontrola vyžaduje potvrzení Wixu, protože obecné API reportuje skutečné charge/refund
a nulové decimal hodnoty samy nepotvrzují testovací režim. Konkrétní dotaz byl
odeslán Erelovi (`1a186f14ad37be72`, ověřeno SENT), včetně otázky na ne-nulový test
a možnost ověření před aktivací. Samotný billing POST nebyl proveden; zdroj
příjmů, delivery journal ani activation nebyly změněny. Po potvrzení postupu
lze provést jediný zdokumentovaný pokus, bez automatického opakování, a jeho
skutečný výsledek předat Erelovi.

## Následný nezávislý audit BI přípravy

[Kritik](wix-bi-verification-CRITIC-2026-10-29.md) ověřil skutečné emaily i úzký
význam OAuth evidence. Našel jednu P3 nepřesnost v přípravné evidenci času; ta je
opravená. Doplněn byl dosud chybějící dormant sender s jedinou pevnou QA instalací,
CHARGE USD0, povinným reviewed vendor approval a fsynced exclusive journalem
sdíleným přes git common directory. Pád, paralelní volání, neznámý výsledek ani
odmítnutí neopravňují další pokus. Nezávisle prošlo 20/20 cílených testů bez skipů.
CLI inspect ukazuje `not-attempted`; žádný billing POST ani activation neproběhly.

Publikace připraveného nástroje byla kritikem schválena. Odeslání stále čeká na
potvrzení konkrétního testovacího postupu Wixem; přijetí BI události a aktivace
se následně ověřují zvlášť. Širší editor/store qualification zůstává samostatnou
nedokončenou částí marketplace práce, nikoli hotovým výsledkem tohoto auditu.

## Pokračování po odpovědi Wixu 1. listopadu

Wix ve zprávě `1a1962120dade694` potvrdil přijetí BI události a udělil přístup
k cenovým plánům. Žádá oznámení po publikaci aplikace. Tím je čekání na souhlas
s nulovým testem a kontrolu BI uzavřeno; historický přípravný stav výše již není
aktuální. [Doklad dokončení](../../integrations/wix/evidence/bi-verification-completion-20261101.json)
spojuje souhlas z 29. října, odeslané oznámení a dnešní potvrzení Wixu. Read-only
kontrola společného journalu ověřila `confirmed`, HTTP200, pokus
`7876ef54-74a5-49ac-828a-a8e0c82ea910`, čas `2026-10-29T14:25:17.034Z`
a všechny tři částky USD0. Událost se znovu neodesílá.

Přístup k plánům sám nedokládá native external-billing/payout stav, marketplace
publikaci ani aktivaci běžného dispatcheru. Zbývá aktuální čtení portálu, dokončení
cenového plánu bez vymyšlené sazby a původní hosting/editor/store release gates.
Při zahájení navazující kontroly byl zdroj widgetu, jeho dependencies a lockfile
shodný s preview `f0fed2a0b`. Následný živý test odhalil nefunkční předání tokenu;
průběh a aktuální omezení popisuje pokračování níže.

### Native účtování odemčeno, živé SDK ověření dosud neprošlo

[Autentizované čtení cenového plánu](../../integrations/wix/evidence/portal-pricing-20261101.json)
ověřilo `isExternalBilling=true`, zachovaný individuální Custom plán, verzi 1.1
a nula nativních blockerů. Privacy/support stránky jsou dostupné; podání není
dokončené jen tím, že Wix zobrazí nula blockerů.

Původní připravený bundle byl krátce nasazen, ale živý Studio test s platným
formulářem neprošel. Po první [obnově](../../integrations/wix/evidence/hosting-rollback-20261101.json)
byl doplněn regresní test skutečného bundlovaného SDK s opožděným vložením prvku.
Odhaluje, že lazy `site.auth()` nemá při konstrukci prvku skriptový kontext.
Commit `2954fabcf` zachytává auth při načtení skriptu; 42 Wix testů a 54 sdílených
checkout testů prošlo, čtyři nezměněné DB testy zůstaly v tomto běhu přeskočené.

Ani [opravený bundle](../../integrations/wix/evidence/hosting-auth-fix-20261101.json)
v živém Studiu nedostal token, a proto byla [produkce podruhé obnovena](../../integrations/wix/evidence/hosting-auth-fix-rollback-20261101.json).
Režim `Site` funguje, autentizovaný POST na proof endpoint pozorován nebyl.
Příčina úplného živého selhání není doložena pouhou lokální opravou načasování.
Produkční API z Wix originu správně odpovídá na neautentizované preflight/rejection
kontroly. Žádný skutečný nákup, hold ani billing událost tímto pokračováním nevznikly.

Připraven je [samostatný diagnostický preview](../../integrations/wix/evidence/auth-diagnostic-preview-20261101.json)
s doslovným module-level klientem a listenerem podle [oficiálního kontraktu](../../integrations/wix/evidence/wix-auth-documentation-20261101.json),
bez checkout iframe a finančních operací. Testuje se přes vývojovou instalaci,
nikoli dalším slepým přepnutím stabilních produkčních assetů.

[Read-only DB evidence](../../integrations/wix/evidence/backend-readiness-20261101.json)
potvrzuje oddělený stav: normální dispatcher zůstává vypnutý a delivery journal
prázdný. Skutečný settlement/acquisition feed nebyl vymyšlen ani aktivován.
Existující dema vyžadují autentizaci a starý veřejný QA slug neexistuje; nelze je
vydávat za anonymní funkční reviewer sandbox.

### Rozhodující nativní reprodukce a bezpečný konečný stav

Samotný draft/Test App změnu URL nepřenesl. Proto byla vydána neveřejná hlavní
testovací verze 2.0 s ruční aktualizací, aktualizována pouze vlastní Studio QA
instalace a vložen jediný nový prvek na dočasnou stránku.
[Skutečně načtená diagnostika](../../integrations/wix/evidence/native-auth-diagnostic-result-20261101.json)
vrátila `mode=Site`, `injectionCount=0`, `proof=timeout`. Jde o nativní výsledek
zdokumentovaného plného module-level SDK klienta, nikoli simulaci s ručním tokenem.
Nedokazuje stejnou chybu na všech Wix webech; příčina nepředání tokenu na této
instalaci zůstává k dořešení s Wix SDK týmem.

[Obnovení verze 2.1](../../integrations/wix/evidence/native-restoration-20261101.json)
vrátilo běžný stabilní script URL, původní SDK dependency a tag bez nových
oprávnění/poplatků. Dočasná stránka byla odstraněna a vrací404. Studio homepage
má původní dva prvky, Harmony původní jeden; původní URL, titulky a styl zůstaly
zachované. Stabilní widget má SHA `e83f4fcaee1e78241300175d4a06fc20b1805a952469f278bbd85f3c391a7025`.
Přítomnost starého wrapperu neznamená funkční starý QA formulář: ten nadále404.

Ve stávajícím Gmail vlákně je [konkrétní odpověď Erelovi](../../integrations/wix/evidence/vendor-followup-draft-20261101.json),
draft `r2329189293174415204`. Obsahuje výsledek testu, přesné SDK verze a
identifikátory aplikace/extension, žádné tokeny. Odeslání vyžaduje výslovný pokyn
podle pravidel relace pro zprávy třetím stranám; ten zatím nepřišel.
App Market podání ani běžný financial dispatcher nebyly aktivovány.

Oprava lokálního script-time SDK regresního testu je na main `2954fabcf`.
[Záznam publikace](../../integrations/wix/evidence/source-publication-20261101.json)
přiznává procesní odchylku: přímý push prošel s obejitím požadavku na PR; další
publikace musí respektovat zjištěné pravidlo. Lokální timing fix se nesmí
vydávat za vyřešené nativní předání tokenu.

### Oprava původní diagnózy a reprodukovatelný výsledek

Porovnání stejného nativního webu a bundle v hlavním Chromu a čistém lokálním
prohlížeči vyvrátilo plošné selhání Wix SDK. Čistá viditelná záložka dostala
nativní callback a skutečný proof POST200; skrytá záložka v hlavním Chromu
inicializaci odkládala. Callback v ní později také přišel, až po našem původním
12sekundovém limitu. Ani pouhé zvýšení wall-clock limitu na60 sekund nestačilo.
Nativní provider i reference prvku byly po dokončení hydratace přítomné.

Opravený kód měří60 sekund viditelného čekání, rozpočet při skrytí pozastavuje
a při opětovném zobrazení zachovává zbývající čas. Po skutečném vypršení request
zruší; není přidán unsigned fallback ani automatické opakování. Regresní test
nejprve prokázal původní chybu s opožděným callbackem, poté prošly případy dlouhé
skryté inicializace, opakovaného hide/show a tokenu doručeného po expiraci.

[Opakovatelný probe](../../integrations/wix/evidence/native-auth-probe-helper-20261101.json)
prošel na Harmony, Studiu a Editoru: přesný načtený SHA bundle, skutečný POST200
a podepsaný kontext v iframe i přímém odkazu. [Skrytý Chrome](../../integrations/wix/evidence/visible-time-candidate-20261101.json)
po75 sekundách správně stále čekal bez falešné chyby. To není tvrzení o dokončené
platbě nebo neprovedeném foreground testu hlavního profilu. V aktuální suite
prošlo46 Wix a54 sdílených testů; čtyři nezměněné DB případy byly přeskočeny.

Zkušenosti a přesný postup jsou v [provozním playbooku](../../integrations/wix/OPERATING-PLAYBOOK.md)
a bezpečný CLI probe v `integrations/wix/scripts/probe-native-auth.py`.
Původní návrh eskalace na Wix byl nahrazen neodeslanou pravdivou aktualizací;
externí problém nebyl potvrzen jako příčina.

Veřejný návod pro pořadatele je na `https://wix-guide.festapp-wix.pages.dev/help`
a očištěný technický postup na `https://wix-guide.festapp-wix.pages.dev/integration-guide`.
[Ikona ve Wixu](../../integrations/wix/evidence/canonical-icon-20261101.json) odpovídá
PNG exportu z kanonického SVG a původní CDN bytes byly ověřeny. Profil2.1
je up-to-date, žádný nový komponentový release tím nevznikl. Skutečná App Market
publikace zůstává odděleným nedokončeným krokem.

### Produkční nasazení 2026-11-01

PR #681 byl po všech pěti zelených kontrolách sloučen do main jako
`d07a41b560c3daee5ea8e9b1b011a68022dfc69e` s povolenou administrátorskou výjimkou;
nejde o nezávislé review. Produkční Pages deployment `50713e1a` servíruje přesné
byty zapečetěného balíčku. [Release receipt](../operations/releases/wix-runtime-20261101.json)
obsahuje hashe, readback všech devíti veřejných souborů a zachovaný rollback.
Nativní probe proti skutečné stabilní adrese bez náhrady skriptu prošel na
Harmony, Studiu i Editoru: přesný hash, proof POST200 a podepsaný kontext.

Veřejné návody: https://festapp-wix.pages.dev/help a
https://festapp-wix.pages.dev/integration-guide. Kanonická ikona je uložená ve
Wix profilu. App Market nebyl odeslán; checkout/reviewer gates a skutečné
finanční podklady zůstávají oddělené. Nebyly vytvořeny objednávky, rezervace ani
platby a opakování BI události ani běžný finanční dispatch nebyly spuštěny.
