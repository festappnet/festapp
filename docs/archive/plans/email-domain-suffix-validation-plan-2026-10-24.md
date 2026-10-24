# Kontrola koncovky domény e-mailu na klientovi

Datum: 2026-10-24
Stav: Implementováno a ověřeno; připraveno k integraci do aktuálního main
Verification: standard při implementaci (sdílená validace a registrační formulář); plán vznikl jedním cíleným průzkumem bez spouštění testů.

## Integrace do main 2026-10-24

Na následné výslovné zadání k merge byla změna přenesena samostatně na
`origin/main` `ad924d6fd` v čistém worktree. Novější capability, formulářové,
autentizační a překladové změny main byly zachovány; původní pracovní strom
s nesouvisející rozpracovanou prací nebyl změněn.

Na tomto základu prošlo 49 cílených JS testů, 14 Dart testů, 3 Flutter widget
scénáře a existující `automation/test_web_startup.sh` (95 testů a 7 izolovaných
browser scénářů). Offline kontrola generovaných dat a kontrola whitespace prošly.
Cílený analyzer nemá chyby ani warningy; main obsahuje ještě jeden původní info
nález v `form_helper.dart`, celkem čtyři. Konfigurační a překladové nástroje byly
provedeny; jejich nesouvisející výstupní drift není součástí této změny. Nové
překladové klíče zůstávají shodné v obou klientech. Commit a publikace této
implementace jsou nyní uživatelem autorizovány; nasazení není součástí zadání.

## Dokončení implementace 2026-10-24

- Oba klienti používají úplný snapshot IANA `2026102400` (1437 koncovek),
  deterministicky generované sady a společnou testovací matici. Generátor
  odmítá poškozený vstup před zápisem; `--check` funguje offline a je součástí
  existujícího `automation/test_web_startup.sh` používaného CI i JS test scriptu.
- Flutter submit vlastní `FormHelper.saveValidateAndScroll`, volaný z
  `FormPage._showOrderPreview`; kontroluje hlavní FormBuilder a jednotlivé
  ticketKey. Stav potvrzení vlastní FormHolder, klíč tvoří instance konkrétního
  FormBuilder a jméno pole. JS stav vlastní FormSession, podpole jsou klíčována
  stabilní identitou vstupenky a ID podpole, nikoli samotným pořadím.
- Konkrétní oprava předpokladu: stávající Flutter email validátor bez explicitního
  `checkNullOrEmpty: false` odmítal prázdné volitelné pole. Oba designy nyní
  ponechávají povinnost validátoru `required`, se stejným validátorem formátu.
  Flutter FieldHolder nově přenáší `isHidden` pro vyloučení skrytých adres z
  potvrzování; dosavadní vykreslovací a payload cesty se nepřestavují.
- Prošlo 46 cílených JS testů (včetně veřejných překladů, poškození generátoru,
  formulářových regresí a login/reset/Google proof), 14 testů přenositelné Dart
  logiky a 3 Flutter widget scénáře pro oba designy, ticket podpole a okrajové stavy.
  JS submit test používá skutečný FormPage/FormRenderer/FormValidator a nahrazuje
  vstup do náhledu počítadlem; registrační/auth služby jsou lokálně mockované.
  Nevytvářely se skutečné objednávky ani účty.
- `node automation/generate_email_tlds.mjs --check` a cílený `git diff --check`
  prošly. Cílený Dart analyzer nemá chyby ani warningy; zůstávají tři původní
  informační nálezy (`typeHere_informal`, dvě použití `withOpacity`).
- Aktuální kontrakt a aktualizace dat: [shared/email/README.md](../../../shared/email/README.md).
  Backend, SQL a produkční data nebyly změněny. Produkční vydání není součástí
  této implementace; žádný lokální implementační blokátor nezůstává.

Původní plán níže je historický podklad, nikoli čekající realizační checklist.

## Výsledek a hranice

Uživatel před odesláním formuláře dostane upozornění, pokud má jeho e-mail
neznámou koncovku domény. Například `jana@seznam.czz` vyvolá otázku, zda adresu
opravit. Kontrola funguje lokálně, bez čekání na síť a bez předávání adresy třetí
straně. Neověřuje existenci domény, její poštovní konfiguraci ani schránky.

Rozsah první implementace:

- Veřejné formuláře a objednávky v JS i Flutteru, včetně obou designů Flutter
  formuláře a viditelných e-mailových podpolí vstupenek, pokud je daný renderer podporuje.
