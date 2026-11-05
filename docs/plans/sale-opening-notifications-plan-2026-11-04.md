# Upozornění na spuštění prodeje

Aktualizace podle uživatele 2026-11-04 po localhost náhledu: odběr je single opt-in. Kliknutí na „Upozornit“ ihned uloží aktivní odběr, bez potvrzovacího e-mailu a bez stavu čekání na ověření. Jediná zpráva je `sale_opening_opened` při skutečném otevření. Zůstávají ordinary recipient/tenant limity, odhlášení, deduplikace a send gates. Odběrový blok lze zobrazit samostatně s `enable_countdown=false`, bez odpočtu i jeho data. Toto rozhodnutí nahrazuje níže uvedené původní požadavky na ověření, dvě šablony a pending retenci.

Datum: 2026-11-04  
Stav: Lokálně implementováno; validační výsledky a meze jsou v `sale-opening-notifications-RESULT-2026-11-04.md`. Bez produkčního nasazení.  
Ověřování při implementaci: standard - veřejný kontrakt, tokeny, databázová migrace a společná e-mailová fronta  
Výchozí bod průzkumu: pracovní strom `main`, HEAD `a31277e3c`, včetně současných necommitnutých změn.

## Výsledek a rozsah

Návštěvník před zahájením prodeje zadá e-mail, potvrdí adresu a dostane jediné oznámení, až se prodej skutečně otevře. Funkce patří do současného formuláře, harmonogramu a komunikace. Nevzniká účet, objednávka, vstupenka, rezervace ani pořadí.

Upřesnění uživatele: odběr je samostatná přesouvatelná komponenta ve stejném obsahovém editoru jako countdown. Umístění pod countdownem je pouze výchozí, nikoli pevná součást layoutu.

Uživatel potvrdil upozornění při spuštění bez přednostního nákupu. Následný nápad na upozornění na docházející místa výslovně vyřadil. Nerealizovat pro něj přepínače, prahy, opt-in ani skrytou infrastrukturu.

Součástí jsou oba veřejné klienty (Flutter i JS včetně embedů), vytvoření akce a následný editor, ověření adresy, odhlášení, přehled zájemců a rozesílky, dvě šablony e-mailů a automatické zpracování i bez otevřeného prohlížeče.

Mimo rozsah: kapacitní náhradníci, prioritní nebo neveřejný prodej, hromadný import adres, marketingové kampaně, připomínka předem, automatické zprávy o změně termínu, SMS, sběr bez známého data a opakované kampaně stejného formuláře. Implementace, commit, push, produkční migrace a release nejsou tímto plánováním provedené ani autorizované.

## Potvrzený současný stav

| Fakt a opora v kódu | Dopad na návrh |
| --- | --- |
| `database/functions/eshop_forms/form_availability.sql`: `get_form_availability_snapshot_internal` a `get_form_availability_from_config_internal` vlastní ruční uzavření, začátek a konec. | Odběr a rozesílka používají tento gate. Žádný druhý výpočet otevření podle countdownu. |
| `lib/components/forms/README.md`, `widgets_view/countdown_content.dart`: odpočet je vložitelný HTML blok bez vlastního data; datum vlastní schedule. `lib/components/html/html_embedded_block.dart` vlastní popis atomic slotu. | Odběr uložit jako další atomic slot v témže HTML dokumentu. Slot neobsahuje stav odběru, tokeny ani datum. |
| `lib/components/html/rich_html_editor_controller.dart` a `html_editor_document.dart` jsou společné pro obsah i e-maily. Countdown je `PreservedHtmlNode` + `_PreservedBuilder`; e-mailové bloky jsou `TemplateTokenBlock` + `_TemplateBlockBuilder` a `TemplateAuthoringProvider`. | Základ editoru je společný, kontrakt samotných atomických bloků zatím plně sjednocený není. Před přidáním odběru sjednotit společné chování a prezentaci bloků, zachovat doménové adaptéry uloženého formátu. |
| `web_client/src/components/forms/form_availability_service.js`: `BEFORE_START` dnes vykreslí countdown a volitelnou informaci; `lib/components/forms/views/form_page.dart` má odpovídající větev. | Rozšířit obě předprodejní větve, včetně varianty se skrytým odpočtem. |
| `lib/components/forms/views/form_editor_content.dart`, `occasion/setup/occasion_setup_sales.dart` a `database/functions/occasion_setup/finalize.sql` vlastní editor a založení harmonogramu. | Jedna uložená konfigurace pro oba administrátorské vstupy. |
| `database/functions/eshop_forms/form_settings.sql`: whitelist a validace metadat; `admin_form_commands.sql`: `manage_form`; `lib/components/forms/form_commands.dart`: klientské příkazy. | Nové nastavení projde současným receipted save, ne vedlejším přímým UPDATE. |
| `database/functions/eshop_waitlist/`, `lib/components/forms/README.md` a `docs/architecture/ai_context.md` popisují již existující kapacitní waitlist s waiting tickets. | Upozornění je odběr kontaktu, ne alternativní evidence účastníků. Existující waitlist se nepřejmenuje ani nepoužije jako úložiště. |
| `lib/components/email_templates/README.md`: obsah a wrapper mají dědičnost akce > pořadatel > organizace; katalog je explicitní. | Nové zprávy používat ve stejném editoru, náhledu a dědičnosti. |
| `database/functions/emails/email_queue.sql`: `enqueue_email`, `email_intent_valid`, `begin_email_send`; `_shared/emailRegistry.ts` a `emailRenderer.ts`. | Přidat explicitní druhy zpráv a jejich platnost; pouze současný worker smí oslovit poskytovatele. |
| `database/functions/abuse/email.sql`: společné recipient/tenant limity a klasifikace. | Oznámení i potvrzení mají ordinary budget, žádnou výjimku pro auth nebo platby. |
| `database/functions/notification_center/form_availability.sql`: interní notifikace jsou podmíněné aktivací centra organizace. | Rozesílka nesmí záviset na aktivaci, odběru ani přečtení interní notifikace. |

