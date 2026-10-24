# Náprava nedoručeného e-mailu u konkrétní objednávky

Datum: 2026-10-24
Stav: Vlny 1-3 implementované a ověřené; po samostatném zadání vydána migrace, funkční sada a vstupenky.online 0.20.375+874. Žádné zkušební zákaznické odesílání. Viz [produkční záznam](../operations/order-email-recovery-release-2026-10-24.md) a [předchozí lokální ověření](order-email-recovery-local-verification-2026-10-24.md).
Ověřování: standard - oprávnění, osobní údaje, souběh a nevratné odeslání e-mailu.
Původní výchozí revize: main `4b883300da89ac0b33cc2cd50e6954fb4668ef51`; drobné opravy UI byly připravené v PR #576. Zpřesnění ověřeno proti pracovnímu stromu `fix/notification-production-theme-20261024` na HEAD `76b7e7afd`; stav sloučení PR ani produkce se tímto neověřoval. Před implementací porovnat s aktuálním kanonickým mainem.

## Výsledek pro pořadatele

Z upozornění na nedoručené potvrzení otevře pořadatel konkrétní objednávku, vidí její symbol, zákazníka, aktuální kontaktní e-mail, adresu původního neúspěšného odeslání a lidsky popsaný problém. Příslušný řádek tabulky se vyhledá, posune do záběru a krátce zvýrazní. Z detailu může opravit kontakt, znovu odeslat potvrzení nebo vědomě zrušit objednávku. Žádná z těchto akcí se nespouští pouhým otevřením upozornění.

Problém je viditelný také přímo u dotčené objednávky, i když pořadatel nepřišel přes zvoneček. V řádku objednávky bude kompaktní varování po vzoru upozornění na bankovní účet a v detailu čitelný notice s konkrétním důvodem a akcí „Vyřešit doručení“. Nejde o problém celé akce ani bankovního účtu.

Historie e-mailů zůstává tabulkou jednotlivých zpráv s jejich stavem a technickým detailem. Souhrnný pás počtů nad tabulkou se odstraňuje v nynějším opravném vydání, včetně jeho klientského načítání. Tento plán nezavádí další přehledový dashboard.

## Úsporný realizační kontrakt

- Změnit jen vlastnické cesty uvedené ve vlnách 1-3 a jejich přímé registry/testy. Vlnu 0 pouze dokončit, pokud již není hotová. Vlnu 4 nespouštět. Žádný redesign celé objednávky, obecný incident systém, nová fronta, nový sender, globální verzování nebo plošný refaktor autorizace/synchronizace.
- Minimum: jeden RPC `repair_order_email_client_sync_v1`, jedna metoda `OrderCommands`, jeden sdílený opravný dialog v existujícím `AppDialog` shellu, kompaktní varování ve stavové buňce a rozšíření existujícího per-order reportingu. „Společný detail“ v tomto plánu znamená tento dialog dostupný ze zvonečku i řádku, nikoli novou univerzální obrazovku objednávky. Storno pouze zavolá současný příkaz a potvrzení.
- Pro nápravu uložit jedinou přímou vazbu nového záměru na zdrojový `message_id` do existující provenience. Opakovanou nápravu řešit řetězem těchto vazeb, bez nové tabulky incidentů a bez seskupování podle adresy nebo času. V tomto rozsahu jeden pokus řeší jeden zdrojový problém stejného druhu. Automatické sloučení více incidentů a náhrada potvrzení vstupenkami nejsou součástí implementace.
- Pracovat sériově, bez subagentů a nezávislých auditů. Jeden cílený průchod po uvedených vlastnících, poté souvislá implementace; další průzkum jen pro konkrétní rozpor nebo chybějící závislost. Nepřepisovat plán při každé editaci, pouze při změně smluveného chování nebo neplatném faktu.
- Výpisy omezit na cílené `rg` a potřebné řádky. Kontroly seskupit nad dokončeným celkem: dotčené SQL, command/widget testy, cílená analýza a jeden lokální integrační průchod. Znovu spustit pouze kontroly zneplatněné další změnou nebo selháním. `verification: standard` zachovává skutečné důkazy ACL, transakcí a souběhu; nevyžaduje plošný build či test celé aplikace.

