# Implementace jednotného HTML editoru a inline úprav

Pracuj v `/Users/miakh/source/festapp` na main, přečti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a CONTRIBUTING.md. Verification: standard, cílené kontroly; žádné nezadané release gates nebo subagent audit.

Prováděj práci úsporně: jeden ověřovací průzkum proti plánu, ucelené dávky podobných callerů, jedna cílená validační dávka po souvislé změně. Passing check neopakuj bez změny covered code nebo nové evidence. Nedělej další prototypy, paralelní plány, nezadané agent audits, celé repo builds ani opakované dumpy logů. Povinné HTML/auth/mobile gates tím nejsou zrušené.

Zachovej současný nebo téměř shodný vzhled: theme, typografii, spacing, barvy, rámce polí, známé toolbar ikony a Save/Cancel. Engine a inline placement se mění; obrazovky se neredesignují. Prototypový dvojpanel ani testovací vzhled nepřenášej do aplikace. Použij malý reprezentativní vizuální baseline a porovnání, ne screenshot každého calleru.

Implementuj hluboký modul s malým rozhraním. Session je stav controlleru; preparer/coordinator jsou skutečné odpovědnosti, nikoli povinnost založit samostatné veřejné vrstvy. Codec, média a UI odděluj jen na reálných seams. Žádné obecné workflow/plugin frameworky, pass-through factories, platformní kopie editoru nebo duplicity paste/save logiky v callerech. Orientační soubory v plánu lze slučovat bez změny invariantů. Úsporný kód musí být čitelný, typovaný a bezpečný pro lifecycle.

Autoritativní zadání je `docs/plans/html-editor-replacement-plan-2026-09-30.md`. Přečti celý plán před změnami. Implementuj jeho vlny a rozhodovací tabulku: jeden Super Editor pro web/Android/iOS, inline ve formulářích a čtecích detailových editacích, společný dialog v gridech/časové ose.

**Persistovaný a veřejný kontrakt zůstává HTML string.** Markdown/Delta/JSON dokument nesmí nahradit uložené HTML. Vstupní HTML fidelity a nativní clipboard gate musí projít před plošným přepnutím. Prototyp ručně mapuje jediný obrázek; nepřenášej jeho hardcoded mapování jako řešení importu.

Implementuj společný HTML codec, controller, media draft a autorizovaný temporary image fetch přes stávající backend. Nahrávej média do vlastního úložiště až při skutečném save rodiče a zachovej retry/cancel/permissions. Unit/organization/group scope řeš podle vlny 2, nikdy cizím occasionId ani anonymní proxy.

Dodrž konkrétní role matrix: fetch-http-data sjednotit na caller-JWT check_upload_permission (occasion editor/orderEditor a unit editor), ne měnit globální authorizeRequest. Parent HtmlSaveCoordinator musí zahrnout všechna nested HTML pole formuláře a grid header/custom saveAction. Option dialog má oba select-one/many callery; product dialog předává registry z ticket row. Neuploaduj při Apply pole ani při zrušeném potvrzení notifikace.

News composer musí awaitovat existující typed async publish writer a zůstat otevřený při chybě; nepřidávej druhý publish tok. Zachovej aggregateVersion a aktivní draft při projection refresh. Současné transport retry se stejným p_command_id ponech, ale unknown outcome neopakuj novým automatickým invoke. Upload nemá serverovou idempotenci; neslibuj přesně jeden side effect při ztracené odpovědi. Vlastnictví assetů a MIME musí být ověřené; odstranění z HTML neznamená fyzický delete sdíleného obrázku.

Přesuň všechny callery, jejich writer/save hranice a nepřímé shared field/grid použití. Regeneruj router a úplně odstraň dva původní editory, jejich dependency, platformní selektor a starý HTML route podle ledgeru. HtmlView ponech jako čtečku.

Pokud důkazy vyvrátí premise plánu, uprav jej s konkrétním nálezem a navazující vlnou; nevytvářej druhý editor, ztrátový fallback, placeholder nebo skrytý compatibility route. Nedostupné reálné zařízení/backend authorization gate vykazuj přesně; nevydávej widget test za ověřený systémový paste.

Použij fixture a save-state matice z plánu jako acceptance checklist. Mobilní web Android/iOS a native Android/iOS jsou oddělené důkazy. Email fidelity nemá doložený skutečný template corpus; tuto bránu uzavři reprezentativním bezpečným vzorkem, ne pouze syntetickým jednoduchým p/table testem. HTML zachované bloky, whitespace, align, list nesting, image atributy a no-op round-trip jsou povinné.

Plán neautorizuje commit/push/deploy, produkční zápisy/uploady, skutečné emaily/notifikace ani builds více tenantů. Nasazení případné backendové změny je samostatný krok s explicitní autoritou. Na konci reportuj HTML kontrakt, migrované inline/dialog callery, uzavřený deletion ledger, cílené výsledky a zbývající device/deployment gate.
