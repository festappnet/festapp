# Proveďte: Google Wallet ve vstupenkovém e-mailu

Pracujte v `/Users/miakh/source/festapp`. Dodržujte AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md. Použijte `focused-development`; ověřování `standard`, protože jde o veřejný capability kontrakt, klíče a migraci.

Přečtěte celý autoritativní plán:
`docs/plans/ticket-wallet-plan-2026-11-10.md`

Dokončete registrační vlnu 0 i implementační vlny 1-4. Implementujte pouze Google Wallet. Apple, jeho účty, certifikáty, APNs, adaptéry i obecný framework pro více providerů jsou mimo rozsah.

## Výsledek

- Každá doručovaná způsobilá vstupenka automaticky dostane v e-mailu možnost uložení do Google Wallet, pokud je integrace připravená a pořadatel nabídku nevypnul.
- V obou stávajících nastaveních doručování je jediný checkbox „Nabídnout uložení do peněženky“, `wallet_enabled`, výchozí zaškrtnutý, nezávislý na PDF / inline QR / obojí. Explicitní false se nesmí ztratit. Náhled respektuje neuloženou volbu bez skutečného vydání.
- Jeden pass odpovídá jedné existující vstupence a používá přesně její QR. Resend ani retry nevytváří novou identitu. Storno, použití a změna termínu/místa se synchronizují.
- Původní doručení funguje i při chybě Wallet. Zachovejte email queue, send fencing a současnou platební/admission autoritu.

## Krátká cesta k dokončení

1. Zkontrolujte pracovní strom a aktuálnost pouze dotčených vlastníků uvedených v plánu. Zachovejte cizí změny. Nenavazujte novým plošným průzkumem ani přepisem architektury. Pokud důkaz vyvrací předpoklad, opravte plán i příslušnou vlnu.
2. Hned zadejte browser agentovi `gpt-6.1-terra` (`fork_turns="none"`) ověření správného Google účtu/projektu a existujícího issuera. Použijte rozšíření Panerelay, skill `panerelay-browser` a `agent-browser --provider panerelay` v uživatelově výslovně povoleném hlavním Chromu, v nových background tabech. Chybějící issuer skutečně zaregistrujte, nastavte API/service account a demo testery. Připravte publishing žádost a po dodání skutečného dema ji odešlete. Nevytvářejte Google Play účet ani placené vývojářské členství. Credentials bezpečně uchovejte dle AGENTS.md, nikdy je nevypisujte. Potřebné lidské ověření řešte konkrétní otázkou; ostatní práci nepřerušujte. Čekání na Google není důvod k opakovanému pollingu ani k zastavení implementace.
3. Zatím implementujte v závislostním pořadí SQL/capability -> Google Class/Object a endpoint -> checkbox/e-mail/veřejná route -> reconciliace a recovery. Použijte stávající vlastníky a sdílené komponenty. Žádné dummy JWT, nefunkční badge, druhý ticket lifecycle, nová email queue, aplikační triggery ani nesouvisející refaktory.
4. Nejprve dokončete jeden propojený průchod od ticket dat po e-mail a bezpečné vydání. Potom doplňte negativní a recovery případy plánu. Změny dělejte v souvislých dávkách; nespouštějte build/test po každém souboru. Znovu použijte existující test infrastrukturu a použitelné disposable závislosti. Negenerujte nové reportovací nástroje.
5. Na finálních vstupech jednou spusťte relevantní canonical CI lanes podle `automation/ci/checks.json` přes `automation/test_ci.sh`. Ověřte sběr nových testů. Nezávislé kontroly seskupte, Flutter nejvýše jeden proces a testy s `--concurrency=1`. Po úpravě opakujte jen dotčené kontroly; neobcházejte povinné gates.
6. S issuerem/testerem ověřte skutečné uložení, stejný QR a aktualizaci/storno. Rozlišujte úspěšný API zápis, uloženou kartu a prokázaný scan. Bez dostupného zařízení uveďte přesně zbývající důkaz. Vypnutí checkboxu musí ovlivnit i připravený dosud neodeslaný snapshot a zachovat již vydané passy.

Nevytvářejte další implementační ani auditní subagenty bez oprávnění. Browser delegace je výslovně povolená; neopakujte stejný průzkum ve více agentech.

## Hranice a předání

Registrace issuera a konfigurace jsou součást zadání. Bez dalšího pokynu neprovádějte produkční SQL migraci/deploy/aktivaci, commit ani push a neobjednávejte placené služby. Pokud bude nasazení později autorizováno, použijte povinný release gate a delegaci dle AGENTS.md; nic z nich rychlost nenahrazuje.

Pracujte do dokončení lokální implementace a dostupných registračních kroků. Předejte nejvýše pět stručných bodů: změny, skutečně provedené kontroly, issuer/publishing stav, end-to-end důkaz a přesný zbývající blokovaný či produkční krok. Neoznačujte demo režim za veřejně aktivovanou funkci.
