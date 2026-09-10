# Plán: Offline funkcionalita (CSM Ostrava 2026)

**Stav: NÁVRH PŘIPRAVENÝ K IMPLEMENTACI (2026-07-12).** Vychází z požadavků
`docs/archive/plans/2026-07-12_offline_funkcionalita_pozadavky.md` (rozhodnutí R3/R5
tam jsou uzavřená — **neptej se na ně, drž se jich**). Všechna tvrzení o kódu
(soubory, řádky, RPC) byla 2026-07-12 ověřena proti repozitáři na větvi
`prod/csmostrava2026`.

> **Rozsah:** R2.1, R2.2, R2.4, R3, R4, R5 + ověření R2.3/R2.5/R6.
> **R1 (offline mapový podklad) se v tomto plánu VĚDOMĚ NEŘEŠÍ** — bude řešen
> samostatně (rozhodnutí uživatele 2026-07-12).

> **Prerekvizity:**
> 1. Na větvi jsou necommitnuté rozpracované změny (mj. `counseling_picker.dart`,
>    service RPC SQL, překlady). Tento plán se implementuje **až po jejich
>    dokončení a commitu** — nemíchej je do svých změn; před začátkem ověř
>    `git status`.
> 2. Existuje paralelní plán `2026-07-11_mista_uklid_architektura_plan.md`,
>    který přesouvá widgety z `cleaning_page.dart` a sahá do `map_page.dart`.
>    Čísla řádků níže platí pro stav **před** ním. Pokud už byl implementován,
>    místa dohledej grepem (názvy funkcí se nemění); pokud nebyl, implementuj
>    tento plán nezávisle a konflikt řeš ten, kdo půjde druhý.

## 0. Výchozí stav (ověřená zjištění)

- **Celý plán je čistě klientský — žádné změny SQL ani zásah do live DB.**
- Sync: `SynchroService.refreshOfflineData()`
  (`lib/data_services/synchro_service.dart:38-83`) — jednosměrné stahování;
  speakers se už cachují (řádky 67-72), plný seznam událostí je gatovaný
  `PlatformHelper.isPwaInstalledOrNative()` (řádky 74-77, pozor na `occasionId!`
  na řádku 75). Voláno z `rights_service.dart:135` (await) a
  `auth_service.dart:35` (fire-and-forget).
- Úložiště: `OfflineDataService` (`lib/data_services/offline_data_service.dart`)
  nad sembastem; generika `saveAllOffline`/`getAllOffline` (řádky 207/242,
  vyžadují `toJson()`), `saveOffline`/`getOffline` pro jednotlivé objekty
  (218/225), `clearUserData()` (200-205). Vzory: bundle `saveSpeakers`/
  `getSpeakers` (169-173, klíč `"speakers"`), seznam `saveAllPlaces` (108).
- **R2.1** Speakers: cache existuje (`SpeakersBundle` má `toJson`,
  `speakersForEvent` helper), ale UI ji nečte — `event_page.dart:1312-1323`
  (`loadSpeakers`) volá živé `get_speakers` a při chybě sekci skryje
  (`_buildSpeakersSection`, 1079-1108); `counseling_picker.dart:94-113`
  (`_loadInitial`) taky živě → offline prázdný výběr oblastí. Živé z podstaty:
  `get_counseling_availability`, `get_counseling_topics_overview`, rezervace.
- **R2.2** Úklid: `DbCleaning` (`lib/components/cleaning/db_cleaning.dart`) je
  záměrně online-only. Stav vrací RPC `get_cleaning_status` → `getStatus`
  (řádky 35-49) vč. per-user flagů `is_blocked`/`notifications_muted`.
  Čtou ho `cleaning_page.dart` `_loadData` (86-110) a `map_page.dart`
  `_loadCleaningStatus` (1038-1049, volané jen v online větvi na ř. 955;
  offline render pinů 843-855 barvy vůbec nezkouší). `CleaningPlaceStatus`
  (`models/cleaning_place_status.dart`) **nemá `toJson()`**.
- **R2.4** Feedback: `DbEventFeedback` online-only; widget `_load`
  (`event_feedback_widget.dart:77-93`) při chybě tiše spolkne výjimku a tváří
  se jako „ještě neodesláno" — offline lže.
