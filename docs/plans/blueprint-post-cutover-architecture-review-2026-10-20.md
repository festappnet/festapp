# Post-cutover architecture review and execution

The original local cutover acceptance completed first, at the timestamp in
`evidence/blueprint-typography-20261020/full-app-journey.json`, revision7.
No production rollout is part of this review.

The canonical ownership is sound: document2 keeps editable source and typed
physical/style intent; immutable whole-text resources and portable vector
commands supply both renderers. Setup and occasion editing share one component.
Commercial commands, authorization and revisioned saves remain in the host.
A future MCP should call these existing commands/importers and schema, and use
the same prepared-resource/save boundary. It should not author an independent
scene format or renderer. Rectangles, furniture and tables already compile
through the same core scene; persisting another scene authority is unnecessary.

## Concrete remaining weakness

`BlueprintTextPreparation.prepare` checks supersession after `prepareSnapshot`
finishes every batch. A replaced draft therefore continues dispatching obsolete
batches, even though its final result is correctly discarded. Large font/style
changes can consume backend time and delay newer preparation unnecessarily.
The save path deliberately owns a captured snapshot and must continue preparing
that snapshot when visible editing changes. Cancellation must distinguish those
intentions inside the preparation owner.

## Implementation plan

1. Share a private preparation implementation with an optional liveness check.
2. UI preparation checks liveness before work, before each batch and after each
   awaited response. Supersession stops queued work and returns Superseded.
3. Captured-save preparation calls the same implementation without a liveness
   predicate. It continues all batches despite cancellation of UI preparation.
4. Verify a33-paragraph/two-batch case: superseded UI dispatches only one batch;
   a captured save still dispatches both and returns every prepared paragraph.
   Retain existing descriptor, stale-response and save/history tests.

No protocol, persisted source, request identity, renderer or font-engine change
is needed. The known maximum20000-seat SVG frame-time limit remains measured
(133.4ms p95 in this headless environment); normal5000-seat p95 is16.8ms with no
frames over20ms. This bounded fix addresses obsolete preparation work, rather
than adding another rendering/cache authority.

Status: executed. Five owning tests passed, including both33-paragraph cases.
Targeted analysis: no errors or warnings; nonfatal style infos retained.
The final local application build and source hashes are recorded in the ledger.

## Následné dotažení podle aktuální kontroly

Datum: 2026-10-20. Stav: obě následující vlny lokálně realizované a ověřené.
Verification: standard - souběh async operací a zachování textového vstupu.
Předchozí sekce zaznamenávají již dokončené zastavování dávek. Následující
sekce jsou jediným plánem zbývajících oprav; hotovou práci neopakovat.
Původní plánovací session neměnila implementaci a nespouštěla nové testy.
Výsledky následné realizace jsou zaznamenané na konci tohoto dokumentu.

### Autorita, scope a výchozí stav

Zachovat produktový kontrakt z
[canonical rendering plánu](blueprint-canonical-rendering-fonts-plan-2026-10-20.md).
Jeho aktuální upřesnění výslovně požaduje nativní text při editaci; kanonické
vektory vznikají pro save/prohlížení. Rozdíl průběžného náhledu není automaticky
regrese a návrat k přípravě vektorů při každém resize není cílem.

Host: `/Users/miakh/source/festapp-blueprint-cutover-release-20261019`,
HEAD při průzkumu `a3a0637d8` plus rozsáhlý dirty diff. Před editací zaznamenat
scoped diff a navázat bez reset/clean. Skutečné závislosti v pubspec/lock:
`vendor/blueprint/venue_seat_picker` 0.3.0 a `venue_layout_core` 0.2.0;
nepracovat proti starému absolutnímu sibling override.

Cíl: pozdní načítání nezahodí nové zdroje; přechod do prohlížení vždy zachytí
dokončený text a buď zobrazí připravenou scénu, nebo zachová editaci s retry.
Bez SQL/protocol/font-engine změn, dalšího dělení obchodního panelu a frameworku.
Bez deploye, produkční migrace, publikace, commitu a pushe.

### Co je potvrzené a co zbývá

