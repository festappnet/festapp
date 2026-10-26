# Živé ověření optimalizace Flutter webu - 2026-10-14

Ověřená verze vstupenky.online: `0.20.205+689`; na začátku i na konci měření shodná. Prohlížeče byly izolované a headless, bez přihlášení. Produkce ani její data se neměnily.

## Prokázaný dopad na produkci

| Položka | Před: 0.20.198+682 | Nyní: 0.20.205+689 |
|---|---:|---:|
| Hlavní JS před kompresí | 21 079 461 B | 10 945 750 B |
| Hlavní JS, skutečný Brotli přenos | 3 489 796 B | 2 890 492 B |
| Fontové soubory požadované při startu | 16 | 9 |
| Přenos fontů v browser Resource Timing | 1 952 271 B | 741 489 B |

Oba hlavní JS soubory byly při ověření dostupné přes své skutečné verzované produkční URL. Byly staženy se stejným `Accept-Encoding: br` a dekomprimovány pro kontrolu velikosti. Aktuální JS odkazuje na `main.dart.js_1.part.js`.

Hlavní balík je o 48,1 % menší před kompresí a o 17,2 % menší při skutečném přenosu. Požadavky na fonty přenášejí přibližně o 62 % méně dat. Dohromady hlavní JS a automaticky načítané fonty představují asi o 1,8 MB menší úvodní přenos. Toto není tvrzení o celkovém provozu: PWA si odložený katalog nadále stahuje při instalaci na pozadí.

Předchozí fontový přenos pochází z dřívějšího čistého měření v tomto rozhovoru. Nové měření přímo zachytilo všech devět fontových požadavků a produkční FontManifest potvrzuje odstranění šesti nepoužitých váhových variant Lucide a fontu golden_toolkit.

## Časová měření a jejich hranice

Stejná vstupní cesta `/unit/1/edit` byla otevřena ve třech čistých profilech a dvakrát opakovaně s cache. Nepřihlášený profil následně skončí na `/login`; nejde o benchmark načtených administrátorských dat.

- Čisté starty do signálu `festapp-app-ready`: 1.88 s, 2.57 s, 1.61 s; medián 1.88 s.
- Opakované starty s cache: 0.31 s, 0.17 s.

Signál neprokazuje dokončené načtení konkrétní administrátorské záložky. Mezi starou a novou verzí byly i jiné změny startu; starší měření navíc použilo jinou cestu a síťové podmínky. Proto z těchto časů neodvozujeme procento zrychlení způsobené touto optimalizací.

Pro přesné ověření dopadu na práci organizátora je potřeba porovnat stejný přihlášený účet, událost a záložku, stejné zařízení a síť a měřit až skutečně připravenou tabulku. V tomto ověření nebyla převzata uživatelova přihlášená browser session.

## PWA

Živá cache `festapp-app-shell-0.20.205+689` obsahovala přesný verzovaný hlavní soubor i `main.dart.js_1.part.js`. To potvrzuje, že se oddělený katalog na produkci instaloval do cache. Nebyl proveden nový plný offline test přihlášené administrace ani iOS standalone režimu.

Strojová evidence: [summary.json](flutter-web-startup-live-evidence-2026-10-14/summary.json). Příslušný adresář obsahuje jednotlivé Resource Timing a naměřené časové záznamy. Všechny měřicí browser sessions byly uzavřeny.
