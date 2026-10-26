# Implementace: Co je nového / What's new

Pracuj v `/Users/miakh/source/festapp`. Nejdřív přečti AGENTS.md, CLAUDE.md,
`docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/platform-updates-plan-2026-10-26.md`

Implementuj jeho tři vlny v pořadí, verification: standard. Výsledkem jsou
veřejné aktualizace platformy pro pořadatele: jeden repozitářový zdroj, jedna
identita každé změny, český a anglický text, stabilní detaily, přehledy, kanonický jazyk
podle stávajícího webu/aplikace a veřejný JSON pro budoucí upozornění. Propoj web a administraci.

Použij současnou společnou marketingovou/release pipeline a jeden výsledný
registr veřejných URL pro renderer, Worker, sitemap, verifikaci a PWA. Zachovej
eventové news i soukromé centrum upozornění. Nic automaticky nerozesílej,
nevytvářej CMS, databázovou migraci ani druhou anglickou kopii aplikace.

Zachovej rozsáhlé souběžné změny pracovního stromu. Pokud aktuální kód vyvrátí
fakt v plánu, aktualizuj plán s konkrétním podkladem a uprav dotčenou vlnu.
Nenechávej placeholdery, duplicitní vlastníky dat ani skryté fallbacky.
Neověřený obsah ponech jako draft; testovací příspěvky nepublikuj.

Spusť cílené kontroly uvedené v plánu, respektuj pnpm 11.24.0 a limit jednoho
Flutter úkolu. Dokončení vyžaduje fungující obě lokalizace, shodu všech
veřejných výstupů, vyloučení draftů i po regeneraci a fungující navigační odkazy.
Neprováděj nezávislý audit nebo delegaci implementace bez dalšího zadání.

Tento prompt není autorizací k zahájení práce. Po samostatném zadání implementace
zpracuj lokální změny; commit/push, produkční nasazení, zřízení anglického tenantu
a odesílání zpráv vyžadují samostatnou autoritu. Na konci stručně uveď změny,
výsledek ověření a případné přesné dosud neprovedené provozní kroky.
