# Bezpečnostní audit Festapp - 2026-10-17

## Závěr

**Festapp zatím nelze označit za bezpečnostně v pořádku. Potvrzené stored XSS v detailu akce a SVG plánku mají vysokou prioritu.** Dřívější kritické databázové nálezy jsou podle dnešního nezávislého readbacku opravené. Nejde o důkaz napadení ani kompletní penetrační test.

Nejprve opravit dva HTML/SVG renderery a přidat regresní scénáře. Poté řešit postupný přechod na CSP se `script-src`, limity sdíleného hostu a preventivní GitHub ochrany. Audit neměnil aplikační kód, produkční data, oprávnění ani konfiguraci; nic nenasazoval a neposílal žádné zprávy.

## Rozsah a zdroje

- Kontrola přibližně 21:20-21:38 UTC, 2026-10-17.
- GitHub `festappnet/festapp`, autoritativní main `8b1420ea1da7349db68b4a293bb37da049fb9047`. Relevantní soubory stažené přes GitHub API byly porovnány s checkoutem.
- Lokální větev `feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`, s rozsáhlým existujícím pracovním diffem. Tento checkout není aktuální main. Existující změny zůstaly zachované.
- Produkční čtení: tenant `festapp`, organizace 1, generation 1. `prod/festapp:automation/project.conf`, živý `backend-activation.json`, SSH hostname, runtime DB a existence organizace se shodovaly s chráněnými target assertions. Použito projektové `festapp-backend-access`; SQL výhradně `BEGIN READ ONLY`.
- Ruční trasování vybraných hranic: veřejný web, HTML/SVG, přihlášení, sdílená Edge autorizace, BankSync vstup, externí image fetch, privátní image worker a SQL/RLS katalog. U Edge handlerů šlo o výběrovou kontrolu zdrojů, nikoli opětovné spuštění všech jejich sad nebo důkaz identity nasazeného bundle.
- Pět npm lockfile auditů lokálního checkoutu a dalších pět nezávislých auditů přesných manifestů aktuálního main. Použito `npm audit --package-lock-only --json`, bez instalace a bez změny locků.
- Lokální browser proof běžel přes `agent-browser`, taskový prázdný config, samostatnou session a HeadlessChrome. Žádný uživatelský profil ani produkční účet. Session byla uzavřena.

## Výběr a instalace skillu

