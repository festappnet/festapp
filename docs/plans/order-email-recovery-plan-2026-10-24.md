# Náprava nedoručeného e-mailu u konkrétní objednávky

Datum: 2026-10-24  
Stav: Připraveno k implementaci; budoucí změny příjemce a opakované odeslání nejsou implementované.  
Ověřování: standard - oprávnění, osobní údaje, souběh a nevratné odeslání e-mailu.  
Výchozí revize: main `4b883300da89ac0b33cc2cd50e6954fb4668ef51`; aktuální drobné opravy UI jsou v PR #576.

## Výsledek pro pořadatele

Z upozornění na nedoručené potvrzení otevře pořadatel konkrétní objednávku, vidí její symbol, zákazníka, aktuální kontaktní e-mail, adresu původního neúspěšného odeslání a lidsky popsaný problém. Příslušný řádek tabulky se vyhledá, posune do záběru a krátce zvýrazní. Z detailu může opravit kontakt, znovu odeslat potvrzení nebo vědomě zrušit objednávku. Žádná z těchto akcí se nespouští pouhým otevřením upozornění.

Historie e-mailů zůstává tabulkou jednotlivých zpráv s jejich stavem a technickým detailem. Souhrnný pás počtů nad tabulkou se odstraňuje v nynějším opravném vydání, včetně jeho klientského načítání. Tento plán nezavádí další přehledový dashboard.

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
| Storno má samostatný potvrzovaný příkaz s identitou a serverovými účinky. | `order_commands.dart`, `DbOrders.stornoOrder`, `OrdersContent.cancelOrders` | Znovu použít storno; nekopírovat inventářovou ani platební logiku. |

## Rozhodnutí a hranice

1. Primární akce na objednávkovém e-mailovém incidentu bude „Otevřít objednávku“. Technická „Historie doručování“ zůstane vedlejší akcí v detailu. Pro zprávu bez objednávky zůstane autorizovaný detail e-mailu.
2. Zvýraznění není zaškrtnutí pro hromadné akce. Otevření odkazu nesmí změnit existující hromadný výběr, potvrdit platbu ani odeslat zprávu. Neviditelný cíl kvůli filtru nabídne výslovné zobrazení cílové objednávky; odvolané oprávnění a smazaný cíl mají stejnou bezpečnou odpověď.
3. Detail nabídne „Upravit e-mail“, „Znovu odeslat potvrzení“ a oddělené „Zrušit objednávku“, vždy podle aktuálních serverových práv a stavu objednávky. Změna kontaktu má akce „Uložit“ a „Uložit a znovu odeslat“. Před odesláním je vidět přesný příjemce a druh zprávy.
4. Oprava e-mailu se týká kontaktu konkrétní objednávky a příslušné odpovědi jejího formuláře. Nemění přihlášení ani e-mail uživatelského účtu, jiné objednávky, platby, částky, místa či QR identity. Po stornu zůstává objednávka pouze pro čtení.
5. Pro nezaplacenou objednávku se znovu odešle potvrzení se stávajícími platebními pokyny, bez nové objednávky nebo nové platby. Vstupenky se posílají pouze pro stav, který jejich odeslání již dovoluje. Typ `order_confirmation` a `order_tickets` se nesměšuje; update, upomínka, storno a neobjednávkové zprávy se nevydávají za potvrzení.
6. U původního problému zůstane historická adresa i důvod zachován. Nová adresa a nové odeslání vytvoří provázaný pokus, nepřepisují doručovací fakta původní zprávy. „Zařazeno k odeslání“, přijetí poskytovatelem a doručení jsou odlišné výsledky. Oprava adresy sama incident neoznačí jako doručený.
7. Hard bounce nebo spam se neobejde vymazáním `email_suppressions`. Stejná blokovaná adresa dostane srozumitelnou informaci a další postup. Opravenou jinou adresu lze posoudit běžnými pravidly fronty. Žádné automatické storno kvůli doručovací chybě a žádné plošné rozesílání při nasazení.

## Kanonický kontrakt změny kontaktu a opakovaného odeslání

