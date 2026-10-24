# Lokální realizace landing page - 2026-10-22

Rozsah: zadání `../vstupenky-landing-EXECUTION-PROMPT-2026-10-22.md` a autoritativní plán R2, následné kompoziční iterace R3/R4. Pouze lokální implementace pro `vstupenky.online`; bez deploye, commitu, pushe a produkčních mutací. Konečné výsledky mediální kritiky a browser kontrol vlastní místní galerie.

## Výchozí stav a source/live odchylka

- Výchozí i průběžně potvrzený HEAD `eb2304724`, checkout `feat/occasion-setup-wizard-20261007`. Rozsáhlé původní rozpracované změny byly zachovány; tento úkol nevytváří čistý release checkout ani novou produkční revizi.
- Živý marketing na `https://vstupenky.online/pro-poradatele` byl obsahově bohatší než původní zdrojová šablona. Obsahoval rezervaci 30minutové online ukázky přes Google Meet, která ve šabloně chyběla. Realizace zachovává skutečný kontakt a veřejnou rezervaci `https://cal.com/michael-bujnovsky-5srszz/ukazka`.
- Zdrojová tenant konfigurace používá `APP_NAME=vstupenky.online`, avšak její stávající sdílený SVG asset zobrazuje Festapp. Landing používá textovou značku odvozenou z `APP_NAME`; globální logo a ostatní tenanty tento úkol nemění.
- Tento záznam neprokazuje nasazení místních změn na živý web. Starý veřejný formulář Sportovního plesu 2026 je archivní, aktuálně nenabízí rezervaci.

## Vlastnictví a URL kontrakt

- Marketingový obsah, kompozice a vlastní klipy zůstávají v existujícím generátoru `automation/release/render_organizer_page.mjs` a adresáři `automation/release/organizers/`.
- `/` je marketing, `/events` existující katalog, `/pro-poradatele` přesměrování na `/`. CTA používá `/events?create=1`, správa `/admin`; zachovány jsou staré root create/hash vstupy a scanner/auth response policy. Jiní tenanté nemají automaticky přesměrovaný katalog.
- Katalog se znovu používá, nevzniká druhý seznam událostí. Root nemá druhou marketingovou implementaci mimo generátor.
- Samostatná videa řídí sdílený přehrávač podle viditelnosti; kontroluje ruční pauzu, dokončení, opakované přehrání a omezený pohyb. Videa jsou vyloučena z PWA precache. Není přidána browser analytika.

## Pravdivost médií a referencí

- Plánek pochází ze skutečného samostatného editoru s předáním téhož dokumentu do JS pickeru. Jeho syntetické ceny a editorové demo nejsou důkazem produkční rezervace nebo platby. Masters, capture takes a konkurenční referenční média zůstávají mimo Git.
- Formulář a design vstupenky byly zachyceny v reálné lokální administraci nad kopií syntetického plesu. QR kontrola a objednávky používají izolovaná testovací data, bez hostů z produkce.
- Katalog referencí obsahuje čtyři skutečné plesy. Případový blok Sportovního plesu Větřkovice používá skutečný plakát a doložené údaje; žádné vymyšlené konverze, počty prodejů ani citace.
- Veřejný zdroj této akce: <https://www.vetrkovice.cz/aktualne/kalendar-akci/sportovni-ples-564_171cs.html>. Plakát <https://www.vetrkovice.cz/evt_image.php?img=3074>. Datum 13. 2. 2026, KD Větřkovice, TJ Dubina. Hodina nebyla použita kvůli rozporu textu obce s plakátem.
- Přesná formulace exportu rozlišuje objednávky od CSV exportu vstupenek; video dokládá skutečný export 260 syntetických vstupenek.

## Lokální Edge runtime pro náhled vstupenky

Disposable Supabase projekt: `/Users/miakh/festapp-landing-local-e2e-20261022`, API `http://127.0.0.1:56831`. Byl zkopírován kompletní strom Functions. Skutečný editor nejprve dostával HTTP 400; dočasný lokální diagnostický log potvrdil chybějící zabalený obrázek `ticket-assets/backgrounds/concert-stub-v3.png`. Fonty se načítaly správně.

Do disposable konfigurace přibylo balení obou typů prostředků:

```toml
[functions.preview-ticket-layout]
static_files = ["./functions/_shared/ticket-assets/*.ttf", "./functions/_shared/ticket-assets/backgrounds/*"]
```

Po restartu lokálního `supabase functions serve preview-ticket-layout` se skutečný editor vykreslil včetně plátna, prvků, barev, fontů, galerie a náhledu PDF. Repository Functions kód ani autorizační pravidla nebyly kvůli tomuto problému změněny. Nešlo o produkční opravu. Konečný stav úklidu procesů má zaznamenat vlastník zachytávání.

## Ověření a jeho hranice

- Routing/build/PWA důkazy: `routing-validation.json`, včetně skutečného browser offline upgradu z katalogového rootu na marketingový root a zachování `/events`.
- Cílený test generátoru po opravě značky a CTA: `node --test --test-reporter=dot automation/tests/organizer_page.test.mjs`, 2/2 prošly.
- Pilot prošel nezávislou kritikou po opravách pracovních výřezů, ovládání a mobilní čitelnosti. Finální celostránkové screenshoty, scroll záznamy, všech osm klipů, jejich stavy a konkrétní opravy jsou v [místní galerii](/Users/miakh/Downloads/festapp-landing-review-2026-10-22/index.html).
- Automatická přístupnost, lokální performance nebo subjektivní srovnání nejsou důkazem konverze ani živého nasazení. Password login v disposable projektu neprokazuje produkční Google OAuth.
- Audit porušení browser izolace je v [lokálním auditním záznamu](/Users/miakh/Downloads/festapp-landing-review-2026-10-22/browser-isolation-audit.md). Několik příkazů bez explicitního configu připojilo Panerelay a přečetlo metadata/accessibility snapshot osobního prohlížeče. Po přepnutí trace neobsahuje navigaci, klikání, vyplňování ani zápis. Session přestala být používána; náhradní zachytávání vynucuje explicitní config, headless a vlastní namespace při každém příkazu.

## Konečné cílené ověření a úklid

- `node --test tests/components/landing_demo_player.test.js`: 3/3 PASS (lazy source, single active, pause/replay/variants, reduced motion/Save-Data, error/retry/hidden).
- `node --test automation/tests/organizer_page.test.mjs automation/tests/public_seo.test.mjs`: 14/14 PASS po finální kompozici.
- `pnpm --dir web_client run build`, pnpm 11.24.0: PASS; poslední build po aktualizaci celého manifestu. Původní routing/PWA/scanner/auth checks a skutečný upgrade/offline průchod jsou v `routing-validation.json`.
- Všech 8 samostatných klipů má desktop i mobilní variantu a poster. Všech 16 MP4 prošlo úplným dekódováním; 3 243 618 bajtů dohromady. Přesné délky, rozměry a SHA256 jsou v `media-validation.json`.
- Nezávislá kritika prošla celé přehrání, opravila výchozí/výsledný vzhled formuláře, export vstupenek, zakrytý checkbox Povinné a drobné mobilní ovládání vstupenky. Poslední mediální opravy mají PASS.
- Finální browser kontrola: 320/390/768/1440 bez vodorovného přetečení, axe 0 porušení. Celé scroll záznamy a detailní stav kritérií jsou v místní galerii. Lokální teplé file:// vitals nejsou tvrzením o produkčním výkonu.
- Vlastní capture browser a pilot session zavřeny; Flutter web-server ukončen `q`, Vite56843 ukončen, package demo57598 zastaven svým run.py, disposable Supabase zastaven (data ponechána pro reprodukci). Root zastavil pouze vlastní Edge Functions runtime a odstranil dočasný diagnostický log. Cizí Flutter/browser procesy nebyly ukončeny.
- Žádný commit, push, deploy ani produkční mutace. Dalším samostatně autorizovaným krokem může být tenant release, nikoli součást této realizace.

Finální nezávislá galerie uzavřena: vizuální a mediální brána PASS, všech 8
klipů + 8 mobilních variant, všechny odkazy platné. Desktop/mobile scroll
potvrdil nejvýše jedno přehrávané video; reduced-motion skutečně aktivní a
žádné automatické přehrávání. Vlastní browser sessions kritika zavřeny.
Přímý lokální náhled: `~/Downloads/festapp-landing-review-2026-10-22/landing.html`;
galerie a kritéria: `index.html` a `index.md` ve stejné složce.