## Potvrzené výchozí chování

| Zjištění | Vlastník / důkaz | Důsledek |
|---|---|---|
| `_detail` zpracuje `messageId` před `orderId` a otevře `email-history?messageId=…`. | `lib/components/notification_center/notification_center_bell.dart` | Pro objednávkový problém je nutné změnit volbu cíle, zachovat alternativu pro neobjednávkové zprávy. |
| DTO e-mailového incidentu přidává příjemce a jméno přes autorizovaný join. | `database/functions/notification_center/core.sql`, `notification_center_dto` | Vazbu na objednávku doplnit z `email_messages.order_id` na serveru, nikoli odhadovat z e-mailu zákazníka. |
| `OrdersContent` přijme `orderId`, hledá v načtených objednávkách a otevře historii nebo detail pořadníku. | `lib/components/eshop/views/orders_content.dart` | Existující odkaz lze využít; chybí jasný opravný detail a soustředění tabulky na daný řádek. |
| E-mailový sloupec je pouze pro čtení; `OrderModel.updateMethod` ukládá interní poznámku. | `eshop_columns.dart`, `models/order_model.dart` | Pouhé povolení editace buňky by neuložilo kontakt správně. |
| `update_order_responses` promítá formulářové pole typu `email` do `orders.data.email` a řeší další odpovědi. | `database/functions/eshop_orders/update_order_responses.sql` | Udržet soulad odpovědi a kontaktní projekce; nepouštět kvůli opravě e-mailu nepřiměřeně široké přepočty. |
| Hromadné `sendTicketsOrConfirmations` může nejdříve změnit nezaplacenou objednávku na zaplacenou. | `views/orders_content.dart` | Tento handler se nesmí použít pro opakované zaslání nezaplaceného potvrzení. |
| Existující fronta má deduplikaci, stav `unknown`, pravidla pro zrušené objednávky, kontrolu aktuální adresy a blokované příjemce. | `database/functions/emails/email_domain.sql`, `email_queue.sql`, `email_schema.sql` | Použít tuto frontu a její pravidla; neopakovat slepě nejasně dokončené odeslání. |
| `send-email` přijímá update, storno, připomenutí a platební oznámení, ne potvrzení objednávky. | `supabase/functions/send-email/index.ts` | Nelze jen zavolat nynější endpoint s novým kódem a označit implementaci za hotovou. |
| Bankovní varování je navázané na konkrétní objednávku a zobrazuje se v její stavové buňce. | `views/order_state_cell.dart`, `views/order_bank_sync_warning.dart`, `bank_accounts/views/bank_sync_warning_button.dart` | Převzít vzor kompaktního varování s vysvětlením a akcí, nikoli bankovní datový model. |
| Objednávka už nese `emailDelivery`; její sloupec používá `EmailDeliveryIndicator` a serverový souhrn obsahuje i počet problémů. | `models/order_model.dart`, `eshop_columns.dart`, `email_delivery/email_delivery_indicator.dart`, `get_order_email_summaries` v `database/functions/emails/email_reporting.sql` | Rozšířit současnou per-order projekci a sdílet klasifikaci problémů; nezakládat další nezávislou signalizaci. |
| Storno má samostatný potvrzovaný příkaz s identitou a serverovými účinky. | `order_commands.dart`, `DbOrders.stornoOrder`, `OrdersContent.cancelOrders` | Znovu použít storno; nekopírovat inventářovou ani platební logiku. |
| Souhrn dnes řadí všechny nezrušené/neexpirované zprávy a `attention_count` počítá i historické chyby; nezná nahrazené pokusy. | `email_reporting.sql`, CTE `messages` / `ranked` | Samotné převzetí počtu nestačí: bez vazby nápravy by varování po doručení nové zprávy zůstalo navždy. |
| Aktivní pokus se nyní znovu používá explicitně pro `order_tickets`; větev potvrzení stejnou ochranu nemá. | `enqueue_order_email` v `email_domain.sql` | Deduplikaci potvrzení je třeba prokázat i mezi dvěma různými command ID, nikoli jen při replay jednoho požadavku. |
| Úprava odpovědí zamyká formulář před objednávkou; send fence zamyká kapacitu, objednávku a zprávu. | `update_order_responses.sql`, `begin_email_send` v `email_queue.sql` | Nový příkaz nesmí obrátit pořadí zámků nebo volat worker uvnitř transakce. |

