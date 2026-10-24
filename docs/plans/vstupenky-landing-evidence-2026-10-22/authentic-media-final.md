# Poslední mediální revize - autentické šablony a čitelné akce

Tato revize nahrazuje příslušné závěry předchozích `real-product-refinement.md`
a `media-validation-vivid.json`. Hero již není screenshot plánku; vlastní jej
stránková implementace. Zachované dříve schválené klipy zůstávají pravdivé.

## Editor a výběr míst

Zdrojem je existující produktová šablona `scout-ball-182`, původní skautský
sál s182místy a31stoly. Geometrie vychází z původních referenčních dat a jejich
source digestů v sibling `scout_reference_data.dart`, nikoli z nově vymyšleného
sálu. Veřejný Festapp picker dostává přesnou původní geometrii přes lokální
adapter; jeho záběry ukazují přiblížení, výběr dvou míst a cenu1300Kč.

Editor ukazuje dva skutečné drags stolů z levé palety a následný samostatný drag
židle. Výsledek kopie má33stolů a195sedadel. Toto jsou neuložené ukázkové úpravy;
není tvrzeno, že byly odeslány do veřejného obchodu. Pravý inspector leží mimo
pevný výřez videa. Produktové UI se neskrývá injekcí ani nenahrazuje překryvem.
Poster ukazuje paletu a první vložený stůl. Druhý klip i showcase obsahují skutečný
skautský sál, výrazné Galaxy kino a divadlo. Konferenční šablona s překrytými
popisky je z dodávky vyřazena, zůstává pouze v historickém raw take.

Raw zdroj a důkaz gest: externí `authentic-layout/`, recepty
`automation/landing_capture/layout/authentic.py` a `finish_authentic.py`.
Příprava fontových resources proběhla kanonickým shaperem z exportu skutečného
dokumentu. Finální záběr nemá chybový banner, potvrzeno UI i obrazem.

## QR bankovní převod

Nový devátý klip `payment-qr` je skutečné UI lokální objednávky155 na1300Kč,
nezaplacené (`paid=NULL`). QR byl zpětně dekódován a odpovídá ceně a syntetickému
neplatnému účtu. Neproběhla žádná skutečná platba ani kontakt s reálným
příjemcem. Důkaz: externí `real-picker/v3/qr-proof.json`; zdroj fixture a capture
postup jsou v `automation/landing_capture/picker/`. Stejné assets slouží
platební sekci; není vytvořena duplicitní manifestová sekce.

## Reprodukce a ověření

Všechny viditelné UI a ukázková data jsou české. Recepty a pořadí devíti kapitol
zůstávají v `automation/landing_capture/README.md`. Anglická verze vyžaduje nový
capture skutečně lokalizované aplikace a dat. Raw frames, cue journals a čisté
masters jsou zachovány mimo Git pro případný pozdější YouTube sestřih.
Společné finální testy a statickou browser QA provádí hlavní koordinátor po
source freeze; mediální kontroly zahrnují skutečná gesta, výsledek, délky a
úplné dekódování exportů.

## Formulář, vstupenky a telefon

Formulář byl znovu zachycen v čitelnějším skutečném viewportu1000x850 s viditelnou
editací otázky a možností. Builder poster ukazuje editaci pole; samostatný
form-style používá nový odpovídající výsledek téhož formuláře, ne historickou
odlišnou otázku. Výsledek zůstává skutečným UI, bez překládacího překryvu.

Tři galerie vstupenek jsou čisté výřezy skutečných různých presetů: Gala
(zelená/zlatá,354x810), Klub (fialová panorama,920x308) a Divadlo
(krémová/vínová,576x810). Video spojuje odlišné skutečné presety se zachovanými
nativními dragy textu a QR. Galerie neobsahuje inspector a není vytvořena
překreslením aplikace. Recept: `automation/landing_capture/admin/clarity.md`.

Skener používá skutečné mobilní UI v symbolickém iPhone. V úvodu je před
kamerou viditelná symbolická vstupenka se stejnými QR daty jako skutečný
kamerový vstup. Prop po načtení zmizí před potvrzením, aby celá skutečná
odpověď a zelený výsledek zůstaly čitelné. Nejde o tvrzení o fyzicky natočené
ruce či telefonu; kamera a potvrzení uvnitř rámu jsou reálný lokální tok.

Mediální freeze: všech18variant (9kapitol) prošlo úplným ffmpeg dekódováním,
rozměry a délky odpovídají finálnímu manifestu; důkaz
`media-validation-authentic.json`. Finální scanner prop mizí v1.8-2.2s,
před skutečným potvrzením v3.2s; závěrečný obraz byl vizuálně ověřen bez
překrytí potvrzení. Form-style3s používá stejný nový formulář jako builder.
Veškeré task-owned browsery, Flutter/Edge, editor server55907, Vite56841 a
Supabase56831 ukončené. Lokální data zachována, jiné stacky nedotčené.
Společné testy/build/static QA nebyly v této mediální větvi opakovány.
