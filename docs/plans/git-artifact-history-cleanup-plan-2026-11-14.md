# Odstranění generovaných API artefaktů z Git stromu a historie

Datum: 2026-11-14
Stav: Realizace zdrojové části a sjednocení worktree; přepis historie odložen
Ověřování: standard; povinné publikační a případné release brány zůstávají platné

## Výsledek a rozsah

Zastavit přidávání generovaných API specifikací, HTML dokumentace a jejich
historických kopií do Gitu. Odstranit jejich dosavadní verze z dosažitelné
historie schválených referencí. Změřit úsporu v novém klonu i po bezpečném úklidu
lokálních objektů. Zachovat zdrojový kód, vydané API, dokumentační URL a kontrolu
zpětné kompatibility. Samotný přepis historie nesmí nasadit žádnou aplikaci.

Uživatel 14. 11. zadal realizaci promptu a následně sjednocení rozpracovaných
worktree do mainu a odstranění začleněných pracovních adresářů. Tato autorita
pokrývá zdrojové změny a přípravu publikace. Produkční deployment není zadán.
Při budoucím spuštění respektovat dřívější požadavek historického odstranění,
ale také explicitní pravidlo rozsahu více tenantů: konkrétní dotčené `prod/*`
reference před zápisem vyjmenovat a zajistit oprávnění pro celý tento rozsah.
Bez něj připravit ověřený přepis offline, nepublikovat neúplnou historii jako hotovou.

Při realizaci zjištěno: main vyžaduje jednu schválenou recenzi a zakazuje
force-push. Během sjednocování vznikl nový worktree pro Android Slunovrat,
takže původní servisní freeze není uzavřený. Historie ani produkční refs se
nepřepisují. Výsledek a další brány eviduje doprovodný execution result.

Zvolený archiv je existující GitHub Releases v témže veřejném repozitáři,
release `api-contract-archive-20261114`. Export obsahuje 240 přesných historických
OpenAPI snapshotů ze všech lokálních referencí. Kontrola obsahu a hashů i nové
stažení proběhly; SHA256 archivu je
`650962babfd9fc4eef0eda39b77a4a607e2c37ac9af1e2cefec0c79e85ef0b39`.
JSON/HTML nejsou nositeli autorských nastavení. Malá metadata schválené vydané
baseline zůstávají v Gitu mimo generovaný adresář, bez změny stavu schválení.
Help potřebuje pouze veřejné adresy, proto je čte ze společného autorského
`api-facades.json`; nepotřebuje generovat celý API kontrakt při konfiguraci tenantu.

Mimo rozsah: plošné mazání jiných generovaných souborů, přepis databázových
migrací, změny API operací, produkčních dat či tajných údajů, nové placené služby,
autonomní vydání nebo nasazení tenantů. Další velké soubory pouze změřit a popsat.

## Doložený výchozí stav

Měřeno proti `origin/main` na `74b5aa7687e5076ffd6d05a238540117a56a3e03`.
Pracovní adresář byl na jiné, starší větvi a obsahoval 1805 změněných/nezařazených
cest; existuje řada dalších připojených worktree. Při realizaci stav znovu změřit,
nepřebírat zdejší seznam větví jako aktuální.