UI/UX prošel subagent `gpt-6-astra`, reasoning `medium`, podle požadavku uživatele, s postupem `impeccable`. Návrh vychází z existujícího UI a komponent; neproběhlo browserové ověření ani vznik nového design systému. `PRODUCT.md` a `DESIGN.md` nejsou k dispozici.

## Produktová rozhodnutí a UI/UX

### Návštěvník

Aktualizace podle uživatele po localhost náhledu: samotný odběrový blok obsahuje pouze pole s placeholderem „E-mail“ a vedle tlačítko „Upozornit“. Bez vlastního nadpisu, úvodního vysvětlení a disclaimeru. Stav potvrzení či chyba se zobrazí až po interakci. Platí i pro neodesílající editorový náhled a oba klienty.

- Název funkce: **Upozornění na spuštění prodeje**. U přihlášek bez vstupenek použít přirozenou variantu „Upozornění na otevření registrace“. Nepoužívat zde „Seznam náhradníků“.
- V předprodejní stránce zachovat vzhled formuláře, název akce, absolutní datum a čas zahájení v jeho časovém pásmu. Výchozí pořadí: nadpis a countdown/datum, kompaktní odběr, rozšiřující informace a obrázky. Autor může odběr v obsahovém editoru přesouvat stejnými ovládacími prvky jako countdown, včetně umístění nad countdown nebo mezi textové bloky. Veřejná stránka i náhled respektují uložené pořadí, bez další pevné kopie pod dokumentem.
- Odběr: viditelný label „E-mail“, tlačítko „Upozornit e-mailem“, text „Pošleme Vám e-mail, až se prodej spustí.“ a vysvětlení „Přihlášení nezajišťuje rezervaci ani přednostní nákup.“ Jen adresa, žádné jméno, počet osob ani účet.
- Úspěch prvního kroku: „Zkontrolujte svou schránku a potvrďte upozornění.“ Stejná odpověď pro novou a již přihlášenou adresu. Síťová chyba zachová rozepsaný e-mail; příliš časté požadavky nabídnou opakování později.
- Odkaz z ověřovacího e-mailu otevře stránku akce s tlačítkem „Potvrdit upozornění“. Samotné otevření/GET nic nemění. Po explicitním potvrzení: „Upozorníme Vás, až se prodej spustí.“ Zobrazit aktuální termín a možnost odhlášení.
- Odhlášení přes e-mailový odkaz opět potvrdit tlačítkem. Opakovaná akce je úspěšná a bezpečná. Neplatný či expirovaný odkaz nabídne aktuální stránku akce, případně nové přihlášení, pokud ještě probíhá sběr.
- Při doběhnutí odpočtu načíst nový serverový bundle. Otevřený prodej zobrazí nákup, ručně zavřený formulář zůstane zavřený. Vyprodaný formulář dál používá existující kapacitní režim; odběratele do náhradníků automaticky nepřevádět.
- Jeden sloupec na mobilu, standardní pole a tlačítka, `autocomplete=email`, chyby přiřazené k poli, klávesnice a focus. Stavový region oznamuje výsledek, nikoli každou sekundu odpočtu. Výška embedu se aktualizuje současným mechanismem.
- Lokalizovat všechny podporované jazyky obou klientů i ukázková data. Výchozí vykání; explicitní existující komunikační tón musí být konzistentní s e-maily. Zachovat témata, kontrast a rozměry současných komponent.

### Administrace

