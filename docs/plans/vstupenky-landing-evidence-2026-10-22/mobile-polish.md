# Revize 17:03-17:13 - mobilní kreslení a jednoduché ukázky

Lokální práce bez nasazení, commitu a pushe. Zachované frameless video a shodné světlé/tmavé pozadí stránky i kompozice.

Úvod: „Vstupenky pro Vaši akci.“ a „Vlastní plánek. Vlastní vstupenka. QR platby bez poplatků.“ CTA „Založit akci“. Rozlišení ceny služby a nulového transakčního poplatku zůstává u plateb. Závěr a FAQ zobecněné z plesu na akci.

Mobil má vlastní portrétní SVG viewBox a kreslí jen viditelné levé motivy. Nejde o oříznuté desktopové kraje: stejný skutečný půdorys, kruhové židle, vstupenka a skeleton formuláře se vykreslí rychlou čárou a plnou výplní. Silnější 1.45 desktop / 1.65 mobil stroke. Reduced motion zůstává statický.

Desktop editor má šířku nejvýše 820px, dále omezenou výškou viewportu, video nejvýše 580px. Mobilní plánek výběru míst nadále nejvýše 330px. Festapp podpis používá skutečné původní SVG křivky loga; textový wordmark sdílí bundlovanou rodinu Futura s aplikací. Původní SVG neobsahuje název rodiny písma, takže nepovažujeme vizuální odhad za identifikaci fontu. Odkazy na festapp.net a plesy.vstupenky.online byly ověřeny čtením veřejných cílových stránek.

Média: souvislý nativní drag místo split-crop mezery; builder s Večeře/Kuřecí/Vegetariánské a povinným souhlasem bez veřejného vyplňování; skutečný 90krokový pinch a šest jednotlivých míst 2A-2F za 3 900 Kč bez objednávky; minimalistická redakční kompozice skutečného camera feedu a doložených ano/ne výsledků, nikoli redesign aplikace. Viz continuous-journeys-final.md a continuous-journeys-freeze.json. Builder má vnější matte #ebf1f6, nativní UI je zachované.

Finální kontroly PASS: 8 cílených Node testů, po jedné opravě mezer podpisu znovu generátor a Vite build, izolovaná statická QA na 320/390/768/1440px. Žádné přetékání, axe 0, nejvýše jedno hrající video, reduced-motion bez autoplay. Desktop editor 819.45 x 579.61px při 1440 x 1000, mobilní SVG zobrazuje 133 cest v portrétní kompozici. Mobilní 18s kreslení a oba scroll záznamy dekódované; mediální freeze SHA ověřené. Aktuální galerie polish-final/index.html a final-review.json. Všechny vlastní capture browsery/procesy zavřené.