- Ručně zadaný e-mail při registraci ve webovém `login_modal.js`.
- Společný zdroj dat, generování, lokalizace a cílené testy.

Přihlášení, obnova hesla, Google proof/link a existující uložené adresy zůstanou
mimo nové potvrzování. Nepřidávat kontrolu do společné autentizační větve bez
rozlišení účelu. Backend, SQL, doručování e-mailů, administrátorské editory a
historická data se nemění. DNS/MX kontrola a návrhy oprav celých domén typu
`gmial.com` jsou samostatné případné pokračování.

## Zjištěný stav

| Fakt | Důkaz | Dopad |
|---|---|---|
| Veřejný JS formulář používá nativní kontrolu formátu. | `web_client/src/components/forms/form_validator.js`: `validateAndShowErrors`, `handleInputValidation`. | Nová kontrola musí fungovat při odeslání i po opravě hodnoty. |
| JS renderer vytváří `input type=email`. | `web_client/src/components/forms/fields/text_field_builder.js`: `TextFieldBuilder.create`, `getInputType`. | Zachovat nativní formátovou kontrolu; doplnit vlastní upozornění. |
| Odesílání a události vlastní formulářová stránka. | `web_client/src/components/forms/form_page.js`: události kolem řádku 482, `handleInputValidation`, volání `validateAndShowErrors`. | Potvrzení zapojit před existující odesílací cestu, nevytvořit druhý submit. |
| Flutter má dvě sestavy validátorů e-mailu. | `lib/components/forms/widgets_view/text_field_builder.dart`: `_buildStandardTextField`, `_buildCardDesignTextField`, `FormBuilderValidators.email`. | Obě varianty musí volat stejný adaptér; upozornění není trvalá validační chyba. |
| Webová autentizace používá vlastní jednoduchý regex. | `web_client/src/components/users/login_modal.js`: `_validateForm`, `_handleRegister`, `_handleLogin`, `_handleReset`. | Připojit nové potvrzení jen k `_handleRegister`. |
| Flutter přihlášení a obnova hesla sdílejí velmi jednoduchou kontrolu. | `lib/widgets/internal_form_fields.dart`: `email` kontroluje prázdnou hodnotu a `@`; volají login/forgot stránky. | Tento helper při této práci neměnit; nehrozit blokací existujících účtů. |
| Existují cílené testovací vstupy. | `web_client/tests/forms/validation_fixes.test.js`, `web_client/tests/components/login_modal.test.js`, `packages/festapp_core`. | Čistou logiku testovat bez spuštění celé aplikace. |

Průzkum vychází z pracovního stromu větve `feat/occasion-setup-wizard-20261007`,
HEAD `353394511`. Strom obsahuje rozsáhlé rozpracované změny. Implementátor musí
zachovat cizí změny a ověřit pouze přímo dotčené úseky proti aktuálnímu stavu.
Tento plán neuděluje oprávnění ke změně větve, commitu ani publikaci.

## Zdroj koncovek a rozhodnutí