- **R3** Zápisy dnes: hlášení úklidu → generický toast
  (`cleaning_report_flow.dart:54`); odeslání feedbacku → generický toast
  (`event_feedback_widget.dart:114-138`), smazání feedbacku ticho (153);
  rezervace poradny (`counseling_picker.dart:150,155`) a přihlášení na program
  (`DbEvents.signInToEvent` `db_events.dart:201`, `signOutFromEvent` :576;
  call-sites `schedule_page.dart:241/246`, `my_schedule_page.dart:175/180`,
  `event_page.dart:1417/1423/1472`) → **neodchycená výjimka, úplné ticho**.
- **R4** Neexistuje globální detekce připojení (connectivity_plus jen mapa+hra,
  bez sdíleného wrapperu), žádný offline banner, žádný „last synced" timestamp.
  Shell pro banner: `occasion_home_page.dart` `build` (123), `body: child`
  (209). Existující hláška: `InformationStrings.offlineWarning`
  (cs.json:1601), použitá jen ve hře.
- **R2.3/R2.5** vlastní ubytování (inventory bundle) a vlastní skupina
  (`UserInfoModel`, `event_page.dart:1329-1337`) už offline fungují — jen ověřit.

---

## Fáze 1 — Základ: `ConnectivityService` + `OfflineStrings`

Sdílený stavební kámen pro R3 i R4 — udělej jako první.

1. Nový `lib/services/connectivity_service.dart` — malý statický servis po
   vzoru ostatních services:
   - `ValueNotifier<bool> isOfflineNotifier` plněný z
     `Connectivity().onConnectivityChanged` (vzor subscribe:
     `game_page.dart:41-63`; offline = výsledek obsahuje
     `ConnectivityResult.none`).
   - `Future<bool> isOffline()` — one-shot `checkConnectivity()` (vzor
     `offline_map_helper.dart:23-24`) pro použití před zápisy.
   - Inicializace (start listeneru) v `main.dart` vedle ostatních init
     služeb; idempotentní.
2. Nový `lib/components/offline/offline_strings.dart` — třída `OfflineStrings`
   dle i18n konvence (namespace `Offline.*`), klíče viz Fáze 7. Existující
   `InformationStrings.offlineWarning` **nech hře** — nekříž importy featur.
3. Do `ExceptionHandler` (`lib/services/exception_handler.dart`) přidej
   `static bool isNetworkError(Object e)` — detekce `http.ClientException` /
   `SocketException` / web „Failed to fetch" (ověř reálný typ výjimky
   supabase klienta na webu vypnutím sítě v DevTools). Nic jiného v guardu
   neměň — chování čtení zůstává.

Ověření: `fvm flutter analyze` čisté.

---

## Fáze 2 — R2.1 Přednášející & poradny: čtení z cache

- ✅ Sloty/rezervace poraden zůstávají **live-only** (real-time obsazenost) —
  offline jen čitelná degradace, žádné cachování dostupnosti.
1. `event_page.dart` `loadSpeakers` (1312-1323): v `catch` doplň fallback
   `_speakersBundle = await OfflineDataService.getSpeakers()` (+ `setState`).
   Sekce se pak vykreslí z cache; když cache není, zůstává dnešní skrytí.
2. `counseling_picker.dart` `_loadInitial` (94-113): před živým voláním
   naseeduj `_bundle` z `OfflineDataService.getSpeakers()` (paint-from-cache,
   vzor `schedule_page.dart:155` `_loadOfflineDataThenFast`), pak nech
   proběhnout živé načtení; když živé selže, cache zůstává → oblasti a
   medailonky přednášejících jsou vidět offline.
3. Tamtéž: když selže `getCounselingTopicsOverview` / `_selectTopic`
   (`get_counseling_availability`, ř. 124) a `ConnectivityService.isOffline()`,
   místo chybového toastu zobraz inline text
   `OfflineStrings.counselingNeedsConnection` v místě výběru slotů. Online
   chyby nech na dnešním `ExceptionHandler.guard`.
4. Greying oblastí bez overview už dnes degraduje (nic nešedne,
   `counseling_picker.dart:54-58`) — nech být.

