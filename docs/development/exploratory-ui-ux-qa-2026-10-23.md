# První průchod UI/UX - 23. 10. 2026

Souhrnná stránka: [QA zápisník](qa-overview.html).

Výsledek: 4 nálezy, z toho jeden závažnější - neúspěšné pozvání končí potvrzením úspěchu. Bez oprav aplikačního kódu a bez produkčních zápisů.

## Prostředí a rozsah

- Aktuální pracovní strom `feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`, včetně existujících necommitnutých změn. Není to audit nasazené produkce.
- Nový vlastní Supabase projekt `festapp-wizard-ux-20261023`, API/DB `56821/56822`. Kanonický baseline, dopředné migrace a syntetický seed.
- Skutečná Flutter aplikace, `test/browser/occasion_setup_e2e.dart`, server `56880`. Běžný dialog vytváření, průvodce vypnutý, podpora aplikace zapnutá.
- Izolovaný headless Chromium, desktop 1440 x 1000 a mobilní viewport 390 x 844. Produkční Festapp, Supabase Cloud a OneSignal blokované. Push callbacky nahrazené existující lokální fixture.
- Syntetická akce `QA Podzimní setkání 2026`, lokální ID 1. Účty Anna a Petr vytvořené jako databázové fixtures a přidané do jednotky. Anna přidána k akci skutečným UI.
- Kliknutí v části Flutter rozhraní potřebovala DOM click na skutečném sémantickém prvku. To ověřuje handlery a uložená data, nikoli všechny fyzické klikací plochy. Záznam je surový průchod včetně opětovného lokálního přihlášení po startu nahrávání.

## Prošlé a omezené scénáře

| Scénář | Výsledek |
| --- | --- |
| Přihlášení lokálního administrátora | Prošlo |
| Založení akce běžným dialogem, automatický odkaz a otevření její administrace | Prošlo |
| Přidání připravené Anny přes Přidat už vytvořeného | Prošlo, členství ověřeno v DB |
| Výběr účastníka a potvrzení pozvání | Prošlo do odesílacího kroku |
| Výpadek služby pozvánek | 3 odpovědi HTTP 503, zavádějící závěr popsaný níže |
| Změna místa konání bez uložení, přepnutí záložky a návrat | Koncept zůstal zachovaný |
| Přímé znovunačtení Nastavení na mobilní šířce | Aktivní záložka se zobrazila správně |
| Vytváření nového účastníka editací tabulky | Nedokončeno kvůli omezení ovládání tabulky automatizací; není vykázáno jako chyba produktu |
| Skutečné doručení e-mailu, OAuth, platby, nativní telefon | Netestováno |

Lokální odesílací Edge služba úmyslně nebyla spuštěna. Nedostupnost služby není nález produktu; způsob, jakým UI tento stav vyhodnotí, nálezem je. Po průchodu byly v `public.email_messages` 0 zpráv a akce měla 2 členy včetně správce.

## 1. P1 - Selhání pozvánek končí potvrzením úspěchu

Postup: Uživatelé > zaškrtnout Annu > Pozvat > potvrdit. Ponechat odesílací službu nedostupnou.

Skutečnost: tři POST požadavky `send-sign-in-code` končí HTTP 503. Závěrečný dialog přesto ukáže `Postup: 1/1` a **Zpracování bylo úspěšně dokončeno.** Žádná zpráva nevznikla. Případný přechodný chybový toast neposkytuje trvalý a pravdivý výsledek dávky.

Dopad: pořadatel má důvod považovat pozvánku za odeslanou a nezkoušet nápravu.

Podklad v kódu: `lib/components/users/views/users_tab_helper.dart`, `processInvites`, zachytí chyby a po vyčerpání pokusů normálně dokončí Future. `lib/services/dialog_helper_progress.dart` proto zvýší dokončený počet a zvolí zprávu o úspěchu. Oprava má předat výsledek položek do výsledku dávky, uvést úspěšné/neúspěšné příjemce a nabídnout opakování neúspěšných.

