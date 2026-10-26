# Vydání českého Joomla modulu

Rozsah: **vstupenky.online 1.0.1**, soubor `vstupenky.online.zip`.
Globální varianta není předmětem veřejného vydání. GitHub release a Joomla
Extensions Directory jsou samostatné distribuční kroky.

## Povinná brána před zveřejněním

1. Sestavit `python3 scripts/package.py` a připravit `python3 scripts/stage-release.py`.
   Výstup je uchovaný pod SHA-256 v `artifacts/sha256/` a `dist/sha256/`;
   dříve ověřené ZIPy se nesmějí přepisovat pod jejich neměnnou cestou.
2. Se spuštěnými izolovanými CMS a fixture provést `python3 scripts/verify.py`.
   Úspěšný wrapper uloží `evidence/verification.json` s hashi přesných vstupů,
   vydávaného ZIPu a každého receiptu. Neúspěšný běh staré schválení neobnoví.
3. Kritik zkontroluje finální změny a výsledek této sady. Jeho
   `evidence/critic.json` musí obsahovat `status: APPROVED`, `zip_sha256`,
   `verification_sha256` a prázdné `unresolved_release_blockers`.
4. `python3 scripts/release-gate.py --seal` vytvoří `dist/RELEASE.json`.
   `python3 scripts/release-gate.py` musí projít bezprostředně před publikací.
   Gate odmítne změněné zdroje, testy, důkazy, dokumentaci, feed i ZIP.

Lokální updater test používá skutečný Joomla discovery/download/installer a
checksum stejného ZIPu přes vlastní HTTP fixture. Záměrné snížení verze v
metadatech je testovací podmínka, nikoli historický veřejný release. Po
publikaci musí následovat kontrola skutečných veřejných URL.

## Veřejný ZIP a aktualizační kanál

Veřejný repozitář: `festappnet/festapp`. Kanonické zdroje v `main`.
Stabilní feed je `integrations/joomla/updates/vstupenky-online.xml`, veřejně
přístupný přes `raw.githubusercontent.com`. Jeho obsah odkazuje na neměnný tag
`joomla-vstupenky-online-v1.0.1` a asset `vstupenky.online.zip` s SHA-256.

Před prvním pushem načíst aktuální `origin/main`, založit izolovaný checkout
z jeho hlavy a přenést jen vlastní Joomla změny. Zkontrolovat případné intervenující
commity; nesahat na cizí rozpracovaný checkout ani ostatní tenant větve.
Publikovat ověřený zdroj do autoritativního `main` podle pravidel repozitáře.
Pokud ochrana větve vyžaduje review, použít PR.

Autorizované veřejné vydání provést jako GitHub release nad přesným schváleným
zdrojovým commitem. Nahrát pouze zapečetěný český ZIP a checksum sidecar;
poznámky obsahují podporované verze, postup instalace a odkaz na dokumentaci.
Před zveřejněním se zdroje a artefakty zmrazují. Distribuční ZIP obsahuje zdrojový
PHP kód a plné znění GPL; na licenci modulu se nevztahují omezení účtu služby.

Po skutečném zveřejnění:

```sh
python3 scripts/release-gate.py --public
```

Tento příkaz stáhne skutečný release asset i stabilní feed a porovná bajty
se schváleným hashem. Dále ověřit registraci/načtení veřejného update kanálu
v čisté izolované Joomle. Teprve příjmové receipty dovolují uvést, že ZIP a
kanál byly veřejně vydány. Bez nich je stav pouze `READY_TO_PUBLISH`.

## Případné podání do JED

[Oficiální checklist](https://extensions.joomla.org/support/knowledgebase/submission-requirements/jed-entries-checklists/)
a [podmínky](https://extensions.joomla.org/community/terms-of-service/)
byly zkontrolovány 2026-10-26. C2.4 dovoluje GPL doplněk vyžadující SaaS účet;
zařazení Free/Paid vychází i z aktuálního modelu služby. D2.6 vyžaduje update
server. Schválení lokálním kritikem není schválením katalogu.

Podání vyžaduje vlastníkem autorizovaný účet/podání, odpovídající název,
veřejnou přímou download/dokumentační stránku a podporu. Pokud bude uveden demo
odkaz, musí jít o neprodukční demo. Neuvádět živou zákaznickou akci jako katalogové
demo. Katalogové schválení, přidělení identity a datum přijetí nejsou garantované.
Odeslání do JED je samostatný autorizovaný krok, který tento návod neprovádí.
