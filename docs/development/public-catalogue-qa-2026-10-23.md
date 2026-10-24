# Veřejný katalog a ovládání klávesnicí - čtvrtý průchod UI/UX, 23. 10. 2026

Souhrnná stránka: [QA zápisník](qa-overview.html).

Výsledek: **2 nové nálezy P2**, oba z veřejného webového klienta. Hledání bez diakritiky, archiv, prázdné výsledky, změna jazyka a obnovení katalogu po simulovaném výpadku prošly. Starších 14 nálezů se v tomto průchodu znovu neověřovalo.

## Stav oprav - 23. 10. 2026

QA-015 a QA-016 jsou opravené a začleněné do `main` přes PR #570, commit `c8e70c6e7`. Po aktualizaci na základ `d97835e79` znovu prošlo 50 cílených testů i produkční Vite build. Probíhající zmrazený produkční release se tímto nemění; tento commit zde nebyl nasazen.

- QA-015: návrat neznámé adresy na `/` pokračuje běžnou inicializací katalogu, místo předčasného označení routy za vykreslenou. Totéž platí pro nepodporované aplikační cesty s návratem na úvod.
- QA-016: nastavení, přihlášený avatar, zavření popoveru, zpětná vazba a její nabídka používají nativní tlačítka. Mají lokalizované názvy, stav rozbalení, viditelný fokus a návrat fokusu po zavření. Dialog zpětné vazby má pojmenované zavření a kopírovací tlačítka. Zavírání a překreslení uklízejí posluchače klávesnice.

Ověření: 50 cílených Node/JSDOM testů prošlo, produkční Vite build prošel. Izolovaný headless Chromium ověřil skutečné moduly routeru, inicializace a UI: neznámá URL se bez reloadu změnila na `/`, katalog se vykreslil; Tab dosáhl nastavení i zpětné vazby, Enter i mezerník je otevřely, Escape je zavřel a obnovil fokus. Při 390 px dokument vodorovně nepřetékal. Browserový test používal syntetický katalog a nahrazenou inicializaci backendu, žádný produkční backend. Neověřuje skutečné odesílání e-mailu ani produkční CDN.

## Prostředí a skutečný rozsah

Pracovní strom `feat/occasion-setup-wizard-20261007`, HEAD `353394511`, včetně existujících lokálních změn. Produkční data a služby se nepoužily, produktový kód se neopravoval.

Původně byl zahájen průchod Info a Místa ve skutečné Flutter aplikaci. V prázdné tabulce vznikl rozpracovaný řádek a přes UI byl zadaný název Doprava a parkování. HTML editor šel otevřít. Při dalším zadávání se zasekla automatizace prohlížeče; příčinu v produktu tento průchod neprokázal. Název ani obsah nebyly uložené do DB. **Správa informačních textů a míst tímto není otestovaná do konce.** [Rozpracovaný řádek](evidence/public-catalogue-qa-2026-10-23/info-new-row.png), [otevřený editor](evidence/public-catalogue-qa-2026-10-23/info-html-editor.png), [surový záznam nedokončené části](evidence/public-catalogue-qa-2026-10-23/info-places-recovered.webm).

Flutter slot mezitím převzal souběžný release. Vlastní Flutter server byl ukončen a znovu nespouštěn. Pro další testování se použil celý skutečný `web_client/index.html` přes `pnpm 11.24.0 exec vite`, na loopback portu 56920, proti vlastnímu obnovenému Supabase projektu `festapp-wizard-ux-20261023`, API/DB 56821/56822. Katalog byl testovaný v čistě webovém profilu: `isAppSupported=false`, `isAllUnit=true`, organizace 1, vypnutá vzdálená aktivace. Úvodní pokusy s nesprávným lokálním profilem a přesměrováním na Flutter nejsou nálezy produktu.

