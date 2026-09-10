# Execution prompt: Místa + úklid — architektonický úklid

Implementuj plán `docs/archive/plans/2026-07-11_mista_uklid_architektura_plan.md`.
Jde o opravu bugu + konsolidaci, **žádnou novou funkčnost**:

1. **Bug:** přesun místa group-adminem tiše selhává (klient to dovoluje,
   RLS na `places` pouští jen editory) → nová SECURITY DEFINER RPC
   `save_place_location` + přepnutí `DbPlaces.saveLocation` na ni + DB test.
2. DDL `place_types` z recovery skriptu do `tables.sql` + policies (jen git).
3. Null-safe souřadnice: `PlaceModel.hasCoordinates` + filtr před
   `MapPlaceModel.fromPlaceModel`.
4. Mechanické rozdělení `cleaning_page.dart` (8 tříd do `widgets/`/`models/`,
   tabulka cílových souborů je v plánu, fáze 4) — **nula změn chování**.
5. SQL drobnosti: `organization` z `occasions` místo `COALESCE(...,1)`
   v `report_cleaning_issue`, feature-gate stránky Úklid v UI, „keep in sync"
   komentáře. 6. i18n (cs+en + kopie do `web_client`).

Nejdřív si přečti: `docs/architecture/ai_context.md`, **celý plán** a jednu
funkci z `database/functions/cleaning/` jako vzor stylu SQL.

Závazné:
- Postupuj po fázích 1→7 přesně podle plánu; rozhodnutí ✅ jsou daná, neptej se.
- Nic „navíc nevylepšuj" — sekce „Mimo rozsah" v plánu je zákaz, ne nápad.
- Na větvi může být rozpracovaná cizí práce — commituj **jen své soubory**.
- Každá SECURITY DEFINER funkce: `SET search_path = public, extensions`,
  explicitní permission check, envelope `{code,message,data}`, GRANT dle vzoru.
- Testy: nový `database/tests/places/save_place_location_test.sql` (vzor
  `database/tests/cleaning/cleaning_test.sql`, scénáře a-e viz plán fáze 1.6);
  `./automation/test_all.sh` zelené (2 baseline failury mimo místa/úklid známé).
- Vždy `fvm`; běh přes `fvm flutter run -d web-server --web-port 8080`
  (nikdy `-d chrome`).
- Po fázích 1-6 **zastav a nech uživatele zkontrolovat localhost:8080**
  (mapa: přesun místa; stránka Úklid; grid Míst). Nasazení (fáze 7 — SQL na
  live před klientem, VERSION bump, `deploy_direct.sh`, žádný `git push`,
  anglická commit message) proveď až po jeho odsouhlasení.
