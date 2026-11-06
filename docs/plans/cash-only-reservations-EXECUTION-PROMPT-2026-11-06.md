# Proveďte celý plán: hotovostní rezervace a platby bez termínu

Pracujte v `/Users/miakh/source/festapp`. Toto je zadání k úplné lokální
implementaci, nikoli k dalšímu plánování. Produkční migrace, nasazení, commit
ani push do rozsahu nepatří.

## Autorita a rozsah

Přečtěte platné AGENTS.md, CLAUDE.md, `docs/architecture/ai_context.md` a celý
již prozkoumaný a nezávisle zkontrolovaný autoritativní plán:

`docs/plans/cash-only-reservations-plan-2026-11-06.md`

Použijte relevantní skills `focused-development` a `codebase-design`.
Verification: **standard**, protože jde o platby, oprávnění, veřejné kontrakty
a migraci. Tokenová úspornost omezuje redundantní práci, ne důkazy správnosti.

Cíl: ve stávajícím společném výběru bankovního účtu, Stripe a dalších metod
každého formuláře přidat **Pouze hotově**. Rezervace s cenou funguje bez banky,
má vlastní pokyny, žádný platební QR ani termín a není falešně zaplacená.
**Bez termínu úhrady** je skutečná politika bez upomínek a platební expirace,
také pro převod. Přidání hotovosti, odkaz k nastavení banky a oprávněná
historie odpojených účtů fungují podle plánu.

## Postup bez opakovaného průzkumu

1. Zjistěte branch/HEAD a existující lokální změny. Zachovejte cizí práci;
   nic nestashujte, neresetujte ani neodstraňujte kvůli čistému pracovnímu stromu.
   Jedním cíleným průchodem potvrďte vlastníky uvedené v plánu. Nevytvářejte
   nový celorepozitářový průzkum, další plán ani nezávislý audit.
2. Udržujte v autoritativním plánu krátký průběžný stav: zbývající kroky,
   skutečné překážky, přijatá rozhodnutí a doklady kontrol. Pokud kód vyvrátí
   faktický předpoklad, opravte příslušnou část plánu s konkrétním důkazem.
   Běžná implementační rozhodnutí řešte samostatně v daném rozsahu.
3. Implementujte kroky plánu v závislostním pořadí: kanonická SQL konfigurace,
   klasifikace a politika; objednávkový a platební lifecycle; historie a
   oprávnění; potom Core/Edge/Flutter/JS prezentace, editory a dokumentace.
   Definujte společný kontrakt před přesunem callerů. Každou souvislou změnu
   dokončete před její validací. Nezastavujte po SQL, samotném UI či prototypu.
4. Cílené významové testy připravte u dotčených vlastníků a spusťte po
   souvislých změnách. Nakonec proveďte jeden konsolidovaný výběr normálních
   repository kontrol pokrývající finální změny a akceptační matici plánu.
   Neopakujte prošlé kontroly pro nezměněné vstupy.
5. Dokončete odstranění nahrazených cest a architektonickou akceptaci plánu.
   Výsledky a skutečné limity zapište stručně do stejného plánu.

## Nepřekročitelné architektonické podmínky

- Jeden SQL vlastník klasifikace metod, jeden resolver politiky, jeden uložený
  snapshot, existující ledger a jednotný význam platebního DTO. Flutter, JS,
  e-maily, setup, MCP, administrativní objednávky a pořadník mají stejné
  vlastníky pravidel. Klienti nevypočítávají obchodní politiku znovu.
- Žádný samostatný cash subsystém, falešný online adaptér, druhý ledger,
  obecný nový framework, kopie pravidel v obrazovkách nebo další přepínač
  rezervačního režimu. Označení Pouze hotově vychází z jediné konfigurace.
- Rozhraní držte malá, názvy doménově přesné a typy výslovné. Soustřeďte
  validaci a výpočty do jejich vlastníků; nepřenášejte je do DTO getterů,
  UI callbacků nebo transportních wrapperů. Nereorganizujte nesouvisející kód.
- Odstraňte nahrazené výpočty, nepoužívané helpery/importy, mrtvé větve a jejich
  zastaralé testy či dokumentaci. Nestačí přidat další if nad původní fallback.
  Zachovejte jen konkrétně ohraničené podporované kompatibilní vstupy z plánu,
  delegující stejnému owneru. Nemažte historická data nebo receipty jako úklid.