| Fakt | Důkaz / vlastník | Důsledek |
|---|---|---|
| API artefakty: 210 souborů, 332 057 430 bajtů, 8 438 461 řádků | `git ls-tree -rl origin/main`, obsah blobů pod `tools/festapp/contracts/api-v1/` | Hlavní cíl očisty |
| Historické kopie: 184 souborů, 7 739 642 řádků | Podadresáře `*/contracts/<digest>/openapi.json` | Archiv patří mimo Git |
| Osm aktuálních projekcí | `tools/festapp/src/remote/endpoints.mjs`: dvě fasády, dva datové a dva proof profily | Všechny zachovat |
| Generátor ukládá aktuální i nové historické soubory | `scripts/generate-api-reference.mjs`: `generate`, `sourceDigest`, `projectionDigest` | Nahradit přibývající archiv build výstupem |
| HTML bundluje Redoc a specifikaci | `scripts/build-api-docs.mjs` | Generovat při buildu |
| Vydaná baseline odkazuje na snapshoty | `contracts/api-v1/release-baseline.json`, `scripts/check-api-compatibility.mjs` | Před odstraněním exportovat a ověřit baseline |
| Runtime obsluhuje i immutable URL podle digestu | `src/remote/api-transport.mjs`, `/contracts/:digest/openapi.json` | Staré zveřejněné URL zachovat externím archivem / balíčkem |
| Docker kopíruje celý adresář | `tools/festapp/Dockerfile.remote` | Build musí nejdřív vytvořit explicitní artefakt |
| Další konzumenti čtou generované soubory | `integrations/make/scripts/build.mjs`, `automation/release/render_help_pages.mjs`, `test/api-contract.test.mjs`, `test/api-docs.test.mjs` | Změnit pořadí přípravy ve všech vstupních bodech |
| Lokální Git má cca 1 023 MiB v packech a 138 MiB loose objektů | `git count-objects -vH` | Není to celé velikost API ani garantovaná úspora |

Čísla výše jsou velikosti textů v aktuálním stromu, nikoli velikost komprimovaného
klonu. Týdenní počet přidaných řádků navíc počítá opakované změny. Cíl 300 000
řádků vlastního kódu dosud nebyl změřen a není akceptační podmínkou tohoto úkolu.

## Cílová architektura a invarianty

1. Zdrojem pravdy jsou katalog operací, schémata a generátor pod
   `tools/festapp/src` a `tools/festapp/scripts`. API obsah se nemění.
2. Aktuální JSON/HTML/manifesty vznikají do ignorovaného build adresáře.
   Preferovat zachování současné relativní struktury v
   `tools/festapp/contracts/api-v1/`, ale přesunout malé autorské release metadata
   mimo tento adresář. Celý výstupní adresář pak lze ignorovat i historicky vyříznout.
3. Generátor běžného vývoje vytváří pouze osm aktuálních projekcí. Immutable
   archiv vytváří oddělený release krok; každé spuštění nesmí archivovat další kopie.
4. Obsahový digest kontraktu neobsahuje digest celého implementačního stromu.
   Provenienci (`sourceSha`, digest vstupů, toolchain) vést odděleně v manifestu.
   Změna identity nových artefaktů nesmí přepsat bajty pod starými digesty.
5. Připnuté vydané baseline a dosud zveřejněné immutable kontrakty jsou mimo Git,
   obsahově ověřené a obnovitelné. V Gitu zůstávají malé autorské metadata,
   schválení a lokátory s hashi. Dostupnost archivu je povinná, žádné tiché přeskočení
   kompatibility při výpadku. Není-li znám úplný seznam publikací, archivovat
   konzervativně všechny dosavadní snapshoty mimo Git.
6. Build/test/Make/help mají jedinou explicitní přípravu artefaktů. Runtime
   používá sestavené lokální soubory; nevyrábí dokumentaci pro každý požadavek.
7. Ve schváleném přepsaném grafu žádný commit neobsahuje vyřazené API cesty.
   Jiné soubory mají nezměněný obsah, kromě zdokumentovaných nutných aktualizací
   interních SHA odkazů a implementace tohoto plánu.
8. Obnovení starého klonu nebo merge staré větve nesmí vrátit odstraněnou historii.
   Hlídání v CI kontroluje index i nově dosažitelné commity, ne pouze `.gitignore`.

## Předpoklady, oprávnění a stop podmínky

- Existuje vhodné již používané úložiště artefaktů. Při realizaci ověřit jeho
  oprávnění, trvalost, adresaci a obnovu. Nepřesouvat automaticky do veřejného
  úložiště bez kontroly obsahu a určení publikačního rozsahu. Nový placený produkt
  vyžaduje zvláštní souhlas. Zvolený backend zapsat do tohoto plánu před implementací.
- Hosting musí dovolit přepis všech dotčených schválených referencí. Ověřit
  ochrany větví, tagy, otevřené PR, release odkazy a servisní boty; pravidla
  automaticky nevypínat. Zamítnutí znamená konkrétní blokátor.
