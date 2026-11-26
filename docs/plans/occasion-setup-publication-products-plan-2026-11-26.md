# Dokončení akce, úvodní obrázek a produkty

Jedna PR na `main` a jedno ověřené nasazení na `prod/festapptickets` pro vstupenky.online.

1. Zahrnout [ověřenou opravu šablon vstupenek](occasion-setup-ticket-gallery-plan-2026-11-26.md) a její dopřednou migraci.
2. Na kroku zveřejnění zobrazit stávající nahrávání úvodního obrázku. U vybrané propagace nebo při zveřejnění v katalogu s otevřeným či naplánovaným prodejem vyžadovat obrázek. Povolit uložení rozpracovaného konceptu a přechod do souhrnu. V souhrnu označit chybějící obrázek barvou chyby i textem a odkazem na krok nahrání. Doplnit regresi a lokalizovanou nápovědu.
3. Prověřit vytvoření a úpravu produktu v editoru formuláře, uložení a načtení rozpracovaného konceptu a vytvoření skutečných produktů při dokončení akce. Opravit nalezené vady v téže PR a ověřit zachování ceny, měny a vazby na správný formulář či typ produktu podle zjištěného chování.
4. Spustit cílené Flutter, SQL a obsahové testy. Ověřit vlastnictví testů, aktuální základ PR a kanonické migrace. Připravit jednu PR s výsledky.
5. Po splnění pravidel pro merge sloučit PR. Po úspěchu všech povinných CI kontrol přesného SHA použít schválený postup pro kanonický backend a jedinou produkční větev. Ověřit migraci a veřejnou verzi vstupenky.online. Produkční koncept organizátora ponechat rozpracovaný.

Autoritu obrázku vlastní existující nahrávání obrázků jednotky. Flutter používá výslednou URL v konceptu. Výpočet zveřejnění vychází z existujícího pravidla plánování prodeje. Ověření na skutečné akci provádíme na testovacích datech.

## Zjištění při provedení

- Průvodce při vytvoření pole `ticket` nastavil `is_ticket_field=true`. Editor formuláře tak hlavní pole skryl společně s jeho vnořenými poli. Normalizace průvodce opraví i uložené koncepty. Test otevře starší koncept, přidá produkt, upraví cenu a znovu načte uloženou verzi.
- Databázový test ověřuje stejný tok přes uložení a načtení konceptu. Při dokončení vznikne trvalý produkt se správnou cenou, měnou a vazbou na skupinu formuláře.
