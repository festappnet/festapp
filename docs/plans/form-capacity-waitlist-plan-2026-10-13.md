# Kapacita formuláře a náhradnické objednávky

Datum: 2026-10-13. Aktuální autoritativní kontrakt po výslovné korekci uživatele.
Ověřování: **release** pro nasazení; cílené standard kontroly pro změněné moduly.
Produkční migrace ani vydání náhradníků zatím neproběhly.

## 1. Jediná evidence vstupenek

`eshop.tickets` je jediná evidence jednotlivých vstupenek a jejich stavu.
Nepřidávat evidenci osob, samostatný participant lifecycle ani backfill historických
vstupenek. Starší vstupenky jsou rovnou součástí dynamického kapacitního výpočtu.
Čekající položka je rovněž vstupenka; pozdější přijetí použije stejné ticket ID.

Objednávka zůstává `eshop.orders`, vztah k vstupenkám a produktům zůstává
`eshop.order_product_ticket`. Nezakládat paralelní vlastnictví ticket/order/form.
Počet vstupenek se z těchto vazeb vždy počítá DISTINCT, protože jedna vstupenka
může mít více produktů. Vlastní odpovědi a volby patří konkrétní vstupence, nikoli
nově vytvořené osobě. Archivní objednávkové snapshoty a recovery journal jsou
historie konkrétní operace, nikoli druhý živý zdroj stavů.

## 2. Čekající vstupenka

Registrace vytváří objednávku ve stavu `waitlisted`, bez ceny a payment_info,
a požadovaný počet `eshop.tickets` ve stavu `waitlisted`. Jejich ticket_symbol je
NULL. Existující vazba order_product_ticket má produkt NULL. Taková vstupenka
není platná ke vstupu, nemá prodejní produkt, platbu ani PDF/QR ke vstupu.

Ticket data uchovává vlastní odpovědi podle stabilních ID formulářových polí.
Čas čekání patří čekající vstupence. Název, poznámka a budoucí jméno na vstupence
nevyžadují další entitu. Stavy nabídky se odvozují z offer slots a jejich termínu;
nezapisují se jako paralelní lifecycle osoby nebo vstupenky.

## 3. Dynamická kapacita

SQL v každém snapshotu počítá:

- Obsazenost: DISTINCT platné vstupenky navázané na formulář, mimo čekající a
  stornované vstupenky a mimo stornované objednávky. Nezaplacená běžná objednávka
  zabírá kapacitu už při potvrzení, stejně jako vybrané produkty.
- Nabídnutá místa: pending offer slots s dosud platnou expirací.
- Čekající vstupenky: aktivní čekání odvozené z ticket stavu a nabídky.
- Volná místa: limit minus obsazenost a chráněná nabídnutá místa.
- Veřejně dostupná místa: volná místa po ochraně pořadí aktivně čekajících.

Neukládat čítač obsazenosti. Revision slouží k ochraně aktuálnosti návrhu nabídky,
nikoli jako hodnota kapacity. Zámek formuláře a navazujících objednávek chrání
přijetí, registraci, změnu limitu a storno před souběžným překročením kapacity.
Storno mění přímo stav vstupenky a existující vazby; nic nesynchronizuje s osobou.

Bez limitu zůstávají dosavadní formuláře neomezené. Náhradníci jsou opt-in.
Blueprint a participant capacity nelze kombinovat. Změna limitu nesmí klesnout
pod platné vstupenky plus chráněná místa nabídek. Aktivní čekání/nabídky brání
vypnutí waitlistu nebo přechodu na nekompatibilní konfiguraci.

## 4. Nabídky

Nabídka je časově omezená možnost přijmout konkrétní počet míst. Editor nejprve
vidí návrh podle pořadí čekání a ručně potvrdí příjemce i expiraci.
`waitlist_offers` uchovává nabídku; `waitlist_offer_slots.ticket_id` odkazuje
přímo na existující čekající vstupenku. Nejvýše jeden pending slot na ticket ID.

