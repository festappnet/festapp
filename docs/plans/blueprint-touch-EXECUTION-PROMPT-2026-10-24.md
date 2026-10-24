# Implementace dotykového ovládání blueprintu

Pracuj v `/Users/miakh/source/festapp` a `/Users/miakh/source/venue_seat_picker`.
Přečti pravidla obou repozitářů a celý autoritativní plán:
`docs/plans/blueprint-touch-plan-2026-10-24.md`.

Implementuj pan z celého viewportu a jednotný tap přesah 8 logických px pro
všechny vybíratelné objekty; rezervace zachová dosavadní interaktivní cíle.
Platí Flutter web i native, gridový i objektový host.

Začni soubory a symboly v plánu. Reprodukci spoj s regresí, pak proveď souvislou
opravu a jeden cílený validační průchod, verification standard. Zachovej cizí
změny. Žádný nový architektonický průzkum, audit, subagenti, framework gest,
migrace modelu nebo oprava wrapperu bez důkazu. Změněný předpoklad oprav v plánu.

Jeden core resolver: přímý zásah má přednost, jinak nejbližší skutečný obrys
v toleranci; respektovat transformace, blokující cíle a mapování skupin.
Grid má odpovídající adaptér nad sloty. `_hitAt` dnes volají i `_selectDown`
a `_dragStart`: toleranci připoj jen k dokončenému tapu, zachovej přesnou cestu
pro down/drag/úchyty a zkontroluj `_selectionBeforeDown` včetně Shift výběru.
Žádné duplicitní pointer tap callbacky; sémantické akce zachovat.

Hotovo lokálně: cílené regrese prokážou pan, tap toleranci, zachování editace,
mouse marquee, pinch/cancel a jeden callback. Použij kontroly z plánu,
jeden Flutter proces, `--concurrency=1`; neopakuj nezměněné úspěšné kontroly.

Bez dalšího zadání necommituj, nepushuj, nenasazuj a neměň databázi.
Pin obou balíčků na stejné dostupné SHA a ověření bez override jsou integrační
gate po autorizované publikaci knihovny; do té doby je označ jako čekající.
Nevymýšlej revizi ani neodstraňuj uživatelův override. Bez placeholderů a nových
kompatibilních cest. Závěrem stručně: změněné chování, kontroly, neověřené body
a stav lokální opravy / publikace / pinu / nasazení.
