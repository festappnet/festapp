# E-shopové konektory Festappu - schválená rozhodnutí a návrh

Historický výzkum a návrh z 29. 10. 2026, začleněný 6. 11. 2026. Nejde o implementaci ani novou autorizaci realizace. Tehdejší záznamy o neodeslání jsou překonané [stavem potvrzeným vlastníkem 1. 11.](shoptet-partner-onboarding-2026-10-26.md): návrh byl odeslán, čeká se na odpověď a další podání se neposílá.

29. 10. 2026. **Vlastník schválil čtyři rozhodnutí níže.** Schválení určuje architekturu, první rozsah a pořadí ověřování; není důkazem proveditelnosti Shoptetu ani pokynem k nasazení. Implementace, sandboxové objednávky ani nasazení neproběhly.

## Schválená rozhodnutí

Vlastník v konverzaci 29. 10. 2026 výslovně potvrdil:

1. Jedno společné jádro Festappu s adaptéry jednotlivých e-shopů.
2. Nejprve ověřit klíčové garance Shoptetu, teprve poté větší implementace backendu.
3. Při nejasném výsledku kapacitu držet do vyjasnění, i za cenu dočasně nižší dostupnosti.
4. Základní rozsah: Shoptet, CZK, jedna akce na košík, běžná kapacita i sedadla, platba v e-shopu a QR z Festappu.

## Schválený směr

**Jeden společný konektor napojený na současný Festapp. Shoptet dodá jen svůj adaptér.** Další e-shop se stejnými ověřenými schopnostmi využije stejné rezervace, objednávky, finanční projekci a doručování.

Pro pořadatele to bude jedno nastavení u jeho akce: připojit e-shop, přiřadit produkty ke vstupenkám a sledovat stav. Pro kupujícího nativní košík a platba e-shopu; pro vstup pořád stejná QR vstupenka Festappu. Tatáž kapacita bude sdílená s našimi přímými formuláři a embedy.

Schvaluje se cílové rozdělení odpovědnosti, první rozsah a pořadí ověřování. Tento přehled sám nic nespouští. Cena doplňku, procento servisního poplatku a partnerská smlouva nejsou tímto technickým návrhem dohodnuté.

## Jaké budou tři části

| Část | Co má dělat | Co z ní nesmí vzniknout |
| --- | --- | --- |
| Extension a adaptér konkrétního e-shopu | Přeložit jeho přihlášení, košík, potvrzení a události. Zobrazit společný výběr v jeho prostředí. | Kopie skladu, výpočtu kapacity, plateb nebo vlastní generátor vstupenek. |
| Společný Commerce Connector | Řídit rezervaci, nabídku, opakované události, převzetí objednávky a dohledání nejasného výsledku. | Samostatný druhý ticketingový systém. |
| Současné doménové jádro Festappu | Rozhodnout o kapacitě, evidovat objednávku a finance, vytvořit QR/PDF a doručit je existující frontou. | Provider-specific podmínky roztroušené v každém formuláři a SQL výpočtu. |

Společné je také nastavení a klientská session. Plánek se nekreslí znovu pro každou platformu. WordPress/Wix embedy, Make a Stripe zůstanou ve svých dosavadních rolích; spojování do jedné rodiny neznamená jejich plošný přepis.

## Co jsem při druhém průchodu změnil

1. **Nejdřív ověřit platformu, pak větší zásahy.** Minimální kontrolovaný Shoptet experiment musí prokázat vazbu nabídky na košík, nepřijetí starého kódu a bezpečný konec rezervace před rozsáhlejším rozšířením SQL. Předejdeme implementaci nad nepodporovanou vlastností.
2. **Obecná rezervace nezná Shoptet ani commerce nabídku.** Inventory vlastní jednotky a jejich obsazenost; commerce nabídka odkazuje na obecnou rezervaci. Ceny, tokeny a mapování e-shopu se neprotlačí do skladového modelu.
3. **Zpřesněný slib dalších konektorů.** Další e-shop přidá adaptér, pokud splňuje stejný kontrakt. Architektura nepředstírá, že každá budoucí platforma nutně umí stejný checkout. Jiný obchodní model vyžaduje výslovné rozšíření společného kontraktu.
4. **Viditelné provozní omezení.** Nejasný výsledek může místo dočasně blokovat. Už zveřejněný výběr se bez prokázané bezpečné revokace nebude měnit za chodu. Refundace nebo změna mimo automatický profil se musí detekovat a doloženě vyřešit, nikoli ignorovat.

Jde o vlastní druhý průchod návrhu, nikoli tvrzení o nezávislém auditu nebo provedených integračních testech.

## Jak proběhne normální nákup

1. Kupující si otevře formulář nebo e-shop. Samotné otevření žádná místa neblokuje.
2. Zvolí vstupenky. Server ověří skutečný košík e-shopu a Festapp rezervuje konkrétní společnou kapacitu.
3. Adaptér připraví platnou nabídku pro nativní checkout. Její kontrola na straně e-shopu musí projít ověřením platformy.
4. E-shop přijme objednávku. Existující objednávka Festappu převezme rezervovaná místa bez jejich uvolnění a druhého odečtu.
5. Ověřená úhrada spustí běžné vydání a doručení QR vstupenek Festappu.