Expirace, odmítnutí a zrušení ukončí nabídnuté místo a upraví pořadí čekající
vstupenky podle původně dohodnutých pravidel. Odhlášení ukončí konkrétní čekající
vstupenku. Nezakládat automatický prodej ani druhé kapacitní rozhodování v klientu.
Scheduled SQL expiry a při-command expiry používají tutéž implementaci.

## 5. Přijetí a jediný finalizer

Běžný prodej i přijetí nabídky používají `finalize_ticket_order_internal_v1`.
Běžný prodej zakládá vstupenky. Nabídka používá již existující vybrané čekající
vstupenky, ověřené vůči scope nabídky a objednávky; nevyrobí jejich náhrady.
Produkt a cenu určuje server, vybrané produkty se obsadí atomicky teprve při přijetí.

Úplné přijetí zachovává order ID, symbol a pořadí. Částečné přijetí vytvoří navázanou
běžnou objednávku a přesune do ní stejné vybrané ticket IDs pomocí stávajících
vazeb. Zbytek zůstává v původní čekající objednávce se svými vlastními odpověďmi.
Platební lhůta začíná až vznikem běžné objednávky.

Musí zůstat oddělené dvě vstupenky s různými jmény, poznámkami, dvěma vlastními
poli stejného typu a produkty 100/200 Kč. Výběr nebo úprava druhé nesmí změnit první.
Výměna nabídnutého slotu za jinou čekající vstupenku stejné skupiny zachová počet
chráněných míst, unikátní pending slot a historii původních vazeb.

## 6. Fakturoid a recovery

Dosavadní příprava faktury, úspěch a abort zůstávají součástí běžného order flow.
Recovery journal zachytí přesné předchozí ticket snapshots, vazby a offer slots
pro konkrétní příkaz. Nejde o druhý živý lifecycle.

Při neúspěchu restore vrátí vybrané vstupenky do čekání, odstraní vytvořené finance
podle existujícího flow a obnoví vazby a nabídku, pokud nevypršela. Split child se
bezpečně odstraní nebo ukončí podle dosavadního abort kontraktu. Restore nesmí
přepsat nezávislé změny nevybraného zbytku skupiny, včetně withdrawal. Opakované
complete/abort jsou idempotentní. Během preparing_payment nelze vstupenky editovat.

## 7. Osobní odkazy a bezpečnost

Oddělené capability scopes manage/offer, pouze hash tokenu v SQL a šifrovaný
zdroj v e-mailové frontě. Fragment `#waitlist?...` obsluhuje veřejný web klient i
Flutter formulář. Nepřepínat plošně URL strategii; zachovat běžné routes.
Načtení a reload jsou read-only. Platná nabídka funguje i na jinak uzavřeném
formuláři. Terminal DTO nevrací jména, odpovědi, finance ani další osobní údaje.

SQL kontroluje tenant, occasion, form, order, ticket a slot scope. Editorův write
vyžaduje existující oprávnění. Příkazy používají existující Client Sync receipts,
replay a konflikt payloadu. SECURITY DEFINER má trusted search_path, oprávnění
se kontrolují explicitně. Žádné domain triggery nebo obecné fallbacky.

## 8. DTO a normalizace

Read vrací `tickets` s BIGINT `id`, vlastními `answers` a odvozeným stavem nabídky.
Mutace vybírá `ticketIds`; jednotlivý checkout payload používá `ticketId`.
Slot používá `ticketId`. Není tu participant UUID nebo druhá identita člověka.

Jedna SQL normalizace ověřuje ID/typ pole v konkrétním formuláři a vstupence.
Starší veřejní klienti s typed + `_subFieldId` mají jediný mechanický vstupní
adaptér, současní klienti stabilní ID. Tyto transporty nesmějí založit dva prodejní
enginy. Alias nepatří do doménových odpovědí; server ignoruje klientskou cenu.
Adaptér lze odstranit až po aktualizaci všech dosud běžících starších klientů.

