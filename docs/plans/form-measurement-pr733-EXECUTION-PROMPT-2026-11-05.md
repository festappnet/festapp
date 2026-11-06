# Implementace doplnění PR #733

Pracuj v repozitáři `/Users/miakh/source/festapp`, v izolovaném checkoutu aktuálního PR #733. Zachovej cizí rozpracované změny. Přečti repo instrukce, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/form-measurement-pr733-plan-2026-11-05.md`

Verification: standard. Cílem je doplnit stávající PR o výchozí vypnutí celé nové měřicí vrstvy, samostatnou konfiguraci/aktivaci, shodné UI/MCP a serverovou organizační politiku. Cizí skripty nesmějí běžet na originu hlavní aplikace. Dokončení zahrnuje migrované callers, odstranění starého loaderu/guardu, replay-safe konverze, waitlist a cílené kontroly.

Postupuj podle závislostí vln. Uložení konfigurace není souhlas ani důkaz spuštění. `forms.save` zůstává jedinou konfigurační mutací; default false, preserve/null/reset a strict návratové schema musí souhlasit mezi SQL, UI a MCP. Kontakty zůstanou tvrdě blokované. Nezaváděj placeholdery, druhou policy autoritu, kompatibilitní same-origin loader ani skrytý platform-admin bypass.

Izolované GTM má povinný ověřovací bod. Bez testovacího kontejneru, konkrétního souhlasového adaptéru nebo ověření kompatibility dokonči nezávislé jádro a přesně označ neověřenou vlnu. Netvrď plnou podporu GTM, nenahrazuj izolaci spuštěním kódu v checkoutu. Nová doména, CMP vendor ani produkční runtime nejsou tímto promptem schválené.

Pokud se PR/main posunuly nebo se ukáže chybný předpoklad, aktualizuj autoritativní plán podle důkazů. Neprováděj deploy, produkční migraci, nákup, commit/push ani komunikaci do GitHubu bez samostatné autorizace. Dodrž jeden Flutter proces, sériové Flutter testy a předepsanou browser delegaci. Při předání stručně uveď výsledný kontrakt, odstraněné cesty, skutečné výsledky ověření a přesné zbývající blokátory či neprovedené provozní kroky.