## Rozhodnutí a hranice

1. Primární akce na objednávkovém e-mailovém incidentu bude „Otevřít objednávku“. Technická „Historie doručování“ zůstane vedlejší akcí v detailu. Pro zprávu bez objednávky zůstane autorizovaný detail e-mailu.
2. Zvýraznění není zaškrtnutí pro hromadné akce. Otevření odkazu nesmí změnit existující hromadný výběr, potvrdit platbu ani odeslat zprávu. Neviditelný cíl kvůli filtru nabídne výslovné zobrazení cílové objednávky; odvolané oprávnění a smazaný cíl mají stejnou bezpečnou odpověď.
3. Detail nabídne „Upravit e-mail“, „Znovu odeslat potvrzení“ a oddělené „Zrušit objednávku“, vždy podle aktuálních serverových práv a stavu objednávky. Změna kontaktu má akce „Uložit“ a „Uložit a znovu odeslat“. Před odesláním je vidět přesný příjemce a druh zprávy.
4. Oprava e-mailu se týká kontaktu konkrétní objednávky a příslušné odpovědi jejího formuláře. Nemění přihlášení ani e-mail uživatelského účtu, jiné objednávky, platby, částky, místa či QR identity. Po stornu zůstává objednávka pouze pro čtení.
5. Pro nezaplacenou objednávku se znovu odešle potvrzení se stávajícími platebními pokyny, bez nové objednávky nebo nové platby. Vstupenky se posílají pouze pro stav, který jejich odeslání již dovoluje. Typ `order_confirmation` a `order_tickets` se nesměšuje; update, upomínka, storno a neobjednávkové zprávy se nevydávají za potvrzení.
6. U původního problému zůstane historická adresa i důvod zachován. Nová adresa a nové odeslání vytvoří provázaný pokus, nepřepisují doručovací fakta původní zprávy. „Zařazeno k odeslání“, přijetí poskytovatelem a doručení jsou odlišné výsledky. Oprava adresy sama incident neoznačí jako doručený.
7. Hard bounce nebo spam se neobejde vymazáním `email_suppressions`. Stejná blokovaná adresa dostane srozumitelnou informaci a další postup. Opravenou jinou adresu lze posoudit běžnými pravidly fronty. Žádné automatické storno kvůli doručovací chybě a žádné plošné rozesílání při nasazení.

8. Nedoručitelnost je problém konkrétní objednávky. Vedle jejího stavu se zobrazí kompaktní varovná ikona/notice po vzoru bankovního upozornění a v detailu textový blok podle druhu zprávy, například „Potvrzení objednávky se nepodařilo doručit“, s dotčenou adresou, důvodem a akcí „Vyřešit doručení“. Klik otevře tentýž opravný detail jako zvoneček. Není nutné nejprve otevřít historii e-mailů. Čtecí role mají vysvětlení a informaci, kdo může problém vyřešit; zápisové akce zůstávají podle práv.
9. Varování vychází z aktuálního autorizovaného souhrnu dané objednávky a zůstává po přečtení upozornění, otevření detailu i zavření notice. Bounce, rejection/rendering failure, dead nebo suppression mají konkrétní popis chyby; `retry_wait`, `delay` a `unknown` dostanou popis čekání či nejistoty, nikoli nepravdivé „adresa je neplatná“. Pouhé `accepted` nebo chybějící data nedokazují nedoručitelnost. Oprava adresy a zařazení nového pokusu mohou změnit text na „Čeká se na nové doručení“, ale ne na úspěch. Varování zmizí až po potvrzené nápravě relevantního pokusu nebo přejde na odpovídající informaci o zrušené objednávce; nesouvisející úspěšný e-mail nesmí skrýt jiný nevyřešený problém. Historické bounce zůstane v historii.

