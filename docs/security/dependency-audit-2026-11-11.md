# Bezpečnostní audit závislostí - 2026-11-11

Kontrola našla aktualizace, které doporučuji udělat. Nejvyšší prioritu má ověření a oprava serverového PostgreSQL podle připnuté verze, následované Node.js v CI. Konkrétní nálezy mají také WordPress vývojové nástroje, ZIP knihovna Edge Functions a lokální Rust graf nativní schránky. Samotné balíčky webového klienta, workerů, Dart a Fastlane byly v kontrolovaných databázích bez nálezu.

Jde o audit současného lokálního pracovního stromu, který již obsahoval rozpracované změny. Závislosti, konfigurace ani produkce nebyly aktualizovány. [Strojové výsledky](dependency-audit-2026-11-11/evidence.json) obsahují verze, cesty, advisory identifikátory a výsledky kontrol.

## Následná lokální oprava WordPress a Edge Functions

Na následný pokyn uživatele jsou lokálně opravené položky 3 a 4 níže. Historické nálezy a původní evidence zůstávají zachované; oprava nebyla publikována ani nasazena. PostgreSQL je výslovně mimo tento zásah, Rust zůstává samostatným otevřeným bodem. Node v CI řeší následná integrace níže.

- WordPress: úzce vymezené overrides rodičů `@wp-playground/storage@3.1.60` a `@php-wasm/cli-util@3.1.60` vybírají `isomorphic-git` 1.38.6 a `fast-xml-parser` 5.12.0. Lockfile mění jen tyto knihovny a související `is-unsafe` na 2.0.3; `@wordpress/env` zůstává 12.0.0.
- Edge: export i test používají `fflate` 0.8.3; stará 0.8.2 je odstraněna z Deno lockfile.
- `pnpm install --frozen-lockfile` prošel. `pnpm run test:dependencies`: 4/4 (cleanup, Express/qs, skutečný Git init/commit/checkout a XML parser načtené přes skutečné tranzitivní spotřebitele).
- `deno test --frozen --lock=supabase/functions/deno.lock --allow-env --allow-read supabase/functions/_shared/ticketBatchExports_test.ts`: 4/4, včetně exportu 200 vstupenek do PDF/ZIP a odmítnutí chybných vstupů.
- Následné `pnpm audit --json` pro WordPress a `deno audit --lock supabase/functions/deno.lock --frozen`: oba bez známých zranitelností. [Výsledky po opravě](dependency-audit-2026-11-11/remediation.json).
- Celý WordPress/Docker nákupní průchod ani produkční Edge runtime nebyly spouštěny. Jde o ověření opravených knihoven a zasaženého exportu, nikoli potvrzení produkčního nasazení.

## 1. Vysoká priorita - PostgreSQL v serverové konfiguraci