Rozšířit existující vrstvu `OrderCommands` / `ClientCommandTransport` o úzký potvrzovaný příkaz. Navržený veřejný název: `repair_order_email_client_sync_v1`. Vstup obsahuje objednávku, očekávaný dosavadní kontakt nebo revizi, novou adresu, volitelné ID zdrojové zprávy, příznak opakovaného odeslání a stabilní `commandId`. Nový vědomý pokus má novou identitu; retry po timeoutu zachovává tu původní.

Server po kontrole `can_write_orders` a příslušného práva číst zprávu ověří, že objednávka, zpráva, akce a organizace patří k sobě. Samostatné přijetí `orderId` a `messageId` nesmí umožnit kombinovat cizí objekty. Zamkne dotčenou objednávku ve stejném pořadí jako její současné příkazy, zkontroluje revizi, stav a validitu adresy. Aktualizuje kontakt i jeho formulářovou projekci a uloží audit do současné historie/receipt infrastruktury. Není-li opravovaný kontakt stále aktuální, vrátí konflikt a žádné odeslání.

Pro „Uložit a znovu odeslat“ je změna kontaktu a vložení jednoho záměru do současné fronty atomická transakce. Při odmítnutí vložení se nic tiše neuloží. „Uložit“ bez odeslání je samostatně platná větev. Výstup obsahuje autoritativní aktualizovanou objednávku, potvrzení příkazu, `messageId`/stav záměru, nebo explicitní „neodesíláno“. Stejná identita vrací stejný receipt a nezaloží další zprávu. Vnější poskytovatel se nevolá uvnitř databázové transakce.

Použít `enqueue_order_email` a existující worker/renderery, případně úzce doplnit jejich autorizovanou hranici pro explicitní opakované potvrzení. Veřejný příkaz nesmí přijímat libovolné HTML, příjemce jiné objednávky nebo service-role tajemství. Nevytvářet paralelní frontu ani používat `send-ticket-order` pro nové vytvoření objednávky. `SECURITY DEFINER` pouze v `public`, s `search_path = public, extensions` a explicitním `eshop.*`.

Předpřipravené zprávy na starý kontakt se řídí stávajícím `email_intent_valid`; implementace musí prokázat jejich invalidaci a chování skutečně probíhajícího pokusu. Přijatou zprávu nelze vzít zpět. U `unknown` nejdříve vyřešit potvrzení původního záměru, nikoli automaticky vyrábět další nejasný pokus. Toto pravidlo nenahrazovat toastem „odesláno“.

## Implementační vlny

### 0. Aktuální drobná oprava historie

Odstranit `_overview`, jeho `get_email_delivery_overview` volání a souhrnný `Wrap` z `EmailDeliveryHistory`. Zachovat jednotlivé řádky, jejich stav a detail, stránkování, filtr organizace a volání `get_email_delivery_detail`. Upravit vlastnický test přepnutí organizace, aby ověřoval pouze načtení řádků a zachování rozsahu. Globální reportovací SQL není součástí této kosmetické změny; na jeho odstranění se neváže databázový zásah.

Výstup: žádný souhrnný pás ani požadavek tohoto widgetu na přehledové API. Ověřit `test/components/email_delivery/email_delivery_history_cases.dart`.

### 1. Přesný cíl upozornění a soustředění objednávky

V `notification_center_dto` přidat autorizované `orderId`/symbol pro objednávkový incident ze serverového spojení zprávy a objednávky. V `NotificationCenterBell._detail` upřednostnit tuto vazbu a předat i identitu problému. V `OrdersContent` rozšířit existující `orderId` cestu: najít řádek, posunout jej do záběru, krátce jej zvýraznit a otevřít společný opravný detail. Při uzavření spotřebovat jen vlastní query target přes `clearNotificationDetailTarget`. Podporovat opakované otevření, zrušené objednávky a nedostupný objekt. Nezavádět druhou navigaci obcházející root router.

Výstup: klik otevře přesně danou objednávku; automatický výběr nesáhne na checkboxy. Testy trasování se dvěma současně otevřenými obrazovkami, omezenými právy, filtrem a opakovaným vstupem.

