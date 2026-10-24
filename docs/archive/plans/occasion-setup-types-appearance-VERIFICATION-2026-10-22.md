# Typy akcí, vzhled a navigace - místní ověření

Implementace dokončena 2026-10-22. Produkce nebyla změněna. Bez commitu a push.

- Tok Název / Termín / Typ / Vzhled, tři typy, podmíněné platby a sál, přímé cíle i mobilní přehled. Progress vyžaduje výslovnou kontrolu; neaktivní konfigurace zůstává v draftu a server ji nevytváří.
- Oprávněné zdroje všech jednotek stejného tenantu, samostatná dostupnost formulářů, automatický název a kompaktní odkaz. Původní revizovaný save a idempotentní finalizace zůstávají jedinou cestou.
- Společné konkrétní barvy/font, Flutter shader, CSS gradient a skutečný PDF axial shading. Náhled nad vlastním draftem s kontrolou revize a dokumentovými limity. Vlastní převzatý design se zachovává do explicitní změny stylu.

## Kontroly

- 25 různých Flutter testů: 19 v závěrečné sadě story/settings/appearance a 6 již úspěšných nezměněných testů shellu. `fvm flutter test --concurrency=1`. Regrese zahrnují kliknutí/klávesnici, velký text, obnovu neaktivního cíle a skutečné public builders nad poli bez databázových ID.
- Cílený `fvm dart analyze --no-fatal-warnings`: bez chyb; zůstává původní warning `FormPage.formLink`/`must_be_immutable` a informační linty.
- 8 SQL souborů: všech 7 `database/tests/occasion_setup/*_test.sql` a `ticket_layout_settings_test.sql`. Práva, tenant, revize preview, idempotence, skryté sekce a neaktivní bankovní trasa bezplatné registrace. Nová migrace prošla skutečným lokálním PostgreSQL.
- 39 Deno testů: 18 ticketLayout + 21 preview-ticket-layout, včetně PDF shading operátorů a autorizovaného draftového preview.
- JS test skutečného veřejného theme/model kontraktu přes pnpm 11.24.0.
- Izolovaný headless browser: nová akce bez předloh, skok s rozepsaným názvem, simulovaný výpadek save a retry, koncert s gradientem, skutečné dokončení, ples se 32 místy, změna typu a návrat, fyzický reload a resume, mobil 390 px a desktop 1440 px. Mobilní spodní akce jsou viditelné, veřejný formulář nepřetéká.
- Skutečný veřejný `FormPage` čte dokončený formulář ze stejné disposable DB. Roboto Slab je načtené podle browser FontFaceSet. PDF je vytvořené přes skutečný Edge endpoint a renderer, bez fontových varování; text s diakritikou se extrahuje přes PDFKit a QR z rastrového PDF se úspěšně dekóduje přes jsQR.

## Hranice a artefakty

Backend: `../festapp-wizard-types-20261022`, vlastní disposable tenant 1, API/DB 56821/56822. Původní `festapp-wizard-local` nebyl resetován. Syntetický účet a banka, žádná reálná platba nebo e-mail. Externí push callbacky jsou stubované lokálním E2E entrypointem. Browser používá sémantické kliky tam, kde Flutter debug DOM nezpracoval CDP pointer; fyzické kliknutí a klávesnici navigace pokrývají widget testy.

Artefakty jsou v `/tmp/festapp-setup-output/`: `gradient-ticket.pdf`, jeho PNG, `appearance.json`, screenshoty veřejného formuláře mobil/desktop a průvodce. Zastaveny jsou pouze vlastní browser session, Flutter/Vite a nový lokální Supabase projekt; data jsou zachována.

Migrace: `supabase/migrations/20261022020000_occasion_setup_types_appearance.sql`. Budoucí produkční aktivace musí dodat čtenáře nového layoutu před zapnutím zápisu gradientu. Žádné nasazení nebylo provedeno ani zadáno. Místní dokončení nemá zbývající blokující bod.