- V části Prodej/Harmonogram pod začátkem přepínač **„Umožnit upozornění e-mailem“**, výchozí vypnuto. Zapnutí vyžaduje konkrétní budoucí začátek a publikovatelný formulář. Countdown může být skrytý, datum a odběr zůstávají použitelné.
- Průvodce vytvořením akce a následný editor zapisují stejnou konfiguraci; v režimech „Příprava“ a „Ihned“ je volba nedostupná s krátkým vysvětlením. Přepnutí režimu nesmí ponechat aktivní neplatný sběr.
- Po zapnutí zobrazit jen krátké vysvětlení ověření a automatického oznámení. Pokročilé ovládání obsahuje **Pozastavit sběr** a **Ukončit upozornění**. Pauza zastaví nové adresy, ale zachová existující závazek upozornit; ukončení zneplatní dosud neodeslaná oznámení. Obnovení nezpůsobí opakované obeslání.
- Obsahový editor nabídne blok **Upozornění e-mailem** s věrným neodesílajícím náhledem a stejným přesunem nahoru/dolů jako countdown. Zapnutí jej při absenci vloží jednou za countdown, případně na konec dokumentu bez odpočtu. Uloženou pozici při dalším načtení, změně data nebo opětovném zapnutí zachovat. Odebrání bloku je explicitní akcí pozastavující nový sběr, nikoli odhlášením existujících zájemců; nesmí se poté automaticky vrátit. Editor je přístupný i při skrytém countdownu. Náhled nesmí zapisovat odběr ani posílat e-mail.
- Odkaz **Zájemci** otevře standardní přehled se souhrny: čeká na ověření, aktivní, odhlášeno, ukončeno; pro oznámení samostatně ve frontě, přijato poskytovatelem, doručeno, chyba/potlačeno. Použít současný grid a komponenty historie doručení. Nevkládat tyto adresy mezi objednávky ani příjmy.
- Detail: maskovaná adresa v souhrnech, plná jen při oprávněném čtení, jazyk, čas přihlášení/ověření a skutečný stav zpráv. MVP nepotřebuje export, ruční hromadný resend ani editaci e-mailu.
- Odkaz **Upravit e-maily** vede do současné Komunikace/editoru šablon, s přesným scope a stejným náhledem. Žádný druhý HTML editor či nezávislá kopie obsahu v nastavení odběru.
- Změna data před spuštěním zobrazí počet ověřených zájemců a informaci: upozornění se odešle až při otevření podle nového nastavení; o změně termínu samostatný e-mail neodchází. Ruční uzavření odeslání odloží. Odebrání data nebo definitivní ukončení vyžaduje explicitně ukončit upozornění, nelze tiše ztratit aktivní odběry.
- Po rozeslání se zobrazí výsledek a funkce se znovu automaticky nevyzbrojí. Změna data ani zavření/otevření téhož formuláře nevytvoří novou kampaň.

## Kanonický datový a servisní kontrakt

Navrhované nové názvy níže jsou cílový kontrakt, nikoli tvrzení o existující implementaci.

### Vlastnictví a persistence

Doména `database/functions/sale_opening_notifications/` vlastní odběry, stav kampaně, tokeny a produkci intentů. Schedule a dostupnost zůstávají v `eshop_forms`; odesílání v `emails`. Funkce SQL pouze v `public`, bez persistentních aplikačních triggerů.

1. `forms.data.sale_opening_notifications`: pouze authoring nastavení `enabled` a `collection_paused`. Chybějící konfigurace znamená vypnuto. Začátek se vždy bere z `schedule.start_time`; žádný duplikovaný čas v nastavení.
2. `public.sale_opening_campaigns`: jedna kampaň na formulář, scope odvozený z uloženého formuláře a akce; fáze `armed / dispatching / completed / cancelled`, revize a čas pozorovaného otevření, metadata bounded zpracování. Žádné kopírování subscription dat mezi akcemi.
3. `public.sale_opening_subscriptions`: kampaň, normalizovaná adresa, jazyk a evidence přihlášení/ověření; stav `pending / active / unsubscribed / closed`, verze souhlasu/ověření. Unikátní `(campaign_id, email_normalized)`. Normalizace trim + case-insensitive deduplikace jako současný mail stack; bez odstraňování plus suffixů nebo teček.
4. `public.sale_opening_capabilities`: hash kryptografického tokenu, subscription, účel `confirm / unsubscribe`, expirace a odvolání. Nepoužívat order/waitlist capabilities se smyšlenou objednávkou. Znovupoužít obecné šifrování a pravidla bezpečných odkazů. Případný raw zdroj potřebný pro rendering pouze šifrovaný, stejně jako nynější capability e-maily.
5. E-mailový stav se čte z `public.email_messages` a stávající delivery projekce. Nemá druhý nezávislý sloupec „odesláno“ ani delivery frontu. Kampaň dokončí produkci intentů, nikoli nutně doručení všech zpráv.

### Obsahový blok a jeho umístění

