# Průvodce přípravou akce - praktický UX průchod

Datum: 2026-10-21. Hlavní závěr: průvodce umožní uložit konfiguraci, ale stále
nevede dost jasně od přípravy k prvnímu použitelnému prodeji. Největší přínos
bude mít dokončovací obrazovka s dalšími kroky a přístupnější nastavení vstupného.

## Co bylo skutečně ověřeno

Heuristický průchod očima nového pořadatele sousedského plesu: vytvořit akci,
zadat místo, nastavit vstupné 350 Kč, potvrdit místní testovací účet, projít
komunikaci a souhrn a zjistit, co udělat po dokončení. Nejde o studii s reálnými
uživateli; dopady na jejich chování jsou odborný úsudek, nikoli změřená data.

Prohlížeč běžel izolovaně a headless, na desktopu a při šířce 390 px. Testovaná
verze byla z novějšího worktree
`/Users/miakh/source/festapp-occasion-repair-main-20261021`, branch
`fix/occasion-setup-copy-followup-20261021`, základ `53c32c458` s rozpracovanými
opravami. Starší root checkout již nereprezentoval aktuální obrazovky.

Reálný Flutter entry `test/browser/occasion_setup_copy_repair_e2e.dart`, lokální
backend `festapp-occasion-repair-20261021` na 56931/56932, server 56980.
`AppConfig.isAppSupported=true`, organizace rovněž podporuje aplikaci.
Závěry o vstupu do průvodce a vzhledu vstupenky proto nejsou automaticky
přenositelné na variantu určenou pouze pro prodej vstupenek.

Použité zdroje: aktuální rozhraní a jeho zdrojový kód, dovednosti `ux-designer`
a `ui-ux-pro-max`. Výběr pravidel mířil na formuláře, zpětnou vazbu a srozumitelnost.
Neprováděl se úplný audit přístupnosti. Kvůli známému chování Flutter semantics
byly potřebné sémantické kliky a scrollování prvků do zobrazení; pohyb myší,
dragování a všechny fyzické hitboxy tento průchod necertifikuje.

## 1. Vysoká priorita: po dokončení chybí odpověď „co teď?“

**Pozorování:** po potvrzení kontroly a tlačítku Vytvořit událost přešla aplikace
na `/6g7cmr9m/admin/info/information`. Na mobilu i desktopu se zobrazila prázdná
tabulka s textem „Tabulka neobsahuje žádné položky“. Chybělo viditelné potvrzení
úspěchu, stav prodeje a přímý další krok pro formulář.

Lokální DB potvrdila vytvoření akce 196, `UX QA Sousedský ples`, cenu 350 Kč,
skrytou akci a zavřený formulář. Bezpečný neveřejný stav je správný. Pořadatel
ale potřebuje vědět, kde pokračovat, aby skutečně mohl začít prodávat.

**Doporučení:** po úspěchu zobrazit například:

> Akce je vytvořená. Zatím je neveřejná a prodej je zavřený.

Následovat mohou konkrétní akce „Zkontrolovat formulář“, „Nastavit otevření
prodeje“ a „Přejít do správy“. Veřejný odkaz označit stavem; samotné zkopírování
odkazu nesmí vytvářet dojem otevřeného prodeje. Automaticky nic nezveřejňovat.

**Ověření zlepšení:** po vytvoření nové i zkopírované akce lze bez hledání v
administraci určit, zda už zákazník může nakupovat a jaký je další krok.

Kód: `occasion_setup_page.dart:OccasionSetupPage.open`, následná navigace přes
`RouterService.navigateToOccasionAdministration`.
Důkaz: `after-create-mobile.png`, `after-create-desktop.png`.

## 2. Vysoká priorita: základní vstupné je schované v editoru formuláře

**Pozorování:** krok přihlášení nejprve ukazuje název a adresu formuláře.
V testovaném desktopovém okně bylo nutné posunout obsah. Produktová karta
zobrazila „Spot“, „Variant 1“, cenu 100 Kč a neaktivní výběrové kolečko.
Pole Cena se objevilo až po výběru okolní karty. Zobrazená karta před výběrem
neměla jednoznačnou výzvu k úpravě ceny.