| Aktuální evidence | Důsledek |
| --- | --- |
| `BlueprintTextPreparation._prepareSnapshot` kontroluje liveness před/po dávce; existují testy zrušeného UI a dokončeného captured save | Hotovo, zachovat. |
| `BlueprintPlanEditor` sdílí setup i existující událost | Rozdělení editoru se zlepšilo; mechanický refaktor velkých souborů není nutný. |
| `_setScreenMode` nově připravuje chybějící vektory | Základ je hotový, ale kontrola scény probíhá před dokončením IME/focus; dokončení vstupu je jen v přípravné větvi. |
| `_loadAssets` a `_uploadBitmap` čtou resources před await a potom nahrazují celou mapu | Mohou přepsat mezitím doplněné fonty/obrázky. Platnost session není dostatečně hlídána pouhým mounted. |
| `_run` pouze zpracovává chyby, nezamyká přechod | Opakovaný přechod může vytvořit souběžnou přípravu; vyžaduje vlastní jednu Future. |

Jde o zdrojově doložená rizika, ne nově reprodukované produkční incidenty.
Konkrétní ztrátu textu musí potvrdit nebo vyloučit řízený widget test.

### Vlna 1: bezpečný commit zdrojů

Owner transientních resources zůstává `VenueLayoutController`. V hostovém
`blueprint_layout_resources.dart` přidat malý helper pro commit ověřených image
příspěvků do nejnovější mapy. Nepřidávat obecný resource manager ani package API.

- `views/blueprint_layout_host.dart:_loadAssets`: zachytit controller a manifesty
  před await. Před zápisem ověřit session; sloučit pouze obrazy, jejichž původní
  manifest stále odpovídá aktuálnímu. Neobnovit smazaný/vyměněný asset.
- `views/blueprint_layout_background.dart:_uploadBitmap`: commit nového manifestu
  a dekódovaného obrázku sloučit s aktuálními zdroji. Zrušený upload nesmí vložit
  uzel. Zachovat hash/rozměry/MIME/byte-length validaci i vlastnictví ui.Image.
- Jedním scoped rg projít ostatní `assets.resolve`/`setResources` callery:
  `seat_reservation/widgets/seat_reservation_widget.dart`,
  `views/blueprint_layout_demo.dart`, setup dialog a
  `lib/components/occasion/setup/occasion_setup_page.dart`. Snapshot-only návraty
  bez zápisu do živého controlleru ponechat; skutečné read/await/replace převést.
- Příprava textu pro živé prohlížení nebo dokončený save smí aplikovat jen svůj
  příspěvek a musí zachovat aktuální images/assets. Frozen save payload se nemění.

Testy rozšířit v existujících `blueprint_layout_assets_cases.dart`,
`blueprint_image_upload_cases.dart`, případně `blueprint_layout_ui_cases.dart`.
Pozdržet response, mezitím doplnit font/asset, dokončit response a ověřit zachování
obojího přes skutečného callera. Přidat výměnu/smazání manifestu, reload/dispose,
chybu a retry. Resource update nesmí přidat dirty/undo checkpoint.

Exit: žádný scoped async image caller nevrací do controlleru celou starou mapu;
late response neovlivní novou session a zachová nejnovější zdroje.

### Vlna 2: jediný dokončený přechod do prohlížení

Upravit `_setScreenMode` / `_applyScreenMode` v `blueprint_layout_host.dart`:
vždy dokončit `finishBlueprintTextEditing` a frame, potom zachytit session a
dokument, validovat placement/dependencies, případně připravit text, pod guardem
commitnout příspěvek zdrojů z vlny 1 a teprve potom přepnout režim.

Jeden přechod má jednu Future a pending stav zapojený do `_busy`. Dvojklik nesmí
spustit další dávky. Změna dokumentu/reload/dispose zneplatní výsledek; chyba
zachová draft, editaci a retry. Pending uklidit ve finally pro příslušnou session.
Použít existující text preparation, ne druhý shaper/cache. Zachovat revizi,
command ID, frozen retry a nezrušitelnou přípravu captured save.

Widget regrese v `blueprint_layout_ui_cases.dart`: rozepsaný text/IME při odchodu
včetně větve, kde původní scéna zatím nemá issues; dvojklik s pozdrženým
transportem; změna dokumentu/reload/dispose; chyba/retry. Prohlížení obsahuje
poslední dokončený text a nemá dependency issues. Zachovat existující důkaz, že
editování a resize neposílá layout-text, příprava patří save/prohlížení.

Exit: jeden přechod na záměr, po chybě funkční editor, žádný stale commit.

### Rozdělení práce a rychlost

Při realizaci UI/widget změny, pending/retry ovládání a widget regrese delegovat
subagentovi `model: gpt-6-astra`, `reasoning_effort: medium`, `fork_turns: none`.
Předat tento plán a přesné soubory. Povinně načte
`/Users/miakh/.codex/skills/ui-ux-pro-max/SKILL.md`. Browser pouze podle potřeby,
přes agent-browser v izolované headless session; žádný redesign.
Nedostupnost Astry oznámit a UI potichu nepřidělit jinému modelu.

