# Provést diagnostiku pomalého ticket RPC

> Historical plan or dated evidence. Statuses, versions, authorization and pending steps below apply to the recorded phase, not automatically to today. Use [current documentation](../../README.md) for operating procedures; archiving does not close unverified gates.


Stav: dokončeno. Diagnostika i následně autorizovaný release jediného indexu
jsou hotové, main `36228be39`, canonical migration `20261016010000`.
Tento původní prompt znovu nespouštěj jako migraci. Nejprve čti výsledek
`docs/operations/spots-ticket-index-release-2026-10-15.json` a aktuální stav
autoritativního plánu. Níže je historické zadání, nikoli nová autorizace práce.

Pracuj v `/Users/miakh/source/festapp` podle pravidel repozitáře.
Přečti celý autoritativní plán:

`docs/archive/plans/ticket-details-performance-plan-2026-10-15.md`

Použij verification: standard a skill festapp-backend-access. Proveď jen dosud
nevyřešené části diagnostických vln 1 a 2 a vytvoř návrh z vlny 3.
Neopakuj již zaznamenaná měření bez důvodu. Přečti také současnou evidenci
`docs/operations/ticket-details-performance-2026-10-15.md` a JSON výsledky.
Zpomalení objednávky 700 vstupenek je již reprodukované na produkci (1,82-1,89 s);
lokální simulace již oddělila oba indexy ve 32 variantách a regresní test
ověřil šest pořadí produktů (cílená Deno sada 6 passed). Samotný spot lookup
index přináší hlavní zlepšení, samotný order lookup ne. Nepřidávej druhý index
ani nepřepisuj SQL bez dalšího konkrétního důkazu. Při samostatném zadání
implementace zbývá připravit migraci spot indexu a ověřit write/rezervační
kontrakt na izolované plné databázi; produkční zásah tento prompt neautorizuje.
Malé objednávky organization 1
byly změřeny na 4-8 ms, tělo SQL odpovídá main a historický PostgREST čítač
v pozorovacím okně nerostl. Tato původní malá sonda sama problém nevylučovala;
pozdější sonda organization 3 jej na velké objednávce potvrdila.
Připsání původního historického agregátu konkrétní události neprezentuj jako
prokázané a neblokuj jím další lokální experimenty s již reprodukovaným problémem.
Rozliš historický průměr 1,8 s od současného provozu, SQL od PDF a velikosti
vstupů. Pro každý další tenant ověř jeho canonical identitu. Respektuj read-only
transakce, timeouty, ověření cíle a zákaz produkčních vedlejších účinků.
Neresetuj globální statistiky, neposílej e-maily ani neexportuj tajné klíče či PII.

Opravu z vlny 4 implementuj jen při samostatném zadání. Tento prompt
neautorizuje produkční změny, migraci, release, commit/push ani publikaci
rozpracované optimalizace testů. Nevytvářej druhé RPC ani kompatibilitní cestu.
Pokud evidence vyvrátí předpoklad plánu, oprav příslušné tvrzení přímo v plánu.

Odevzdej příčinu nebo její vyvrácení, srovnatelná měření, navrženou nejmenší
změnu a přesný stav toho, co zůstává neprovedené.
