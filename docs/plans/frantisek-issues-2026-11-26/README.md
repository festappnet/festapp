# Audit issue od Františka v repozitáři Festapp

Stav k 26. 11. 2026, GitHub `festappnet/festapp`, autor `bujnovskyf`, základ
`50bd830f163e697eef51ad35bd580d8d9e4cb867` na `main`. Dotaz
`gh issue list -R festappnet/festapp --author bujnovskyf --state all --limit 300`
vrátil 20 issue, z toho tři otevřená. Ke každému je níže výsledek kontroly
zadání, uzavírací události, souvisejícího PR a aktuálního vlastníka v kódu.
Vlastní PR autora slouží jako důkazy k issue. Audit vychází ze zdrojů a historie.
Chování živých instalací se ověřuje podle jednotlivých plánů.

## Práce pro společný PR

| Issue | Zjištění a výstup |
| --- | --- |
| [#1067](https://github.com/festappnet/festapp/issues/1067) | Fronta volá root navigátor pod portálem nastavení účtu. Karty navíc nemají šířku panelu. [Plán fronty](1067-bank-email-queue.md). |
| [#1068](https://github.com/festappnet/festapp/issues/1068) | Řazení se uloží do vazby účtu na jednotku. Čtecí RPC nevrací prioritu ani pořadí a Flutter se vrátí k pořadí ID. [Plán pořadí](1068-bank-account-priority.md). |
| [#1069](https://github.com/festappnet/festapp/issues/1069) | Samostatný checkout bez živého openeru správně použije místní cookie lištu. Z kampaně lze směřovat do vloženého formuláře na stránce pořadatele. [Plán odkazu](1069-consent-in-app.md). |
| [#958](https://github.com/festappnet/festapp/issues/958) | Callback opraven v [#983](https://github.com/festappnet/festapp/pull/983). Komentář popisuje i odlišný problém s výběrem oprávnění. Aktuální UI už rozlišuje výběr jednotlivých akcí a celého pořadatele. README ukazuje pouze read-only připojení Codexu bez vysvětlení, jak výslovně požádat o další podporované rozsahy. [Plán navazujícího ověření a návodu](mcp-follow-up.md). |

## Uzavřená issue a současný stav

| Issue | Důkaz na současném main a další krok |
| --- | --- |
| [#1008](https://github.com/festappnet/festapp/issues/1008) | [#1023](https://github.com/festappnet/festapp/pull/1023). Návrat po objednávce v `form_page.js` volá vnitřní inicializaci. Zachování relace je chráněno podmínkami stejného formuláře a platného zdroje. Regrese patří do ověření #1069. |
| [#1007](https://github.com/festappnet/festapp/issues/1007) | Implementaci dodal [#1031](https://github.com/festappnet/festapp/pull/1031), issue formálně uzavřel [#1050](https://github.com/festappnet/festapp/pull/1050). `bank_sync_email_confirmation.sql` drží potvrzení, práva a audit. Párování určuje platbu, doručení a způsobilost pro Meta. Automatické párování e-mailu zůstalo výslovně mimo dohodnutou první verzi. #1067 opravuje její UI. |
| [#1006](https://github.com/festappnet/festapp/issues/1006) | [#1022](https://github.com/festappnet/festapp/pull/1022). Výběr účtu pro formulář a vysvětlení priority existují, výchozí účet se řeší podle měny. #1068 opravuje nesoulad zobrazení s uloženým pořadím. |
| [#961](https://github.com/festappnet/festapp/issues/961) | [#970](https://github.com/festappnet/festapp/pull/970) a [#994](https://github.com/festappnet/festapp/pull/994). `measurement-setup.mjs` má čtení, export, probe, zápis/zakázání vazeb a žádost o schválení. `forms.mjs` má samostatný přehled efektivního měření a embed kód. Potvrzení pokrytí je prohlášení pořadatele. Konfigurace Meta konektoru, token a přepínač organizace patří do administrace podle rozhodnutí #994. |
| [#960](https://github.com/festappnet/festapp/issues/960) | [#988](https://github.com/festappnet/festapp/pull/988). `form_creation_domain.sql` zakládá novou skupinu a výchozí produkt samostatnému formuláři. Výběr existujících produktů podle blueprintu zůstává výslovná větev pro sál. `primary_product_guard_test.sql` je regresní místo. |
| [#959](https://github.com/festappnet/festapp/issues/959) | [#984](https://github.com/festappnet/festapp/pull/984). `forms.mjs` projektuje snapshot před striktní validací a `command-boundary.mjs` odlišuje zapsaný příkaz s neúspěšným readbackem. `/healthz` při auditu ohlásil build obsahující #984. Původní příčina na hostované instanci zůstala hypotézou. [Postup ověření hostované verze](mcp-follow-up.md). |
| [#956](https://github.com/festappnet/festapp/issues/956) | Otázka architektury uzavřená s variantou vysvětlit hranici. Úvod `tools/festapp/README.md` ji už dokumentuje. Lokální stdio používá běžnou relaci a omezený katalog. Delegovanou revokaci a čerstvé MFA drží hosted OAuth. [#957](https://github.com/festappnet/festapp/pull/957) řeší prefix přihlášení, ne změnu oprávnění. Lokální privilegované nástroje a PAT vyžadují samostatné rozhodnutí o autorizačním modelu. |
| [#917](https://github.com/festappnet/festapp/issues/917) | [#918](https://github.com/festappnet/festapp/pull/918) a další hardening. `meta_purchase_consent.sql`, `meta_purchase_worker.sql` a `process-meta-purchases` vlastní aktuální souhlas, způsobilost po zaplacení a odeslání. #1067 ani #1069 nepřidávají vlastní konverzní cestu. |
| [#858](https://github.com/festappnet/festapp/issues/858) | Podle uzavíracích komentářů a `website_consent_bindings.sql` řeší konfiguraci serverový export navázaný na přesný web a revizi. WordPress/Joomla mají instalační testy a jejich produkční rollout je doložen v issue. #1069 doplňuje navigaci odkazu, serverový export zůstává jeho zdrojem konfigurace. |
| [#824](https://github.com/festappnet/festapp/issues/824) | [#826](https://github.com/festappnet/festapp/pull/826). `host_cookiebot.js` ověřuje explicitní aktuální volbu, scope, origin a uložený záznam. `form_consent_link_cookiebot.test.js` kryje přenos samostatným odkazem. #1069 nemění rozhodování adaptéru. |
| [#808](https://github.com/festappnet/festapp/issues/808) | [#809](https://github.com/festappnet/festapp/pull/809). `mereni-formularu.html` už doporučuje vložení do webu s jeho dataLayer. #1069 zpřesní chování odkazu v prohlížečích aplikací. |
| [#807](https://github.com/festappnet/festapp/issues/807) | [#809](https://github.com/festappnet/festapp/pull/809). Uložené weby, stav žádosti a potvrzení pokrytí popisuje aktuální nápověda. `measurementApproval.inspect/request` a vazby webu zachovávají rozdíl mezi uloženým webem, pokrytím souhlasu a schválením měřicího runtime. |
| [#804](https://github.com/festappnet/festapp/issues/804) | [5a01046df](https://github.com/festappnet/festapp/commit/5a01046df343d003eec4f3caf8f44f5011267c4c) a aktuální `integrations/measurement/festapp-host-gtm.json`. Šablona má vlastní zdroj a odkaz z nápovědy. Další změna šablony k těmto opravám není potřeba. |
| [#787](https://github.com/festappnet/festapp/issues/787) | Původní nápověda [7975f8619f](https://github.com/festappnet/festapp/commit/7975f8619f4490f5b58752ab9f5a5dd9a335d18c). Aktuální stránky CS, SK a EN v `automation/release/help/` pokrývají oba režimy, souhlas, šablonu a řešení problémů. Výpadek URL autor v issue označil za vyřešený. |
| [#782](https://github.com/festappnet/festapp/issues/782) | [#786](https://github.com/festappnet/festapp/pull/786). `host_consent_link.js` a `form_consent_link.js` drží ověřenou obnovitelnou relaci přes `postMessage`. Její hranice vysvětluje #1069. |
| [#781](https://github.com/festappnet/festapp/issues/781) | [#785](https://github.com/festappnet/festapp/pull/785). Výchozí generovaný embed v `form_embed_code.dart` používá dataLayer webu, režim GTM pořadatele zůstává výslovná volba. Atribuci vlastní stávající měřicí kontrakt. |

## Pořadí práce

Nejdřív návrat priority a jeho DB kontrakt. Potom nezávislé opravy fronty a
odkazu. MCP je ověřovací a dokumentační krok. Každá změna má vlastní commit
a společný PR lze prověřit jako celek. Viz [execution prompt](EXECUTION-PROMPT.md).
