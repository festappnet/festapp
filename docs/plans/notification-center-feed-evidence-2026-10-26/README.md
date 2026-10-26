# Notification feed: finální lokální evidence

Sjednoceno 26. 10. 2026 nad origin/main `85c655137c9c2472b402aaed6fdbf0fe24501d24`,
se zachováním lokální opravy `0eff86e7b`, změn po snapshotu `9ea59b28d4`,
platform updates včetně `0f081e8d5` a nového notification feedu.
Výsledek je necommitovaný. Produkce, ostatní worktrees a prod větve nebyly změněny.

## Ověření finální kombinace

- Canonical client runner: 2340 případů (251 core, 87 adapters, 2002 Flutter), 2 přeskočené, 0 selhání; architecture a semantic inventory PASS. [Receipt](receipts/unified-client-summary.json).
- Po přenesení do původního adresáře: dalších 389 Flutter PASS, zdroje shodné s otestovaným worktree.
- Opačné pořadí shared Flutter: 389 PASS; dotčená česká navigace: 9 PASS.
- SQL: 16 souborů PASS; skutečný souběh: 6 testů PASS. Čistý canonical bootstrap i dopředná migrace na izolovaném Supabase PASS.
- Web: 783 případů, 753 PASS, 30 přeskočených; poslední příchozí help změna dalších 20 PASS; web build PASS.
- Automation: 42 PASS. Workers: 118 + 22 + 9 PASS, všechny typechecky PASS.
- Dart lib/test: 0 chyb, 18 existujících varování. Assembler --check a git diff --check PASS.

[Finální desktop](unified-desktop.png) a [finální mobil](unified-mobile.png)
jsou skutečná aplikace s lokálním Auth/REST/SQL na vlastním disposable tenantu.
Ověřeny ploché řádky, ruční/časové zavření, přes 30 položek a další stránka,
nové události bez automatického potvrzení, dvouvstupenková objednávka,
náhradník, storno a skutečná navigace na orderId=110.
E-mailový worker je pozastavený, produkční domény blokované.
Starší flutter-desktop/mobile a ostatní starší receipts dokumentují předchozí
lokální průchod (včetně mute/revokace); nenahrazují finální snímky.

## Zachování původní práce

Původní archiv a čerstvý archiv těsně před přenosem jsou v privátním adresáři
`/Users/miakh/festapp-cleanup-archives/20261026-notification-reconciliation/`.
164 konfliktních cest bylo rozhodnuto podle canonical ownerů a doloženého
nového záměru, nikoli hromadným ours/theirs. Ledgery jsou v receipts.
809 root-only souborů odpovídalo přesně uloženým starým Git verzím; jejich
canonical odstranění je zachováno. Dva staré organizer shell soubory nahrazuje
současný site_shell.mjs/site-header.html. Původní notifikační plán je zachován
jako historický podklad s výslovnou korekcí odstraněné aktivace.
Ignorovaný absolutní pubspec_overrides.yaml je archivován a vyřazen z aktivní
konfigurace, aby neobcházel sledované relativní vendor overrides. Přihlašovací
soubory zůstávají na místě. Žádné reset --hard, clean, commit, push ani release.

## Oprava vizuální regrese po vydání

Přepis feedu omylem nahradil novější incident UI ze zděděného main
(commit b0f07a4f3) starším plným errorContainer. Obnovena neutrální plocha
s jemným okrajem, zdůrazněný příjemce, červený důvod chyby a akce Detail.
Běžné řádky nyní následují vybraný preview.html: nadpis akce s oddělovačem,
typ a kontakt vlevo, kompaktní datum/čas vpravo, šipka pouze pro detail.
Na úzké šířce a při velkém textu čas přechází pod obsah. Počty míst mají
krátké CLDR tvary ve všech šesti jazycích. SQL, doručování, oprávnění a ack beze změny.

Skutečný vykreslený panel se syntetickými daty a reálnými překlady/ThemeConfig:
[světlý](restored-light.png), [tmavý](restored-dark.png), [mobil](restored-mobile.png).
Reprodukovatelný UI fixture: test/browser/notification_visual_preview.dart.
Zkontrolováno izolovaným headless prohlížečem; bez backendových volání.
