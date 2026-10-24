# Úprava scénáře: sestavení sálu a formulář

Nahrazeno [souvislým přetočením](continuous-retake-2026-10-23.md). Následující
text dokumentuje předchozí verzi, nikoli aktuální výstupy.

Zadání a realizace z 2026-10-23. Tento scénář nahrazuje prázdný začátek
`layout-build` a skokový střih `form-build`. Výstupy pro desktop i mobil mají
společné skutečné zdrojové záběry. Ostatní videa nejsou součástí této úpravy.

## Sál: hotová řada od prvního snímku

Výchozí stav připravit před nahráváním v reálném editoru: pódium, obrys sálu
a jedna kompletní řada pěti stolů se židlemi. Pod ní nechat prostor pro další
řadu. Zachovat dosavadní vzhled, měřítko a princip přetažení a kopírování.
Hotová řada musí být vidět i během prvního přetažení z palety.

| Orientační čas | Děj |
|---|---|
| 0-2 s | Klidný pohled na pódium, sál a hotovou první řadu. |
| 2-6 s | Přetáhnout jeden nový stůl z palety na začátek druhé řady. Celá cesta kurzoru a náhledu zůstává viditelná. |
| 6-8 s | Nechat nový stůl se židlemi usadit; ukázat jeho vztah k hotové řadě. |
| 8-14 s | Stejným principem jako dosud kopírovat stůl a doplnit druhou řadu. První kopii ukázat čitelně, opakování lze mírně zrychlit. |
| 14-17 s | Zrušit výběr a podržet hotové dvě řady. |

Nezačínat kreslením pódia, prázdným sálem ani přeskokem z prázdného plánu na
plný. Příprava první řady nepatří do záběru. Závěrečné podržení se nesmí
přelepit přes začátek tak, aby stoly při opakování zdánlivě mizely uprostřed
gesta. Případné další úpravy sálu patří do existujícího `layout-refine`.

## Formulář: jedna souvislá práce, potom další otázka

Zachovat skutečný editor a stávající vstupné. Večeři dál ukazovat jako placené
produkty u vstupenky, nikoli jako neplacený výběr, který jen vypadá podobně.
Pro nový lokální záběr použít čtyři ukázkové možnosti:

- Kuřecí večeře - 180 Kč.
- Vegetariánská večeře - 160 Kč.
- Veganská večeře - 160 Kč.
- Bezlepková večeře - 180 Kč.

Ceny jsou syntetická data pro lokální ukázku. První dvě navazují na dosavadní
záběr. Použít pouze izolovaný lokální formulář; neupravovat produkční nabídku.

| Orientační čas | Děj |
|---|---|
| 0-2 s | Ustálený pohled na místo ve vstupence, kde se přidává typ produktu. |
| 2-6 s | Kliknout na Přidat typ produktu a pojmenovat jej Večeře. |
| 6-11 s | Přidat první produkt, vyplnit Kuřecí večeře a cenu 180. Krátce ukázat hotový řádek. |
| 11-23 s | Postupně přidat další tři večeře a ceny. Ukázat každé přidání a jeho výsledek; nevynechat prostředek interakce. |
| 23-26 s | Podržet všechny čtyři hotové možnosti v jednom čitelném pohledu. |
| 26-29 s | Plynule odscrollovat k Přidat pole. Zachovat orientaci vůči právě dokončené večeři. |
| 29-35 s | Přidat pole typu Text a pojmenovat je Poznámka pro pořadatele. Ponechat nepovinné. |
| 35-38 s | Ukázat hotovou otázku. |

Časy jsou cílové, ne pevné limity pro ořez. Pokud skutečné ovládání potřebuje
více času, prodloužit záběr. Uložení provést a ověřit mimo hlavní záběr:
editor při ukládání scrolluje nahoru a tento skok do ukázky nepatří. Závěr
zůstává v editoru, bez přechodu na veřejné vyplňování.

Nahrát jednu souvislou práci od přidání Večeře po hotovou textovou otázku.
Držet stejné měřítko a výřez, scrollovat plynule jen v případě potřeby.
Nezrychlovat psaní, scroll ani rozbalování ovládacích prvků. Zkracovat pouze
nečinnost, pokud spojení nezmění polohu obsahu a kurzoru. Nepoužívat dosavadní
dvousekundové výřezy z oddělených cue jako základ nového sestřihu.

## Převzetí nových záběrů

