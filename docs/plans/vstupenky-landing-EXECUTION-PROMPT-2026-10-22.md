# Realizace: úvodní stránka vstupenky.online pro plesy

## Organizace a efektivita

Koordinátor: `gpt-6-astra`, reasoning `medium` (Astra medium). Uživatel výslovně
požaduje efektivní práci se subagenty. Toto je zadání implementace, ne dalšího
obecného plánování. Koordinátor vlastní výsledný návrh, integraci a dokončení.

Po jednom společném cíleném průzkumu rozděl práci maximálně mezi tři souběžné
subagenty. Každému dej stručný samostatný handoff, přesné vlastnictví souborů,
vstupní fakta, výstup a validační hranici; použij `fork_turns="none"`. Nenechávej
všechny znovu číst celý repozitář nebo opakovat výzkum Tickenderu.

1. **Obsah a média:** `gpt-6-luna`, reasoning `low`. Inventura existujících
   skutečných referencí, assetů, editorových takes a příprava clip manifestu.
   Žádné vymyšlené citace/čísla, žádné změny routeru. Nejasná tvrzení eskalovat
   koordinátorovi místo drahého otevřeného pátrání.
2. **Routing a integrace:** `gpt-6-astra`, reasoning `medium`. Root marketing,
   `/events`, legacy vstupy, SEO a PWA podle plánu. Vlastní routing, generátorové
   kontrakty a cílené testy. Se změnami prezentační šablony se domluví přes přesný
   kontrakt; stejný soubor v jednu chvíli upravuje jen jeden vlastník.
3. **Kritika a porovnání:** `gpt-6-astra`, reasoning `medium`. Spustit teprve,
   když je konkrétní pilot nebo R3/R4 výsledek k posouzení. Čtení a nezávislé
   posouzení skutečných záběrů, scrollování a UI proti Tickenderu. Výstup nejvýše
   pět prioritních nálezů s důkazem a opravou. Žádná paralelní druhá implementace.

Koordinátor vede vizuální kompozici a pilot plánku. Po jeho kvalitativním
ověření může prvnímu agentovi zadat přípravu zbývajících samostatných takes
podle hotového režijního vzoru; při nedostatečné schopnosti změnit vlastníka
konkrétního úkolu, ne oslabit výsledek. Čisté natáčení celé sady nezačíná před
pilotem. Nečekej na subagenta, pokud lze nezávisle dokončit jinou část.

Vývojové změny dávkuj, nekontroluj každý edit zvlášť. Cílené checks spusť jednou
po ucelené integrační změně a znovu jen pro změněný kód nebo konkrétní selhání.
Nedělej plný Flutter build v každé iteraci landing page. Napříč všemi agenty
smí běžet jediná Flutter úloha; slot vlastní koordinátor. Browser sessions jsou
izolované, headless, s vlastním configem od prvního příkazu. Nespouštěj nové
servery pro statické galerie. Masters a takes nech mimo Git, opravuj jen
nevyhovující klipy. Zachovej standard ověření pro routing/PWA/auth vstupy.

## Zadání a autoritativní plán

Pracuj v `/Users/miakh/source/festapp`. Přečti `AGENTS.md`, `CLAUDE.md`,
`docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/vstupenky-landing-plan-2026-10-22.md`

Realizuj finální návrh R2 včetně jeho srovnávacích iterací R3 a R4. Root `/`
musí být propracovaná vlastní landing page, katalog je `/events` podle posledního
upřesnění uživatele. `/pro-poradatele` přesměruje na root. Primární příběh je
ples. Hlavní formát jsou samostatné krátké klipy u funkcí při scrollování:
plánek (sestavení i vzhled), formulář (pole i vzhled), vlastní design vstupenky,
výběr míst, odbavení a přehled. Každá funkce má vlastní sekci a video; nejde
o kapitoly společného filmu. Dlouhý sestřih pro YouTube je jen volitelný výstup. Použij skutečné reference; nejsou volitelné ani obecný blocker.

Použij `product-demo-video` včetně capture reference a `agent-browser` pro čisté
izolované nahrávky. Tickender je vybraný režijní směr, ne podnět k dalšímu
hledání konceptu. Dodrž část plánu „Závazný charakter“: čisté velké UI, vedené
gesto, okamžitá změna, čitelný výsledek a komponovaný reveal sekce. Nejdříve
ověř jeden pilot plánku proti referenci; pak stejný charakter rozšiř na ostatní
klipy. Samotný běžný screencast vedle textu nestačí. Zachyť skutečnou customizaci
plánku, formuláře i vstupenky
a její výsledek. Videa načítej postupně a přehrávej podle viditelnosti vždy jen
jedno; respektuj ruční pauzu, dokončení a reduced-motion. Skládání sálu je povinné: drag stolu, židle, kopie a hromadná
úprava. Nejprve prohlédni existující takes. Ověř skutečný zdroj editoru a handoff
stejného dokumentu do pickeru; nespojuj editor-only example střihem s falešným
platebním nebo rezervačním důkazem. Nepoužívej konkurenční média v produkci.

Zachovej existující registraci/admin, root legacy hash odkazy, scanner/auth
response policy a ostatní tenanty. Odkazy na katalog měň podle významu,
ne globálním nahrazením `/`. Videa vyluč z PWA precache. Obsah musí být použitelný
bez animace a při chybě JS nebo videa. Nevkládej browser analytics; aktuální
rozhodnutí je pouze serverové měření.

Před změnami zachovej rozpracovaný strom a zaznamenej source/live odchylku.
Veď obsah, URL, vizuální kompozici a vlastní média přes existující generátor a
build pipeline. Pokud skutečný stav vyvrátí premisu plánu, oprav plán s důkazem
a příslušnou vlnu; nesnižuj potichu rozsah skládání plánku, referencí nebo rootu.

Ověření standard pro veřejné směrování/PWA a vstup do aplikace. Použij cílené
existující testy a definovaný srovnávací scénář. Iteruj podle konkrétních nálezů,
ne do nekonečna. Finální galerie obsahuje skutečné desktop/mobil screenshoty,
scroll záznam všech sekcí, samostatné klipy a customizační varianty, porovnání před/po a stav každého kritéria. Neuváděj
neotestované návrhy jako hotové chování a subjektivní skóre jako konverzní důkaz.

Žádný deploy, commit, push, placené nákupy nebo produkční změny nejsou tímto
promptem autorizované. Případný pozdější release je pouze pro vybraný tenant
`prod/festapptickets` a podle místních release pravidel. Při předání stručně uveď
hotové chování, URL kontrakt, odstraněnou duplicitu, důkazy, ověření a přesné
zbývající kroky.

Nezastavuj po inventuře, rozdělení úkolů, návrhu nebo prvním pilotu. Dokonči
autorizovanou lokální implementaci, samostatné klipy, porovnání a cílené ověření.
Pokud konkrétní externí překážka blokuje část natáčení, dokonči nezávislé části
a popiš přesně chybějící přístup/asset; nevydávej placeholder za hotový výstup.