## Životní cyklus problému a přesné podmínky nápravy

Kanonický reporting oddělí historický stav zprávy od aktuálního problému objednávky. Zachovat dosavadní pole souhrnu pro staré klienty; přidat explicitní projekci aktuálních problémů s identitou zdrojové zprávy, druhem, stavem nápravy a identitou navázaného nového záměru. `attention_count` bez rozlišení historie nepoužívat jako důkaz nevyřešené chyby. Server vlastní výběr relevantních problémů; Flutter pouze sdílí jejich popis a vizuální závažnost.

| Autoritativní situace | Chování v objednávce |
|---|---|
| Bounce, reject, rendering failure, dead nebo suppression bez prokázané nápravy | Varování s přesným druhem zprávy a srozumitelným důvodem. |
| Complaint | Informace o označení za spam; nenabízet opakované zasílání na stejnou adresu. |
| Retry, delay, globální pozastavení nebo limit fronty | Čekání s důvodem; neslibovat čas doručení a neoznačovat adresu za chybnou. |
| Unknown nebo již povolené `sending` původního relevantního pokusu | Nejistý/probíhající výsledek; další odeslání blokovat do autoritativního vyjasnění. Samostatnou opravu kontaktu lze uložit s vysvětlením, že původní odeslání již nelze odvolat. |
| Jen uložení nové adresy | Problém trvá; zobrazit aktuální kontakt a původní neúspěšnou adresu. |
| Nový navázaný pokus pending/preparing/accepted | „Čeká se na nové doručení“; enqueue ani přijetí poskytovatelem nejsou vyřešení. |
| Delivery u prokazatelně navázaného, stále relevantního pokusu | Vyřešit pouze odpovídající problém. Historickou chybu zachovat; další problémy zůstávají viditelné. |
| Pozdní bounce/complaint navázaného pokusu po delivery | Znovu zobrazit problém podle autoritativních faktů; pozdní starší událost nesmí slepě přepsat novější fakta. |
| Open/click bez delivery, chybějící či nedostupná data | Samy neprokazují nápravu. Při chybě obnovení označit poslední data za neaktuální. |
| Zrušená objednávka | Pouze informace a historie, bez oprav a opakovaného potvrzení; zrušení není doručení ani refundace. |

Vazbu nápravy vytváří server ve stejné transakci jako enqueue a ukládá ji do stávající provenience zprávy/receipt; neodvozovat ji jen z adresy, času nebo posledního úspěšného e-mailu. Jeden nový pokus nahrazuje pouze výslovně zvolenou zdrojovou zprávu stejného druhu a její předchozí řetěz nápravy; ostatní problémy zůstanou viditelné. Nezaplacené potvrzení a placené vstupenky nejsou automaticky zaměnitelné. U historické chyby, která po změně obchodního stavu již nemá být opakována, ukázat „Původní zpráva již neodpovídá stavu objednávky“ a nabídnout pouze aktuálně platný druh odeslání; v tomto rozsahu ji automaticky nepovažovat za nahrazenou zprávou jiného druhu.

Problém `post_action_failed` znamená selhání navazujícího zpracování, nemusí znamenat nedoručení. Rozlišit ho v textu a nenabízet nové zákaznické odeslání jako automatickou nápravu. UI nesmí pro selhané vstupenky tvrdit „Potvrzení objednávky se nepodařilo doručit“; nadpis vychází z druhu zdrojové zprávy.

## Kanonický kontrakt změny kontaktu a opakovaného odeslání

Rozšířit existující vrstvu `OrderCommands` / `ClientCommandTransport` o úzký potvrzovaný příkaz. Navržený veřejný název: `repair_order_email_client_sync_v1`. Vstup obsahuje objednávku, očekávaný kontakt, obchodní stav a `email_payment_version` (existující `updated_at` přidat jen jako ověřený token souběhu, ne jako nový systém verzování), novou adresu, ID zdrojové zprávy povinné při nápravě konkrétního incidentu (bez něj pouze běžná úprava kontaktu / výslovné nové odeslání), příznak opakovaného odeslání a stabilní `commandId`. Nový vědomý pokus má novou identitu; retry po timeoutu zachovává tu původní.

