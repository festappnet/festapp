# Měření startu Flutter webu vstupenky.online

Navazující lokální úpravy a jejich ověření popisuje [implementační záznam](flutter-web-startup-implementation-2026-10-14.md). Níže zůstává původní měření před úpravou.

Datum: 2026-10-14. Účel: změřit možnosti oddělení kódu při přímém vstupu do administrace a ověřit chování odloženého načítání v PWA. Produkční implementace ani nasazení se neměnily.

## Výsledek

Nejlepší první kandidát je odložené načítání knihovny `google_fonts`, kterou používá vzhled veřejného formuláře a editor jeho designu. Její dynamický katalog představuje přibližně 10,07 MB výsledného JavaScriptu. Nejde o soubory písem: ty tvoří další, samostatný náklad.

Experiment odložil tuto knihovnu ve dvou místech použití, bez přepínání všech rout. Počáteční JavaScript klesl o 47,5 % před kompresí, o 19,6 % v gzip a o 18,0 % při stejně nastavené Brotli kompresi. Přibyly tři části. Pokus není hotová produkční implementace: vyžaduje ošetření chyby načítání, opakování a ověření konkrétních obrazovek.

## Srovnání skutečných buildů

Všechny hodnoty jsou desetinné MB. Komprese: gzip level 9 a Brotli quality 9, vždy stejné pro všechny varianty. Jde o lokální srovnávací kompresi, nikoli přesné nastavení CDN.

| Varianta | Počáteční JS | Počáteční gzip | Počáteční Brotli | Oddělené soubory | Celý JS v Brotli |
|---|---:|---:|---:|---:|---:|
| Současný kód | 21,33 MB | 3,78 MB | 3,09 MB | 0 | 3,09 MB |
| Odložené routy plošně | 8,17 MB | 2,21 MB | 1,87 MB | 487 | 3,48 MB |
| Pouze odložené `google_fonts` | 11,19 MB | 3,04 MB | 2,54 MB | 3 | 3,04 MB |

Plošné odložení rout nevystihuje celý start konkrétní administrace. Podle importů kompilátoru potřebují routy rezervací a objednávek společně přibližně 19,38 MB JavaScriptu / 3,32 MB gzip včetně základu a 204 dalších souborů. Google Fonts katalog se v této variantě stále přitáhne s objednávkami. Toto je výpočet závislostí, nikoli měření vykreslení přihlášené stránky.

Plošné přepnutí také neprošlo kompilací bez výjimek: typy `MapEditorMode` a `NewsSubmission` jsou součástí argumentů rout a generátor je odkazoval přes odložený import. V měřené variantě zůstaly knihovny mapové stránky a editoru novinek eager. Automatické přepnutí všech rout proto nedoporučuji jako první produkční změnu.

## Co zabírá místo

`--dump-info` přisuzuje jednotlivým knihovnám a balíčkům následující velikosti generovaného kódu. Hodnoty nejsou velikostí stažených balíčků z pub.dev ani úplným součtem výsledného souboru; kompilátor má také společnou režii a konstanty.

| Balíček | Generovaný kód před kompresí |
|---|---:|
| `google_fonts` | 10,07 MB |
| Vlastní `fstapp` | 2,64 MB |
| `flutter` | 2,04 MB |
| `timezone` | 0,81 MB |
| `super_editor` | 0,42 MB |
| `image` | 0,32 MB |
| `trina_grid` | 0,25 MB |

Samotný vlastní kód editoru vstupenek má přibližně 163 kB, mapových komponent 152 kB a blueprintu 63 kB. Tyto hodnoty nezahrnují jejich sdílené závislosti a nelze je automaticky pokládat za odstranitelnou velikost počátečního balíku. Jsou výrazně menší než katalog písem.

Předchozí živé měření `/login` dále zachytilo 16 fontových souborů: 1 952 271 přenesených bytů / 4 341 436 bytů po rozbalení. Obsahovaly základní Lucide a šest váhových variant, Geist a font z `golden_toolkit`. Tento náklad se experimentem s `google_fonts` neodstranil. Jeho redukce je samostatná vhodná práce.

## PWA: co je ověřené

Současný `automation/generate_pwa_service_worker.mjs` a `automation/lib/pwa_shell_manifest.mjs` zahrnují všechny `main.dart.js_<n>.part.js` do atomického instalačního cache. Při dokončené instalaci tedy může být oddělený kód dostupný offline ještě před prvním otevřením příslušné funkce.

V izolovaném headless Chromium byl spuštěn malý skutečně zkompilovaný Dart program s `deferred import`, dvěma verzemi a service workerem generovaným přímo tímto projektem. Nešlo o ručně simulované soubory vydávající se za Dart chunk. Pro offline kroky byl HTTP server fyzicky zastaven; běžný nekachovaný požadavek současně selhal.

| Scénář | Výsledek |
|---|---|
| Instalace v1, offline reload, první vyvolání odložené funkce | Vrátila `feature-v1`, nekachovaný síťový požadavek selhal |
| Druhá karta přijala v2 a obnovila se; původní v1 karta funkci dosud neotevřela; server vypnut | Stará karta vrátila `feature-v1`, nedošlo k promíchání verzí |
| Karta s v2 se obnovila při vypnutém serveru a otevřela odloženou funkci | Vrátila `feature-v2` |

