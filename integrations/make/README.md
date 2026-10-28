# vstupenky.online pro Make

Implementovaný native konektor má pět modulů, jednu OAuth connection a jeden RPC výběr akcí. Jediný transport je verzovaný JSON HTTP adaptér ve stávající regionální službě, který volá kanonický `Operations.invoke` a profil `order-summary`. Backend je nasazený z `903145af6`; nesdílí klienta ani grant s ChatGPT/Codex a DCR zůstává vypnuté.

Publish a jedna žádost o review byly přijaty, včetně navazujícího formuláře (case `2351677:2082001`). Čeká se na kontrolu a vydání Make. Aktuální publikační stav a další krok jsou v [execution-20261028.json](evidence/execution-20261028.json). Publish, podání review, schválení a vydání do katalogu jsou samostatné stavy. Samotné fungování privátní aplikace neznamená dostupnost v katalogu.

- [Návod uživatele a nativní Make README](SETUP.md)
- [Znalosti z review, ověřené výjimky a publikační postup](review/REVIEW-LESSONS.md)
- [Konfigurace aplikace](app.json), [zdroj OAuth](src/connection.json), [generované komponenty a manifest](src/generated/manifest.json)
- [Nasazení](evidence/http-deployment-20261028.json), [45 cílených testů včetně skutečného SQL](evidence/server-tests-20261028.json)
- [Čerstvý průchod všemi moduly a chyba druhé stránky](evidence/live-qualification-20261028.json), [15 případů limitů a oprávnění](evidence/guardrails-20261028.json)
- [Souběžný refresh a neměnná serverová expirace](evidence/refresh-20261028.json), [okamžitá revokace](evidence/revocation-20261028.json), [shoda s Make SDK](evidence/source-readback-20261028.json)
- [Veřejné důkazy nákladů](evidence/publisher-costs.json), [podklady pro review](review/REVIEW.md)

Zdroj lze regenerovat a kontrolovat z `tools/festapp/` pomocí Node 24 a pnpm 11.24.0:

```sh
pnpm exec node ../../integrations/make/scripts/build.mjs
pnpm exec node ../../integrations/make/scripts/build.mjs --check
pnpm exec node ../../integrations/make/scripts/verify.mjs
```

`sync.mjs --apply` synchronizuje již existující privátní aplikaci. Příznak `--review-update` dovoluje aktualizovat stejnou publikovanou aplikaci před schválením. Nevytváří nový účet, druhou aplikaci, Publish ani žádost o review. API token čte z chráněného `~/.config/festapp/make-api-token`; do repozitáře nepatří.

Make zobrazenou expiraci připojení při refresh posouvá i s explicitní hodnotou v definici. Autoritou je serverová `Delegation.expiresAt`, která se při dvou souběžných skutečných bězích nezměnila. Souhlas je platný sedm dnů a server jej kontroluje při každém čtení i obnově. Po vypršení nebo revokaci je nutná reautorizace.

`review/demo-data.json` obsahuje jen syntetické objednávky a reporty. Heslo existuje pouze v chráněném lokálním úložišti. Provisioner již proběhl a nesmí se opakovat; starší ChatGPT fixture, její oprávnění ani ostatní klientské granty se nemění. Nepoužívaný pilotní grant Make pod starým syntetickým účtem byl odvolán.

Historický [přípravný důkaz](evidence/preparation-20261028.json) se nepřepisuje. Autoritativní zadání: [plán](../../docs/plans/make-connector-plan-2026-10-28.md) a [execution prompt](../../docs/plans/make-connector-EXECUTION-PROMPT-2026-10-28.md).

AI review z 2026-10-28 bylo vyhodnoceno: platné připomínky jsou opravené, sporné body mají důkazy v [odpovědi](review/RESPONSE-20261028.md). Nové definice prošly 34 SDK kontrolami, všemi pěti moduly, dvěma konzumenty mapovaných polí a šesti hraničními případy. Backend se neměnil; původní cílené testy zůstávají platné. Živý cílený průchod lze zopakovat přes `scripts/qualify.mjs --apply` ze stejného pnpm prostředí; používá jen dvě existující on-demand scénáře.