- **Architektonický požadavek uživatele:** countdown, odběr a blokové komponenty e-mailových šablon rozšiřují jednu společnou infrastrukturu atomických bloků v `lib/components/html/`. Nestačí přidat podporu více countdown-like widgetů a nechat jejich chování oddělené od e-mailových bloků. Současné dva typy uzlů jsou potvrzený výchozí stav, nikoli hotová cílová unifikace.
- Společný kontrakt vlastní identitu typu a instance, registry/resolution, vložení a omezení počtu instancí, výběr/focus, přesun v povoleném HTML kontejneru, odstranění, undo/redo a obálku komponenty v editoru. Sdílená obálka poskytne stejné ovládání, přístupnost a oddělení preview obsahu od identity; nezdvojovat tlačítka a pravidla v `_PreservedBuilder` a `_TemplateBlockBuilder`. Existující `canMoveNode` a editorové requests zůstávají vlastníkem omezení přesunu a transakcí. Neznámé bezpečné HTML dekorace zůstávají zachovaným obsahem, nejsou automaticky registrovanou funkční komponentou.
- Doménové adaptéry dodají označení, popis, preview a konkrétní serializaci: formulářové komponenty zůstávají `div.html-editor-block.*`, e-mailové komponenty zůstávají `{{code}}` s existujícími template resolver pravidly. Jednotný editorový kontrakt neznamená přepis doručovaných e-mailů na formulářové HTML sloty. Inline e-mailové proměnné a URL tokeny si ponechají odpovídající textovou semantiku; neproměňovat je kvůli sjednocení v bloky. Sdílené údaje o opakovatelnosti využijí současné `TemplateAuthoringEntry` pravidlo, nikoli druhý paralelní seznam.
- Jediným vlastníkem pořadí je současný HTML dokument předprodejního obsahu (`schedule.countdown_title`), nikoli nové JSON pořadí nebo separátní HTML dokument pro odběr. Zachovat současné datum i původní dokumenty, název uloženého klíče není důvodem k paralelní migraci obsahu.
- Nový slot: `<div class="html-editor-block form-sale-opening-notification"></div>`. Použít stejný atomic node, serializaci, přesun a undo/redo jako `form-countdown`. Slot je bezpečná značka pro živý widget, ne uložený formulářový HTML kód s inputy, adresami nebo tokeny.
- Současné Flutter API předává jediný `embeddedBlock`; rozšířit společný editor/reader kontrakt pro více typů bloků a převést countdown volání na stejný mechanismus. Nezakládat druhý renderer nebo editor jen pro odběr. JS provede sanitizaci a následnou hydrataci obou druhů slotů ve stejném pořadí; společná HTML politika musí značku zachovat a nepovolit aktivní HTML vstupy ze zdrojového obsahu.
- Jeden dokument obsahuje nejvýše jeden funkční odběrový blok a jeden countdown. Duplikáty z paste nebo starého dokumentu deterministicky normalizovat podle stejného pravidla jako countdown; nevytvářet více nezávislých formulářů/session listenerů. Vypnutý či pozastavený odběr může zachovat uložený slot, veřejně ale nenabízí aktivní sběr.
- V režimu bez countdownu se odstraní/skryje jen jeho widget, nikoli ostatní text a odběr. Editor ani reader nesmějí z přítomnosti slotu odvozovat serverové oprávnění k odběru. Pozice se ukládá současným form save a respektuje draft/Cancel/media-save chování.

### Vstupy a oprávnění

- Veřejný formulářový bundle vrátí minimální `saleOpeningNotification` projekci: `canSubscribe`, důvod nedostupnosti, aktuální termín a serverový čas. Nikdy adresy, počty, tokeny ani administrátorské detaily. Demo a neveřejné akce zachovají současná omezení.
- Jedna Edge hranice `sale-opening-notifications`: operace `subscribe`, `confirm`, `unsubscribe`. Autoritativní SQL transakce váže form/tenant z uloženého linku nebo tokenu, ne z klientem dodaného organization ID. Veřejné operace nevyžadují účet, ale mají úzké účelové oprávnění a abuse gate; service-role klíč zůstává na serveru.
- `subscribe` ověří aktivní kampaň, budoucí začátek, `is_open`, velikost/syntax adresy, limity a suppression, atomicky uloží pending + potvrzovací intent. Využít současnou kontrolu neobvyklého suffixu v klientu. Stejná adresa nevyvolá neomezené potvrzovací e-maily: resend nejdříve za 60 s, limit přes centrální abuse policy, nepřepisovat dosud platný token při pouhém duplicitním požadavku.
- `confirm` vyžaduje explicitní POST a neexpirovaný token; aktivuje odběr idempotentně. Potvrzení po otevření ještě během 24h platnosti launch oznámení vytvoří stejný jediný launch intent; později zobrazí aktuální prodej bez slibu dodatečného e-mailu. Nepotvrzené adresy nikdy nedostanou oznámení.
- `unsubscribe` je idempotentní explicitní POST, atomicky odvolá odběr a neodeslané intenty. Potvrzovací token nelze použít k odhlášení a naopak. Opětovné přihlášení po odhlášení vyžaduje nové ověření, neobnoví staré tokeny a neobchází jednorázový launch dedupe.
- Nastavení používá současný form command a `can_author_forms`; čtení seznamu vyžaduje nový úzký typed predicate/capability `can_read_sale_opening_subscribers`, odvozený z existujících práv ke kontaktům a uloženého occasion scope. Nepřidělit PII jen proto, že někdo smí upravit grafiku formuláře. SQL/UI/testy musí sdílet tutéž projekci, bez nových lokálních kombinací rolí.
- Bez přímých veřejných SELECT/UPDATE na nové tabulky, RLS a explicitní grants. Nové service-only funkce nejsou volatelné přes anon/authed RPC. `SECURITY DEFINER` musí mít `search_path=public,extensions` a odpovídající typed nebo service/účelový guard. Kompatibilita MCP nesmí vytvořit alternativní zapisovač nastavení.