Po otevření editoru byla změna ceny na 350 Kč funkční a uložila se. Zároveň byl
uvnitř editoru výchozí limit jedna vstupenka na objednávku. Pro běžný nákup více
vstupenek jde o důležité rozhodnutí, které lze při pouhém pokračování přehlédnout.

**Doporučení:** přímo nabídnout srozumitelnou sekci „Vstupenky a ceny“ s viditelnou
úpravou názvu, ceny a maximálního počtu vstupenek na objednávku. Interní názvy
„Spot“ a „Variant 1“ nechat v pokročilém editoru nebo je nahradit lidským
označením. Zvážit explicitní volbu zdarma/placené; existující kanonické výchozí
hodnoty případně měnit na jejich skutečné hranici, nikoli duplikovat v UI.

**Ověření zlepšení:** nový pořadatel nastaví vstupné a umožní nákup dvou vstupenek
bez znalosti výběru karet, typů produktů a editoru polí.

Kód: `occasion_setup_page.dart`, `FormEditorContent.prototype`,
`forms/widgets_editor/form_fields_generator.dart`, `product_type_editor.dart`.
Důkaz: `form-top.png`, `form-products-visible.png`, `product-edit.png`.

## 3. Střední priorita: konec má příliš podobných potvrzovacích stavů

**Pozorování:** závěrečný tok obsahuje checkbox kontroly, Potvrdit kontrolu,
100 % dokončeného nastavení, Uložit dokončený koncept a teprve Vytvořit událost.
Text vysvětluje, že koncept je stále neveřejný. Jeho existence a vznik skutečné
akce ale zůstávají dvěma podobně pojmenovanými cíli.

Před potvrzením byla sekce Soukromí a dokončení červeně orámovaná s ikonou chyby,
přestože její text jen vysvětloval správný neveřejný stav. Po potvrzení se změnila
na úspěšnou. Jde o matoucí použití barvy chyby pro potvrzovací fázi.

**Doporučení:** rozlišit jasně „Uložit koncept a odejít“ a „Vytvořit neveřejnou
akci“. Pokud má samostatné Potvrdit kontrolu zůstat, popsat, že teprve následující
akce vytvoří událost. Červenou vyhradit skutečné opravitelné chybě; vysvětlení
soukromí zobrazit informačně. Zvážit checkbox + jediné finální vytvoření.

**Ověření zlepšení:** z poslední obrazovky je jednoznačné, zda akce už existuje,
co ještě chybí potvrdit a zda se spustí veřejný prodej.

Důkaz: `review-bottom-mobile.png`, `ready100-mobile.png`.

## 4. Střední priorita: kontrola konfigurace nenabízí celý pohled zákazníka

**Pozorování:** aktivní aplikační větev umožnila placený formulář se vstupenkou,
ale v seznamu 16 otázek nebyl vzhled vstupenky. Komunikace nabídla adresu pro
odpovědi a tón, bez náhledu skutečného potvrzovacího e-mailu. Souhrn ukazoval
nastavení, bez přímého vstupu do zákaznického průchodu před otevřením prodeje.

Kód záměrně přidává otázku Ticket jen při `!appSupported`. Nejde o tvrzení, že
náhled vstupenky chybí v celém produktu nebo v ticketing-only variantě.

**Doporučení:** před spuštěním prodeje nabídnout bezpečný zákaznický náhled:
formulář, celkovou cenu, potvrzení a vstupenku, pokud je relevantní. Případně jej
umístit do dokončovacího rozcestníku z bodu 1. Uvést, co náhled ověřuje a že
neodesílá reálné zprávy ani neotevírá prodej.

**Ověření zlepšení:** pořadatel může zkontrolovat, co zákazník skutečně uvidí,
bez veřejného zveřejnění a bez hledání v několika nastaveních.

Kód: `occasion_setup_story.dart:questions`,
`occasion_setup_communication.dart`, `_reviewBody`.
Důkaz: `review.snapshot`, `communication-mobile.png`.

## 5. Střední priorita: provozní dopady zděděných nastavení nejsou konkrétní