### 2. Autoritativní změna kontaktu a fronta

Implementovat výše uvedený kontrakt a zapojit ho do `OrderCommands`, stabilní identity příkazů a současného command registry/receipt vlastníka podle vzoru storna. Úzce rozšířit podporu potvrzení a provenienci nového pokusu, nikoli obecný přeposílač. Přidat kanonické SQL a jednu unikátní migraci; žádné persistentní aplikační triggery. Udržet kontaktní/formulářovou projekci bez přecenění, změny zásob či platby.

Výstup: DB testy pro read-only uživatele, cizí tenant/zprávu, neplatnou adresu, konflikt kontaktu, storno/stock, replay, souběžný dvojklik, timeout po commitnutí, selhání enqueue a blokovanou adresu. Prokázat nezměněnou platbu, cenu, inventář a identitu vstupenek. Navázat na `database/tests/emails/canonical_email_queue_test.sql`, `order_ticket_intents_test.sql`, `database/tests/notification_center/email_sources_test.sql` a testy `OrderCommands`.

### 3. Opravný detail a zpětná vazba

Vytvořit kompaktní kontaktní sekci společného detailu objednávky, využívanou jak z upozornění, tak z objednávek. Ukázat starou neúspěšnou adresu a současný kontakt jako dvě různé informace, při shodě je neopakovat. Nabídnout výše definované akce; během požadavku zakázat dvojklik a po konfliktu znovu načíst serverový stav. Čtecí role uvidí stav a historii, nikoli aktivní zápisové akce. „Zrušit objednávku“ použije nynější potvrzení a `DbOrders.stornoOrder`; u zaplacené objednávky popíše skutečný existující postup vrácení peněz a neslíbí refund, který příkaz neprovedl.

Provázání původního incidentu a nového záměru ukládat do existujícího receipt/provenience vlastníka. Nový pokus se zobrazí jako čekající; až potvrzené doručení může být označeno jako doručeno. Storno se označí jako zrušená objednávka, ne úspěšné doručení. Nevytvářet obecnou tabulku ručně řešených incidentů.

Výstup: widgetové testy čtení/editace, konfliktních stavů a následků akcí, mobil 320 px při 200 % textu, světlý/tmavý `ThemeConfig` a dialog skutečně otevřený z AppBar. Ověřit celou cestu na izolovaném lokálním tenantovi s falešným transportem e-mailu; žádné reálné zákaznické odeslání v testu.

### 4. Samostatné autorizované vydání

Před vydáním znovu ověřit unikátnost migrace, ACL, rollback a zachování kanonické main/tenant ancestry. Nové backendové rozšíření před novým UI, žádná změna očekávaného kontraktu starým klientům. Nasazení na jeden vybraný tenant, lokální build a `automation/deploy_direct.sh`. Ověřit přesnou živou verzi, právní stránky a skutečnou cestu detailu s bezpečnými testovacími daty. Produkční migrace a odeslání zákazníkům vyžadují samostatné zadání; tento plán je neprovádí.

## Odstranění a otevřené předpoklady

- Klientský souhrn historie se odstraní v nynějším PR, stavové informace jednotlivých zpráv zůstávají.
- Staré přesměrování všech e-mailových incidentů do historie nahradí objednávkový cíl; neobjednávkový fallback má pojmenovaný důvod a zůstává.
- Nezavádět editaci buňky bez serverového příkazu, druhý send endpoint, implicitní označení jako zaplaceno ani V1/V2 obrazovky.
- Předpoklad: formulář má jedno autoritativní kontaktní e-mailové pole. Ve vlně 2 ověřit jeho mapování na stávající `update_order_responses`; pro starou objednávku bez takového pole zachovat pouze její současný kontaktní formát a žádná data nevymýšlet.
- Předpoklad: část problémových e-mailů nemá objednávku. DTO musí vracet nepřítomnou vazbu, UI pak zachová detail zprávy a nenabízí neplatné opravy objednávky.
- Po dokončení neexistuje živá cesta, která by ze selhaného potvrzení založila novou objednávku nebo změnila platební stav. Historická pravda o původním bounce zůstává dohledatelná.