Server po kontrole `can_write_orders` a příslušného práva číst zprávu ověří, že objednávka, zpráva, akce a organizace patří k sobě. Samostatné přijetí `orderId` a `messageId` nesmí umožnit kombinovat cizí objekty. U formulářové objednávky zamkne nejprve formulář podle `update_order_responses`, pak objednávku a dotčené zprávy; pořadí nesmí vytvořit cyklus s `begin_email_send`. Pod zámky porovná očekávaný kontakt, stav a verzi podkladů se současnými hodnotami a ověří adresu. Aktualizuje kontakt i jeho formulářovou projekci a uloží audit do současné historie/receipt infrastruktury. Není-li opravovaný kontakt stále aktuální, vrátí konflikt a žádné odeslání.

Pro „Uložit a znovu odeslat“ je změna kontaktu a vložení jednoho záměru do současné fronty atomická transakce. Při odmítnutí vložení se nic tiše neuloží. „Uložit“ bez odeslání je samostatně platná větev. Výstup obsahuje autoritativní aktualizovanou objednávku, potvrzení příkazu, `messageId`/stav záměru, nebo explicitní „neodesíláno“. Stejná identita vrací stejný receipt a nezaloží další zprávu. Před replay znovu ověřit aktuální práva; stejný `commandId` s jiným payloadem vrací konflikt, nikoli cizí starý receipt. Porovnání chrání před přepsáním odlišného aktuálního kontaktu nebo odesláním zastaralých platebních podkladů. Požadavek nezavádí globální čítač všech historických změn A -> B -> A; pokud jsou aktuální kontakt, stav i podklady shodné, nejde samo o konflikt. Dva odlišné command ID nesmějí při současném kliknutí vytvořit dva aktivní relevantní záměry: druhý vrátí existující pokus nebo konflikt. Toto pravidlo musí pokrýt potvrzení i vstupenky.

Vnější poskytovatel se nevolá uvnitř databázové transakce. Zachovat existující `enqueue_email` -> `wake_email_worker` s `net.http_post`; síťové spuštění respektuje commit transakce. Nepřidávat další klientské probouzení nebo endpoint. Selhání probuzení nesmí vytvořit druhý záměr; současný cron zajišťuje obnovu. `requested_by`, druh zprávy, tenant a příjemce odvodit ze serverových dat, nikoli z volných klientských metadat. Validaci a normalizaci adresy sdílet se současnou frontou; odmítnout prázdný kontakt a zalomení hlaviček, neodstraňovat svévolně plus aliasy ani tečky.

Použít `enqueue_order_email` a existující worker/renderery, případně úzce doplnit jejich autorizovanou hranici pro explicitní opakované potvrzení. Veřejný příkaz nesmí přijímat libovolné HTML, příjemce jiné objednávky nebo service-role tajemství. Nevytvářet paralelní frontu ani používat `send-ticket-order` pro nové vytvoření objednávky. `SECURITY DEFINER` pouze v `public`, s `search_path = public, extensions` a explicitním `eshop.*`.

Předpřipravené zprávy na starý kontakt se řídí stávajícím `email_intent_valid`; implementace musí prokázat jejich invalidaci a chování skutečně probíhajícího pokusu. Přijatou zprávu nelze vzít zpět. U `unknown` nebo již uděleného send permit nejdříve vyřešit původní relevantní pokus, nikoli automaticky vyrábět další nejasný pokus ani při změně adresy. Po překročení send fence nelze slíbit odvolání původní zprávy; po případném uložení kontaktu to detail výslovně vysvětlí. Toto pravidlo nenahrazovat toastem „odesláno“.

## Zpřesnění při implementaci 2026-10-24

- Řádková projekce `get_orders` nenese `occasion`; varování dostává rozsah z již autorizovaného vlastníka `OrdersContent`, nikoli z globálního aktivního kontextu. Dialog i poté ověřuje skutečný rozsah přímo načtené objednávky.