- `automation/hetzner-supabase/runtime/docker-compose.festapp.yml:131` a `automation/hetzner-supabase/backup/pgbackrest/Dockerfile:2` připínají `supabase/postgres:17.6.1.136`. Stejný základ používá pgBackRest instalační skript, tedy nestačí změnit pouze hlavní Compose overlay.
- Upstream PostgreSQL před 17.11 obsahuje například [CVE-2026-14669](https://www.postgresql.org/support/security/CVE-2026-14669/) s CVSS 8.8: vhodně připravené časové pásmo při `to_char(timestamptz)` může vést ke spuštění kódu pod uživatelem databáze. [Seznam oprav řady 17](https://www.postgresql.org/support/security/17/) obsahuje i další bezpečnostní opravy po 17.6.
- **Dopad:** pokud nasazený image skutečně obsahuje neopravený PostgreSQL 17.6, databázový proces obsahuje známé chyby umožňující za určitých podmínek spuštění kódu. Dosažitelnost z veřejných Festapp RPC zde nebyla prokázána.
- Doporučení: ověřit skutečný serverový build a případné backporty; připravit kompatibilní Supabase/pgBackRest image s opravami nejméně na úrovni PostgreSQL 17.11. Zachovat rozšíření, obnovu zálohy, PITR a rollback. Změna major verze na 18 není pro tyto opravy sama o sobě nutná.
- Jde o potvrzený problém připnutého upstream základu, nikoli důkaz aktuální verze nebo zranitelnosti běžící produkce. Produkční inventura ani sken obsahu image nebyly součástí této kontroly.

## 2. Vysoká priorita - Node.js v CI

- Node `22.23.3` používají workflow `image-service-regressions`, `image-upload-regressions`, `seat-checkout-regressions` a `web-startup-regressions`. Například `.github/workflows/image-service-regressions.yml:41`.
- `.github/workflows/artifact-retention.yml:31` používá ještě `22.18.0`.
- [Bezpečnostní vydání 22.23.4 z 2026-10-21](https://nodejs.org/en/blog/release/v22.23.4) opravuje mimo jiné Brotli memory corruption s možným spuštěním kódu, DNS validaci a TLS ověřování. Viz také [bezpečnostní oznámení](https://nodejs.org/en/blog/vulnerability/october-2026-security-releases).
- Doporučení: sjednotit tyto piny na podporovaný opravený Node 22, minimálně 22.23.4, a ověřit dotčené CI lanes. Praktické zneužití přes konkrétní vstup CI nebylo doloženo.
- `tools/festapp/Dockerfile.remote:1` již používá Node 24.22.1; tento konkrétní základ není stejný nález. Bez úplného skenu image to není potvrzení bezpečnosti všech jeho systémových knihoven.

## 3. Vysoká závažnost advisory - WordPress vývojové prostředí

`integrations/wordpress/package.json:21` používá `@wordpress/env` 12.0.0. Jeho nepřímé závislosti obsahují:

| Balíček | Nyní | Minimální oprava | Nález |
| --- | --- | --- | --- |
| `isomorphic-git` | 1.37.6 | 1.38.6 | 1 high a 2 moderate advisories: zápis mimo pracovní strom přes symlinky/path traversal a DoS |
| `fast-xml-parser` | 5.11.2 | 5.12.0 | 1 low advisory: kvadratická spotřeba CPU |

Důkazy: `integrations/wordpress/pnpm-lock.yaml:890` a `:739`. [isomorphic-git high advisory](https://github.com/advisories/GHSA-9qw7-j9xw-fv9c), [path traversal](https://github.com/advisories/GHSA-cw2g-2vwq-88w6), [DoS](https://github.com/advisories/GHSA-96wc-2m84-2cj7), [XML parser](https://github.com/advisories/GHSA-474x-hrwr-fgx4).

Jde o devDependencies pro WordPress testovací prostředí. Nález neznamená, že publikovaný PHP plugin obsahuje tuto JavaScriptovou knihovnu. Zpracování nedůvěryhodného Git repozitáře ale může ohrozit vývojový nebo CI stroj.

Registr nyní nabízí `@wordpress/env` 12.1.0. Nejprve prověřit jeho závislosti; nelze předpokládat, že samotné zvýšení této verze odstraní nález. `@wp-playground/storage@3.1.60` totiž připíná `isomorphic-git` přesně na 1.37.6, takže prosté obnovení lockfile nemusí stačit. Preferovat opravenou nadřazenou knihovnu; případný úzký override ověřit přes `test:dependencies` a WordPress kontrakty.

## 4. Střední závažnost advisory, nižší doložená expozice - fflate

- `supabase/functions/_shared/ticketBatchExports.ts:2` a odpovídající test importují `fflate@0.8.2`.
- [GHSA-px8p-9vwx-vf98 / CVE-2026-45820](https://github.com/advisories/GHSA-px8p-9vwx-vf98): `unzipSync` může při chybném ZIP64 archivu uvíznout v nekonečné smyčce. Opraveno v 0.8.3.
- Provozní export používá `zipSync`, rozbalování bylo nalezeno v testu nad vlastním exportem. Přímá cesta k útoku přes nahraný archiv zde nebyla prokázána.
- Doporučení: oba explicitní importy na 0.8.3, aktualizovat lockfile a spustit test exportu. Lockfile již obsahuje i 0.8.3 pro jinou závislost; přítomnost opravené kopie neřeší explicitní import 0.8.2.

## 5. Nativní schránka - lokální Rust závislosti

Dart používá lokální override `packages/super_native_extensions`. Jeho existující `rust/Cargo.lock` obsahuje následující nálezy. Tento lockfile je ignorovaný Gitem; výsledky se týkají lokálního grafu, nikoli automaticky binárek dodaných uživatelům. `rust/cargokit.yaml` navíc umožňuje podepsané předkompilované binárky, jejichž obsah nebyl analyzován.

| Balíček | Lokálně | Oprava nebo postup | Advisory / rozsah |
| --- | --- | --- | --- |
| `bytes` | 1.6.0 | >=1.11.1 | [RUSTSEC-2026-0007](https://rustsec.org/advisories/RUSTSEC-2026-0007.html), integer overflow a memory corruption; větev JNI |
| `idna` | 0.5.0 | >=1.0.0 přes kompatibilní `url` | [RUSTSEC-2024-0421](https://rustsec.org/advisories/RUSTSEC-2024-0421.html), nesprávné zpracování domén |
| `time` | 0.3.36 | >=0.3.47 | [RUSTSEC-2026-0009](https://rustsec.org/advisories/RUSTSEC-2026-0009.html), stack exhaustion při parsování; přes `simple_logger` |
| `anyhow` | 1.0.86 | >=1.0.103 | [RUSTSEC-2026-0190](https://rustsec.org/advisories/RUSTSEC-2026-0190.html), undefined behavior v `downcast_mut`; build dependency |
| `rand` | 0.8.5 | >=0.8.6 v řadě 0.8 | [RUSTSEC-2026-0097](https://rustsec.org/advisories/RUSTSEC-2026-0097.html), problém při reentrantním použití generátoru z vlastního loggeru |
| `glib` | 0.17.10 | >=0.20.0, koordinovaně s GTK | [RUSTSEC-2024-0429](https://rustsec.org/advisories/RUSTSEC-2024-0429.html), unsound iterátory; linuxová větev |
| `atty` | 0.2.14 | odstranění/náhrada přes `simple_logger` | [RUSTSEC-2021-0145](https://rustsec.org/advisories/RUSTSEC-2021-0145.html), možné nezarovnané čtení na Windows; také neudržovaný balíček |
| `proc-macro-error` | 1.0.4 | náhrada přes nadřazené GTK závislosti | [RUSTSEC-2024-0370](https://rustsec.org/advisories/RUSTSEC-2024-0370.html), upozornění na ukončenou údržbu |
| `pin-utils` | 0.1.0 | náhrada přes nadřazené futures závislosti | [RUSTSEC-2026-0441](https://rustsec.org/advisories/RUSTSEC-2026-0441.html), upozornění na ukončenou údržbu |

Poslední dvě položky jsou údržbová upozornění, nikoli doložené bezpečnostní exploity. Ani samotné advisories typu unsoundness nedokazují dosažitelnou chybu ve Festapp. Doporučení: aktualizovat kompatibilní Rust graf a správně spravovat jeho reprodukovatelnost; zásah do GTK vyžaduje samostatné posouzení. Ověřit skutečné knihovny pro Android/iOS a používané desktopové cíle.

## Pokrytí a výsledky bez nálezu

- `pnpm audit --json`, pnpm 11.24.0, všech 11 verzovaných JavaScriptových lockfiles: 10 bez nálezu, WordPress 4 advisories. Zahrnuto produkční i vývojové větvení.
- Bez nálezu: `web_client`, `tools/festapp`, všech pět workerů, Wix, image-migration a platform_updates.
- OSV API, přesná jména/verze z lokálních lockfiles: 412 kombinací Pub, 83 npm z Deno včetně identifikovatelných esm.sh importů, 204 crates.io a 102 RubyGems. Bez nálezu v Pub a RubyGems. Počty jsou unikátní kombinace ekosystém/jméno/verze, ne součet instalací. Jsou zahrnuty i lokální pomocné/example lockfiles; cache, build a `.private` byly vyloučeny.
- `deno audit --lock supabase/functions/deno.lock --frozen`: 1 moderate, `fflate`. Pouze čtení, bez `--fix`.
- Runtime piny mají platný formát 11 immutable images. `node automation/hetzner-supabase/runtime/verify-pins.mjs --online` ale skončil na driftu Docker Compose: připnuto 5.5.0, upstream 5.7.0. Další online kontroly tento příkaz už nevykonal. Samotný drift neprokazuje CVE.
- Dependabot má týdenní kontroly webu, čtyř aktivních workerů a GitHub Actions. Chybí například Dart, Rust, Fastlane, WordPress, Wix, operator a serverové images. V `.github/workflows` ani `automation/ci` nebyl nalezen samostatný audit závislostí jako CI gate. Doporučuji doplnit monitoring podle ekosystému a používat jej pro prioritizaci aktualizací.

## Hranice závěru

Tento audit není kompletní SBOM/CVE sken všech release artefaktů. Není ověřen živý server, systémové balíčky uvnitř kontejnerů, host OS, úplný Android Gradle tranzitivní graf, CocoaPods/native framework binárky, Flutter/Dart SDK ani obsah podepsaných předkompilovaných Rust knihoven. Git/path závislosti a libovolné vzdálené Deno URL mají omezené pokrytí advisories. Nulový výsledek v databázi nezaručuje nepřítomnost zranitelnosti.

Doporučené pořadí: ověřit serverový PostgreSQL a připravit jeho bezpečnou opravu; aktualizovat Node v CI a WordPress nástroje; provést malý update fflate; samostatně vyřešit nativní Rust graf a průběžný monitoring. Nic z toho nebylo tímto auditem nasazeno.

## Integrace na aktuální main

Příprava vychází z `88f856e59` (aktuální upstream při zahájení integrace), nikoli ze starého lokálního pracovního stromu původního auditu. Tento main už obsahuje opravený `isomorphic-git` a testy nebezpečných checkoutů z `f62ab0124`; jsou zachované. Doplněna je oprava XML parseru a fflate. Node 22 ve všech workflow a společném CI kontraktu je sjednocený na bezpečnostní vydání 22.23.4. Původní auditní evidence výše zachycuje starší lokální stav. PostgreSQL a Rust se v této integraci nemění.