### Automatické spuštění, změny a souběh

- Service-only `maintain_sale_opening_notifications(p_limit)` běží v existující infrastruktuře plánovaných SQL úloh, samostatně od aktivace notification centra. Nový bounded cron tick po minutě používá aktuální dostupnost a `SKIP LOCKED`; žádné volání z countdown klienta jako podmínka spuštění.
- První pozorované skutečné otevření vyzbrojené kampaně zahájí bounded fan-out. Platí jak dosažení termínu, tak dřívější otevření změnou harmonogramu. Prodej se nesmí pouze předpokládat z prošlého timestampu: zkontrolovat gate a současný registrační režim. `full` ani `waitlist` neposílá nepravdivé „Prodej byl spuštěn“; kampaň zůstane čekat na otevřenou nakupovatelnou registraci až do konce harmonogramu/ukončení.
- Každý ověřený odběr má nejvýše jeden launch intent s dedupe klíčem kampaň + subscription + `opened`. Ověření souběžné s fan-outem dosáhne stejného výsledku. Postup práce evidovat tak, aby pád mezi dávkami neztratil adresy ani neoznačil nevyrobené intenty za hotové.
- Bounded dávka má limit 100 intentů a respektuje stávající kapacitu/backlog. Při quota/rate odmítnutí se subscription nepřeskočí a neztratí; pokračuje se příště. Zachovat současné pořadí zámků form command/abuse/email, než přidat subscription lock. Souběhové testy mají ověřit i save/confirm/unsubscribe/worker, ne pouze dva fan-outy.
- Přesun začátku před prvním otevřením nemění kampaň ani verified odběry. Předčasné připravené launch zprávy zneplatní SQL send gate; po obnovení se tentýž neodeslaný intent bezpečně reaktivuje/připraví v kanonické frontě, bez druhého dedupe klíče. Zvolený postup nesmí slepě opakovat `unknown` provider výsledek.
- Po prvním otevření zavření dočasně brání odeslání; obnovení dovolí pokračovat jen v původním 24h okně, nejdéle do `schedule.end_time`. Změna termínu po otevření nikdy nenuluje toto okno. Nedokončené nebo nepozorované krátké otevření mimo chod maintenance není zpětně důvodem k rozeslání zprávy o aktuálně zavřeném prodeji.
- `email_intent_valid` i finální `begin_email_send` ověří subscription/verzi, živý scope, kampaň, aktuální otevření a expiraci. Nové větve musí být před obecným `order_id IS NULL -> true`. Odhlášení/ukončení invaliduje i připravený snapshot. Odešlou-li se podmínky platně na hranici `begin_email_send`, už probíhající provider call nelze vzít zpět; UI neslibuje opak.
- První nasazení i kopie akce vytváří jen nové vypnuté nastavení. Žádný backfill z objednávek ani z kapacitního waitlistu. Duplicitní/form-copy cesta nekopíruje kontakty, aktivní kampaň ani tokeny. Odstranění akce/formuláře invaliduje intenty a odstraní odběry v existující aggregate delete transakci.

### E-maily

Dva explicitní druhy a template kódy: `sale_opening_confirmation` a `sale_opening_opened`. Registrace v SQL enqueue allowlistu, TS registry, render dispatch, šablonovém katalogu a seed defaults; nepřevlékat zprávy za `custom`, auth ani `waitlist_offer`.