- Odkaz na zákaznický přehled je schopnost svázaná s kořenovou objednávkou a jeho šifrovaný zdroj uchovává historickou adresu. `get_order_email_overview_source_v1` již ověřuje současný kontakt obou objednávek. Renderer po opravě kontaktu ověřuje existující zdroj podle organizace, akce, kořenové objednávky, unit a hashe tokenu/obsahu; neporovnává nový kontakt se starou adresou ve zdroji. Odkaz ani historický zdroj se nepřepisují. Pokud opravená odvozená objednávka má jiný kontakt než její kořen, volitelný odkaz na společný přehled se vynechá; nedostane tím přístup k ostatním objednávkám a jejich kontakty se nemění.

- `set_payment_deadline` mění pouze `email_reminder_version`, nikoli `email_payment_version`; tento čítač sám nedokazuje shodu platebních podkladů. Opravný příkaz proto navíc vyžaduje `p_expected_payment_fingerprint`: úzký otisk současných částek, splatností, platebních referencí a přijímajícího účtu, vrácený autorizovaným `get_order_history`. Pod zámkem porovná aktuální fakta a worker jej znovu ověří před send permitem. Nevzniká uložená verze ani globální čítač.

- `client_sync_component_sources.source_relation` má typ `regclass`; rozšíření registru používá tento typ bez změny verze či readiness.
- Renderer `order_confirmation` vyžaduje `data.ticket_order.order` v checkoutovém tvaru. RPC při opakovaném potvrzení skládá aktuální snapshot přes `get_order_details_for_email`, zachovává původní platební `command_id` a frontu; samotné `order_id` renderer neobslouží.
- `email_intent_valid` je služební SECURITY DEFINER hranice ověřující service-role JWT. Uživatelské RPC ji přímo nevolá; pod zámkem konzervativně odmítne aktivní relevantní záměr a staré předpřipravené kontakty vyřadí. Worker nadále používá stávající send fence.

## Implementační vlny

### 0. Aktuální drobná oprava historie

Odstranit `_overview`, jeho `get_email_delivery_overview` volání a souhrnný `Wrap` z `EmailDeliveryHistory`. Zachovat jednotlivé řádky, jejich stav a detail, stránkování, filtr organizace a volání `get_email_delivery_detail`. Upravit vlastnický test přepnutí organizace, aby ověřoval pouze načtení řádků a zachování rozsahu. Globální reportovací SQL není součástí této kosmetické změny; na jeho odstranění se neváže databázový zásah.

Výstup: žádný souhrnný pás ani požadavek tohoto widgetu na přehledové API. Ověřit `test/components/email_delivery/email_delivery_history_cases.dart`.

### 1. Přesný cíl upozornění a soustředění objednávky

V `notification_center_dto` přidat autorizované `orderId`/symbol pro objednávkový incident ze serverového spojení zprávy a objednávky. V `NotificationCenterBell._detail` upřednostnit tuto vazbu a předat i identitu problému. V `OrdersContent` rozšířit existující `orderId` cestu: najít řádek, posunout jej do záběru, krátce jej zvýraznit a otevřít společný opravný detail. Při uzavření spotřebovat jen vlastní query target přes `clearNotificationDetailTarget`. Podporovat opakované otevření, zrušené objednávky a nedostupný objekt. Cíl hledat autorizovaně podle ID i mimo právě načtenou stránku; nehledat ho pouze v klientském seznamu. Při přepnutí organizace nebo zavření detailu zahodit pozdní výsledek starého načítání a nezobrazit jeho kontaktní údaje v novém kontextu. Nezavádět druhou navigaci obcházející root router.

Výstup: klik otevře přesně danou objednávku; automatický výběr nesáhne na checkboxy. Testy trasování se dvěma současně otevřenými obrazovkami, omezenými právy, filtrem a opakovaným vstupem.

### 2. Autoritativní změna kontaktu a fronta