**Pozorování:** E-mail pro odpovědi zobrazoval „Podle organizace (Systémový
odesílatel)“, bez konkrétní adresy. U testovacího bankovního účtu byla výstraha,
že automatická synchronizace není nastavena. Nápověda požadovala kontaktování
organizátora/správce účtu, i když aktuální uživatel procházel vytvořením akce
jako organizátor a mohl účty spravovat.

Samotný výběr a potvrzení konkrétního bankovního účtu fungovaly dobře. Mezera
je ve vysvětlení, kam odpovědi opravdu dorazí a kdo v tomto režimu řeší úhrady.
Tento audit nezjišťoval živé doručování e-mailů nebo párování plateb.

**Doporučení:** vedle informace o dědění ukázat účinnou hodnotu - skutečnou
adresu pro odpovědi. U nesynchronizovaného účtu vysvětlit konkrétní další postup,
například kde organizátor potvrdí platbu a jak souvisí úhrada s doručením
vstupenky. Text musí vycházet ze skutečného platebního režimu.

Důkaz: `payments.png`, `communication-mobile.png`.

## 6. Střední priorita: v aplikační variantě se průvodce obtížně hledá

**Pozorování:** tlačítko Vytvořit novou událost otevřelo stručný dialog pro název,
odkaz a termín. Vytvořit krok za krokem bylo až pod ikonou tří teček. Pro člověka,
který neví, že průvodce existuje, to není zřejmá cesta k úplné přípravě.

**Doporučení:** v tomto vstupu nabídnout pojmenované možnosti Krok za krokem a
Rychle vytvořit, s krátkým popisem. Zachovat rychlou cestu zkušeným uživatelům.
Ticketing-only varianta již má jinou vstupní politiku, tu neposuzovat podle
tohoto konkrétního pozorování.

Kód: `occasion_creation_helper.dart:createNewOccasion`, podmínka AppSupported.
Důkaz: `entry.png`.

## 7. Nižší priorita: dva ukazatele postupu a nepojmenované proužky

**Pozorování:** při otázce 11 z 16 bylo dole Dokončené nastavení 17 %. V tomto
průchodu se využily i přeskoky přes horní navigaci; procenta proto nelze vydávat
za výsledek čistě sekvenčního průchodu. UI každopádně ukazuje dvě různé míry bez
vysvětlení jejich vztahu. Na šířce 390 px je všech 16 navigačních proužků bez
viditelných názvů; uživatel musí vědět, který představuje například Platby.

**Doporučení:** primárně používat jeden jednoduchý ukazatel průchodu. Zbývající
nutné úkony ukazovat konkrétně, například Potvrdit bankovní účet. Na mobilu
nabídnout seznam pojmenovaných kroků místo spoléhání na úzké segmenty.
Aktuální segmenty již podporují přeskok i tooltip; to zachovat jako doplněk.

Důkaz: `communication-mobile.png`.

## Co už pomáhá a nemá smysl hlásit znovu jako chybějící

- Kopírování vysvětluje, že objednávky, účastníci a rezervace zůstanou ve zdroji.
- Adresa formuláře má návrh a průběžnou kontrolu dostupnosti.
- Účet je zobrazený konkrétně a musí se pro danou akci potvrdit.
- Splatnost vysvětluje začátek počítání, dědění, nulu i odpovědnost za zrušení
  nezaplacené objednávky. Připomínky mají popsané výchozí hodnoty.
- Místo konání, popis a úvodní obrázek už mají svůj krok.
- Tým a ověření organizace lze přeskočit. Spodní navigace zůstává dostupná při
  posunu dlouhého obsahu. Přeskok přes horní navigaci již funguje.

## Doporučený rozsah nejbližšího UX zlepšení

Začít body 1 a 2, poté sjednotit závěrečné stavy z bodu 3. Ostatní body řešit
jako navazující zlepšení, ne jako blokaci již připravených technických oprav.
Nejde o nový plán implementace ani o oprávnění k publikaci.

Evidence je v `/tmp/festapp-wizard-ux-20261021/`. Testovací událost 196 zůstala
v izolovaném backendu; nevznikla zákaznická objednávka, nebyla provedena platba
ani odeslána pozvánka. Produkce se neměnila. Kód průvodce tento audit neupravoval.
