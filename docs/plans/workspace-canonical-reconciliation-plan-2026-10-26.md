# Sjednocení pracovního adresáře s kanonickým main

Datum: 2026-10-26. Stav: lokálně sjednoceno a ověřeno; výsledek zůstává necommitovaný.
Ověřování: standard. Notification feed je dokončen nad sjednoceným základem.

## Výsledek

Jeden aktuální sdílený základ obsahuje pozdější opravy z main i skutečně novou
lokální práci. Staré kopie již začleněného kódu se nevrátí jako nové změny.
Centrum upozornění pak naváže na existující oprávnění a inicializaci organizace,
nikoli na odstraněnou aktivační architekturu. Původní rozpracovaný obsah zůstane
obnovitelný a žádný tenant se tímto postupem nenasazuje.

## Co se skutečně stalo

| Doložený fakt | Důkaz | Význam |
|---|---|---|
| Pracovní adresář zůstal na starém předkovi main. | HEAD `353394511`, větev `feat/occasion-setup-wizard-20261007`; `git merge-base HEAD main` vrací HEAD; `0/1088` commitů. | Není to nová větev s vlastními nezaintegrovanými commity. |
| Připravená práce byla už jednou uložena a začleněna. | Snapshot `d4dc170b1`, merge `6c7b73615` z 24. 10. | Nelze považovat celý rozdíl proti starému HEAD za nové změny. |
| Existuje další soukromá záloha před touto úlohou. | `refs/worktree-cleanup/20261026-round2/festapp` -> `9ea59b28d4`, 26. 10. 09:51. | 416 kandidátních souborů má v této záloze přesný obsah; pozdější změny vyžadují další snapshot. |
| Aktuální obsah je směs historie a nové práce. | Obsahové hashe: 2 897 cest už odpovídá main, 1 309 odpovídá starému snapshotu, 396 se změnilo na obou stranách, 137 jen lokálně. | Přenášet pouze doložený nový rozdíl. Čísla zahrnují i změny právě rozpracovaného feedu. |
| Část nové práce existuje také na jiné větvi. | Dalších 5 souborů odpovídá commitu `9b923ec14` s platform updates. | Před ručním přenosem zkontrolovat již existující integrační větev a neduplikovat změnu. |
| Ani lokální main nebyl celý aktuální. | Po fetch: lokálně `0eff86e7b`, upstream `03aa99975`, rozdíl `1/5` commitů. | Zachovat jednu lokální opravu a pět příchozích commitů. Jejich dry-run merge je bez konfliktů. |
| Dostupnost upozornění byla změněna záměrně. | Commit `cebaf0f65`, publikovaná migrace `20261024235000`, lokální release receipt 24. 10. | Tabulka activation/setter byly nahrazeny organizacemi a jednorázovou inicializací; nejde o důkaz ztracených souborů. |

Kompletní obsahová klasifikace a přesné příkazy jsou v
[evidence](workspace-canonical-reconciliation-evidence-2026-10-26/git-receipts.txt).
Inventář není automatické rozhodnutí o úmyslu autora; rozdíly jsou kandidáti.
Produkce nebyla kontaktována. Lokální release receipt dokládá vydání v daný den,
nikoli dnešní live stav.

## Správný integrační základ

Použít aktuální canonical main se zachováním jeho lokálního nepushed commitu.
Pro původní připravenou práci použít jako obsahový základ snapshot `d4dc170b1`,
ne pouze starý root HEAD `353394511`. Root HEAD je společný Git předek, ale
nerozlišuje práci již začleněnou přes d4dc od pozdějších místních úprav.
Novější soukromý snapshot `9ea59b28d4` uchovává další lokální vrstvu; vlastní
nové úpravy po 09:51, včetně feedu, tvoří další samostatný rozdíl.

Provedený merge-tree nad main + 9ea s explicitním d4dc základem ukázal 164
konfliktních cest. Jde o návrh ve zvláštních Git objektech, nikoli o probíhající
merge v pracovním indexu. Není bezpečné hromadně použít ours/theirs ani kopírovat
celé staré adresáře. Konkrétní seznam je v
[dry-merge-conflicts.json](workspace-canonical-reconciliation-evidence-2026-10-26/dry-merge-conflicts.json).

## Invarianty

- Zachovat aktuální main oprávnění (`can_*` a jeho doménové ownery), inicializaci
  organizace, novější opravy a skutečnou aplikovanou migrační historii.