- Repozitářové SHA jsou používány například v tenant overlay `baseMainSha`,
  release dokladech a manifestech. Nestačí přepsat názvy větví. Je nutný inventář
  a ověření ancestry; libovolné nahrazování čtyřicetiznakových řetězců je zakázáno.
- SHA a podpisy přepsaných commitů/tagů se změní; historické CI výsledky na nové
  SHA nepřecházejí. Před příštím release znovu splnit canonical exact-SHA CI gate.
- Skryté reference PR, forky, cache a serverové GC nejsou pod kontrolou běžného
  Git push. Jejich chování ověřit v aktuální oficiální dokumentaci hostingu při
  realizaci; nevydávat přepsané větve za důkaz fyzického odstranění na GitHubu.

## Exekuční vlny

### 0. Servisní okno a obnova

**Cíl:** Nikdo současně nepoužívá měněný graf.

- Ověřit s vlastníky relací nečinnost všech worktree, agentů, buildů, release,
  automatických pushů a CI jobů, které mohou publikovat. Samotný výpis procesů
  nebo uplynutí několika minut není důkaz nečinnosti. Cizí procesy nezastavovat.
- Získat výlučný servisní zámek respektovaný aktivními vlastníky. Při nedostupném
  okně skončit s odloženým stavem; nic neplánovat na konkrétní čas bez zadání.
- Uložit mimo repozitář a jeho běžně klonované adresáře: mirror/bundle všech
  vlastněných referencí, ref inventář, konfiguraci a kontrolní součty. Samostatně
  zálohovat staged/unstaged/untracked práci všech worktree, včetně ignorovaných
  uživatelských dat, která by se při obnově mohla ztratit. Tajné soubory ponechat
  v chráněné lokální záloze, nikdy je necommitovat ani nevypisovat.
- Ověřit obnovu do odděleného adresáře a manifest obsahu, nikoli jen existenci
  souboru. Neprovádět `reset --hard`, `clean` ani repack živého sdíleného checkoutu.
- Změřit disk, objekty, fresh-clone velikost a ref SHA před operací.

**Výstup:** Obnovitelná záloha, záznam servisního okna a uzavřený seznam vlastníků.

### 1. Inventář a export publikovaných kontraktů

**Cíl:** Nic potřebného pro běžící nebo budoucí vydání není závislé pouze na Gitu.

- Z čerstvého odděleného klonu načíst všechny heads/tags; inventarizovat vlastní
  lokální větve a worktree, dosažitelné odstranitelné bloby, tagy, PR reference,
  release metadata, ochrany a automatizace. Neprovádět slepý mirror push.
- `git grep` nad aktuálním autoritativním main a relevantními nástroji dohledá
  konzumenty `contracts/api-v1`, immutable URL a starých SHA. Zvlášť projít
  `automation/tenant-overlay.json`, drift policy, CI selection a podpisy/tagy.
- Exportovat baseline v přesných původních bajtech a všechny potřebné snapshoty
  do zvoleného externího archivu. Ověřit hash, opakované stažení a obnovu bez
  původního checkoutu. Schválení vydání nesmí být ztraceno s mazaným adresářem.
- Sestavit přesný manifest old SHA, refs, zamýšlený nový SHA, scope a vlastník.
  Všechny dotčené prod větve vyjmenovat a vyřešit oprávnění před publikací.

**Výstup:** Export je nezávisle obnovitelný; každý dotčený ref i SHA konzument má postup.

### 2. Zastavení nového růstu a migrace konzumentů

**Cíl:** Nový checkout umí bez verzovaných výstupů build, test i balení.

- Upravit `generate-api-reference.mjs`, `build-api-docs.mjs`, package skripty,
  `.gitignore`, `check-api-contract.mjs`, `check-api-compatibility.mjs` a README.
  Oddělit metadata baseline od generovaného adresáře; ověřovat externí baseline
  proti připnutým hashům. Nepřeznačovat vydanou baseline na nepublikovanou.
- Docker použije build stage s připnutým pnpm/toolchainem nebo explicitně
  ověřený vstupní balíček; runtime image obsahuje pouze požadované artefakty.
  Původní generátor vyžaduje Git metadata a širší zdrojové vstupy: přizpůsobit
  předávání provenience pro build bez `.git`, nekopírovat implicitně starý strom.
