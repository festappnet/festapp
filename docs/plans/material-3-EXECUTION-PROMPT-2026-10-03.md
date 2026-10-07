# Festapp: migrace Flutter UI na Material 3

Proveď rychlou a cílenou migraci Flutter UI Festappu z Material 2 na Material 3.

Nejprve přečti AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md. Zkontroluj aktuální větev a pracovní změny. Zachovej rozpracovanou práci uživatele, zejména editor vstupenek. Sdílený kód patří na main; případnou izolaci práce proveď bez ztráty nebo přenášení nesouvisejících změn.

## Cíl

Celá Flutter aplikace používá společný Material 3 základ ve světlém i tmavém režimu. Zachovej branding, font, tenant konfiguraci a funkční chování. Nepřidávej novou UI knihovnu ani Material 3 Expressive.

## Známá výchozí místa

Před úpravou ověř aktuální stav:

- `lib/theme_config.dart`: hlavní motiv má `useMaterial3: false` a `ColorScheme.fromSwatch`.
- `lib/main.dart`: motivy zapojuje `AdaptiveTheme`.
- `lib/components/occasion/occasion_home_page.dart`: používá `BottomNavigationBar`.
- `lib/components/timeline/advanced_timeline_day_list.dart`: odsazení odkazuje na `kBottomNavigationBarHeight`.
- Editor vstupenek už má vlastní Material 3 motiv.
- `automation/apply_config.sh` zapisuje tenant barvy do `ThemeConfig`.

## Postup

1. Sjednoť tvorbu světlého a tmavého motivu na Material 3 a odpovídajícím `ColorScheme`. Zachovej konfigurovatelné barvy a čitelnost jejich kontrastních protějšků. Společné styly definuj centrálně, lokální výjimky přidávej pouze z konkrétní potřeby.
2. Převeď `BottomNavigationBar` na `NavigationBar` a `NavigationDestination`. Zachovej pořadí a dostupnost záložek, přihlášení, badge, modální vyhledávání, opakované klepnutí a uchování stavu mapy. Uprav související odsazení podle skutečného layoutu.
3. Zkontroluj program, detail události, profil, formuláře a administraci. Oprav konkrétní konflikty ručních barev, typografie a pevných rozměrů s novým motivem. Existující vlastní editory a tabulky uprav jen tam, kde vznikne problém.
4. Nepřepisuj plošně všechny widgety. Nabídky a výběrová pole nahrazuj pouze tehdy, pokud je to nutné pro cílový vzhled nebo správné chování.

## Rozsah

- Flutter aplikace včetně Flutter webu.
- Samostatný `web_client` ponech beze změn, pokud nenajdeš přímou nezbytnou závislost; případný návrh změny pouze uveď.
- Bez změn backendu, obchodní logiky, SDK či závislostí, pokud migraci neblokují.
- Bez nasazení, pushování a propagace do dalších tenant větví.

## Efektivita

Udělej jednu cílenou rešerši kódu, potom souvislý implementační celek. Neopakuj čtení a kontroly bez důvodu. Rutinní implementační rozhodnutí vyřeš samostatně. Průběžné zprávy drž stručné.

## Ověření

Použij `verification: standard`, protože měníš sdílené chování aplikace.

- Používej `fvm`.
- Spusť cílenou analýzu změněných Dart souborů.
- Spusť relevantní testy motivů, navigace, programu a systémových lišt. Doplň smysluplné regresní testy změněného chování.
- Ověř hlavní obrazovky v light/dark režimu, na úzkém mobilu a desktopu, se zvětšeným písmem a českými texty.
- Browser kontroly prováděj v izolované relaci na pozadí podle pravidel repozitáře.
- Dostupné kontroly Androidu/iOS proveď cíleně; chybějící platformní ověření výslovně přiznej.
- Kontroly seskup až po souvislé změně; opakuj je jen po relevantní opravě.

## Dokončení

Společné motivy používají Material 3, spodní navigace funguje beze změny významu akcí a kontrolované obrazovky nemají nečitelné prvky, přetékání ani překrytý obsah. Tenant barvy a přepínání motivů zůstávají funkční.

Na závěr stručně uveď provedené změny, výsledky ověření a konkrétní zbývající omezení. Neoznačuj neprovedené kontroly za úspěšné.
