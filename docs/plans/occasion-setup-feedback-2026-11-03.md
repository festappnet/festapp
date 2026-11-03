# Opravy průvodce založením akce - 2026-11-03

Rozsah: 14 připomínek ze screenshotů. Zachovat stávající komponenty a soukromé koncepty. Bez nasazení do produkce.

1. Náhled formuláře: tlumené pozadí a barevné akcenty podle veřejného formuláře, světlý i tmavý režim.
2. Písmo: sdílený FontFamilyPicker s hledáním Google Fonts. Rozšířit generovaný společný registr o podporované katalogové fonty, zachovat identitu PDF fontů.
3. Předgenerované vstupenky: změna provozního přepínače nesmí resetovat vzhled ani galerii náhledů.
4. Konec prodeje: jiný termín včetně pozdějšího než konec akce; sladit klientskou a SQL validaci.
5. Tón: tři explicitní volby - organizace (aktuální hodnota), Vy, Ty.
6.-7. Banner: označit dědění, rozlišit dědění / vlastní obrázek / bez banneru. Odstranění musí platit i v e-mailovém náhledu a po dokončení.
8. Plánek: vložený náhled ze stejného dokumentu a zdrojů jako editor, s opakováním při chybě.
9. Produkty v souhrnu: nevydávat chybějící produktový limit za neomezenou kapacitu akce; nezobrazovat tento zavádějící údaj.
10. Tým: potvrdit platnou rozepsanou adresu při pokračování, ponechat adresy a role v souhrnu, umožnit návrat k úpravě.
11. Komunikace: použít stejné dvousloupcové řádky jako ostatní části souhrnu.
12. Skupiny plánku: uvádět pouze skutečné skupiny s místy, přirozeně seřazené; dekorativní sál vynechat.
13. Soukromí: oddělit stav formuláře od zveřejnění v katalogu a popsat skutečné chování uložených příznaků. Otevření ihned nebo naplánování zveřejní katalogovou položku, pokud je vybraná viditelnost v katalogu. Příprava a vypnutá viditelnost zůstávají skryté. Výsledek vrací uložený stav.
14. Dokončení: jedna hlavní akce Spravovat akci, vedlejší návrat na seznam; katalogové zveřejnění patří do správy akce.

Ověření: cílená Dart analýza, existující a doplněné regresní testy průvodce, SQL testy na izolované lokální DB. SQL změny dodat i jako migraci. Browser jen izolovaně na lokálním běžícím preview, je-li dostupné. Ověřování standard kvůli změně serverového kontraktu.

## Výsledek

Všech 14 bodů provedeno lokálně. Sdílený výběr nabízí 1892 písem s kanonickou PDF identitou; při otevření kroku se načítá pouze zvolené písmo. Tým ukládá platnou rozepsanou adresu při pokračování a souhrn umožňuje návrat k úpravě.

- 88 cílených Flutter testů prošlo, včetně šesti nových regresí. Dva nové testy vyžadovaly opravu selektoru a očekávaného překladu; následně prošly.
- 19 SQL testovacích souborů prošlo na označené izolované databázi na portu 55432, včetně pozdějšího konce prodeje, obou voleb katalogu, skutečného stavu v potvrzení a odstranění banneru po vytvoření.
- 13 Deno testů náhledu e-mailu prošlo, včetně potlačení zděděného obrázku.
- Cílený Dart analyzátor: žádné chyby ani warningy; existující informační linty zůstávají. Generovaný registr odpovídá zdroji, kontrola whitespace bez nálezů.
- Dokončovací obrazovka zkontrolována z reálného Flutter widget renderu (`/tmp/festapp-wizard-completed.png`). Celý přihlášený tok v browseru ani produkční build v tomto kroku neběžel.

SQL migrace: `supabase/migrations/20261103143000_occasion_setup_feedback.sql`.
Případné nasazení musí zahrnout SQL migraci, Edge Function `occasion-setup-email-preview` a Flutter klienta. Backend nasadit před klientem. Produkce se neměnila.

## Architektonické sjednocení

Po druhé kontrole byly odstraněny lokální kopie pravidel:

- `forms/form_appearance_theme.dart` vlastní výběr režimu, barvy ovládacích prvků a pozadí. Používá jej veřejný formulář i náhled konceptu.
- `public.email_banner_wrapper_internal` vytváří wrapper pro uložený e-mail i autorizovanou projekci konceptu. Edge renderer už banner samostatně neskládá. HTML atributy se escapují u vlastníka.
- `OccasionSetupReviewRow` vykresluje všechny řádky souhrnu, včetně komunikace, bez injektovaného callbacku.
- Skupiny míst vlastní `SetupBlueprintConfiguration`, který filtruje existující místa a používá společné přirozené řazení. Přidání spoluorganizátora a potvrzení rozepsané adresy sdílejí validaci.
- Výsledek serveru vrací skutečné `isOpen`, `isHidden` a `isPromoted`. Model z nich pouze odvozuje textový stav zveřejnění; příznaky se vzájemně nenahrazují.

Ověření po sjednocení: 103 cílených Flutter testů, 19 SQL sad a 13 Deno testů prošlo. Po nahrazení řazení společným vlastníkem prošly znovu tři dotčené testy. Rozšířená analýza zahrnula veřejný formulář: žádné chyby, dva jeho již existující warningy (`duplicate_import`, `must_be_immutable`).

Nové regrese jsou přidané do společného CI kontraktu a jeho GitHub path filtrů. Lokální CI runner nastavuje neinteraktivní `CI=true` pouze procesům kontrol; ochrany Flutteru, databáze a produkce zůstávají aktivní. Regrese runneru a shoda workflow s kontraktem: 6 testů prošlo. Kompletní lokální CI je dokončené: všech osm kontrol prošlo.


## Kompletní CI po opravách

Všech 8 kontrol z `automation/ci/checks.json` prošlo v kanonickém lokálním mirroru. Prvních šest prošlo společně, poslední dvě po opravách dotčených SQL testů; žádná kontrola nebyla vypnutá.

Opraveno také:

- Neinteraktivní instalace závislostí v lokálním runneru (`CI=true`) s regresním testem.
- Generovaný kontrakt shody aktuálních SQL zdrojů, obnovený přes `automation/generate_canonical_source_contract.py`.
- Skutečná sekvence upgradu v `seating_concurrency.test.mjs`, která vynechávala dopřednou migraci `20261101173000_seating_compatibility_admissions.sql`. Neměnily se již aplikované migrace ani kontroly shody.

Souhrnný záznam je `/tmp/festapp-ci-all-eight.json`; samostatné logy jsou v `~/Library/Caches/festapp-ci/`. Záznam uvádí dvě spuštění a opravy SQL testů mezi nimi. GitHub CI na těchto nepublikovaných změnách spuštěné nebylo. Produkce se neměnila.
