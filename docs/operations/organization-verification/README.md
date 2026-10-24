# Ruční ověřování pořadatelů

Právní profil patří Unit. Manager jej spravuje jako podsekci nastavení pořadatele; tenant Organization určuje schvalovací autoritu. Profil se ukládá online samostatně, mimo běžný save Unit a offline sync. Veřejný formulář zobrazuje pouze schválenou aktuální identitu. Ověření není garancí kvality akce ani dodání vstupenek.

## Ověřovací standard první verze

1. Žadatel uloží právní název, zemi, registrační číslo, strukturované sídlo a veřejný kontaktní e-mail. DIČ, telefon a HTTPS web jsou volitelné. Samotný platný kontrolní součet českého IČO není ověřením.
2. Manager výslovně odešle uloženou revizi k ověření. Před odesláním vidí, že údaje budou veřejné u všech formulářů Unit.
3. Správce příslušné platformy otevře **Ověření pořadatelů** v administraci platformy. Porovná právní název, registrační číslo a sídlo s autoritativním veřejným rejstříkem dané země. Ověří také oprávnění žadatele subjekt zastupovat: doložená role ve veřejném rejstříku nebo potvrzení z nezávisle zjištěného oficiálního kontaktu subjektu. Shoda e-mailové domény sama nestačí.
4. Do zdroje ověření zaznamená odkaz/název rejstříku, datum kontroly a způsob ověření zastoupení. Interní poznámka nesmí obsahovat osobní doklady nebo zbytečné osobní údaje. Schválí přesně zobrazenou pending revizi. Při nedostatečných podkladech žádost zamítne se srozumitelným feedbackem žadateli.
5. Při zjištěném problému vyhledá profil ve filtru **Ověřené** a odebere ověření s důvodem. Nové načtení veřejného formuláře již patičku nezobrazí; otevřená stránka je snapshot do svého dalšího refresh.

Manager vidí feedback, nikoli interní poznámku ani zdroj. Profil a audit nejsou přímo čitelné přes tabulkové API. Každá změna veřejných údajů ruší pending/verified stav a vyžaduje novou žádost. Nezměněné normalizované údaje nic nezapisují. Každý skutečný save nebo přechod zvyšuje revizi a atomicky zapisuje audit.

## Konflikt, timeout a provoz

Po konfliktu se zastaralé rozhodnutí neopakuje. Načtěte aktuální profil a znovu posuďte konkrétní revizi. Po timeoutu klient obnoví potvrzený stav a ponechá rozepsaná pole; neprohlašuje neznámý výsledek za úspěch. Před vědomým načtením serverových údajů do editoru si zachovejte potřebný koncept.

Přesun celé Unit mezi tenanty není součást této funkce. Privilegovaná migrace musí ještě před přesunem v téže transakci zrušit ověření, zvýšit revizi a zaznamenat audit; samotná změna FK není podporovaný workflow. Kontrola aktuálního tenanta veřejnou projekci při nesouladu skryje, ale nenahrazuje tuto podmínku (zejména při přesunu zpět).

Kanonické SQL: `database/functions/organization_verification/`. Migraci sestavuje `python3 automation/assemble-organization-verification-migration.py`; zachycuje i příslušné autorizované čtecí projekce. Produkční migrace a klientské nasazení vyžadují samostatné zadání pro jeden tenant podle AGENTS.md.
