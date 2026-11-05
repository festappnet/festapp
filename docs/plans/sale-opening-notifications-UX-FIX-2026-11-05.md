# Oprava UX upozornění - 2026-11-05

Uživatel nahlásil matoucí přepínače a počítadla v hlavním editoru a nefunkční
veřejné zobrazení. Výslovně požádal o Astru Medium a přesunutí celé volby do
tří teček. Astra (`gpt-6-astra`, medium) prověřila snímek, původní implementaci
a návrh změny; ovládání je v nabídce karty Dostupnost přímo v editoru.
Seznam formulářů se u jediné položky přeskakuje, takže by jeho nabídka nestačila.

## Výsledné ovládání

- Hlavní editor neobsahuje e-mailové přepínače, sedm počítadel ani správu rozesílky.
- Dialog ukazuje stav a pojmenovanou akci Zapnout/Pozastavit/Obnovit, jeden počet
  zájemců a oprávněné odkazy. Chyba načtení má Retry a nevydává se za nulu.
- Dialog má izolovaný draft. Zrušit/křížek/Escape jej zahodí, Použít změny předá
  nastavení a HTML dokument rodiči. Persistenci provádí jediný stávající Save.
- Neuložené nové zapnutí lze vrátit včetně původního HTML bez skrytého zbytku.
- Veřejné zobrazení při neuložených změnách nabídne uložit a zobrazit, zobrazit
  uloženou verzi nebo zůstat v editoru. Chyba save navigaci nepředstírá.
- Po pozastavení se místo samotného neviditelného slotu zobrazí plánovaný termín.
  Aktivní odběrový blok zůstává čistý bez vynuceného data. Ruční uzavření vítězí.

## Zjištěné chyby a důkaz

Živý formulář s budoucím začátkem, vypnutým odpočtem a pozastaveným sběrem
vracel správně `is_open=true`, `registrationMode=closed` a `reason=paused`.
JS správně vyhodnotil BEFORE_START, ale odstranil jediný slot a ponechal prázdnou
stránku. Stejná kombinace byla reprodukována na disposable datech a nový test
nejprve selhal s prázdným textem; po opravě prochází.

Flutter E2E navíc odhalil rychlé opakované načítání a překrývající se odpovědi.
Příčinou dalšího opakování byl nový jednorázový Timer do začátku vzdáleného přes
měsíc. JavaScriptový timer má limit 2147483647 ms (asi 24,8 dne); delší doba se
přeteče. Viz [MDN](https://developer.mozilla.org/en-US/docs/Web/API/Window/setTimeout).
`FormOpeningTimer` nyní čeká nejvýše den, mezitím pouze lokálně přeplánovává
čekání a síťový reload zavolá jednou až při skutečném termínu. Zrušení/dispose
předchozí čekání zastaví. Generace načítání brání staré odpovědi přepsat novou.

Spekulativní změna opakovaného načítání oprávnění byla po diagnostice odstraněna;
`RightsService` a jeho autorizační chování zůstávají ve stavu vydaného main.

Dosavadní kontroly zdrojů: 42 JS testů, 44 Flutter/auth/editor/timer testů; timer má případy
40 dní bez předčasného reloadu, přesný blízký termín a zrušení. Mechanický detektor
Impeccable pro upravené UI vrátil prázdný seznam nálezů. Skutečný browserový
průchod a případné nasazení se doplní až podle skutečného výsledku.

Skutečný lokální prohlížeč po opravě timeru: budoucí termín přes měsíc se
zobrazil a počet relevantních RPC se ustálil na 5, beze změny po dalších třech
sekundách (před opravou přes 611 a rostoucí). Dialog otevřený přes tři tečky:
Obnovit + Zrušit ponechalo SQL paused=true a neaktivní Save; Obnovit + Použít
aktivovalo rodičovské Save a uložení změnilo SQL na enabled=true/paused=false.
Skutečná akce Zobrazit formulář otevřela veřejné pole E-mail a tlačítko.

Závěrečná Astra kontrola odstranila i nepravdivý stav zpracování při chybějícím
nebo minulém datu. Znovu otevřený dialog ukazuje neuložené změny rodiče a
uchovává výchozí stav pro vrácení dosud neuloženého zapnutí.

Závěrečný průchod po poslední změně: všech 45 cílených Flutter testů formuláře,
autorizace a timeru prošlo; poslední JS sada upozornění 11/11 (předchozí
širší JS sada 42/42). Rozšíření o nově příchozí occasion_sale_cases.dart
odhalilo 9 již existujících selhání (staré texty prodeje a validační očekávání).
Jedna diagnostická kontrola s occasion_setup_sales.dart přesně z origin/main
f7c76e92a reprodukovala stejných 9 chyb, nové 3 testy příchozí změny prošly.
Nesouvisející testy nebyly měněny. Vlastní soubor byl po diagnostice obnoven
bytově přesně.

Pozastavit + Použít + Uložit bylo také ověřeno čtením lokálního SQL;
Zobrazit formulář následně ukázalo plánovaný termín. JS veřejná stránka byla
ověřena na šířkách 375 a 1280 a ruční uzavření ukázalo nedostupnost.
Neuložený přechod na veřejnou stránku nebyl samostatně proklikán v browseru.
Žádná produkční data, odběry ani zprávy nebyly v tomto QA měněny.
