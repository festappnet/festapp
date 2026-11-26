# #1067 Dialogy a čitelnost fronty bankovních e-mailů

## Příčina a cílový tok

`RoutedBankAccountDialog` staví root `OverlayPortal` a vlastní
`Navigator` s `BankAccountDialogScope`. `BankSyncEmailQueue._confirm`
a `_dismiss` dnes volají `showDialog(context: context)` s výchozím root
navigátorem. Tato routa se ocitne pod portálem. Sousední dialogy už používají
`BankAccountDialogScope.contextOf(context)` a `useRootNavigator: false`.
`_observationCard` a sloupec fronty zarovnávají obsah na začátek, karty se
proto stáhnou na šířku textu.

## Implementace

1. Přepni oba vstupy fronty na existující vzor pro navigátor bankovního účtu.
   `BankAccountDialogScope` má fallback na lokální kontext. Zachovej
   `AppAlertDialog`, příslušný typ návratové hodnoty a `barrierDismissible:false`.
   Zavření, Escape a zpět patří aktivnímu vnitřnímu dialogu. Ověř fokus při
   otevření a návrat na původní akci nebo logické další místo, pokud řádek
   po uložení zmizí. Zachovej `PopScope`, stav ukládání a `mounted` kontroly.
   Pokud se při testu prokáže, že Escape zachytává skořápka účtu, oprav
   přednost obsluhy v existujícím dialogovém vlastníkovi.
2. Roztáhni seznam karet na dostupnou šířku bez změny šířky ostatních
   tlačítek v panelu. Karta má přehled faktů, varování před duplicitou a
   společnou skupinu akcí. Na širším panelu fakta vlevo a akce vpravo, pod
   nimi varování nebo v rámci faktů podle stávající struktury. Na úzkém
   panelu jsou akce pod fakty a zalamují se. Využij omezení dostupné šířky
   panelu a stávající Material UI. Akce vizuálně rozliš podle významu.
   Přístupný název a čitelnost zachovej při delším překladu i zvětšeném textu.
3. Tok zůstává načtení, kontrola v bankovnictví, volba platby nebo důvod
   odmítnutí a zpětná vazba. Zachovej kompaktní rozbalovací variantu i
   roztaženou verzi a read-only zobrazení. Potvrzení/dismiss stále volá
   `DbBankAccounts` a kanonický BankSync příkaz se stávající kontrolou
   účtu, targetu, duplicit a auditní stopou. Při chybě zůstane rozepsaný
   dialog k dispozici dle stávajícího toku, při úspěchu obnov frontu.

## Akceptace a kontrola

- Použij `test/components/bank_accounts/bank_sync_email_queue_test.dart`.
  Přidej realistický root overlay a vnořený navigator nebo přímo existující
  shell. Test se musí rozbít při návratu k root dialogu. Pokryj obě akce,
  potvrzení, zrušení, Escape, neúspěšné uložení a read-only. Ověř, že se vedle
  fronty nezavře dialog účtu a že jedno potvrzení vyvolá jediný příkaz.
- Ověř úzký panel přibližně 320 px, desktop a zvětšený text na
  reprezentativních českých datech. Karta zabírá šířku, text a akce jsou
  dostupné bez vodorovného scrollu. Zkontroluj pořadí fokusu a viditelnost
  aktivního dialogu. Pro skutečný prohlížeč použij jednorázový tenant a
  repozitářový postup dle `festapp-local-e2e`.
- Spusť dotčený Flutter test s `--concurrency=1` a dotčené CI lane. DB
  chování prověř stávající regresní sadou BankSync podle CI výběru.
