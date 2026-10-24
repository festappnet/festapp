# Realizace zrychlení a zjednodušení tvorby událostí

Pracuj v `/Users/miakh/source/festapp`. Přečti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a celý autoritativní plán:

`docs/plans/occasion-setup-usability-performance-plan-2026-10-21.md`

Implementuj jeho vlny v pořadí 0-4: identifikace skutečného runtime a baseline, zmenšení práce se zdroji, bezpečný tok plánku, požadavky průvodce, karty a stejné měření po změně. Plán pokrývá všech 20 screenshotových bodů. Kde aktuální kód již požadavek splňuje, dolož to a nevytvářej jej znovu. Zjištění odporující plánu zapracuj přímo do něj a přizpůsob práci bez tiché změny zadání.

Zachovej rozsáhlou cizí rozpracovanou práci. Ověř aktuální větev, HEAD a relevantní diff; nezačínej resetem nebo přepnutím větve. Standardní cílené ověření pro SQL, platby, odkazy a perzistenci; kosmetiku ověř společně na konci. Nejvýše jeden Flutter proces na celé stanici, testy --concurrency=1. Použij existující fixture a izolovaný headless browser, ne uživatelův Chrome.

Pro ohraničenou logiku a UX plánku je vyžádaný subagent `gpt-6-astra`, reasoning `medium`, `fork_turns="none"`. Dej mu konkrétní vlastnictví souborů/úseku a aktuální kontrakt. Nespouštěj další agenty na opakované audity. Zachovej SQL autoritu, revize autosave, command-id retry, sanitizaci kopií, bankovní oprávnění a oddělení dohledatelnosti od otevření prodeje.

Runtime conversion error a příčina pomalosti dosud nejsou naměřené. Nevymýšlej čísla ani kořenovou příčinu. Slug s podtržítky je nevyjasněný a odporuje současnému kontraktu; vyjasni rozsah a mezitím pokračuj nezávislou prací. Bez potvrzení neprováděj plošnou změnu slugů. Nezanechávej skryté blokující validace ani druhou implementaci editoru nebo plateb.

Bez samostatného zadání neprováděj commit, push, deploy, produkční zápis/migraci ani převod zdrojových plánků. Výsledek předej stručně: změny, skutečné časy před/po, cílené kontroly, neuzavřené body a přesné zbývající omezení. Hotovo vyhodnoť podle definice v plánu, ne podle pouhé kompilace.