Nainstalován a použit [OpenAI security-best-practices](https://github.com/openai/skills/tree/49f948faa9258a0c61caceaf225e179651397431/skills/.curated/security-best-practices), upstream main při kontrole `49f948faa9258a0c61caceaf225e179651397431`. Instalace: `~/.codex/skills/security-best-practices`. Skill bude automaticky dostupný v dalším tahu; v tomto auditu byl načten přímo včetně celé příslušné vanilla JS reference.

Na GitHubu byly porovnány také [Trail of Bits skills](https://github.com/trailofbits/skills) a [OpenAI Codex Security](https://github.com/openai/plugins/tree/main/plugins/codex-security). Trail of Bits nabízí specializované auditní a validační postupy a dokumentuje použití s Codexem. Oficiální Codex Security má komplexnější orchestraci; jeho `deep-security-scan` spoléhá na `start_codex_security_deep_scan`, které tato session nenabízí. Nebyl zde spuštěn a není vydáván za použitý nástroj.

**Nebyl nalezen doložený srovnávací benchmark skillů pro přesné označení „6.1 Solo Medium“.** Vybraný skill je praktický základ pro dostupný audit, nikoli prokázaný univerzální vítěz. Jeho konkrétní jazyková podpora je Python, JS/TS a Go; PostgreSQL/Supabase a Dart byly posuzovány podle projektových pravidel a skutečného kódu, nikoli pod záminkou přímé podpory skillu.

## Potvrzené nálezy

### F01 - Vysoké: stored XSS v detailu akce

- Pravidlo: `JS-XSS-001`, CWE-79.
- Zdroj: `web_client/src/components/occasion/occasion_detail_dialog.js:33`, `:52`, `:95`, `:115`; cesta z karty `web_client/src/components/occasion/occasion_card.js:41`.
- `occasion.title` a `occasion.description` se bez escapování či DOMPurify interpolují do `overlay.innerHTML`. I textový název je HTML parserem interpretován jako markup.
- Útočník potřebuje možnost uložit obsah akce, například vlastní pořadatelský účet nebo kompromitovaný editor. Není doložen anonymní zápis obsahu. Návštěvník následně otevře detail této akce.
- Dopad: JavaScript v originu aplikace může číst dostupná data a JS přístupnou Supabase session nebo provádět operace v kontextu přihlášené oběti. Není doloženo plošné převzetí všech tenantů.
- Důkaz: lokální skutečný Chrome spustil neškodné markery přes `img onerror` v názvu i popisu. Vstup neobsahoval exfiltraci ani síťový cíl. Modul detailu je bajtově stejný v checkoutu i kontrolovaném main.
- Nasazený web `live.festapp.net` obsahuje stejnou nechráněnou cestu v `/web-assets/index-DpCLmvut-0.20.161-645.js`: lokální proměnné odvozené přímo z title/description jsou interpolovány do `innerHTML`. Tento artefakt má SHA-256 `99cf4c52d275967038c238caea9682272be301813ba9de54e6a67d2af6e85b51`. Neproběhl zápis payloadu do produkce ani exploit proti návštěvníkovi.
- Náprava: název a tlačítkové texty přes `textContent` nebo escapující `html` helper; bohatý popis přes existující `sanitizeHtml`. Zahrnout do kontroly i dynamické atributy/style stejné šablony.
- Obrana navíc: CSP se `script-src` po ověření kompatibility. Živá hlavička je pouze `base-uri 'self'; object-src 'none'`; inline event handlery neblokuje. CSP není náhrada opravy sinku.

### F02 - Vysoké: stored XSS přes SVG pozadí plánku

- Pravidlo: `JS-XSS-001`, CWE-79.
- Zdroj: `web_client/src/components/blueprint/svg_utils.js:11`, `:49`, `:56`; `web_client/src/components/blueprint/blueprint_renderer.js:105`, `:115`.
- `DOMParser` a `XMLSerializer` upravují rozměry SVG, ale neodstraňují aktivní obsah. Výsledek se vkládá do `bgContainer.innerHTML`. Chybová větev navíc vrací původní řetězec jako SVG.
- Vstupní cesta: `database/functions/eshop/get_blueprint.sql:45` vrací uložené `background_svg` pro platný veřejný formulář. Živá interní zapisovací funkce obsahuje SVG i kontrolu oprávnění, bez nalezené sanitizace. Útok tedy vyžaduje možnost editovat plánek nebo kompromitovaného editora; není doložena anonymní editace.
- Dopad: script v kontextu originu návštěvníka rezervačního formuláře, včetně přístupu k JS přístupné session.
- Důkaz: lokální skutečný Chrome vykonal neškodný SVG `onload` po průchodu skutečným `SvgUtils.prepareBackgroundSvg` a metodou `renderBackground` z aktuálního main. Nejde jen o nalezení textového vzoru. Nasazení konkrétního lazy blueprint chunku nebylo samostatně ověřeno; produkční exploit se neprováděl.
- Náprava: sanitizace s úzkým SVG profilem před vložením, zákaz event atributů, skriptů, `foreignObject` a aktivních/external URL podle skutečných potřeb editoru. Případně převod SVG na bezpečný obrazový formát. Nevracet nevalidní původní SVG v režimu fail-open. Ověřit zachování rozměrů a renderování legitimních plánků.

### F03 - Střední: slabá izolace spotřeby mezi backend službami

- Živý `docker inspect` potvrzuje explicitní RAM/CPU/PID rozpočty pro Studio a Meta, ale nikoli pro DB, Edge, Auth, REST, Storage a další hlavní kontejnery (`Memory=0`, `NanoCpus=0`, `PidsLimit=null`).
- Jde o chybějící per-container izolaci, nikoli tvrzení o úplné absenci aplikačních limitů nebo cgroup pravidel na všech úrovních hostu. Request/body limity a centrální abuse mechanismus již existují.
- Dopad: drahá legitimní či zneužitá operace může zasáhnout další služby stejného hostu. Zátěžový/OOM test nebyl proveden a vzdáleně dosažitelný úplný výpadek nebyl prokázán.
- Náprava: navázat na existující měření v `docs/operations/security-remediation-20261016/native-resource-*.json`, vybrat rozpočty z reálných špiček a rezervy DB, ověřit řízené překročení a obnovu. Nenasazovat libovolné nízké stropy bez měření.

### F04 - Střední: veřejný GitHub nemá preventivní secret scanning

- Aktuální GitHub API `repos/festappnet/festapp` hlásí `visibility=public`; `secret_scanning`, `secret_scanning_push_protection`, non-provider patterns i validity checks jsou `disabled`. Automatické Dependabot security updates jsou také `disabled`.
- Jde o potvrzenou chybějící prevenci, nikoli potvrzený únik. Cílený lexikální scan 2 343 sledovaných textových souborů checkoutu nenašel privátní PEM/OpenSSH klíč, service-role JWT ani hledané formáty GitHub/AWS/Stripe produkčních tokenů. Nezkoumal kompletní historii ani všechny formáty tajných hodnot.
- Náprava: zapnout secret scanning a push protection, přidat sken historie/CI a zavést automatické aktualizace s příslušnými testy. Nic z těchto nastavení audit neměnil.

## Co se oproti včerejšímu auditu změnilo

Následující údaje jsou dnešní vlastní čtení produkčního katalogu, nikoli pouze převzatý migration ledger:

| Oblast | Stav 2026-10-17 |
| --- | --- |
| `migrate_users_to_org`, `update_spot`, `apply_allocations_claim_only`, `send_email_mailersend` | Veřejné funkce těchto jmen neexistují |
| Tři external sync tabulky | RLS `service_only`, role `{service_role}`, anon nemá SELECT ani INSERT/UPDATE/DELETE |
| Anon TRUNCATE na public/eshop | 0 tabulek |
| dblink extension | 41 kontrolovaných funkcí bez anon/authenticated EXECUTE |
| Public SECURITY DEFINER | 679 funkcí, 218 anonymně spustitelných; počet sám není nález |
| Search path | Dvě výjimky bez nastavení jsou `dblink_connect_u`, obě klientům nepřístupné; prázdný explicitní search_path u plně kvalifikovaných wrapperů není absence nastavení |
| Široké zápisové politiky | Žádná nalezená PUBLIC/anon ALL/INSERT/UPDATE/DELETE politika s bezpodmínečným USING/WITH CHECK true ve zkoumaných schématech |
| RLS | 149 public/eshop/storage tabulek se zapnutým RLS; dvě public tabulky bez RLS nemají anon CRUD granty |
| Auth | Password-verification hook zapnutý, rate-limit header `X-Festapp-Client-IP` |
| Caddy | Cloudflare/loopback origin allowlist, trusted-IP přepis, read timeouts, Auth 64KB, Storage 52MiB, ostatní API 32MB |
| Síťová izolace | Gateway porty bindované na 127.0.0.1; pro DB/Studio/Meta nejsou publikované Docker porty |
| PITR | `archive_mode=on`, timeout 5min, 395 úspěšně archivovaných segmentů, 0 archive failures při kontrole |
| Údržba hostu | `reboot-required` při kontrole neexistuje |

GitHub main obsahuje také novější pgBackRest/PITR a recovery receipts. Nebyla znovu provedena obnova ani načtena dnešní provider control-plane politika. Nelze opakovat včerejší tvrzení „PITR je vypnuté“ nebo „čeká restart“ jako aktuální stav.

## Závislosti: main a checkout mají odlišný stav

| Sada | Aktuální main: npm hlášení | Rozpracovaný checkout: high položky |
| --- | --- | --- |
| web_client | 0 | 2 |
| image-worker | 0 | 5 |
| sync-worker | 0 | 5 |
| sync-publisher | 0 | 5 |
| self-hosted-monitor | 0 | 4 |

Počty high zahrnují propagované položky dependency řetězce, nejsou počtem nezávislých exploitačních cest. V checkoutu jde mimo jiné o nanoid/source-map-js a řetězec Wrangler/Miniflare/sharp/undici. Hlavní worker tooling je vývojová závislost; report neoznačuje jeho přítomnost za důkaz zranitelného produkčního Worker runtime. Nerevertovat novější locky main starším checkoutem. Údaj „0“ se vztahuje jen ke známým npm advisories v okamžiku dotazu, nikoli ke všem ekosystémům či ručně auditované bezpečnosti.

## Reprodukce a hranice závěru

[Lokální self-contained browser proof](security-audit-2026-10-17-proof.html) obsahuje relevantní skutečné renderovací metody z kontrolovaného main a minimální stuby jejich ostatních UI závislostí. Používá jen neškodné `window.audit*` markery; CSP zakazuje síťová spojení. Po načtení ukáže JSON. Ověřený výsledek: `svg=true`, `title=true`, `description=true`; automatizační session potvrdila `HeadlessChrome`. Jde o izolovanou reprodukci renderovacích sinků, nikoli kompletní E2E aplikace nebo produkční zápis.

Otisky stažených zdrojů: `svg_utils.js` SHA-256 `c5c9650e961624da7e7149b529570f19deeb88ad36bae0ac33120a4de79c7f52`; `occasion_detail_dialog.js` SHA-256 `45713e551c2249fb34f16a4ef4ca463f1a5db3e8427078f0ad502446eb49018a`.

Audit nepokryl všechny SQL funkce jednotlivě, všechny RLS kombinace a tenanty, kompletní Flutter/mobile klienty, historii Gitu, CVE všech Docker image, reálný fyzický push fan-out, všechny vendor billing stropy ani incident response historii. Nepouštěl produkční fixtures, exploity měnící data, zátěžové testy nebo recovery drill. Tato omezení neoslabují doložené XSS reprodukce, ale brání tvrzení, že zbytek systému je kompletně prověřený.