Lokální konfiguraci dodal task-owned Vite transform s kontrolou loopback backendu; v repozitáři se neměnil generovaný `app_config.js`. Nebyly mockované odpovědi katalogu ani Auth. [Použitý profil bez klíčů](evidence/public-catalogue-qa-2026-10-23/local-profile.json).

Izolovaný headless Chromium `festapp-public-qa-20261023`, explicitně prázdná konfigurace, desktop 1440 x 1000 a mobilní viewport 390 x 844. Produkční Festapp, Supabase Cloud a vstupenky.online požadavky blokované. Syntetické lokální akce byly označené jako propagované, protože veřejný katalog jinak správně vrací prázdný seznam; přibyla jedna archivní fixture QA Archivní ples 2025. Nejde o ověření publikování přes administrátorské UI.

Ve Flutter tabulce byla pro pointer ovládání dočasně vypnutá pointer vrstva sémantických DOM uzlů. To umožnilo práci se skutečným editorem buňky a není to změna aplikace ani důkaz plné přístupnosti Flutteru. Nálezy níže pocházejí až z následného HTML/JS klienta bez tohoto zásahu.

[Surový záznam veřejného webu](evidence/public-catalogue-qa-2026-10-23/public-catalog-recovered.webm) zahrnuje přípravu lokálního profilu i kontroly. Oba záznamy byly po ukončení zaseknuté automatizace remuxované; nejsou to sestříhané demonstrace. Poslední zavěšení nastalo při doplňkové diagnostice po funkčních kontrolách a není vykazované jako další chyba produktu.

## Prošlé a omezené scénáře

| Scénář | Výsledek |
| --- | --- |
| Vytvoření názvu nové informační položky v tabulce | Název zadaný; uložení a obsah nedokončené |
| Výchozí prázdný katalog bez propagovaných akcí | Správně ukázal prázdný stav |
| Změna jazyka přes nastavení na Češtinu | Prošlo |
| Katalog tří nadcházejících a jedné archivní akce | Prošlo, archiv byl původně sbalený |
| Hledání formulare bez diakritiky | Našlo dvě akce s Formuláře v názvu |
| Hledání archivní akce | Našlo ji a automaticky rozbalilo archiv |
| Neexistující hledání a Vymazat hledání | Správná hláška, návrat ke kompletnímu katalogu |
| Chybná hluboká URL, pak reload přepsané úvodní URL | Prázdná stránka po fallbacku, reload katalog obnovil; nález 1 |
| Tab od loga přes přihlášení dál | Přeskočilo nastavení; nález 2 |
| Přerušené lokální get_available_occasions | Správná chyba a Zkusit znovu |
| Odstranění přerušení a Zkusit znovu | Prošlo, všechny čtyři karty znovu načtené |
| Mobilní šířka 390 px | Nebylo vodorovné přetékání dokumentu |

Kontrolní důkazy: [načtený katalog](evidence/public-catalogue-qa-2026-10-23/catalogue-loaded.png), [chyba načítání](evidence/public-catalogue-qa-2026-10-23/catalogue-load-error.png), [úspěšné opakování](evidence/public-catalogue-qa-2026-10-23/catalogue-retry-success.png), [mobilní zobrazení](evidence/public-catalogue-qa-2026-10-23/catalogue-mobile.png). [Finální lokální stav](evidence/public-catalogue-qa-2026-10-23/final-state.json) má 0 informačních záznamů, 0 objednávek a 0 zpráv v e-mailové frontě.

## 1. P2 - Neznámá adresa přepíše URL na úvod, ale ponechá prázdnou stránku

Reprodukce:

1. V čistě webovém profilu otevřít platný kořen `/` a ověřit zobrazený katalog.
2. Otevřít neznámou adresu `/qa-neexistujici-stranka`, kterou lokální SPA server obslouží stejným webovým shellem.
3. Po dokončení inicializace zkontrolovat URL i viditelný obsah.