Ověření: letadlový režim → detail události ukáže přednášející; výběr poradny
ukáže oblasti + hlášku u slotů.

---

## Fáze 3 — R2.2 Úklid: cache stavu + offline čtení (těžiště plánu)

- ✅ Cachuje se **jen seznam stavů** (veřejná data) + čas stažení. Per-user
  flagy `is_blocked`/`notifications_muted` a crew reporty (`get_cleaning_reports`)
  se **necachují** — offline se crew ovládání (mute, block, resolve, historie)
  prostě nenabízí/degraduje.
1. `models/cleaning_place_status.dart`: doplň `toJson()` (zrcadlo `fromJson`,
   řádky 5-28; status serializuj přes `name` enumu).
2. `OfflineDataService`: konstanta `cleaningStatusOfflineStorage = "cleaningStatus"`
   (vedle `speakersOfflineStorage`, ř. 28) + pár
   `saveCleaningStatus(List<CleaningPlaceStatus>, DateTime fetchedAt)` /
   `getCleaningStatus()` vracející i `fetchedAt` — ulož jako jeden objekt přes
   `saveOffline` (vzor speakers), např. mapa
   `{"places": [...], "fetchedAt": iso}`. Do `clearUserData()` **nepatří**
   (data jsou veřejná).
3. `SynchroService.refreshOfflineData()`: do bloku `occasionId != null` (za
   speakers, ř. 72) přidej krok gatovaný
   `FeatureService.isFeatureEnabled(FeatureConstants.cleaning)`:
   `DbCleaning.getStatus(occasionId)` → `saveCleaningStatus(...)`. **Obal
   vlastním try/catch** — selhání úklidu nesmí přerušit zbytek syncu (řetěz
   dnes nemá ochranu, nezhoršuj ho).
4. `cleaning_page.dart` `_loadData` (86-110): při úspěchu `getStatus` ulož do
   cache (refresh-on-read, vzor `news_page.dart:107`); v `catch` čti cache —
   vykresli dlaždice/souhrn z cache + banner se stářím dat
   (`OfflineStrings.lastUpdated` s `fetchedAt`). Offline skryj/zablokuj crew
   sekce závislé na živých datech (historie, mute, block, resolve) a tlačítko
   hlášení nech na degradaci z Fáze 4. Periodický poll (ř. 75-77) nech — chyby
   už polyká.
5. `map_page.dart` `_loadCleaningStatus` (1038-1049): při úspěchu ulož do
   cache; v `catch` čti cache do `_cleaningByPlace`. Navíc zavolej
   `_loadCleaningStatus()` i z offline renderu (za načtení míst, ř. 843-855),
   ať mají záchody barvy i bez sítě.

Ověření: online projít úklid (žádná regrese vč. crew pohledu), pak letadlový
režim → seznam záchodů s posledními barvami + stáří dat; mapa barví piny.

---

## Fáze 4 — R2.4 Zpětná vazba: offline stav „už jsem odeslal"

1. `OfflineDataService`: klíč `eventFeedbackOfflineStorage = "eventFeedback"` +
   `saveMyEventFeedback(int eventId, Map json)` / `getMyEventFeedback(eventId)`
   — jeden objekt `{eventId: feedbackJson}` přes `saveOffline`/`getOffline`.
   Přidej mazání do `clearUserData()` (vazba je per-user/per-device).