Použít úplný verzovaný snapshot [IANA seznamu delegovaných TLD](https://data.iana.org/TLD/tlds-alpha-by-domain.txt),
ověřeného při plánování (hlavička verze `2026102400`). Význam zdroje popisuje
[IANA Root Zone Database](https://www.iana.org/domains/root/db).
Seznam obsahuje i méně obvyklé a punycode koncovky. Nevytvářet krátký ruční
seznam `.cz`, `.sk`, `.com` ani omezení délky koncovky na 2-4 znaky.

Rozhodnutí:

1. Neplatný formát zůstává blokující podle stávajícího klientského validátoru.
2. Koncovka přítomná ve snapshotu projde bez nového upozornění. Posuzuje se
   poslední label, takže `firma.co.uk` kontroluje `uk`.
3. Neznámá koncovka vyvolá upozornění s explicitní možností zachovat adresu.
   Není to důkaz neexistující domény; nový TLD může ve starším klientovi chybět.
4. Adresu nikdy automaticky neopravovat. V první verzi nenabízet odhad opravy.
   Třeba `.co` a `.cm` jsou platné koncovky a nelze je odmítnout jako překlep `.com`.
5. Během psaní nezobrazovat chybu u rozpracované adresy. Upozornění zobrazit
   po opuštění pole nebo při odeslání; při opravě ho přepočítat.
6. Prázdné volitelné pole projde. Povinnost vyplnění dál řídí definice pole.
7. Trim okrajových mezer a porovnání domény bez ohledu na velikost písmen
   provádět pro kontrolu; část před `@` nepřepisovat ani nelowercasovat.
   Případnou normalizaci ukládané hodnoty tento plán nepřidává.
8. ASCII a punycode TLD kontrolovat přímo. Nezavádět nový zákaz Unicode ani
   vlastní IDNA převod. Unicode vstup, který připustí dosavadní syntaktický
   validátor a který nelze porovnat, dostane stejné překonatelné upozornění.
   Plná podpora IDN/EAI není cílem této změny.

## Kanonický kontrakt a vlastnictví

Navržené nové soubory:

- `shared/email/iana-tlds.txt`: jediný autoritativní snapshot v původním formátu,
  s hlavičkou verze a zdrojovou URL v doprovodné dokumentaci.
- `automation/generate_email_tlds.mjs`: deterministický generátor Dart a JS
  konstant; režim `--check` porovná soubory bez zápisu a bez sítě.
- `packages/festapp_core/lib/src/forms/email_domain_suffix.dart`: čistá Dart
  klasifikace, exportovaná stávajícím veřejným exportem balíčku.
- `web_client/src/logic/email_domain_suffix.js`: stejný kontrakt pro JS.
- `shared/email/domain-suffix-cases.json`: společné příklady pro obě implementace.

Čistá kontrola dostane neprázdnou syntakticky přijatou adresu a vrátí pouze
`knownSuffix` nebo `unrecognizedSuffix`, případně extrahovanou koncovku pro UI.
Nevrací `deliverable` ani `domainExists`. Povinnost a syntaxi vlastní dosavadní
adaptéry. Generované sady koncovek nesmí mít ruční lokální doplňky.

Stav potvrzení vlastní konkrétní pole ve formulářové relaci: aktuální hodnota,
zda je upozornění viditelné a zda uživatel právě tuto hodnotu výslovně potvrdil.
Každá změna hodnoty potvrzení zruší. Stav je pouze v paměti, neposílá se do API,
neloguje se a neukládá do localStorage. Při přerenderování stejné relace se
nesmí ztratit; při otevření nové relace nesmí přetrvat. Potvrzení jednoho pole
nesmí potvrdit jiné pole se stejnou adresou.

Při submitu nejdřív proběhnou obvyklé blokující validace, potom se ukáže první
nepotvrzené upozornění a přesune se na něj fokus. Explicitní akce „Adresa je
správně“ pouze potvrdí pole; uživatel následně odešle formulář standardním
tlačítkem. Tím nevzniká automatický opakovaný submit ani další objednávka.
Zpráva například: „Koncovku domény .czz neznáme. Zkontrolujte e-mailovou adresu.“
Použít existující lokalizační adaptéry, respektovat tón formuláře a zpřístupnit
zprávu pomocí vazby na pole a přístupného oznámení. Tlačítko potvrzení není submit.

## Implementační kroky

### 1. Data a čistá kontrola

Uložit IANA snapshot a generátor, vytvořit odvozené Dart/JS konstanty a čisté
pomocné funkce. Generátor musí odmítnout prázdný či poškozený vstup a zapisovat
až po úspěšném zpracování celého seznamu. Nevolat síť při běhu aplikace ani
obyčejném buildu. Aktualizace seznamu je explicitní stažení z IANA, kontrola
diffu a regenerace; výpadek stažení nesmí přepsat poslední dobrou verzi.

Ověření: společná matice testů v obou jazycích a `--check`. Hotovo, když obě
implementace vracejí stejné výsledky a generované soubory odpovídají snapshotu.

### 2. Veřejné formuláře v JS a Flutteru

V JS připojit klasifikaci do `FormValidator` pro odeslání i opravu pole; renderer
doplní upozornění a akci potvrzení. Stav uložit do existující formulářové relace
odděleně od payloadu a blokujících `validationErrors`. V `form_page.js` zajistit,
že neodsouhlasené upozornění zastaví stávající odeslání před síťovým požadavkem.

Ve Flutteru využít stejný adaptér v obou designech `TextFieldBuilder`. Na začátku
kroku dohledat od `FormBuilderState.saveAndValidate`/`validate` jedinou skutečnou
submit cestu veřejného formuláře v `lib/components/forms/`; tam zapojit kontrolu
potvrzení před odesláním. Nepokoušet se potvrzovací UI vyjádřit pouze návratovou
chybou ze synchronního validátoru. Stejným průchodem ověřit e-mailová podpole
vstupenek, viditelnost a disabled/read-only stavy; posuzovat pouze odesílatelná
editovatelná pole podle současné politiky formuláře.

Dosavadní formátové validátory a pravidla povinnosti zůstávají vlastníkem těchto
kontrol. Neodstraňovat je a nekopírovat nový seznam TLD do jednotlivých widgetů.

Ověření: cílený JS DOM test a Flutter widget test pokryjí blur, opravu, potvrzení,
změnu po potvrzení, přerender a submit. Síťový submit se nesmí provést před
potvrzením ani dvakrát po něm. Hotovo, když oba designy a oba klienti mají stejné
pozorovatelné chování.

### 3. Registrace, údržba a uzavření

Zapojit stejnou JS kontrolu a potvrzení pouze do registrační cesty
`LoginModal._handleRegister`; vyčistit stav při změně adresy nebo opuštění
registrační relace. Testem prokázat, že login/reset/proof nové potvrzení nevyžadují.
Nepřepisovat jejich regex ani Flutter `InternalFormFields.email` v rámci této práce.

Doplnit krátký návod aktualizace snapshotu a zapojit offline `--check` do nejbližší
existující JS/automatizační kontrolní cesty, kterou používá CI. Nedělat novou
deploy pipeline. Hotovo, když je odchylka generovaných dat detekovatelná bez sítě.

## Ověření implementace

Provádět po souvislém dokončení změny, nikoli po každém souboru. Před Flutter
testem ověřit, že na workstation neběží jiná Flutter úloha; použít concurrency 1.

- `node automation/generate_email_tlds.mjs --check`.
- `pnpm --dir web_client exec node --test tests/logic/email_domain_suffix.test.js tests/forms/email_domain_suffix.test.js tests/components/login_modal.test.js`.
- V `packages/festapp_core`: `fvm dart test test/forms/email_domain_suffix_test.dart`.
- `fvm flutter test --concurrency=1 test/components/forms/email_domain_suffix_test.dart`.
- `fvm dart analyze` jen změněné Dart zdroje; upravené existující testy přidat do
  stejné cílené dávky. Názvy nových testů výše jsou navržené implementační cíle.

Matice: běžné i dlouhé platné koncovky ze snapshotu, uppercase, plus adresování,
subdoména a `co.uk`, ASCII punycode, neznámé `.czz`/`.comm`, platné `.co`/`.cm`,
prázdná volitelná/povinná hodnota a stávající neplatné formáty. Dále dvě pole se
stejnou adresou, neznámá koncovka potvrzená/nepotvrzená, změna po potvrzení,
skryté pole, nová relace a simulovaná nová TLD chybějící ve snapshotu. IDN vstup
nesmí kvůli nové vrstvě dostat nepřekonatelnou chybu.

## Ponechané cesty, předpoklady a rizika

- Nejde o výměnu celé e-mailové validace. Stávající validátory formátu a backend
  se záměrně ponechávají. Nevytvářet paralelní formuláře, RPC ani příznaky V1/V2.
- Předpoklad: první priorita jsou veřejné formuláře a webová registrace. Další
  administrátorská pole lze připojit později ke stejnému kontraktu.
- Přesné Flutter místo submitu a uložení pomocného stavu relace musí implementátor
  dohledat v uvedeném omezeném rozsahu; tento plán netvrdí, že už byla ověřena.
- Snapshot stárne zejména u dlouho neaktualizovaných mobilních klientů. Explicitní
  možnost pokračovat je součást návrhu; aktualizaci seznamu kontrolovat při údržbě
  vydání. Neslibovat detekci všech překlepů.
- Platná koncovka neprokazuje existenci domény ani doručitelnost. Kontrola
  `jana@neexistujici-firma.cz` může projít. To je očekávané omezení.

## Nasazení a dokončení

Plán nevyžaduje migraci dat, přístup do produkce ani přepis existujících adres.
Implementace a lokální validace jsou samostatný následující úkol; commit, push a
nasazení potřebují samostatné zadání. Budoucí nasazení se řídí vybraným jediným
tenantem a pravidly lokálního buildu; rollback vrátí klientský bundle, data nemění.

Hotovo je až při shodě obou čistých implementací, zapojení všech uvedených
formulářových cest, potvrzování vázaném na konkrétní hodnotu a pole, zachování
přihlášení/obnovy hesla a úspěšné cílené validaci. Runtime nesmí být závislý na
externím validačním API ani načítat seznam ze sítě.