Implementovat výše uvedený kontrakt a zapojit ho do `OrderCommands`, stabilní identity příkazů a současného command registry/receipt vlastníka podle vzoru storna. Úzce rozšířit podporu potvrzení a provenienci nového pokusu, nikoli obecný přeposílač. Přidat kanonické SQL a jednu unikátní migraci; žádné persistentní aplikační triggery. Udržet kontaktní/formulářovou projekci bez přecenění, změny zásob či platby.

Výstup: DB testy pro read-only uživatele, cizí tenant/zprávu, neplatnou adresu, konflikt kontaktu, storno/stock, replay, souběžný dvojklik, timeout po commitnutí, selhání enqueue a blokovanou adresu. Prokázat nezměněnou platbu, cenu, inventář a identitu vstupenek. Zahrnout změnu kontaktu nebo platebních podkladů od načtení dialogu, stejnou identitu s jiným payloadem, replay po odebrání práv, dva různé příkazy pro stejný aktivní záměr, závod s platbou/stornem/odstraněním formulářového pole a s `begin_email_send`, selhání wake po commitu a pozdní/duplicitní provider události. Testy používají izolovanou DB a falešný transport, nikoli živou frontu. Navázat na `database/tests/emails/canonical_email_queue_test.sql`, `order_ticket_intents_test.sql`, `database/tests/notification_center/email_sources_test.sql` a testy `OrderCommands`.

### 3. Opravný detail a zpětná vazba

Doplnit objednávkové varování vedle stavu v `views/order_state_cell.dart` podle vzoru `OrderBankSyncWarning` a výraznější textový notice do společného detailu objednávky. Nedoručenost musí být rozpoznatelná přímo při běžné práci s objednávkou, nikoli pouze ve zvonečku či historii e-mailů. Použít existující `order.emailDelivery` a autorizované `get_order_email_summaries`/`get_order_email_summary`; stejný zdroj a jedna klasifikace stavu ve vlastníkovi `email_delivery` musí řídit `EmailDeliveryIndicator`, řádkové varování i detail. Nekopírovat seznam chybových stavů do každého widgetu a nevytvářet druhý globální přehled. Rozšíření souhrnu pro prokázané nahrazení původní neúspěšné zprávy provést v kanonickém serverovém reportingu a propojení receipt z vlny 2.

Notice obsahuje ikonu i text, má čitelný kontrast ve světlém/tmavém motivu a dostupnou akci „Vyřešit doručení“. U více problémů zůstane kompaktní s počtem a přehledem konkrétních zpráv v detailu. Skrytí notice ani změna read cursoru nezmění doručovací stav. Po opravě/odeslání/stornu se obnoví řádek, detail i zvoneček z autoritativního výsledku. Při neúspěšném načtení se nesmí staré varování změnit na domnělý úspěch.

Vytvořit kompaktní kontaktní sekci společného detailu objednávky, využívanou jak z upozornění, tak z objednávek. Ukázat starou neúspěšnou adresu a současný kontakt jako dvě různé informace, při shodě je neopakovat. Nabídnout výše definované akce; během požadavku zakázat dvojklik a po konfliktu znovu načíst serverový stav. Čtecí role uvidí stav a historii, nikoli aktivní zápisové akce. „Zrušit objednávku“ použije nynější potvrzení a `DbOrders.stornoOrder`; u zaplacené objednávky popíše skutečný existující postup vrácení peněz a neslíbí refund, který příkaz neprovedl.

Provázání původního incidentu a nového záměru ukládat do existujícího receipt/provenience vlastníka. Nový pokus se zobrazí jako čekající; až potvrzené doručení může být označeno jako doručeno. Storno se označí jako zrušená objednávka, ne úspěšné doručení. Nevytvářet obecnou tabulku ručně řešených incidentů.