Důkaz: [snímek](evidence/ui-ux-qa-2026-10-23/invitation-false-success.png), [HTTP výsledky](evidence/ui-ux-qa-2026-10-23/invitation-network.txt), [strom dialogu](evidence/ui-ux-qa-2026-10-23/invitation-false-success.snapshot), [surový záznam průchodu](evidence/ui-ux-qa-2026-10-23/exploration.webm).

## 2. P2 - Skryté navštívené záložky zůstávají v přístupnostním stromu

Postup: otevřít Uživatelé, přejít do Nastavení a zpět. Při širším průchodu navštívit i Formuláře.

Skutečnost: vizuálně jsou vidět Uživatelé, přístupnostní snapshot však obsahuje také pole Nastavení, případně ovládání editoru formuláře a předchozích Objednávek. Samostatný DOM výpis potvrdil 14 vstupů mimo viewport, bez předka `aria-hidden=true`. Starší snapshot po návštěvě více sekcí obsahuje více tlačítek Uložit a ovládání nesouvisejících sekcí.

Dopad: strom zpřístupňuje nesouvisející ovládání a opakované názvy. Konkrétní chování VoiceOver ani klávesová dosažitelnost všech těchto prvků nebyly ověřené; nejde o tvrzení, že proběhl kompletní audit čtečky.

Směr opravy: oddělit životnost zachovaných tabů od jejich sémantické viditelnosti. Prověřit neaktivní děti `AutoTabsRouter.tabBar` v `lib/components/navigation/routed_tab_scaffold.dart`.

Důkaz: [snapshot](evidence/ui-ux-qa-2026-10-23/hidden-tabs.snapshot), [výpis skrytých vstupů](evidence/ui-ux-qa-2026-10-23/hidden-tab-elements.json), [viditelná obrazovka](evidence/ui-ux-qa-2026-10-23/users-retained-tabs.png).

## 3. P2 - Po zúžení okna není vidět aktivní záložka

Postup: na desktopu otevřít Nastavení akce a zúžit viewport z 1440 na 390 px.

Skutečnost: obsah Nastavení se přizpůsobí, ale pruh záložek zůstane posunutý na začátku. Aktivní Nastavení bylo na x=840 při šířce viewportu 390. Viditelné jsou Objednávky, Přihlášky a Formuláře bez označení právě otevřené sekce.

Kontrola: fyzický reload stejné URL na mobilní šířce aktivní Nastavení správně přisune do záběru. Jde tedy o změnu rozměru/rotaci, nikoli obecné selhání mobilního deep linku.

Směr opravy: po změně dostupné šířky znovu přisunout aktivní položku navigace. Zachovat funkční horizontální posouvání ostatních položek.

Důkaz: [po zúžení](evidence/ui-ux-qa-2026-10-23/settings-mobile.png), [kontrolní reload](evidence/ui-ux-qa-2026-10-23/settings-mobile-reload.png).

## 4. P3 - Prázdný výběr účastníků nevysvětluje další krok

Postup: v nové akci otevřít Přidat už vytvořeného, když jednotka nemá další dostupné účastníky.

Skutečnost: velký dialog ukazuje pouze vyhledávání, Žádné výsledky a Storno. Nevysvětluje, odkud se kandidáti berou, zda jsou všichni přidaní, ani jak založit nového účastníka.

Dopad: nový pořadatel nemá oporu pro další krok. Jde o slabinu vedení uživatele, nikoli funkční blokaci.

Směr opravy: rozlišit prázdný seznam od nulového výsledku hledání; vysvětlit rozsah výběru a nabídnout Vytvořit účastníka nebo návrat k odpovídající akci.

Důkaz: [prázdný dialog](evidence/ui-ux-qa-2026-10-23/add-existing.png). Po doplnění syntetických členů jednotky se kandidáti objevili a přidání Anny prošlo.

## Doporučené pořadí

Nejdříve pravdivý výsledek pozvánek, poté sémantika zachovaných záložek a reakce navigace na změnu šířky. Prázdné stavy lze upravit samostatně. Nálezy nebyly publikované jako GitHub issues a produkt nebyl upravovaný ani nasazovaný.


## Navazující průchod

[Formuláře a zakládání akcí - dalších 6 nálezů](forms-occasion-qa-2026-10-23.md).
