# Kick-off prompt (spustit v Claude Code v repu festapp)

Implementuj refaktor „Přednášející jako core + Poradny jako featura“ podle
schváleného plánu docs/archive/plans/2026-07-10_speakers_core_counseling_feature_plan.md.

NEJDŘÍV SI PŘEČTI (v tomto pořadí, celé):
1. docs/archive/plans/2026-07-10_speakers_core_counseling_feature_plan.md — jediný
   zdroj pravdy; rozhodnutí R1–R8 v sekci 2 jsou závazná, znovu je neotvírej.
   Sekce 3 je přesná mapa dotčených míst, sekce 4 kompletní seznam testů.
2. docs/architecture/ai_context.md + CLAUDE.md (kritická pravidla, split-brain).
3. Kontext hotové feature: docs/archive/plans/2026-07-09_speakers_counseling_plan.md
   (feature je živá jako 0.19.48+298 — měníš gating a UX, ne rezervační logiku).
4. Kód, který budeš měnit: lib/components/features/{speakers_feature,
   feature_service,feature_constants,feature.dart,feature_metadata}.dart,
   lib/components/speakers/admin/*, lib/components/schedule/{event_edit_page,
   event_page}.dart, lib/components/search/db_search.dart,
   lib/data_services/synchro_service.dart, database/functions/speakers/*,
   database/functions/events/sign_user_to_event.sql,
   database/functions/others/search_occasion_content.sql.

PRACUJ TAKTO:
- Pracuj na větvi prod/csmostrava2026 (aktuální produkční větev; žádný nový
  branch, výsledkem je JEDEN verzovaný commit dle R8).
- POZOR — stav pracovního stromu (k 2026-07-10): fáze 1 (SQL) je už zčásti
  rozpracovaná a JE součástí tohoto refaktoru: změněné
  database/functions/{events/sign_user_to_event.sql,
  others/search_occasion_content.sql, speakers/create_counseling_slots.sql,
  speakers/get_counseling_availability.sql}, smazaný
  speakers/get_is_speakers_enabled_on_occasion.sql a nový
  speakers/get_is_counseling_enabled_on_occasion.sql. NEzahazuj je —
  zkontroluj je proti R2/R3 a navaž (dodělej migraci a testy).
- Ostatní necommitnuté změny (mj. lib/components/schedule/event_page.dart,
  lib/router_service.dart, database/functions/others/get_app_config.sql,
  database/recovery/*, database/tests/eshop/*,
  database/tests/event_feedback_gate_test.sql, automation/deploy_direct.sh)
  jsou CIZÍ rozdělaná práce — commituj VÝHRADNĚ své soubory podle explicitní
  cesty, nikdy `git add -A`; cizí změny nech být a nezahrnuj je do commitu.
  (Výjimka: pokud si fáze 1 vyžádá update database/recovery/* kvůli novým
  zněním funkcí, uprav a commitni jen dotčené hunky vědomě.)
- Postupuj po fázích ze sekce 5 plánu; každou fázi dokonči včetně testů, než
  začneš další:
  1. SQL: funkce dle R3, migrace dle R2 (idempotentní transformace
     occasions.features + DROP staré gate funkce + plná znění změněných
     funkcí), DB testy dle sekce 4 (vč. nového bloku 9 — test migrace).
     Lokální DB: postgresql://postgres@localhost:55432/festapp_test (když
     neběží, bootstrap ve scratchpadu pgtest/bootstrap.sh; musí mít aplikovaný
     i database/recovery/*.sql a obě speakers migrace).
  2. Flutter feature vrstva: CounselingFeature (R4), všechny gaty dle R5+R7,
     unit testy (speakers_mapping_test úprava + nový counseling_gating_test).
  3. SpeakerPickerField dle R6 (testovatelný, bez RPC uvnitř) + integrace do
     event_edit_page + widget testy (speaker_picker_field_test, scénáře a–f).
     R6 obsahuje ověřená fakta a dvě závazné úpravy navíc: (a) save volá
     set_event_speakers s id z NÁVRATU DbEvents.updateEvent (ne widget.id!),
     gate widget.id != null na load i save odstranit; (b) SpeakerEditorDialog
     _save popuje uložený SpeakerModel místo true, speakers_tab reload na
     truthy výsledek.
  4. i18n jen cs+en (namespace FeatureCounseling; Speakers.*/Counseling.*
     zůstávají), sync web_client/public/assets/translations (byte-identické);
     fvm dart analyze = 0 errorů; fvm flutter test celá sada;
     ./automation/test_all.sh.
  5. Nasazení: NEJDŘÍV aplikuj migraci na živou DB csmostrava
     (lwfpdjxsdmkfyrzqbrlk — POZOR, ne ref z .env.local; management API
     POST /v1/projects/{ref}/database/query přes curl, python-urllib blokuje
     Cloudflare) a ověř transformaci features na occasion 643; PAK version
     bump (automation/project.conf + node automation/configure_version.js
     <verze>) a verzovaný commit `<verze>; speakers core + counseling feature
     split`; push prod/csmostrava2026 (fast-forward; force jen
     --force-with-lease); sleduj gh run watch; ověř festapp-version.json a
     smoke testy dle sekce 4 plánu.

ZÁVAZNÁ PRAVIDLA REPA:
- Vždy fvm prefix; build_runner jen při změně rout/modelů (tady nečekám);
  needituj *.gr.dart.
- SQL: jen public schema, SECURITY DEFINER checklist (search_path = public,
  extensions; explicitní guardy get_is_editor_on_occasion /
  get_is_editor_view_on_occasion; žádný EXECUTE s raw stringy). Zápisy do
  speakers tabulek JEN přes RPC.
- UI chyby přes ExceptionHandler.guard; admin prvky gatuj přes RightsService;
  žádné dart:io ve sdíleném kódu; lokalizace jen přes *Strings třídy
  (žádné 'literál'.tr() v UI).
- Verze nejde nikdy dolů — chybu v nasazené verzi opravuj novým vyšším
  commitem, ne přepisem historie.

HOTOVO ZNAMENÁ: DB testy zelené (speakers_test vč. bloku 9 + celá sada na
lokální baseline), fvm dart analyze 0 errorů, celá fvm flutter test sada
zelená, test_all.sh prochází (známé env výjimky), migrace aplikovaná a ověřená
na live (643: counseling element, žádný speakers element), deploy zelený,
festapp-version.json = nová verze, a stručný závěrečný report: co se změnilo,
ověření na live, co zbývá (nic než data od Julie).