Výstup: objednávkové varování je viditelné z tabulky i detailu bez návštěvy zvonečku. DB testy projekce pro historický bounce následovaný navázaným delivery, nesouvisející úspěch, více souběžných problémů a pozdní bounce po delivery. Widgetové testy pro bounce, suppression, čekání a unknown, chybějící data, více problémů, přečtení/zavření bez vyřešení, přechod na nový čekající pokus a odstranění varování až po potvrzené nápravě. Současně testy čtení/editace, konfliktních stavů a následků akcí, mobil 320 px při 200 % textu, světlý/tmavý `ThemeConfig` a dialog skutečně otevřený z AppBar. Ověřit celou cestu na izolovaném lokálním tenantovi s falešným transportem e-mailu; žádné reálné zákaznické odeslání v testu.

### 4. Samostatné autorizované vydání

Před vydáním znovu ověřit unikátnost migrace, ACL, rollback a zachování kanonické main/tenant ancestry. Nové backendové rozšíření před novým UI, žádná změna očekávaného kontraktu starým klientům. Návrat UI na předchozí verzi ponechá aditivní SQL a již uložené záměry/provenienci; nesmí smazat doručovací důkazy ani znovu enqueueovat historické chyby. Nasazení nesmí obsahovat automatický resend/backfill. Nasazení na jeden vybraný tenant, lokální build a `automation/deploy_direct.sh`. Ověřit přesnou živou verzi a skutečnou cestu detailu s bezpečnými testovacími daty. Produkční migrace a odeslání zákazníkům vyžadují samostatné zadání; tento plán je neprovádí.

## Odstranění a otevřené předpoklady

- Klientský souhrn historie se odstraní v nynějším PR, stavové informace jednotlivých zpráv zůstávají.
- Staré přesměrování všech e-mailových incidentů do historie nahradí objednávkový cíl; neobjednávkový fallback má pojmenovaný důvod a zůstává.
- Nezavádět editaci buňky bez serverového příkazu, druhý send endpoint, implicitní označení jako zaplaceno ani V1/V2 obrazovky.
- Předpoklad: formulář má jedno autoritativní kontaktní e-mailové pole. Ve vlně 2 ověřit jeho mapování na stávající `update_order_responses`; pro starou objednávku bez takového pole zachovat pouze její současný kontaktní formát a žádná data nevymýšlet.
- Předpoklad: část problémových e-mailů nemá objednávku. DTO musí vracet nepřítomnou vazbu, UI pak zachová detail zprávy a nenabízí neplatné opravy objednávky.
- Po dokončení neexistuje živá cesta, která by ze selhaného potvrzení založila novou objednávku nebo změnila platební stav. Historická pravda o původním bounce zůstává dohledatelná.

## Podmínka předání implementace

Vlny 1-3 jsou hotové teprve tehdy, když upozornění i běžný seznam otevřou stejný detail, oprava projde jediným serverovým příkazem a databázové testy prokážou životní cyklus problému včetně jeho opětovného otevření. Cíleně ověřit výše jmenované SQL testy přes `node web_client/scripts/run_db_tests.js <soubor>`, dotčené command/widget testy v jednom běhu přes `fvm flutter test --concurrency=1 test/components/eshop/order_commands_cases.dart test/components/email_delivery/email_delivery_widget_cases.dart test/components/notification_center/notification_center_cases.dart` (doplnit pouze skutečně vzniklé vlastnické testy) a dotčené Dart soubory přes `fvm dart analyze <soubor>`. Před Flutterem ověřit volný jediný pracovní slot. Ověřit nenulový počet vybraných SQL testů a skutečné spuštění případů, nikoli jen existenci souboru. Nové Flutter testy dát do `*_test.dart`, případně registrovat v současné suite, nevytvářet paralelní test runner. Konkrétní nově vzniklé testy doplnit do výsledku implementace; samotné textové kontroly nejsou důkaz správnosti RPC. Lokální integrační cestu spustit postupem `festapp-local-e2e` se syntetickými daty.

Plán neprokazuje aktuální schopnosti produkčního poskytovatele potvrzovat delivery. Před implementací nápravy ověřit existující event kontrakt a testovací fixtures; nepřichází-li důkaz delivery, stav zůstane čekající/nejistý a nesmí se po časovém limitu sám prohlásit za úspěch. Chybějící provozní důkaz uvést ve výsledku, nevyžaduje nový placený nebo produkční pokus.
