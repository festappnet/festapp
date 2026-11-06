# Realizace dotažení platebních konektorů

Pracuj v `/Users/miakh/source/festapp`. Přečti platné AGENTS.md, CLAUDE.md,
`docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/payment-provider-hardening-plan-2026-11-06.md`

Použij `verification: standard`. Realizuj vlny 0-5 v jejich pořadí a aktualizuj
jejich stav a výsledkový receipt. Zachovej existující bankovní/Stripe fakta,
historii a cizí změny v silně rozpracovaném workspace.
Zmraz migrační vstupy před editací kanonického SQL. Chybějící account evidence
ve vlně 0 zaznamenej jako unknown a pokračuj v nezávislých vlnách 1-3 a lokálním
migračním ověření; skutečný sandboxový acceptance tím nenahrazuj.

Výsledkem jsou nezávislé provider projekce, explicitní uložená volba poskytovatele,
typovaný recovery kontrakt bez předstírané jistoty, jeden SQL owner finančních
důsledků, obecně provozovatelná obnova a skutečný druhý sandboxový integrační
důkaz. Neopisuj Stripe business logiku do dalšího adaptéru a nepřepisuj všechny
Stripe tabulky do nového ledgeru. Dodrž deletion ledger a testy fresh i populated
upgrade. Fake konektor není náhradou reálného sandboxového důkazu.

Pokud aktuální důkaz vyvrátí předpoklad plánu, oprav plán a příslušnou vlnu.
Nezaváděj bokem druhý model ani skryté fallbacky. Chybějící oprávnění sandboxu
přesně zaznamenej; pokračuj v nezávislých úlohách a neoznačuj závislou vlnu za
dokončenou. Podporu marketplace neodvozuj od běžného merchant checkoutu.

Existující service-fee source je jediný owner příjmu platformy. Automatické
účtování či rozdělování provize, implicitní 4 %, multi-organizer platby a nové
zálohy nejsou součástí tohoto pověření. Dodrž E1/E2 a navazující finanční gate.

Spusť přiměřené cílené kontroly uvedené v plánu. Dodrž pnpm, jedinou souběžnou
Flutter/Dart úlohu a disposable DB. Případný browser deleguj Terra a respektuj
Panerelay, vedlejší autorizovanou kartu a zákaz přepínání uživatelových oken.

Tento soubor je realizační zadání, nikoli sám o sobě nové pověření ke spuštění.
Produkční migrace, aktivace poskytovatele, ostré finanční operace, nasazení,
commit a push vyžadují odpovídající navazující uživatelský pokyn. Po realizaci
odevzdej stručný výsledek, ověřené brány, zrušené duplicity, přesné blockery
a rozdíl mezi lokální připraveností a skutečně nasazeným stavem.