- Make builder, help renderer, CI `mcp-auth-contract` a testy dostanou explicitní
  přípravu. Žádný test nesmí projít pouze díky souborům z minulého checkoutu.
- Runtime immutable URL zachová přesné historické bajty z ověřeného archivu
  materializovaného do release balíčku. Existující nasazení není tímto úkolem měněno.
- Přidat úzkou CI ochranu před sledováním generovaného adresáře i znovuzavlečením
  vyřazených blobů/history přes merge. Zahrnout i výslovné `git add -f`.
- V čistém klonu provést `pnpm install --frozen-lockfile` v package adresáři,
  připravit všechny projekce, cílené API/docs/transport/Make testy a příslušné
  canonical CI mirror lanes z `automation/test_ci.sh` dle současné selection policy.
  Ověřit druhou generaci na stejných vstupech a beze změny sledovaného stromu.
- Před publikací implementace fetch aktuální main a zopakovat pouze checks
  zneplatněné jeho změnami. Publikovat podle repo pravidel a udržet write freeze.

**Výstup:** Konzumenti jsou migrováni, běžný build nehromadí snapshoty, CI brány prošly.

### 3. Offline přepis historie a důkaz zachování

**Cíl:** Připravit úplný a kontrolovatelný nový graf bez zbytečných artefaktů.

- V jednorázovém samostatném klonu použít `git filter-repo`; dostupnost nástroje
  byla ověřena. Nikdy ho nespouštět v dnešním dirty repozitáři s worktree.
- Přesná deletion sada: celý `tools/festapp/contracts/api-v1/` ve všech historických
  názvech doložených inventářem. Předem exportovaná autorská metadata nyní žijí
  mimo tuto sadu. Nemažte jiné kontrakty, migrace ani autorská schémata.
- Zpracovat všechny schválené dotčené refs v jednom konzistentním grafu.
  Uchovat commit/ref mapu mimo Git. Neudržovat záložní refs na původní graf uvnitř
  běžného repozitáře a neposílat je na origin.
- Připravit explicitní transformaci pouze skutečných strojových SHA referencí
  (zejména `baseMainSha`). Řešit, že dodatečný commit mění SHA znovu: finální mapa
  musí zahrnout finální topologii a ověřit ancestry. Nedělat plošný textový replace.
  Historické důkazní receipts nezfalšovat: označit jako předpřepisovou provenienci
  s externí mapou; autoritativní aktuální metadata musí fungovat na novém grafu.
- Pro každý původní/nový commit ověřit strom bez vyřazených cest, se zvláštní
  allowlist transformací metadata; pro všechny zachované větve ověřit ancestry,
  tenant drift a obsahové rozdíly. Nepřepisovat tenant konfiguraci na jiné hodnoty.
- Z nového grafu v čistém checkoutu zopakovat affected canonical mirror lanes.
  Zkontrolovat, že všechny dosažitelné commit stromy neobsahují vyřazené cesty,
  nikoli jen HEAD. Změřit pack po GC pouze tohoto jednorázového klonu.

**Výstup:** Kompletní final ref mapa, žádné odstranitelné cesty v grafu, zachované
ostatní stromy, ověřená metadata a prokazatelná úspora.

### 4. Řízená publikace přepsaných referencí

**Cíl:** Origin odkazuje na ověřený nový graf bez ztráty souběžné práce.

- Těsně před zápisem znovu načíst remote heads/tags a porovnat přesný snapshot.
  Jakýkoli posun ruší připravený publish; integrovat nové změny a přepočítat ověření.
- Push pouze explicitních schválených refspeců s očekávaným původním SHA
  (`--force-with-lease=<ref>:<old>`). Pokud server podporuje atomický push, použít
  jej pro celou potřebnou sadu. Žádný obecný `--force`, žádný `push --mirror`.
- Pokud atomický zápis není dostupný, předem stanovit sekvenční transakční postup,
  uzavřený write freeze a ověřený návrat konkrétních refs při částečném selhání.
- Neobcházet branch protection a CI. Nechat proběhnout povinné CI na novém main.
  Příští tenant release musí projít exact `baseMainSha` gate podle
  `automation/ci/release_gate.py`; staré úspěchy nejsou přenositelné.