- Zachovat všechny legitimní lokální změny, ale nepovažovat starý snapshot za
  požadavek vrátit pozdější main změny. Každé vědomé neobnovení zdokumentovat.
- Žádný `reset --hard`, `clean`, slepé stash pop ani přepnutí dirty root větve.
- Neměnit veřejné smlouvy, tenant konfiguraci ani prod větve jako vedlejší efekt.
- Generované soubory vzniknou z finálních vlastníků, nejsou zdrojem rozhodnutí.
- Bez samostatného release zadání neprovádět produkční migraci či deployment.
  Původní zákaz commitu/push stále respektovat: integrační výsledek může zůstat
  necommitovaný a doložený. Záložní tar nepotřebuje nový authored commit.

## Vlny provedení

### 1. Zmrazit a ověřit obnovitelný obsah

Vytvořit privátní archiv aktuálních tracked změn, untracked zdrojů a explicitní
seznam smazaných cest; zaznamenat refy, režimy souborů a SHA-256 archivu.
Zachovat soukromý 9ea ref. Ignorované přihlašovací soubory a lokální config
ponechat na místě, nikam je nepublikovat. Před následným přenosem znovu ověřit
hashe kandidátů, protože v repozitáři mohou paralelně pracovat další relace.
Výstup: obnovitelný archiv a shodný manifest, žádný ztracený lokální soubor.

Záloha této vlny už vznikla:
`/Users/miakh/festapp-cleanup-archives/20261026-notification-reconciliation/working-source.tar.gz`
(4 236 souborů, manifest 509 odstraněných cest, žádný soubor se během archivace
nezměnil). SHA-256:
`9c99bd036eb29e1f03eea633748563a5aed7ba9e7a9b6b4837ef7dcfc54c4b37`.
Index i větve původního adresáře zůstaly beze změny.

### 2. Sjednotit aktuální canonical základ

V odděleném integračním worktree spojit lokální main a čerstvý origin/main.
Dry-run pro zaznamenané SHA je bez konfliktu. Pokud upstream pokročí, porovnat
nový stav a tento důkaz obnovit. Nedotýkat se produkčních větví ani worktree,
ve kterých právě pracuje jiná relace. Výstup: základ obsahující obě historie.

### 3. Přenést skutečné místní celky

Porovnat d4dc -> 9ea -> aktuální root a použít inventář jako filtr:
`already_integrated` a `old_snapshot_only` ponechají canonical obsah; pro
`local_delta_only` a `both_changed_since_snapshot` dohledat konkrétní úmysl.
Nejdříve převzít už existující samostatné větve/commity, pokud nesou přesně tu
práci; jinak přenést její obsahový rozdíl proti d4dc. Nikdy neobnovovat celý
starý soubor jen proto, že je označen jako untracked vůči původnímu HEAD.

Přenášet po ověřitelných celcích: sdílené Flutter/native závislosti a adaptéry,
pnpm/build/PWA tooling, veřejné CMS/organizer/platform-updates zdroje a jejich
odvozené balíčky, ostatní cílené doménové opravy, nakonec nové upozornění.
Tenant konfigurace v `automation/project.conf`, `lib/app_config.dart` a
generovaných webech se řídí canonical main/overlay politikou, nikoli náhodným
obsahem staré preview sestavy. Nevydávat žádný další tenant.

Každý ze 164 konfliktů musí mít řešení zachovávající oba platné úmysly nebo
konkrétní důvod, proč jeho stará strana už byla nahrazena. U generovaných
`app_router.gr.dart`, lockfiles, katalogů, fontů, veřejných HTML a integračních
zipů rozhodovat podle owning zdrojů a regenerace, ne podle ručního hunk výběru.
Výstup: nulové unresolved cesty, každá nová lokální změna accounted for.

### 4. Přesadit notification feed na sjednocené ownery

Použít [notifikační plán](notification-center-feed-plan-2026-10-26.md), ale
aktualizovat jeho staré aktivační předpoklady. Zachovat canonical organizace,
`initialize_notification_center_internal` a již vydané activity/email/bank
kontrakty. Ruční/scheduled form helper zapojit do skutečného konstrukčního ownera
`eshop_forms/form_creation_domain.sql`, nejen do permission wrapperu
`create_form_internal_v1`. Wizard používá stejný konstrukční owner.

