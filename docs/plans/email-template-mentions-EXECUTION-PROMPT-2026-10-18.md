# Implementace proměnných e-mailových šablon přes @

Aktualizováno 2026-10-19. Toto je hotové zadání pro následné spuštění implementace.

Implementuj plán v `/Users/miakh/source/festapp`. Nejdříve přečti repository instrukce, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/email-template-mentions-plan-2026-10-18.md`

Přečti také `docs/plans/email-template-mentions-editor-evidence-2026-10-18.md`: používaná dev.52 už obsahuje nativní podporu tagů. Použij `ActionTagsPlugin` pro composition a `AttributedText` inline placeholdery; nepiš vlastní mentions engine ani nepřidávej fork/závislost. Stock submit action tagu má natvrdo `/`, takže použij plánovaný explicitní doménový příkaz. Předmět sdílí editorový engine omezený na prostý odstavec.

Pro UI použij doprovodnou specifikaci `docs/plans/email-template-mentions-ux-2026-10-18.md` a skill `ux-designer`. Veškerý návrh a implementaci UI zadávej modelu `gpt-6-astra` s `medium` reasoning; je to výslovný požadavek uživatele. Dodrž `verification: standard`, ale ověřuj cíleně po ucelených změnách.

Výsledek: @ nabídka v předmětu i těle, rozumné pořadí, realistické bloky ze skutečného HTML e-mailových rendererů, viditelná neaktivní tlačítka/odkazy, náhled aktuálního draftu a nenásilná doporučení. Psaní adres jako `jana+akce@example.cz` ani rozpracované `jana+@` nabídku nikdy neotevře. Interně zůstává jediný formát `{{code}}`. Dokončení vyžaduje bezpečný roundtrip HTML/clipboardu, atomické úpravy a undo, funkční fullscreen, ochranu draftu a odstranění nahrazených cest z plánu.

Pracuj z kanonického main v izolovaném checkoutu; zachovej cizí rozpracované změny. Použij tento krátký postup:

1. Připrav registr/provider, pure extrakci existujících action-link/finalization rendererů a generátor deterministického JSON assetu. Využij skutečné `generateFullOrder`, platební překlady a `generateChangeOverview`; zachovej dnešní vzhled každého producenta. Žádné ruční Flutter kopie e-mailových karet.
2. Předej Astře medium jeden ucelený UI řez nad hotovým kontraktem: společný engine předmětu/těla, tokeny, nabídku, guard adres, inertní `EmailPreviewHtml`, scénáře a doporučení. První cílená brána ověří tokenový import/export, jednu undo transakci a clipboard; pak dokonči zbývající UI bez kontrol po každé drobné editaci.
3. Proveď jeden závěrečný cílený batch core/Flutter/TS/freshness/analyze a jednu izolovanou UX kontrolu. Ověř reálné HTML, soulad částek a nulovou interakci tlačítek; odstraň staré technické výpisy a slovní falešné příklady. Úspěšné checky opakuj pouze po relevantní změně.

Pokud současné zdroje vyvrátí předpoklad plánu, oprav plán s konkrétním důkazem. Nezaváděj druhou syntaxi, nový uložený editorový markup, produkční preview endpoint, runtime JS engine ani AI službu. Věrnost ukázek zajisti společnými renderery a generováním, ne další serverovou službou.

Proveď pouze cílené ověřování určené plánem. Toto zadání neopravňuje produkční operace, odesílání e-mailů, migrace, commit/push ani deployment. Předej stručně výsledek, doklad zachování ukládacího kontraktu, odstraněné staré cesty, ověření a zbývající omezení.
