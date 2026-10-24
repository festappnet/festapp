# Revize 17:39-17:57 - čisté ukázky bez ovládacích lišt

Tato revize nahrazuje starší kontrakt viditelného přehrávače. V samotné stránce
nejsou názvy klipů, délky, tlačítka Pozastavit ani záložky variant. Transparentní
button přes video ponechává kliknutí/tap a klávesnici Enter/Space pro pauzu a
přehrání; přístupný název popisuje aktuální akci. Více klipů jedné sekce se
přehrává v pořadí manifestu a automaticky opakuje celou sekvenci. Jediný klip má
nativní loop. Ruční pauza přežívá scroll, autoplay je omezený na jedno viditelné
video, reduced-motion a save-data čekají na výslovný klik. Fallback při chybě
zůstává dostupný. Patička nyní nese skutečný vektorový podpis Festapp s odkazem;
podpis z hlavičky a malý text o odbavení telefonem z hero jsou odstraněné.

Kreslení sálů přebírá skutečné uložené objekty a rekurzivní parent transformace:
Moderní ples z vivid-document.cs.json, autorský plánek a skutečné kino/divadlo
z brand-cinema.cs.json a brand-theatre.cs.json. Jednotné měřítko zachovává poměry
geometrie. Ohradní rám obsahuje úplné footprinty všech sedadel, ověřené generátorem.
Kreslení postupuje po skupinách stolů a po skutečných označených řadách místo
náhodného pořadí UUID. Původní procedurální obloukové rozložení bylo odstraněno.
QR v hero je nově záměrně jednoduchá dekorativní značka se třemi rohy a několika
bloky. Není to skenovatelný kód, platební QR ani úprava funkčních kódů vstupenek.

Nativní média viz stage-refinement-final.md a stage-refinement-proof.json: kreslení pódia/obrysu, build17/142, refine s odstraněním3stolů a kulatým stolem8židlí, oblouk -9/+9. Picker má skutečné svislé webové ovládání (3 cílené viewport testy PASS), gala má symbol i QR uvnitř rámu, formulář je oříznutý bez nativní ukládací lišty. Galerie odlišuje Kino a Moderní ples68. Všechny zmrzlé hashy ověřené.

11 cílených Node testů a Vitebuild PASS; skutečná QA320/390/768/1440px ověřila automatickou sekvenci, nativní loop jediného klipu, pauzu kliknutím, nepřetékání a nulové viditelné toolbar/tab prvky. Po přesunu podpisu byla opravena světlá zděděná barva na navy. Cílená finální kontrola footer390/1440 a axe v pravém reduced-motion stavu (všechny reveal sekce viditelné) PASS0violations. První footer-only probe s pending offscreen reveal animacemi byl falešně pozitivní kontrastní audit, uchovaný pro průhlednost. Plné scroll záznamy jsou před poslední opravou barvy podpisu; finální footer screenshoty/HTML ji obsahují. Tři nové review záznamy dekódované. Galerie quiet-review/index.html a final-review.json.

 Font původního
loga se zkoumá porovnáním skutečných křivek; název Mateo nebyl potvrzen, první
commit loga má už pouze SVG paths. Žádné produkční změny, deploy, commit či push.