Nové hooky v update/copy/delete/occasion wrapperech přidat k jejich aktuálním
canonical tělům. Nepřepsat je celými staršími lokálními verzemi: liší se i
oprávnění a kopírování venue/font/resource dat. Stejně přestavět forward manifest
na skutečné canonical názvy prerequisites (historie na main používá i jiné
původní timestampy). Neaplikovat dvě varianty téhož historického CREATE TABLE.
Žádná změna aplikované SQL historie a žádné obnovení activation/rollout aliasů.
Výstup: nový delta navazující na správný katalog a jeden flat Flutter feed.

### 5. Ověřit finální kombinaci a uzavřít pracovní adresář

Použít cílené normální testy jednotlivých převzatých celků a poté společný
finální validační batch. Jeden Flutter task, testy `--concurrency=1`; pnpm
11.24.0, žádný duplicitní npm lockfile. Pro feed: skutečné SQL/row-lock testy,
formatter, registrovaný widget/nav běh v obou pořadích a lokální headless E2E.
Discovery musí být nenulové.

Clean rehearsal musí běžet z celé správné canonical historie. Již provedený
pokus main bootstrapu narazil na produkční data guard `Slunovrat` ID 19;
to není chyba feedu. Použít existující podporovanou lokální rehearsal fixture
pro tento guard, případně doložit chybějící fixture jako konkrétní blocker.
Guard neodstraňovat a nepřenášet skutečná produkční data. Upgrade rehearsal
musí ověřit jen nový delta nad již canonical notification katalogem.

Teprve po této kombinované validaci nahradit zastaralý root sjednoceným stavem,
se zálohou a kontrolou všech lokálních delta. Nejdříve vyřešit vlastnictví main
worktree; nestěhovat živé relace a nesmazat starý root jako součást úklidu.
Bez commitu/push zůstane výsledek připravený k review, nikoli vydaný.

## Dosavadní důkazy a jejich meze

- Canonical notification katalog + rozpracovaný feed: 16 cílených SQL souborů
  a 6 skutečných concurrency testů prošlo v disposable DB.
- Flutter shared suite: 371 testů v obou pořadích; formatter 1; cílená analýza
  bez nálezů. Mobilní/desktopové full-app snímky a pagination/ack/mute/revocation
  byly provedeny na předchozím lokálním katalogu.
- Tyto receipts nejsou důkazem finálního sjednoceného výsledku po všech mergích.
  Dotčené brány se musí spustit nad konečnými společnými vstupy.
- Zastaralá root historie při clean bootstrapu postrádá canonical authorization
  prerequisites. Nepřidávat kvůli tomu náhodně jejich fragmenty do feature SQL;
  řešením je správný sjednocený základ.

## Ledger

| Artefakt | Výsledek |
|---|---|
| Stará root větev a oba snapshoty | Zachovat obnovitelnost do ověření nové kombinace. |
| 1 309 cest starého snapshotu | Neobnovovat nad pozdější main opravy; původ uchovává Git/archiv. |
| 533 kandidátních dalších cest | Každou zařadit jako přenesenou, již integrovanou, generovanou nebo doloženě nahrazenou. |
| Aktivace a tenant rollout v notification backendu | Neobnovovat; canonical init zůstává jediný owner. |
| Group UI/model/cursory v novém klientu | Odstranit dle feed plánu. |
| Group SQL pro vydané klienty | Omezený externí serializační adaptér do doloženého retirement. |
| Staré lokální draft kopie migrací | Nespouštět paralelně s skutečně aplikovanými canonical verzemi; zachovat historický důkaz bez změny aplikovaných souborů. |

Hotovo je teprve tehdy, když existuje jedna ověřená kombinace nového main a všech
legitimních místních změn, bez rollbacku novějších oprav a bez ztracených souborů.

## Dokončené provedení

Finální upstream: `85c655137c9c2472b402aaed6fdbf0fe24501d24` (znovu fetched před přenosem).
164 konfliktů vyřešeno podle doménových ownerů; source parity potvrzena pro 7599 souborů.
Přeneseno 4026 cest, 812 zastaralých cest včetně absolutního lokálního override
archivováno a vyřazeno z aktivního stromu. Kořenová větev má nyní HEAD shodný
s origin/main a integrované změny v pracovním stromu. Lokální main v jiném
worktree ani produkční větve se neměnily. Žádný nový commit nebo push.

Čerstvý `pre-transfer-source.tar.gz` SHA-256:
`2ae586d1634117db025ab0f31daa23e630cc743ab2a9fb961257833e67c6b592`.
Finální ověření a ledgery: [notification evidence](notification-center-feed-evidence-2026-10-26/README.md).
