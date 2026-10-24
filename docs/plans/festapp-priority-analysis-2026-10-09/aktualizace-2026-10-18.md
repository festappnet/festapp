# Aktualizace priorit Festapp - 18. 10. 2026

Podklad: čerstvý fetch `origin/main`, přesný snapshot `6d9b5be58d6e331b5dc645c07a9f397d317c9334`. Lokální větev `feat/occasion-setup-wizard-20261007` má stále HEAD `eb2304724`; její rozpracované změny nejsou důkazem začlenění do main. Upraven je pouze tento přehled a jeho podklady. [Předchozí pohled](index-2026-10-17.html) i [původní pohled](index-2026-10-09.html) zůstávají zachované.

## Co je nově doložené

- **Průvodce už má webový vstup.** `194f37a5f` přidává volbu „Vytvořit krok za krokem“ v nabídce založení akce, ovládanou `FESTAPP_OCCASION_SETUP`; současný `automation/project.conf` ji zapíná. Koncepty lze otevřít a zahodit (`122d91df4`, `10ae2a0d6`). Nahradit starý závěr „záměrně skrytý“. Stále není doložená celá cesta nového pořadatele až k první objednávce ani její současná dostupnost na produkčním tenantovi.
- **Volba produktů při skenu má implementaci.** `61a8e0c93` a následné opravy zahrnují serverové all/none/selected produkty a pole, nastavení s náhledem, kameru, ruční/HID vstup a trvalou offline frontu. [Implementační evidence](https://github.com/festappnet/festapp/blob/6d9b5be58d6e331b5dc645c07a9f397d317c9334/docs/plans/web-scanner-implementation-2026-10-18.md) popisuje SQL, skutečné IDB a syntetický video stream. Nedokládá produkční release ani fyzickou kameru/HID. Spotřeba jednotlivého produktu zůstává jiný požadavek.
- **Ověřování pořadatelů má implementaci.** `ddad66016` a následné commity přidávají právní profil, revize, audit, ruční schválení/odebrání, veřejné zobrazení, ARES a oznámení administrátorům. [Evidence](https://github.com/festappnet/festapp/blob/6d9b5be58d6e331b5dc645c07a9f397d317c9334/docs/operations/organization-verification/IMPLEMENTATION-2026-10-18.md) a [provozní pravidla](https://github.com/festappnet/festapp/blob/6d9b5be58d6e331b5dc645c07a9f397d317c9334/docs/operations/organization-verification/README.md) neprokazují produkční migraci a release. ARES sám nikoho neschvaluje. Vizitka/kontakt zůstává částečná kvůli neověřenému úplnému pokrytí původního zadání.
- **Migrace úložiště a vyřazení zdrojů jsou dokončené.** Nejnovější [provozní doklad](https://github.com/festappnet/festapp/blob/6d9b5be58d6e331b5dc645c07a9f397d317c9334/docs/operations/security-remediation-20261016/storage-r2-retirement-execution-20261018.md), zejména závěrečná sekce, potvrzuje zrušení tří zdrojových bucketů i omezení backup readeru. Skutečná izolovaná obnova ověřila 2 817 objektů, 5 226 aktuálních R2 referencí a nula chybějících/neshodných referencí. Starých 50 odkazů už neuvádět jako otevřený blocker. Zůstávají limity fyzického offline ověření map a úplného cold-start incident RTO.
- **Kapacitní rozhodnutí je konkrétnější.** [Nová evidence](https://github.com/festappnet/festapp/blob/6d9b5be58d6e331b5dc645c07a9f397d317c9334/docs/operations/security-remediation-20261016/storage-r2-capacity-followup-20261018.json) uvádí konzervativní deficit 735,8 MiB na 4GB hostu před bezpečnostní rezervou navíc, nebo 223,8 MiB při nenasazené menší admin variantě. Jde o součet nesouběžných vzorků a rezerv, nikoli měření souběžného OOM nebo důkaz nutnosti koupit více RAM. Otevřené jsou globální Edge admission, souběh zálohy a reprezentativní editace ve Studiu.

## Doporučené pořadí

1. Ověřit první vlastní akci přes dostupný vstup průvodce, existující demo, zveřejnění a první objednávku. Měřit potřebu podpory.
2. Podle skutečné poptávky dodat jeden konkrétní scénář podmíněné nabídky; kapacitu a náhradníky znovu nestavět.
3. Vymezit a dokončit pozvání týmu do Unit se správnými rolemi.
4. Souběžně uzavřít konkrétní release podmínky a kapacitní rozhodnutí. Potvrzená závažná bezpečnostní chyba má přednost před růstovým pořadím.
5. Využít existující veřejný web a malý měřitelný pilot Plesuj. Jeho samostatný pracovní strom dnes nebyl hodnocen.

## Nové karty a hranice tvrzení

Přehled má 43 karet: 10 hotových na main, 10 částečných, 18 otevřených a 5 k upřesnění. Výchozí pohled skrývá hotové implementace, nikoli všechny provozní návaznosti. Přibyly dvě karty:

- **Release podmínky.** [Konsolidovaný release](https://github.com/festappnet/festapp/blob/6d9b5be58d6e331b5dc645c07a9f397d317c9334/docs/operations/consolidated-release-2026-10-18.md) dokládá jedenáct webů ve verzi `0.20.257+741`. Neprokazuje nasazení pozdějšího scanneru nebo právního profilu. Read-ACL/default fáze vyžadují konkrétní kompatibilitu podporovaných mobilních klientů; CSP zůstává Report-Only. Historická autorizační tvrzení v těchto podkladech nerozšiřují rozsah tohoto úkolu.
- **Platební reference.** [Festapp-owned reference](https://github.com/festappnet/festapp/blob/6d9b5be58d6e331b5dc645c07a9f397d317c9334/docs/operations/banksync/FESTAPP-PAYMENT-REFERENCES-2026-10-18.md) mají implementaci a lokální důkazy souběhu i obnovy. Import historie a aktivace konkrétní organizace zůstávají samostatné kroky; nelze je zaměnit za sloučení kódu.

Jde o jeden cílený průzkum změn od předchozího snapshotu `8b1420ea1`, nikoli nové úplné QA všech původních požadavků. Nezměněné otevřené karty znamenají chybějící důkaz dokončení, ne prokázanou absenci funkce. Produkce dnes nebyla samostatně dotazována, nebyly získány obchodní metriky ani provedeny migrace, nasazení či publikace. Priority jsou produktový úsudek. Autoritativní soubory jsou odkazovány na pevný commit; jejich lokální kopie mohou být starší.