- Potvrzení: předmět „Potvrďte upozornění na prodej - {{occasionTitle}}“, hlavní tlačítko „Potvrdit upozornění“. Odkaz platí 24 hodin. Vysvětlení, že bez potvrzení oznámení nepřijde; není třeba odesílat třetí e-mail po ověření. Pokud obsahuje datum, je označené jako aktuálně plánované.
- Otevření: předmět „Prodej byl spuštěn - {{occasionTitle}}“, CTA „Přejít na prodej“. Odkaz vede na aktuální kanonickou veřejnou stránku formuláře, ne checkout session. Po vyprodání na této stránce platí běžný režim dostupnosti.
- Obě zprávy: aktuální identita akce/pořadatele, existující odesílatel/reply-to, wrapper/banner, lokalizace a tón, samostatná možnost odhlášení. Bez čísla objednávky, QR, VS, platebního bloku či marketingového rozšíření účelu.
- Použít `get_email_template_and_wrapper` / současné resolvery a sdílené action-link/render/preview komponenty. Přidat deterministické syntetické scénáře do existujícího generátoru email preview příkladů; nevytvářet jiný renderer pro editor. Katalog zobrazí šablony při příslušném nastavení v daném scope, nikoli podle capacity waitlist flagu.
- Veškeré odesílání přes `public.email_messages` a `process-email-queue`, ordinary priorita a společné limity, suppression i pause. Tokeny ve fragmentu, `Referrer-Policy: no-referrer`, bez click/open trackingu a bez raw tokenů v logu, analytics, URL query, sync nebo admin historii. Po načtení klient token odstraní z adresního řádku a ponechá jen v paměti.
- Fronta znamená plán, provider acceptance znamená přijetí poskytovatelem; „doručeno“ zobrazit jen z delivery evidence. Minutový tick a fronta negarantují doručení všem v sekundě spuštění.

### Uchování

Implementační upřesnění: odhlašovací capability má `expires_at=infinity`; omezují ji účel, živý odběr, revokace a odstranění zdroje při retenčním úklidu. Pevný kalendářní limit by odpojil možnost odhlášení u dostatečně vzdáleného nebo opakovaně posunutého začátku. Potvrzovací token zůstává omezený na 24 hodin.

Produktový návrh k implementaci: pending a potvrzovací token expirují za 24 h; neověřené kontakty odstranit nejpozději do 7 dnů. Aktivní odběry uzavřít po dokončení, expiraci oznámení či ukončení kampaně; osobní kontakty/tokenové zdroje odstranit do 30 dnů poté. Ponechat anonymní agregace. Nové zprávy respektují současnou retenční a šifrovací politiku e-mailové fronty; mazání subscription nesmí znemožnit bezpečně vyhodnotit starý intent jako neplatný. Jsou to navržené provozní defaulty, ne právní posouzení.

## Implementační vlny

### 1. Datový kontrakt a bezpečné příkazy

Změny: nová doména SQL, canonical `database/tables/tables.sql`, settings whitelist/validace v `eshop_forms/form_settings.sql`, typed permission/capability a veřejná bezpečná projekce v `get_form_by_link.sql`. Doplnit receipted save/finalize, copy a delete; nastavovací a lifecycle transakce musí být atomické. Nová additive migrace v `supabase/migrations/` se skládá z canonical SQL, neudržovat dvě ručně různé verze.

Migrace: pouze nové tabulky, indexy, grants, default off; žádná migrace zákazníků. Chybějící klíče současné klienty neovlivní. Ošetřit současné uložené `[null,{metadata}]` formáty přes existující normalizaci.

Validace/exit: SQL test `database/tests/sale_opening_notifications/contracts_test.sql` pro tenant izolaci, anonymous zakázané operace, kontaktní role, schedule validaci, copy/delete a souběžný save. Nová funkce zůstane vypnutá a obyčejný checkout/waitlist se chová stejně.

### 2. E-mailová fronta, renderer a automatické zpracování

Změny: produkce confirmation/opened intentů, registry/render/validity větve, dvě inherited šablony a skutečné preview scénáře. Nový service-only bounded maintenance tick, registrace v provozním cron SQL a retenční úklid. Edge producer po úspěšném commitu probouzí existující worker; cron zajišťuje obnovu. Potvrzení adresy a fronta nesmí vzniknout odděleně při chybě šifrování/enqueue.

Validace/exit: `queue_test.sql` a souběhový test v nové doméně ověří duplicitní submit/verify, více workerů, pád po dávce, quota rollback/recovery, pause/suppression, zrušení, posun termínu, no-order send guard a verzi připraveného snapshotu. TS testy rendereru ověří inherited wrapper, lokály/tón, jediná CTA, tracking off a bez platebních údajů. Bez otevřeného klienta vznikne právě jeden launch intent na ověřený odběr při otevření.

### 3. Sjednocení atomických bloků a veřejný odběr v obou klientech