Skutečnost: URL se přepíše na `/`, ale stránka zůstane úplně prázdná. `window.__FESTAPP_APP_READY__` už je true, `#app` má `display:none` a `document.body.innerText` je prázdný. Není zde katalog, vysvětlení ani ovládání pro návrat. Fyzické znovunačtení stejného kořene katalog obnoví.

`RouterService.handleInitialLoad` v čistě webovém režimu pro neznámou cestu zavolá `history.replaceState`, nastaví `_lastPath='/'` a vrátí true. `Main.init` to vyhodnotí jako již vykreslenou routu, označí aplikaci za připravenou a přeskočí vykreslení katalogu i zviditelnění `#app`.

Směr opravy: po změně na úvodní URL skutečně vykreslit katalog, případně zobrazit srozumitelnou stránku Nenalezeno. Ověřit přímé zadání chybné adresy i pokračování bez ručního reloadu.

Rozsah: potvrzeno pro lokální SPA fallback v čistě webovém profilu. Chování produkčního CDN při obsluze neznámé cesty nebylo ověřované; nález není tvrzením, že každý neplatný produkční odkaz nutně končí tímto stavem.

Důkazy: [prázdná stránka po přesměrování](evidence/public-catalogue-qa-2026-10-23/catalogue-unknown-route-blank.png), [DOM stav](evidence/public-catalogue-qa-2026-10-23/unknown-route-state.json), [snapshot bez ovládání](evidence/public-catalogue-qa-2026-10-23/unknown-route.snapshot), [kontrolní reload](evidence/public-catalogue-qa-2026-10-23/catalogue-root-recovery.png).

## 2. P2 - Nastavení a zpětná vazba veřejného webu nejsou dostupné přes Tab

Reprodukce: na katalogu začít na odkazu loga a postupovat klávesou Tab. Zkontrolovat dostupnost ikonky nastavení v hlavičce a plovoucí zpětné vazby.

Skutečnost: po logu se fokus přesune na Přihlásit se a pak rovnou na Pro pořadatele; ikonku nastavení přeskočí. Nastavení je `<i class="material-icons settings-icon-btn">settings</i>`, zpětná vazba je `<div id="fab-button" class="fab-button">…</div>`. Oba prvky mají pouze onclick handler, žádnou roli tlačítka ani popisek a `tabIndex=-1`. V přístupnostním snapshotu jsou to klikatelné generic prvky s názvy settings a chat_bubble, nikoli tlačítka. Pro tyto prvky chybí standardní klávesová cesta otevření.

Jde o samostatný nález vůči dřívějšímu zachování skrytých Flutter záložek v přístupnostním stromu. Zde byl testovaný HTML webový klient. Kompletní průchod čtečkou obrazovky se neprováděl.

Směr opravy: použít skutečné `<button type="button">` se srozumitelnými českými aria-label, zachovat viditelný fokus a ověřit otevření pomocí Enter i mezerníku. Stejně prověřit zavírací ikonku a další ikony tohoto menu.

Důkazy: [DOM obou ovládacích prvků](evidence/public-catalogue-qa-2026-10-23/catalogue-action-semantics.json), [přístupnostní snapshot](evidence/public-catalogue-qa-2026-10-23/catalogue-controls.snapshot), [katalog s ikonami](evidence/public-catalogue-qa-2026-10-23/catalogue-loaded.png).

## Omezení a další postup

Nedokončeno: vytvoření a publikace informačního textu, správa míst a mapových tras. Neověřeno: skutečné odesílání zpětné vazby, přihlášení přes Google, produkční routování CDN, e-maily a platby. Tyto části nejsou vykázané jako úspěšné testy ani jako vady.

Nejbližší opravy z tohoto průchodu: vykreslení obsahu po fallbacku na úvod a standardní klávesové ovládání ikon. [Otisky zdrojů](evidence/public-catalogue-qa-2026-10-23/source-digests.json) identifikují testované soubory. Produktové opravy ani deployment se v tomto vlákně neprováděly.
