# Statický náhled a ověření produktových klipů

Nástroje používají aktuální generátor a manifest. Výstupní adresář zvolte mimo Git. Žádný příkaz nespouští HTTP server, deploy, commit ani push.

```sh
python3 automation/landing_capture/review/build_preview.py --output /absolute/task-review
python3 automation/landing_capture/review/capture_review.py --preview /absolute/task-review/landing.html --output /absolute/task-review/evidence
python3 automation/landing_capture/review/build_gallery.py --output /absolute/task-review/evidence --preview /absolute/task-review/landing.html
```

`--repo` lze u generátorů explicitně změnit. Výchozí repo se odvozuje z umístění skriptu, nikoli z uživatelského home. Náhled vloží lokální Futuru a JS přehrávače, motion i referenčního carouselu; média odkazují na skutečné soubory v checkoutu. Je přenosný spolu s checkoutem a novým vygenerováním, ne jako jediný samostatně distribuovatelný HTML soubor.

Capture vyžaduje lokální agent-browser a vytváří unikátní namespace s prázdným configem a `--headed false` v každém příkazu. Před interakcemi ověří vlastní headless Chrome proces a jednu kartu. Zachytí 4 šířky, konkrétní sekce, carousel a skutečné scroll video desktop/mobil. Během nahrávání nesmí měnit emulaci, viewport nebo reloadovat stránku, protože to může zahodit záznam. Reduced-motion ověřuje samostatně skutečnou emulací a stavem při průchodu sekcemi; normální scroll video nepovažuje za důkaz reduced-motion. Svůj browser vždy zavře.

Galerie nevymýšlí stav kritérií: odkazuje na skutečné JSON výsledky a dynamicky čte klipy ze zdrojového manifestu. Jazyk samotných záběrů musí ověřit jejich capture recipe a vizuální kontrola; toto není OCR audit médií. Delší YouTube film je samostatný export z uchovaných takes, nepředstírat jeho vytvoření sestavením této galerie.

## Střídavé kreslení v úvodu

`build_hero_sketch.py` generuje dvanáct dekorativních motivů z uloženého
skutečného plánku, typů objektů editoru a vstupenkových šablon. QR motiv je nyní záměrně jednoduchý dekorativní znak se třemi rohy a několika bloky,
nikoli skenovatelný kód nebo platební údaj. Sály přebírají skutečnou geometrii
uložených šablon v fixtures. Žádná nová runtime závislost.

`motion.js` střídá dva samostatné pruhy po 4.8 sekundách. Hotový druhý motiv
zůstává při mazání i kreslení. Mobil používá dvě kompozice nad sebou a stejnou
šířku čar díky non-scaling-stroke. QA sleduje skutečnou časovou osu a ověřuje
nezměněný hotový protějšek během obou přechodů; netvoří fiktivní stavy screenshotu.
