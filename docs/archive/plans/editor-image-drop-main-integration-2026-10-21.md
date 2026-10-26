# Přenos editor image drop na canonical main - 2026-10-21

Původní implementační plán z 2026-10-20 byl ověřen proti rozpracovanému workspace. Před publikací kontrola `origin/main` na `1c8b5a219` zjistila, že Blueprint již přešel na `BlueprintPlanEditor` a `BlueprintLayoutHost` s verzovaným dokumentem. Původní `BlueprintControlsBar` a ukládání `backgroundSvg` byly odstraněny. Tyto cesty se nesmějí obnovit.

Existující main již nabízí picker a vnořený DropFile v importním dialogu Blueprintu; nemá však externí file drop přes tělo žádného editoru. Sdílený `EditorFileDropRegion` se přidává pouze k chybějícímu chování. Blueprint picker a drop vedou přes společný `_importSelection` a stejný busy zámek. Drop mění jediný podklad, nepřidává samostatnou grafiku.

Aktuální Worker a `DbImages.uploadImageWithResult` již podporují SVG pro profil `blueprint-background` s validací a konverzí na PNG. Blueprint proto použije tento aktuální kontrakt také pro SVG podklad. Původní lokální inline SVG cesta se nepřenáší. Vstupenka zůstává pouze rastrová. Demo bez occasion/unit scope nepovolí remote upload. Formátový seznam Blueprintu odpovídá již podporovanému profilu (PNG/JPG/JPEG/WebP/GIF/SVG); kontrola bajtů a velikosti před čtením zůstává autoritou.

Přenos zachovává novější keyboard handling vstupenky a současné geometrické editory; nevnáší staré zdrojové soubory, testy ani nesouvisející workspace změny. Ověření: cílené existující sady, nové channel testy obalu, testy importu aktuálního Blueprint editoru, cílený analyzer. Původní webový smoke patří původnímu workspace a není vydáván za nový smoke tohoto přenosu. Tento krok neprovádí release ani produkční upload.

## Výsledek kontrol před publikací

- Výše uvedených pět cílených sad: `fvm flutter test --no-pub --concurrency=1 test/components/shared/editor_file_drop_region_test.dart test/components/ticket_layout/ticket_layout_cases.dart test/components/blueprint/blueprint_background_picker_cases.dart test/components/blueprint/blueprint_image_upload_cases.dart test/components/blueprint/blueprint_editor_file_drop_test.dart`: **118/118 prošlo**. Aktuální main již nemá původní tři chyby palet.
- Cílený `fvm dart analyze` změněných Dart souborů: bez chyb a varování, pouze informační linty existujícího kódu. `git diff --check` prošel.
- Autoritativní main byl před publikací znovu načten a odpovídal základně `1c8b5a219cd9d766ad91060ca6ccb4ebf55bc5ca`. Změna vznikla v čistém odděleném worktree; silně rozpracovaný původní workspace zůstal nedotčený.