2. `event_feedback_widget.dart`:
   - `_load` (77-93): při úspěchu ulož odpověď do cache; v dnešním tichém
     `catch (_)` (90) čti cache — když je záznam, vykresli „odesláno" stav
     jako dnes; když není a `ConnectivityService.isOffline()`, zobraz místo
     formuláře text `OfflineStrings.feedbackStateUnknown` (žádné lhaní
     „ještě neodesláno").
   - `_submit` (102): při úspěchu zapiš do cache.
   - `_remove` (140-153): při úspěchu smaž z cache; tichý `catch (_)` na 153
     nahraď toastem (offline větev viz Fáze 5, jinak
     `EventFeedbackStrings` generická chyba).

Ověření: odeslat vazbu online, letadlový režim → detail události ukazuje
„odesláno"; u neodeslané události offline ukazuje hlášku, ne prázdný formulář.

---

## Fáze 5 — R3 Čitelná degradace zápisů (var-D)

- ✅ **Žádná fronta.** Jediný cíl: každý zápis offline řekne jasně
  `OfflineStrings.writeRequiresConnection` („Bez připojení nelze odeslat,
  zkus to prosím u signálu.") místo ticha/generické chyby.
1. Vzor větvení v catch: `if (ExceptionHandler.isNetworkError(e))` →
   `ToastHelper.Show(context, OfflineStrings.writeRequiresConnection,
   severity: NotOk)`, jinak dnešní chování.
2. **Přihlášení na program**: try/catch přímo do `DbEvents.signInToEvent`
   (`db_events.dart:201`) a `signOutFromEvent` (:576) okolo `rpc(...)` —
   pokryje všech 5 call-sites najednou; návratová hodnota/flow při chybě
   stejné jako dnešní ne-200 větev (ověř, že call-sites po false/void jen
   nerefreshují). Toast z Db vrstvy je zde OK — třída už přes switch kódů
   toasty ukazuje; drž lokální konvenci.
3. **Rezervace/zrušení poradny**: `_bookSlot`/`_cancelReservation`
   (`counseling_picker.dart:150,155`) jedou přes upravené
   `DbEvents.signIn/Out` z bodu 2 — jen ověř, že se offline neukáže dvojí
   toast a UI se nerefreshne do lživého stavu (`_reloadAfterChange` se při
   selhání nesmí tvářit jako úspěch).
4. **Hlášení úklidu**: `cleaning_report_flow.dart` catch (54) — doplň offline
   větev před generický `CleaningStrings.reportError`.
5. **Feedback**: `_errorMessage` (`event_feedback_widget.dart:122-138`) —
   offline větev před generickým `feedbackCouldNotBeSaved`; `_remove` viz
   Fáze 4 bod 2.

Ověření: všechny čtyři akce v letadlovém režimu → jednotná srozumitelná
hláška, žádné ticho, žádný rozbitý stav UI; online beze změny.

---

## Fáze 6 — R4 Offline indikátor + stáří dat

1. Timestamp syncu: na konec `refreshOfflineData()` (za
   `rebuildOfflineIndex()`, ř. 82) `OfflineDataService.saveOffline` klíč
   `"lastSyncedAt"` (ISO string) + getter. Jeden timestamp za celý bundle
   stačí (per-store má jen úklid, viz Fáze 3).
2. Nový widget `lib/components/offline/offline_banner.dart`: tenký proužek
   poslouchající `ConnectivityService.isOfflineNotifier`
   (`ValueListenableBuilder`), text `OfflineStrings.youAreOffline` +
   `OfflineStrings.lastUpdated(lastSyncedAt)` když timestamp existuje.
   Online → `SizedBox.shrink()`.
3. Vlož do `occasion_home_page.dart` (`body: child`, ř. 209):
   `Column(children: [OfflineBanner(), Expanded(child: child)])` — pokryje
   všechny taby. Stránky mimo occasion shell (login, unit) banner vědomě
   nemají.
4. Stáří dat u úklidu řeší Fáze 3 bod 4 (kritická čerstvost); jinde stačí
   globální banner.

Ověření: vypnout síť → banner naskočí na všech tabech; zapnout → zmizí.

---

## Fáze 7 — R5 Prohlížeč (nice-to-have): odgatovat cache událostí

- ✅ Rozhodnuto podle R5 „pokud půjde levně" — jde (jeden gate), děláme.
1. `synchro_service.dart:74-77`: odstraň podmínku
   `isPwaInstalledOrNative()`; blok přesuň dovnitř `occasionId != null` (nebo
   nahraď `occasionId!` bezpečnou kontrolou) — dnes by anonymní web bez
   occasion na `!` spadl.
2. Payload pozor: `getAllEvents(occasionId, true)` tahá i HTML popisy —
   největší cachovaný balík. Žádná další optimalizace se nedělá (sembast_web
   = IndexedDB, funguje v obyčejném tabu); jen ověř na localhostu, že sync
   v prohlížeči viditelně nezpomalí start (fire-and-forget větev z
   auth_service to kryje).

Ověření: obyčejný (nenainstalovaný) Chrome tab → načíst program online,
letadlový režim + reload → program se zobrazí z cache.

---

## Fáze 8 — i18n

Nové klíče **jen** přes `OfflineStrings` (namespace `Offline.*`), cs + en,
doplnit do `assets/translations/cs.json` + `en.json` a **byte-identickou
kopii** do `web_client/public/assets/translations/`. Ostatní jazyky
(de/pl/sk/uk) nedoplňuj. Návrh znění (finální text dolaď dle stylu okolí):

| Klíč | cs |
|---|---|
| `Offline.youAreOffline` | „Jsi offline — zobrazují se naposledy stažená data." |
| `Offline.lastUpdated` | „Naposledy aktualizováno {time}." |
| `Offline.writeRequiresConnection` | „Bez připojení nelze odeslat. Zkus to prosím znovu, až budeš u signálu." |
| `Offline.counselingNeedsConnection` | „Dostupnost poraden a rezervace vyžadují připojení k internetu." |
| `Offline.feedbackStateUnknown` | „Bez připojení nelze zjistit stav zpětné vazby." |

Před zavedením každého klíče zkontroluj, jestli nesedí existující
(`InformationStrings.offlineWarning` zůstává hře).

---

## Fáze 9 — Ověření (R6, R2.3, R2.5), testy, nasazení

1. `./automation/test_all.sh` — žádné nové failury (2 baseline DB failury mimo
   rozsah jsou známé); `fvm flutter analyze` čisté. Žádné SQL změny → DB testy
   se nemění.
2. Lokální revize: `fvm flutter run -d web-server --web-port 8080` (nikdy
   `-d chrome`), uživatel projde na `localhost:8080`. **Počkej na
   odsouhlasení, pak teprve nasazuj.**
3. Akceptační průchod v letadlovém režimu (nativní + nainstalovaná PWA;
   prohlížeč po Fázi 7 bonusově):
   - program + detail události, můj program;
   - přednášející v detailu události, výběr poradny (oblasti vidět, sloty
     degradují hláškou);
   - úklid: seznam se stavy + stáří dat, mapa s barvami záchodů;
   - mapa s trasami; **vlastní ubytování (R2.3)**; **moje skupina (R2.5)** —
     detail skupinové události ukáže vedoucího a členy;
   - všechny 4 zápisy → jednotná offline hláška;
   - offline banner viditelný, po připojení zmizí.
   - Regrese online: program, poradny (rezervace + zrušení), úklid vč. crew,
     feedback — beze změny chování.
4. Nasazení (standard csmostrava): bump `VERSION` (nikdy dolů), commit **jen
   vlastních souborů** s anglickou zprávou, `deploy_direct.sh`, **žádný
   `git push`**. Live DB se nemění.

## Závazná pravidla (připomínka)

- Lokalizace jen přes `*Strings` třídy (žádné `'literál'.tr()`), cs+en,
  kopie do `web_client/public/assets/translations/`.
- UI chyby přes `ToastHelper`/`ExceptionHandler`; gate přes
  `FeatureService`/`RightsService`; vždy `fvm` prefix; localhost-first.
- Stavět jen to, co říká plán — žádná vylepšení navíc.

## Mimo rozsah (vědomě NEDĚLAT)

- **R1 offline mapový podklad** — řeší se samostatně mimo tento plán.
- Fronta odložených zápisů (zamítnuto, R3 var-D).
- Adminské přehledy offline: katalog služeb ubytování (`getAllServices`),
  „kdo kde bydlí", správa přednášejících (`get_speakers_for_edit`), výsledky
  feedbacku — vše live-only (rozhodnutí R5: cílem je běžný uživatel).
- Cache herních týmů / druhé skupiny (mezera u R2.5 — až si Julie vyžádá).
- Cachování dostupnosti poradenských slotů (real-time obsazenost).
- Offline mute/block/resolve úklidu a crew historie hlášení.
- `signOutFromEvent` bez `default:` větve ve switchi (online-only kosmetika)
  a jakýkoli další polish online chybových stavů nad rámec R3.
- Per-store „last synced" timestampy mimo úklid; banner na stránkách mimo
  occasion shell (login, unit stránky).
