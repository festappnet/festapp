# Font původního loga Festapp - zatím nepotvrzen

V assets/icons/fstapplogo.svg, dark variantě i v prvním dohledaném commitu
6783098d0 je text již převedený na SVG křivky. Soubor neobsahuje font-family,
font ID ani původní textový objekt. Současná Futura je font aplikace, nikoli
prokázaný font těchto křivek.

Porovnání se provádělo na skutečných obrysech glyphů, zejména charakteristickém
zakončení f a p. Zkoumané fonty Futura, Ubuntu, Marmelad, Magra, Mako, Amaranth,
Merienda, Maven Pro, Acme, Cantora One, Sansita, Exo2, Overlock, Fresca, Mogra,
Laila, Diavlo, Fontin a Delicious neposkytly shodu. Nezávislé porovnání Aller
z aktuálního origin WOFF2 DaltonMaag a Fontin Sans Regular/Bold z origin ZIP
exljbris také neprokázalo shodu. To nevylučuje starší verzi, upravené logo nebo
jinou dosud nezjištěnou rodinu. Nepoužívat žádného kandidáta jako údajně přesný.

Primární zdroje: https://www.daltonmaag.com/font-library/aller.html,
https://www.exljbris.com/fontinsans.html, https://www.exljbris.com/diavlo.html,
https://github.com/google/fonts. Linotype Mateo je podle vlastní foundry lomený
linkový font, takže není potvrzením názvu pro toto logo:
https://www.myfonts.com/collections/mateo-font-linotype/.

Pracovní skutečné outline srovnání /tmp/festapp-font-research/compare.png a SVG
se nachází mimo repo. Žádný z těchto zkušebních fontů nebyl přidaný do stránky,
nová fontová licence koupena nebyla. Hlavička ponechává Futura wordmark; v patičce
je skutečné původní vektorové logo Festapp s odkazem na festapp.net.