- Nevypouštějte ochrany pro zjednodušení kódu: scope, verze, zámky, idempotence,
  souběžná kapacita a transakční email intenty zůstávají společné.

## Povinné regresní důkazy

Pokryjte celou akceptační matici plánu, zejména následující nalezené pasti:

- Cash nevolá bankovní `presentPayment`, povinnou bankovní referenci ani online
  attempt. Povinnou fakturaci neobcházejte; vyřešte ji podle pravidla v plánu.
- None nepřebere týdenní, zálohový nebo datumový fallback ani po editaci
  produktů. Nové časované objednávce zůstane při editaci původní absolutní
  deadline. Historické objednávky mají jediný popsaný legacy výklad.
- Platný vstupní QR je oddělený od platebního QR. Potvrzení rezervace nezapíše
  úhradu; skutečný pohyb používá přesnou částku, ověřenou jednotku/měnu,
  idempotentní command a existující přepočet. Storno a used stavy jsou chráněné.
  Nový refund workflow po stornu je mimo rozsah.
- Historie připojených pohybů a širší osobní bankovní historie mají rozdílná
  oprávnění. Cash objednávka nenabízí párování bankovního pohybu. Prázdný
  aktivní účet, nenastavená banka a chybějící práva nejsou stejný stav.
- Starý full save nesmí přepsat cash na bank. Realizujte v plánu určený
  `payment_selection_intent` a `client_capabilities` kontrakt, včetně chyby
  pro nepodporovaný vstup. Replay nesmí přepočítat původní výsledek.
- Zachovejte bankovní platby s termínem, banku bez termínu, zálohy, online
  poskytovatele, bezplatné objednávky a změnu ceny z nuly na kladnou.

## Efektivní ověřování a práce s kontextem

Používejte `rg --files`, scoped `rg` a cílené čtení. Nezávislé lookupy a lehké
kontroly dávkujte; závislé změny, generování a migrace provádějte v pořadí.
Úspěšné logy držte stručné, plné výstupy čtěte jen při chybě. Po kompakci
pokračujte ze zaznamenaného stavu, nezačínejte průzkum od začátku.

Používejte předepsaný pnpm a repository test harness, nikoli nové náhradní
skripty. Ověřte skutečné spuštění vybraných testů; importovaný fixture není
provedený test. Finanční a autorizační kontrakty ověřte na disposable databázi,
ne pouze mockem. Zkontrolujte paritu kanonických SQL zdrojů a dopředné migrace
příslušným zavedeným checkem. Neprovádějte produkční SQL ani skutečné platby.
Flutter nejvýše jeden task na stanici, testy `--concurrency=1`.
Browser průchod proveďte podle plánu a AGENTS.md: delegace Terra, izolovaná
session, bez zvuku, bez zásahu do uživatelova prohlížeče a s úklidem session.
Další implementační nebo review subagenty nezakládejte bez výslovné potřeby
a oprávnění; již provedený architektonický audit neopakujte.

Při selhání diagnostikujte konkrétní příčinu, opravte ownera a opakujte dotčenou
kontrolu. Neukrývejte regresi přes skip, slabší assertion, jiný účet, vyšší
oprávnění, syntetický receipt či fallback. Nezávislá předchozí selhání popište
odděleně s důkazem. Neoznačte požadovanou cestu za dokončenou, pokud neprošla
její povinná kontrola; tokenová úspornost neopravňuje tuto kontrolu vynechat.

## Podmínka dokončení a předání

Hotovo je až po implementaci všech vstupů plánu, odstranění nahrazeného kódu,
aktualizaci stávajících README a cíleném ověření finálních zdrojů. Doložte
scoped seznamem callerů, že nahrazené výpočty a bankovní fallbacky v dotčených
cestách nezůstaly dosažitelné. Není požadována celorepozitářová přestavba.

Ve finále uveďte nejvýše pět stručných bodů: výsledné chování, společné
vlastníky a odstraněné cesty, skutečně provedené kontroly, případné mezery
a neprovedené produkční kroky. Nezaměňujte připravenou migraci za aplikovanou
ani úspěšný test za důkaz nasazení. Při skutečném blokování zachovejte práci,
zapište přesnou překážku a zbylé kroky; neoznamujte částečný výsledek jako hotový.