- Tagy, releases a otevřené PR podle inventáře opravovat vědomě; neodstraňovat
  automaticky artefakty vydání. Produktové deploy workflow nesmí být vyvoláno
  vedlejším účinkem přepisu prod refs; pokud to nelze zaručit, publikace čeká.

**Výstup:** Readback každé schválené reference odpovídá mapě, žádná novější práce nezmizela.

### 5. Nové klony, lokální úklid a hosting

**Cíl:** Odstraněná data se nevrátí a běžná práce je nezávislá na starém klonu.

- Ověřit skutečný nový klon z origin přes síť, ne lokální hardlink clone. Změřit
  přenos, `.git` velikost a dosažitelné objekty; ověřit absenci vyřazených cest.
- Všechny aktivní pracovní adresáře obnovit z nového klonu a zálohovaných změn.
  Lokální nepublikované commity transplantovat přes kontrolované patche na nové
  báze; nemergovat původní historii. Ověřit staged/unstaged/untracked obsah
  a funkční worktree. Starý klon držet do ověření v karanténě bez možnosti push.
- Teprve po obnově všech vlastníků odstranit staré klony/worktree nebo bezpečně
  prořezat jejich objekty. Žádné `gc --prune=now` v používaném sdíleném checkoutu.
- Inventarizovat skryté hosting refs, PR diffs, forky a cache; ověřit dostupné
  postupy odstranění a serverového GC u hostingu. Pokud je nutná součinnost
  podpory nebo vlastníka forku, zapsat přesný zbytkový stav. Nikdy nehlásit
  fyzické odstranění ze všech serverových záloh jen podle úspěšného push.
- S externí zálohou zacházet jako s dočasnou obnovovací výjimkou: termín
  přehodnocení 14 dní po úspěšné obnově všech vlastníků, potom odstranit se
  souhlasem vlastníka zálohy. Žádné trvalé duplikované gigabajty pod `source/`.
  Vydané API artefakty v externím archivu jsou úmyslná dlouhodobá výjimka.

**Výstup:** Ověřené nové klony, obnovená práce, odstraněné běžné lokální staré
objekty a pravdivý záznam dosažitelného versus fyzického serverového odstranění.

## Deletion ledger

| Objekt | Konečný stav | Důkaz |
|---|---|---|
| Aktuální API JSON a HTML v indexu | Jen ignorovaný build výstup | Čistý klon umí generovat; `git ls-files` je neuvádí |
| Historické digest snapshoty v Gitu | Z žádného schváleného ref nedosažitelné | Audit všech commit stromů a blobů |
| Autorské baseline metadata v mazané složce | Malý verzovaný soubor jinde | Zachované schválení a ověřená externí baseline |
| Archivování při každém `api:generate` | Odstraněno | Opakování nepřidává snapshoty |
| Čtení build výstupu bez přípravy | Odstraněno z Docker/CI/Make/help/test | Čistý build a canonical checks |
| Staré refs/reflogy/klony držící objekty | Po obnově odstraněny nebo explicitní karanténa | Ref/object/disk inventář |
| Staré veřejné immutable API URL | Zachovány mimo Git | Přesné bajty, digest, ETag a cache chování |

## Návrat a dokončení

Před publikací lze zahodit jednorázový přepis. Po publikaci neobnovovat starý graf
obyčejným merge. Nouzový návrat provádět jen podle uloženého inventáře pod write
freeze, s leases a následným readbackem; znamená dočasný návrat velkých objektů,
ne splnění cíle. Běžící aplikace mají dál používat existující immutable release
artefakty, nikoli záviset na dostupnosti starých commit SHA.

Hotovo znamená současně: žádné verzované generované API výstupy ani jejich
historie ve všech schválených refs; fungující build/CI/kompatibilita/immutable URL;
platná tenant ancestry a metadata; obnovená nepublikovaná práce; změřený čistý
klon a lokální disk; žádný mechanismus běžného návratu starého grafu. Odděleně
uvést případné zbylé serverové objekty či externí forky a vlastníka jejich úklidu.
Dokud chybí povinný ref nebo je neobnovená práce, neoznačovat úlohu jako hotovou.