- První snímek sálu obsahuje pět hotových stolů; další přibude skutečným
  přetažením. První řada během gesta zůstává na místě.
- U formuláře lze sledovat přidávání všech čtyř večeří a jejich cen. Hotové
  možnosti zůstávají čitelné alespoň 3 s, potom přijde zřetelný přechod
  k textové otázce.
- V obou výřezech pro landing nejsou skoky scrollu, chybějící části gest ani
  useknuté ovládací prvky. Případný mobilní výřez je prezentace desktopového
  editoru, nikoli tvrzení o mobilním ovládání.
- Až po novém nahrání aktualizovat příslušné MP4, JPG/WebP postery, skutečné
  délky v manifestu a lokální náhled. Zkontrolovat začátek, přechody a konec
  obou videí a úplné dekódování exportů.

Staré číslované zdrojové JPEG byly podle externího `RAW-FRAMES-CLEANUP.md`
odstraněny. Souvislé nové přidávání čtyř večeří a další otázky proto vyžaduje
nové nahrání, nikoli pouze opětovné spuštění historického encoderu.

## Nové nahrání a reprodukce

Nové zdroje, cue manifesty, snímky a exporty jsou mimo Git v
`~/Downloads/festapp-video-revision-20261023/`. Sál používá skutečný archivní
build původního editoru z `layout-continuation/app`; SHA-256 `main.dart.js` je
`cb532b8fd82f6915a788c8b09d91b97da4a907f66eb7dbe570e92a5821709789`.
První řada byla připravena skutečným výběrem a odstraněním ostatních stolů
před zapnutím nahrávání. Čtení `captureLayoutDocument` potvrzuje na začátku
5 stolů / 30 židlí a na konci 10 stolů / 60 židlí.

`layout/row_ready.py` zaznamenává tento připravený stav, přetažení nového stolu
a kopie do druhé řady. Používá pozorování a nativní gesta ze skillu
`product-demo-video`, nikoli programové vkládání objektů během záběru.
Encoder zrychluje jen opakované kopie 1,5x a vynechává jejich přechodné snímky
s varováním o kolizi; seznam je v externím `copy-transition-cuts.json`.
První přetažení je souvislé. Výstup má 14,666667 s, 1140x792 / 820x792.

Formulář používá skutečnou aplikaci a izolovaný backend na loopback 56831,
organizaci 1, příležitost 1 a formulář 1 (`e2e-first-form`). Základ tvoří
kanonický lokální baseline, dopředné migrace, seed a navigační fixture.
U příležitostí vložených přímo fixturem je nutné před otevřením jejich URL
zavolat kanonický `reserve_public_link_internal('occasion',id,link,true)`.
Přejmenovat lokální příležitost na Ples pod hvězdami, základní skupinu na
Vstupné a produkt na Základní vstupné / 450 Kč. Nevytvářet objednávky.

`admin/continuous_form.py` očekává viewport 1000x1000, zvolenou Vstupenku,
viditelné Přidat typ produktu a prázdnou demonstraci. Nahrává jednu souvislou
cue od přidání skupiny přes čtyři produkty po novou textovou otázku. Nativní
scroll a klávesnice zachovávají skutečné tempo. Pokud sémantická vrstva
nepropouští nativní vstup, otevřít nový tab pouze v tomto izolovaném prohlížeči,
zavřít starý pracovní tab a znovu ověřit jednu stránku. Titul otázky se píše
do skutečného vykresleného pole; sloučený sémantický input není jeho přesný
hitbox. Uložení a databázové ověření patří až za konec nahrávání.

Pro oba záběry nastavit `CAPTURE_OUTPUT`, `CAPTURE_BROWSER_WRAPPER` a
`PRODUCT_DEMO_SKILL` na vlastní externí adresáře a izolovaný headless wrapper.
Export: `python3 automation/landing_capture/encode_revision.py CHAPTER TAKE OUTPUT`,
kde CHAPTER je `layout-build` nebo `form-build`. Formulář se exportuje celý
v původním čase bez střihů; desktop 1200x804, mobilní prezentace desktopu
720x638. Finální souvislý záběr má 45,933333 s; orientační kratší časy scénáře
se nepoužily k ořezání skutečného ovládání. Uložení a přímé čtení lokální DB
potvrdily všechny čtyři názvy a ceny i titul textové otázky; počet objednávek
zůstal nula. Surové JPEG, přihlašovací údaje a runtime logy nepatří do Git.
