# To-do: odstranit původní cesty integrace Make při canonical cutoveru

Založeno: 2026-11-13
Stav: odloženo do schválení integrace Make a komplexnějšího canonical cutoveru

- [ ] Po schválení Make zahrnout do komplexnějšího canonical cutoveru migraci
  integrace na zvolenou kanonickou cestu a odstranění původních rout.
- [ ] Předem určit přesný seznam původních rout, aliasů a jejich konzumentů.
  Výchozím bodem je aktuální connection definice v
  [integrations/make/src/connection.json](../../../../integrations/make/src/connection.json)
  a transport v
  [tools/festapp/src/remote/make-transport.mjs](../../../../tools/festapp/src/remote/make-transport.mjs).
- [ ] Převést Make connection a moduly, ověřit existující scénáře a teprve po
  potvrzení funkční náhrady odstranit starou cestu včetně zbylých odkazů a testů.

Tento záznam odkládá odstranění starých cest. Neoznačuje současné routy za
nepoužívané a nespouští jejich migraci ani odstranění během probíhajícího review.
