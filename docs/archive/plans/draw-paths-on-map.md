# Kreslení cest na mapě (místa + volné body)

## Context

Dnes se cesta (path group) v adminu zadává jen ručně — v tabu **Cesty** je textový sloupec „Places", kam se píše CSV **ID míst** ve formátu `1,2,3;5,6` (segmenty oddělené `;`, ID míst uvnitř segmentu `,`). Každé číslo je FK na `places.id`. Mapa (`map_page.dart` + `map_page_helper.dart`) tato ID dohledá na souřadnice a vykreslí polyline.

Uživatel chce cesty umět **nakreslit přímo na mapě**, a to **obojím způsobem**: klikáním na existující místa i vkládáním **volných bodů** kdekoliv na mapě. Klíčový požadavek: volné body **nesmí vznikat jako řádky v tabulce Místa** — jsou to čistě vrcholy cesty.

Řešení: volné body žijí **inline v `path_data`** jako souřadnice (ne jako řádky `places`), takže se v tabu Místa nikdy neobjeví. `path_data` je JSON, takže **žádná DB migrace není potřeba** a staré řádky (jen čísla) fungují dál.

## Datový model (jádro)

Rozšířit JSON `path_groups.path_data` tak, že segment je pole **uzlů**, kde uzel je:
- **číslo** → odkaz na `places.id` (dnešní formát, zpětně kompatibilní), nebo
- **objekt** `{"lat": <num>, "lng": <num>}` → volný bod (inline souřadnice).

Příklad: `[[1, {"lat":49.83,"lng":18.28}, 2], [5,6]]`.

Nová hodnotová třída `PathNode` (v `path_group_model.dart` nebo vlastní soubor `path_node.dart`):
- varianta `PathNode.place(int id)` a `PathNode.point(double lat, double lng)`,
- `factory PathNode.fromJson(dynamic)` (num → place, Map → point),
- `dynamic toJson()` (vrací `int` nebo `{lat,lng}`),
- `int? get placeId`, `LatLng? resolve(List<PlaceModel> places)`.

`PathGroupsModel.pathData` změnit z `List<List<int>>` → `List<List<PathNode>>`.

## Změny po souborech

**`lib/components/map/path_node.dart`** (nový) — třída `PathNode` viz výše.

**`lib/components/map/path_group_model.dart`**
- `pathData` typ → `List<List<PathNode>>?`.
- `fromJson` (ř. 36–40): místo `sub.cast<int>()` mapovat každý prvek přes `PathNode.fromJson`.
- `toJson` (ř. 125): serializovat `pathData` jako `List<List<dynamic>>` přes `node.toJson()`.
- `fromPlutoJson` (ř. 60–67) a `toTrinaRow` (ř. 132–137): textový CSV rozšířit o token pro volný bod — místa jako číslo, volný bod jako `@lat:lng` (dvojtečka, aby nekolidovala s `,`). Parser: prvek začínající `@` → point, jinak `int.parse` → place. Grid tak zůstává funkční jako „advanced" fallback.

**`lib/components/map/map_page_helper.dart`** (`loadGroupPolylines`, ř. 56–64)
- Segment `List<PathNode>` → `List<LatLng>`: pro place-ref dohledat v `placesList` (dnešní `firstWhereOrNull`), pro point použít souřadnice přímo. Zbytek (polyline, trojúhelníky) beze změny.

**`lib/components/map/map_page.dart`**
- Nový vstupní parametr pro kreslicí mód, např. `PathGroupsModel? editPathGroup` (analogicky k `place` + `isOnlyEditMode`). V něm:
  - živá editovaná cesta jako `List<List<PathNode>>` ve stavu; render přes existující `_polylines` vrstvu.
  - **tap na marker existujícího místa** → přidá `PathNode.place(id)` do aktivního segmentu; **tap do prázdné mapy** (`onMapTap`, ř. 572) → přidá `PathNode.point(lat,lng)` a marker/pin pro volný bod.
  - ovládací lišta (obdoba `_buildEditControls`, ř. 1043): Zpět (undo posl. bodu), Nový segment, Storno, Uložit.
  - **Uložit** → `RouterService.goBack(context, <path_data JSON>)` (stejný round-trip jako `saveNewPosition`/`isOnlyEditMode`, ř. 627–634).
- `_onGroupIconTap` (ř. 986–989): `placeIdsInSelectedGroup` plnit jen z place-ref uzlů (`node.placeId`), volné body přeskočit.

**`lib/components/map/path_groups_content.dart`**
- Do gridu přidat sloupec s tlačítkem **„Kreslit na mapě"** (vzor: sloupec „Location on map" v `places_content.dart:118–154` — `RouterService.navigatePageInfo(context, MapRoute(editPathGroup: pm))`, návratovou hodnotu zapsat do buňky `path_data`/`Tb.places.table` přes `changeCellValue`). Textový CSV sloupec ponechat jako fallback.

**`lib/router_service.dart` / AutoRoute** — přidat parametr do `MapRoute` a přegenerovat (`fvm dart run build_runner build --delete-conflicting-outputs`).

**Uložení do DB** — beze změny cesty: `DbPlaces.updatePathGroup` (`db_places.dart:129–166`) zapisuje `path_data` jako JSON. Nová struktura projde bez migrace.

## Splnění požadavku „volné body nejsou v tabu Místa"

Volné body jsou pouze souřadnice v `path_data`, **nevytváří se řádek v `places`**. Tab Místa (`places_content.dart`) načítá jen tabulku `places`, takže volné body se tam z principu neobjeví. Žádné filtrování není potřeba.

## Ověření (end-to-end)

1. `fvm dart run build_runner build --delete-conflicting-outputs` (kvůli MapRoute).
2. `fvm flutter run -d chrome`, admin → Místa → tab Cesty → u řádku „Kreslit na mapě".
3. Nakreslit cestu kombinací kliků na místa i do prázdna; Uložit; ověřit polyline na uživatelské mapě a že se volné body neobjevily v tabu Místa.
4. Otevřít starou cestu zadanou přes CSV čísel — musí se vykreslit i editovat beze změny (zpětná kompatibilita).
5. Unit test round-tripu `PathNode`/`PathGroupsModel` (smíšené uzly: `fromJson`→`toJson`, `fromPlutoJson`→`toTrinaRow`) v `test/components/map/`.