### Výchozí volby formuláře

Podporovaná výběrová pole sdílejí `form_fields.data.default_value`: single select
má jednu hodnotu, multiselect seznam, produkty používají produktová ID. Již uložená
odpověď nebo draft mají přednost, včetně výslovně prázdné volby. Default se nesmí
vrátit po přidání vstupenky, překreslení nebo předvyplnění nabídky.
Ve webu počáteční produktový výběr a renderer používají společný choice helper;
dosavadní výběr prvního produktu bez konfigurace zůstává výslovným UI pravidlem.
Čekající formulář nemá produktová pole ani jejich defaulty. Vymazaný produkt se
neposílá jako prázdné produktové ID. Server rozhoduje o dostupnosti a ceně,
nedoplňuje další implicitní výchozí produkty. Produktový multiselect může mít
více různých produktů stejného pole, nikoli tentýž produkt vícekrát.
Obecné textové/datumové defaulty nejsou nově zavedeny; tento release neslibuje
jednotný default editor pro nepodporované typy polí.

## 9. E-maily

Potvrzení náhradníků a nabídka používají dosavadní šablony, renderer,
`public.email_messages` a jediný `process-email-queue`. Žádný přímý druhý provider.
Waitlist registrace nemá běžný paid/free-order intent. Šifrované email snapshots
se po commit renderují s aktuálně přidělenou identitou objednávky. QA neposílá
skutečné e-maily zákazníkům.

## 10. Odstranění původního návrhu

Z aktivního schématu a zdrojů odstranit `eshop.order_participants`,
`form_participant_backfill_issues`, jejich writers/readers, shadow storno updates,
backfill guard a participant UUID kontrakt. Neuchovávat compatibility view nebo
participant API alias, protože nový endpoint ještě nebyl produkčně nasazen.

Historická migrace 1900 už je publikovaná na main, ale není v produkční DB.
Nová forward migrace 2000 odstraní odmítnuté schéma a nahradí všechny konzumenty.
Produkční aplikace obou migrací proběhne v jediné transakci bez backfill scope:
žádný historický participant se nevytvoří, výsledné schéma obsahuje jen tickets.
Historický SQL text v migration ledgeru není druhý běžící kontrakt.

## 11. Připravené další změny

Zachovat aktuální main, storno a mazání stornovaných objednávek, dialogy
potvrzující vybrané položky, ticket usage a poslední produktový/formulářový editor.
Před publikací porovnat původní rozpracovaný checkout bez přepisování jeho indexu.
Nevracet již publikované migrace ani změny dalších agentů.

## 12. Acceptance

Ověřit existující vstupenky bez backfillu; více produktů na jeden ticket počítá
jednou; waitlisted a storno se nepočítají do obsazenosti; partial/full reuse IDs;
vlastní odpovědi a produkty; overflow rollback a souběh; expiraci/withdrawal;
oprávnění a idempotency; Fakturoid abort/complete s izolací ostatních vstupenek;
jedinou email queue; fyzický reload a webové osobní odkazy; absenci odstraněných
tabulek a funkcí po migraci.

## 13. Moduly a závislosti

SQL vlastní schema, kapacitu, tickets, offers, acceptance, capabilities a recovery.
Klienti renderují stávající formuláře a posílají ticket kontrakt. E-mailový modul
zůstává existující. Nejprve zafixovat SQL/DTO, poté upravit konzumenty, odstranit
staré cesty a provést jednu souvislou cílenou validaci změněných oblastí.

## 14. Implementační subagenti

Backend/koordinace GPT-6.1-Sol Medium, UI Astra Medium, backendové regrese Sol.
Maximálně čtyři aktivní agenty včetně koordinátora. Oddělit SQL, klienty a testy;
koordinátor vlastní dokumentaci a autorizované vydání. Nepřidávat obecný audit.
Publikace a následné nasazení autorizovány uživatelem včetně admin override;
rozsah klientského vydání je pouze `prod/festapptickets` / vstupenky.online.
