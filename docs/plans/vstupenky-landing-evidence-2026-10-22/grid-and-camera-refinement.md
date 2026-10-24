# Revize 18:14-18:21 - velké sály, souvislá mřížka a věrné nástroje

Hero používá mimo menší68místný sál i skutečný uložený sál31stolů/182míst,
kinovou šablonu198míst a divadelní188míst. Geometrie není náhodně generovaná;
parent transformace a rám obsahující všechna sedadla zůstávají zachované.
Uložený větší sál je hero-large-hall.json (původní skutečný stock-document.cs.json
z předchozího nativního capture). Kino se dostává dříve do střídání, vedle gala
vstupenky, aby byla variabilita vidět bez čekání na celý cyklus.

U stůl má jedinou společnou mřížku10×12 s jednotkou21. Nohy i příčka jsou
obsazené buňky téže mřížky; obvod i vnitřní hrany se počítají z těchto buněk.
Společné vnitřní hrany se vykreslují jednou. Židle navazují na středy dvojic
buněk, místo starého nezávislého rozestupu. Generátor a jeho geometrické
kontroly prošly,2cílené testy generátoru PASS.

Navazující revize18:30-18:35: přímé oslovení používá velké V. Schůzka jasně
nabízí30min ukázku a možnost rovnou nastavit vstupenky pro konkrétní akci.
Správa objednávek uvádí připomínky, změny/storna, evidenci hotovosti,
náhradníky a export. Galerie má8šablon bez nejvýraznějšího festivalového
plakátu; dvě odůvodněně seskládané řady respektují skutečné poměry stran a
neřežou obsah ani QR. Závěr doplňuje vektorový půdorys skutečného68místného
sálu. Podpis Festapp je uprostřed patičky a zůstává odkazem.

Po celé koherentní změně znovu proběhl cílený Node batch:2PASS. Média,
source fixy a cílené finální ověření budou doplněné po zmrazení. Tato revize
neprovádí další hledání fontu. Žádný deploy, commit nebo push.


Finální média jsou build → refine → grid; žádná přehlídka šablon na konci.
Grid závěr36,63s skutečně smaže dokument, vytvoří stůl, prodlouží/zkrátí jej,
použije dřevěný preset a vloží samostatný podkladový obdélník dozadu.
Picker má tři nativní ikony bez textu. Scanner má čtvercový obraz, nativní
rohové zaměřovací značky a indikátor Živý obraz. Owner:7cílených testů a
nové MP4 decodePASS. Root porovnal30aktuálních souborů s grid-final-proof.json.

Finální browser review320/390/768/1440PASS: bez overflow/brokenimages/toolbarů,
nejvýše jedno běžící video,8vstupenek se zarovnanou výškou v každé řadě,
podpis uprostřed layoutviewportu, editor pod581px a větší skutečné sály.
Jedna cílená oprava: původní zděděné tři sloupce galerie byly resetované na
celou šířku; centerassert používá šířku bez scrollbarů. Původní receipt je
zachovaný. Nativní timeline hero kroků1/3/6 byla natočená a WebM dekódovaný.
Evidence: Downloads/festapp-landing-review-2026-10-22/grid-review/final-review.json.

Materiální limit videa: skutečný workspacePNG235,241,246 odpovídá stránce;
JPEG/YUV420 komprese v browseru posune pixel na236,240,248. Native dokument
má fill#00000000. Nejde o starý theme ani neprůhledný dokument. Bez nasazení.