Primární agent vlastní resource helper a jeho testy. Astra vlastní widgety,
background caller a jejich testy. Helper kontrakt dohodnout předem; jeden
editující vlastník na soubor. Neprovádět další agentní audit ani další průzkum
celé architektury. Práci sloučit do jednoho coherent diffu před validací.

Vendor se pro hostovou opravu nemění, nevyrábět archivy ani Flutter build.
Pokud konkrétní důkaz vyžaduje veřejnou změnu balíčku, nejdřív aktualizovat tento
plán a jeho brány. Skutečně vyvrácený nález odstranit s evidencí, neimplementovat
pro jistotu nepotřebný helper. Žádný slib přesného času bez měření.

### Validace, odstranění a hotovo

Při plánování žádné testy. Při realizaci nejdřív ověřit běžící Flutter procesy;
nepřerušovat cizí úlohu. Jeden Flutter task, testy vždy concurrency 1.
Po obou vlnách jeden targeted `fvm dart analyze` změněných produkčních/testovacích
Dart souborů a jeden owning session batch:

```sh
fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart --plain-name 'blueprint_'
```

Ověřit, že filtr skutečně vybral text/assets/upload/UI/setup suites. Neopakovat
celý dokončený cutover ani testy po každé editaci. Browser/build přidat jen pro
konkrétní změněné chování, které owning test neumí doložit. Syntetický widget
vstup není úplný důkaz skutečného platformního IME; mez uvést v handoffu.

Odstranit nahrazené async read/await/replace a duplicitní přechodové větve.
Zachovat synchronní settery, nativní preview, captured-save cestu, SQL a hotové
batch cancellation. Žádné nové aliasy, fallbacky nebo placeholdery.

Hotovo: oba exity, passing targeted batch, přesný rozsah změn/checků doplněný
do existujícího ledgeru bez přepisování historické evidence. Dřívější výsledky
QA nejsou passing check nového diffu. Známý výkonový limit 20 000 míst zůstává
mimo tento rychlý úkol. Produkční/distribuční akce vyžadují samostatné zadání.

### Výsledek realizace

Obě exit podmínky splněny. `commitBlueprintImages` přidává pouze obrazy se
stále aktuálním manifestem; upload přidává nový manifest s obrazem atomicky a
odmítá konflikt. `commitBlueprintTextResources` slučuje pouze fontFamilies,
textLayouts a numberSymbols, zachová aktuální assets/images. Opravené callery:
host `_loadAssets`, host save a přechod do prohlížení, background `_uploadBitmap`
a setup/demo save. Seat picker `_load` i `occasion_setup_page.prepare` vracejí
samostatné snapshoty, nepřepisují živý controller; změnu nepotřebovaly.

Host přechod má jednu Future v busy stavu. Vždy dokončí composing/focus a frame
před zachycením dokumentu; změna dokumentu/session nebo dispose zneplatní
přípravu. Chyba zachová editaci a retry. Před přepnutím se kontrolují scene
issues. Odstraněny async read/await/replace zápisy a předčasná větev kontroly
scény před dokončením vstupu. Captured save zůstává nezrušitelný přes
prepareSnapshot; frozen payload není sloučen s live mapou. Vendor/SQL/protokol
a již hotová batch cancellation se neměnily.

První předepsaný batch odhalil 15 selhání fixtures/UI očekávání. Opraveny:
neplatný klíč assetu `other` místo image:hash, chybějící nativní font pro textový
vstup, čekání na dekódování a zastaralé očekávání toolbaru místo již existující
levé knihovny/horizontálního scrollu. Funkční assertions zůstaly zachované.

Aktuální passing evidence: 80 testů v osmi suites - assets 12, text 5, host 17,
UI 19, upload 6, background picker 5, form defaults 13 a setup 3. Po opravách
byly zopakovány dotčené UI/upload suites; ostatní passing vstupy se nezměnily.
Celý batch po opravách fixtures znovu spuštěn nebyl. Targeted analyzer osmi
Dart souborů: exit 0, žádné errors/warnings, 33 style infos; finální analyzer
upravených UI/upload testů: exit 0, dvě style infos.

Přesné běhy a zdrojové SHA256:
[lifecycle receipt](evidence/blueprint-typography-20261020/lifecycle-followup-20261020.json).
Syntetický composing vstup není úplný důkaz platformního IME. Bez buildu,
browseru, produkčních změn, deploye, commitu a pushe. Původní dirty diff zachován.
