# Integrace embedu na main

Změna přenesená izolovaně z původního rozpracovaného checkoutu na aktuální
`origin/main` 48d8b6db0479818b556e3852c7ea50ead4035d11.
Původní pracovní strom zůstává beze změny; součástí integrace nejsou jeho další
rozpracované změny ani návrat novějších úprav mainu.

Zachované novější chování: kanonické zákaznické `/order` query odkazy, odmítnutí
starých osobních fragmentů, waitlist rekapitulace a demo režim, aktuální
navigace a štítky polí, hlavička veřejného katalogu, ochrana zavírání plánku.
Embed se přenáší z formuláře do kanonického `/order` jako `embed=1`, bez nové
čtečky capability nebo kompatibilní cesty. Admin preview nabídky je v embedu
odmítnuté. Tracker historie se aktualizuje při přechodu do přehledu, aby zavření
výsledku nezpůsobilo navigaci původní cestou.

Ověření finálního portu:

- `npm test --prefix web_client`: 513 testů, 488 pass, 25 skip, 0 fail.
  Zahrnuje varianty úspěšného i neúspěšného načtení waitlist přehledu s embeddem
  i bez něj; registrace se při návratu neopakuje.
- `npm run build --prefix web_client`: pass, veřejný `dist/embed.js` přítomný.
- `npm run test:form-access-browser --prefix web_client`: všech 7 Chromium
  scénářů pass (guest/editor/unit editor, otevřený/uzavřený formulář a běžné
  přihlášení z katalogu). Backend tohoto regresního browser gate je fixture.
- `fvm flutter test test/components/forms/public_link_settings_cases.dart --concurrency=1`:
  3 pass na aktuálním mainu.
- Cílený `fvm dart analyze`: bez chyb a varování, dvě existující info diagnostiky
  (typeHere_informal a nepotřebný foundation import ve stávajícím testu).

Aktuální main postrádal deklaraci `fake-indexeddb`, přestože ji tři scanner
sady importují. Doplněna pouze dev závislost a lockfile. VM startup fixture
zároveň dostala stuby importovaných kontextových/scanner funkcí; běžné
organizer a catalogue scénáře zůstaly zachované.

Původní skutečný cross-site nákup, QR, seat locking a ztracená odpověď jsou
zaznamenané ve [verification.md](verification.md). Celá backendová browser
matice nebyla při portu opakována; aktuální port má výše uvedené Node,
Flutter a browser regresní kontroly. Omezení Safari/iOS a storage přes reload
zůstávají v platnosti. Tato integrace neprovádí produkční nasazení.