Karta, která sama odesílá `SKIP_WAITING`, se musí po aktivaci obnovit, jak vyžaduje současný produkční aktualizační tok. Pokus ponechat tuto kartu běžet na starém runtime po přijetí aktualizace selhal při načítání staré části. Ochrana v service workeru záměrně odmítá starou verzi právě u iniciátora aktualizace. Ostatní otevřené karty si mohou ponechat starou generaci. Test s dvěma kartami tuto podporovanou variantu ověřil.

## Podmínky a neověřené části

- Rozdělení zrychluje zpřístupnění potřebného kódu, ale při zachování všech funkcí offline nesnižuje zásadně celkový instalační objem. PWA musí zbývající části stáhnout na pozadí a dokončit instalaci před deklarací offline připravenosti.
- Pokud browser cache odstraní nebo dojde místo, dříve připravená část může chybět. Současná ochrana odmítá smíchat starý hlavní soubor s novou částí a v některých případech obnovuje kartu. Je potřeba ošetřit chybu a rozpracované formuláře; nezaručovat zachování konceptu při nucené navigaci.
- Offline dostupnost katalogu Google Fonts neznamená offline dostupnost binárního souboru každého z tisíců fontů. Dosud nepoužité externí písmo se nemusí dát offline stáhnout. Tato vlastnost existuje již před rozdělením.
- Není provedeno kompletní E2E přihlášené Flutter administrace s experimentálním buildem, měření času před/po, test iOS standalone PWA ani tlak na kvótu úložiště. Výsledky dokazují velikosti buildů a chování odloženého Dart kódu se skutečným service workerem, nikoli úplnou připravenost k nasazení.
- Buildy vycházejí z aktuální rozpracované pracovní kopie, nikoli ze zdrojů garantovaně identických s živou verzí `0.20.198+682`. Lokální konfigurace má `0.20.1+485`; konfigurace se kvůli měření nepřepínala a produkce se neměnila.

## Doporučené pořadí

1. Samostatně zredukovat nadbytečné binární fonty a varianty ikon.
2. Produkčně dopracovat úzké odložení `google_fonts`: explicitní načítání při potřebě, chybu a opakování. Zachovat současné přednačítání všech tří částí do PWA cache.
3. Na této variantě změřit přímý vstup do administrace organizátora i objednávek, zvlášť čistou a připravenou PWA cache. Ověřit vzhled formulářů a editor designu.
4. Až potom rozhodnout o dalších hranicích pro editory. Plošné přepínání všech rout přineslo stovky požadavků a pro objednávky výrazně menší úsporu, než napovídá velikost samotného hlavního souboru.

## Reprodukce a evidence

Použitý toolchain: Flutter 3.47.2, Dart 3.13.2. Každý experiment proběhl ve zdrojové kopii pod `/tmp/festapp-startup-audit-20261014/source`. Základní příkaz:

```sh
fvm flutter build web --release --no-pub --base-href / \
  --no-web-resources-cdn --no-wasm-dry-run --dump-info \
  --output /tmp/festapp-startup-audit-20261014/baseline
```

Předtím `fvm flutter pub get --offline` v kopii. U varianty rout následovala změna anotací a `fvm dart run build_runner build --delete-conflicting-outputs`. Varianta pouze fontů vycházela z původního routeru. Experimentální patche jsou v [adresáři evidence](flutter-web-startup-evidence-2026-10-14/). Neaplikovat plošně na aktuální pracovní větev; jde o měřicí prototypy.

V kopii vznikly kompletní `main.dart.js.info.json` (stovky MB), JS soubory a logy. Do repozitáře jsou uloženy jen malé souhrny, patche, zdroje PWA sondy a výsledky. `analyze_info.py <adresář-buildu>` znovu získá rozpad z dump-info.

Zdroje PWA sondy lze zkopírovat do samostatného dočasného adresáře: `pwa-probe-main.dart` jako `compiler/main.dart` a `pwa-probe-feature.dart` jako `compiler/feature.dart`. Zkompilovat `fvm dart compile js -O4 -o <tmp>/v1/main.dart.js <tmp>/compiler/main.dart`, změnit `feature-v1` na `feature-v2` a zkompilovat do `v2`. Server spustit s `FESTAPP_PWA_PROBE_ROOT=<tmp> FESTAPP_REPO_ROOT=<repo> node <evidence>/pwa-probe-server.mjs`. Používá port 4187 a endpoint `/__switch?version=v2`; `auditReady`, `loadAuditFeature()` a `auditUpdate()` jsou prohlížečová rozhraní sondy. `auditUpdate()` volat v druhé kartě a tuto kartu obnovit; první nechat na původní verzi. Potom zastavit server a vyvolat funkci v obou kartách. Žádný testovací server po měření nezůstal běžet.

Kontroly: `pwa_reconcile.test.mjs` a `pwa_manifest.test.mjs` prošly (2 testy). Původní `pwa_offline.test.mjs` narazil na zastaralý textový požadavek, že `npm ci` a `npm run build` musí být na jednom řádku. V dočasné kopii byl upraven jen tento regex; celá sada pak prošla. Repozitářový test zůstal beze změny. Podrobnosti a strojové výsledky: [checks.txt](flutter-web-startup-evidence-2026-10-14/checks.txt), [comparison.json](flutter-web-startup-evidence-2026-10-14/comparison.json), [pwa-results.json](flutter-web-startup-evidence-2026-10-14/pwa-results.json).