Změny: nejprve vyčlenit společný kontrakt a obálku atomických bloků ze současných větví v `rich_html_editor.dart`, `rich_html_editor_controller.dart`, `html_editor_document.dart`, `html_embedded_block.dart` a `template_authoring.dart`. Převést countdown a e-mailové bloky na tento mechanismus, zachovat jejich uložené formáty a stávající email authoring provider jako doménový adaptér. Teprve potom přidat odběr jako další registrovaný typ; žádná třetí větev ovládání. Dále Edge `sale-opening-notifications`, JS availability/page/widget/model a Flutter `FormPage`/sdílený `FormDefinition` s malým znovupoužitelným widgetem. Rozšířit společný editor/reader o více typů, vložit odběr přes uložený atomic slot a sjednotit hydrataci s countdownem; zkontrolovat `shared/html/app-content-cases.json` a vlastníka sanitizační politiky. Přidat účelové confirm/unsubscribe zobrazení na existující form route a bezpečné zpracování fragmentů; případné AutoRoute soubory generovat. Odběr funguje s countdownem i bez něj, respektuje ruční uzavření a embed lifecycle.

Migrace/odstranění: odstranit duplikované společné ovládání a pravidla použitých blokových builderů po převedení všech jejich současných callerů. Typově odlišné uzly lze zachovat jen jako serializační adaptéry, ne jako dva vlastníky editorového chování. Žádný backfill uložených šablon ani přepis `{{code}}` na HTML komponenty. Návrh konkrétního rozhraní omezit na doložené potřeby countdownu, odběru a nynějších email bloků, bez obecného plugin frameworku.

Validace/exit: rozšířit `web_client/tests/forms/countdown_availability.test.js`, přidat testy odběru a Flutter widget/definition testy pro stejné stavové fixtures. Ověřit společný HTML round trip a sanitizaci, přesun odběru před/za countdown a mezi texty, save/reload/undo/Cancel, odstranění bez automatického návratu, skrytý countdown, duplicitní sloty a neodesílající preview. Edge testy ověří payload limits, účel tokenu, expiraci, scanner GET a idempotentní POST. Oba klienty mají shodné stavy a uložené pořadí, žádné PII v bundle a žádný checkout před otevřením.

Společná regresní brána: rozšířit `test/components/html/html_editor_document_cases.dart` a `template_authoring_cases.dart` o stejné operace pro countdown, odběr a e-mailový blok. Prokázat výběr/přesun/odstranění/undo, respektování tabulkových kontejnerů a limitů počtu, přesný round trip původních formátů a zachování inline placeholderů. Dosavadní e-mailové náhledy i produkční substituce musí zůstat funkční; passing nového odběru bez této regrese není dokončení vlny.

### 4. Administrace a dokončení

Změny: `form_editor_content.dart`, `occasion_setup_sales.dart`, setup draft a `occasion_setup/finalize.sql`; jeden settings adapter a pravidla validace. Přehled zájemců využije standardní grid, doručení a přístupové predikáty; Komunikace a email catalog využijí současný authoring kontrakt. Lokalizace, forms/email README a stručný veřejný návod.

Validace/exit: cílené setup/editor widget testy ověří default off, save/reload, změnu termínu, pauzu vs ukončení, zachování draftu při konfliktu a kontaktní oprávnění. Jedna browserová kontrola na disposable lokálním backendu: přihlásit -> potvrdit -> otevřít -> jediná zpráva -> odhlásit; mobilní embed a zavřený formulář. Browser delegovat Terra dle pravidel, izolovaně, ztlumeně; nepoužívat produkční kontakty ani odesílat skutečné e-maily.

## Ověřování a release

Při tomto plánování se testy/buildy nespouštějí. Implementace používá standardní cílené kontroly, dávkované po souvisejících změnách:

- SQL přes `node web_client/scripts/run_db_tests.js database/tests/sale_opening_notifications/contracts_test.sql` a odpovídající queue test na disposable backendu; concurrency runner podle sousedních DB testů. Rozšířit existující availability/save/email queue regresní testy podle dotčených kontraktů.
- JS přes `pnpm --dir web_client exec node --test tests/forms/countdown_availability.test.js tests/forms/sale_opening_notifications.test.js`.
- Edge přes cílený `deno test --frozen --lock=supabase/functions/deno.lock` s minimálními potřebnými permissions pro nové testy. Preview generátor spustit v jeho současném `--check` režimu po přegenerování příkladů.
- Dart diagnostika pouze dotčených souborů pomocí `fvm dart analyze <soubor>`; cílené `fvm flutter test --concurrency=1 <dotčené testy>`. Před Flutter úlohou ověřit volný workstation slot, žádná paralelní Flutter úloha.
- Browserový smoke výše až po společné implementaci; využít `festapp-local-e2e` a repozitářové browser příkazy, žádné obcházení deterministic gate přímým Playwrightem.

Případné následně autorizované nasazení: nejprve additive SQL včetně queue/validity a neaktivního maintenance, potom Edge/renderer, potom klienti, ověřit worker a enable maintenance. Jedna jmenovaná tenant větev, ne plošný rollout. Produkční restart Functions pouze současným chráněným postupem s pause/drain/probe/resume fronty. Web build/deploy lokálně podle pravidel repozitáře. Rutinní release delegovat levnějšímu subagentovi až s konkrétními validovanými revizemi a oprávněním k release.