Když má tentýž košík otevřený ve dvou záložkách, mají společný serverový stav a revizi. Starší okno nesmí přepsat novější výběr. Jiný telefon může být jiný košík; stejný e-mail se nepoužije jako náhražka identity rezervace.

## Jak se systém zachová při problému

| Situace | Chování, které má návrh zajistit |
| --- | --- |
| Dva zákazníci chtějí poslední místo z různých kanálů | Jedna kanonická databáze přidělí místo jen jednomu. Druhý nedostane platný checkout na totéž místo. |
| Otevřený formulář ukazuje starší dostupnost | Rozhodne nové serverové ověření; zákazník uvidí konflikt a neztratí nesouvisející vyplněné údaje. |
| Nabídka vyprší, ale objednávka byla přijata těsně předtím | Místo zůstane chráněné. Worker dohledá skutečný výsledek a přiřadí ho objednávce. |
| Ztratí se odpověď při zveřejnění nabídky | Stav je nejasný, nepřijde slepé opakování s novým nákupem. Původní alokace zůstává blokovaná do srovnání. |
| Webhook dorazí dvakrát nebo po reinstalaci | Stejná obchodní identita vrátí stejnou objednávku; nevznikne druhá platba ani vstupenka. |
| Pořadatel změní kapacitu nebo chce místo ručně uvolnit | Existující claim se nedá obejít běžnou úpravou. Nejdřív se bezpečně vypořádá rezervace nebo objednávka. |
| E-shop přestane poskytovat potřebný přístup | Zastaví se nové nabídky, rozpracované alokace zůstanou chráněné a obsluha uvidí důvod. Vydané QR nadále používají běžné odbavení. |

To jsou cílová pravidla. Jejich dodržení se musí prokázat testy; tato tabulka není jejich výsledek.

## První rozsah

První adaptér Shoptet, český trh, CZK a jedna akce na košík. Návrh zahrnuje běžnou kapacitu i konkrétní sedadla; experiment začne jednoduchým případem a stejné garance se ověří i pro sedadla. Platba probíhá přes podporovanou metodu e-shopu.

Více měn, zálohy, libovolné kombinace fyzického zboží a vstupenek nebo automatické složité refundace nejsou slibované jako hotová první verze. Události mimo podporovaný profil se musí rozpoznat a vyřešit; neschovají se pod úspěšný import. Omezení košíku musí být ověřená na rozhodující serverové straně.

Tenký extension neznamená nulovou práci v backendu. Bezpečné společné rezervace musí respektovat i současné změny kapacity, admin operace a čtecí projekce. Proto je před nimi levný test proveditelnosti.

## Co je ověřené a co ještě potřebuje důkaz

| Úroveň | Dnešní stav |
| --- | --- |
| Současný Festapp | Ve zdroji existují rezervace sedadel, zamykání kapacity, kanonické objednávky, finanční projekce a doručování. Živá produkce nebyla touto prací přetestovaná. |
| Veřejné podklady Shoptetu | Doložené shipping-request API, ověřovací kód, dokumentovaná expirace a frontendová obsluha; také kandidátní nastavení omezení doprav. |
| Vlastní Shoptet sandbox | Dosud neproběhl. Chybí skutečný důkaz pro změnu košíku, staré okno, obcházející dopravu a konečný výsledek při expiraci. |
| Nový společný konektor | Navržený; kód, migrace a provoz zatím nevznikly. |

Nejslabší místo stále není naše vlastní SQL, ale to, zda rozhodující Shoptet kontrakt skutečně vynutí správnou rezervaci. Pokud test tuto podmínku nepotvrdí, větší implementace se zastaví a výsledek se předloží k rozhodnutí. Nevznikne automatický přechod na kvóty nebo jiný checkout.

## Doporučené pořadí práce

1. Malý společný interface, první adaptér a testovací harness bez živého prodeje.
2. Při dostupném vlastním oprávněném sandboxu ověřit klíčový kontrakt Shoptetu.
3. Až poté společná rezervace v Inventory SQL a napojení na stávající objednávky a finance.
4. Jednotná klientská session a nastavení v administraci; úplné testy přes oba prodejní kanály.
5. Samostatně připravený a schválený pilot jedné akce po splnění podmínek.

Čtyři rozhodnutí výše jsou schválená a jsou výchozím bodem další práce. Nejde o potvrzení partnerství ani hotového doplňku. Zákaz zpráv a podání trvá; v této revizi neproběhla žádná implementace, sandboxová mutace nebo produkční operace.

## Detailní podklady

- [Společná architektura a stavové automaty](../architecture/commerce-connectors.md)
- [Konkrétní Shoptet adaptér](../architecture/shoptet.md)
- [Realizační plán a dotčená místa](commerce-connectors-plan-2026-10-29.md)
- [Připravené samostatné ověřovací scénáře](shoptet-self-verification-2026-10-29.md)
- [Veřejné API a frontend důkazy](shoptet-direction-evidence-2026-10-29/public-contract.json)