Rollback pozastaví nový sběr i produkci launch intentů a zneplatní jejich send gate, ne celou e-mailovou službu. Zachová kontakty a historii pro bezpečné obnovení, nereaktivuje staré tokeny a neopakuje již přijaté/unknown zprávy. Starší klient nové nastavení ignoruje; během rollout okna je nutné otestovat, že jeho full-save neukončí aktivní kampaň - server chrání neznámá nastavení a vyžaduje explicitní lifecycle příkaz.

## Co odstranit a co zachovat

| Současný artefakt nebo pravidlo | Výsledek a důkaz |
| --- | --- |
| Předprodejní větev ukončená po samotném countdownu v JS/Flutter | Nahradit kompozicí podle uložených atomic slotů, s výchozím odběrem pod countdownem. Test změny pořadí, varianty bez countdownu i ručního uzavření. |
| Jediný typ `embeddedBlock` v dotčeném Flutter editor/reader kontraktu | Převést dotčené countdown call sites na sdílený mechanismus více typů; bez druhé implementace editoru pro odběr. |
| Oddělené společné ovládání `_PreservedBuilder` a `_TemplateBlockBuilder` | Převést na jeden editorový kontrakt a obálku, odstranit duplikované chování. Formátové adaptéry HTML slotů a email tokenů zůstanou; společná regresní sada prokazuje oba. |
| Settings whitelist a form model bez nových klíčů | Rozšířit jediný kanonický kontrakt; odstranit lokální pokusné kopie nastavení, pokud při implementaci vzniknou. |
| Email registry/catalog bez nových druhů | Rozšířit současné vlastníky a jejich testy, žádný paralelní sender ani generický custom bypass. |
| Existující kapacitní waitlist a jeho waiting tickets | Zachovat celý kontrakt; nový odběr do něj nezapisuje. Důkaz DB regresí i absence order/ticket mutation v nové cestě. |
| Existující schedule, countdown HTML slot, queue, wrappers a preview renderer | Zachovat jako kanonické vlastníky, nepřidávat časové aliasy, nový editor nebo frontu. |

Jde o aditivní funkci, nikoli náhradu existující čekací listiny. Žádné historické waitlist tabulky, objednávky ani šablony se nemažou.

## Předpoklady a zbytková rizika

- **Potvrzeno uživatelem:** pouze upozornění na spuštění, bez priority a bez docházejících míst.
- **Rozhodnutí návrhu:** povinné ověření adresy, konkrétní termín, dvě zprávy, jednorázová kampaň a výše uvedené TTL/retence. Lze změnit během připomínkování plánu, nejsou to existující produktová fakta.
- **Předpoklad:** běžný minute cron a šifrovací boundary lze rozšířit současným deployment mechanismem. Před implementací maintenance ověřit existující job instalaci v `automation/email-delivery/` a aktuálních `supabase/migrations/`, ne produkčním průzkumem. Není-li to možné, aktualizovat tuto sekci a konkrétní instalační krok.
- **Předpoklad:** nový úzký kontaktní predicate může sdílet stávající pravidlo `can_read_participant_contacts`; implementátor ověří jeho skutečnou roli a delegace v `database/functions/user_permissions/` a přidá matrix test, bez rozšíření rolí odhadem.
- **Riziko:** velký počet adres a globální limity znamenají zpoždění. Dávky musí být obnovitelné a přehled musí ukazovat čekání i chyby. Nelze slíbit současný okamžik doručení nebo rezervaci místa.
- **Riziko:** cizí rozpracované změny v setup/email/form souborech. Vycházet z aktuálního stromu, nevracet je a před implementací znovu zkontrolovat pouze dotčené kontrakty.
- **Blokátory plánování:** žádné. Produkční rollout a skutečné testovací mailboxy zůstávají samostatně autorizované kroky.

## Hotovo znamená

- Oba klienty sbírají a ověřují adresy ze stejného harmonogramu a serverových pravidel; manuální uzavření vítězí.
- Odběrový blok je v témže editoru přesouvatelný jako countdown; oba klienty a náhled respektují uloženou pozici po save/reload, bez pevné duplicitní komponenty.
- Countdown, odběr a email blokové komponenty používají stejný editorový kontrakt a společné ovládání; původní HTML sloty, email tokeny a inline proměnné projdou regresním round tripem bez migrace uloženého obsahu.
- Přehled a nastavení používají současný UI jazyk, role a komponenty; e-maily současnou dědičnost, renderer a frontu.
- Jen ověřený aktivní odběr dostane nejvýše jeden launch intent; retry, souběh, změna data, ukončení a odhlášení neobcházejí dedupe/send gate.
- Automatika funguje bez klienta; neobsahuje prioritní vstup, scarcity ani paralelní evidenci účastníků.
- Cílené testy a jeden lokální průchod projdou; stav produkční migrace a nasazení je výslovně uvedený, nikdy předpokládaný.
