# Zpřesnění po uživatelské kritice 14:27-14:32

Nejnovější instrukce uživatele mají přednost před předchozím pilotem:

- Úvod se inspiruje vzdušností https://ticketnow.cz/. Používá krátký centrovaný titulek, dvě akce a vlastní jemné SVG obrysy. Screenshot plánku již není hero.
- Hlavička přebírá skutečný veřejný kontrakt user_header.css: výška 80 px, pozadí #19243b, plocha značky 56 px, vytvoření akce #82bff2 a průsvitné přihlášení s 8 px blur. Landing nepřidává další navigační položky do hlavičky. Stávající vstup do vytvoření/přihlášení zůstává zachován. Tenantový wordmark zůstává vstupenky.online: současný sdílený logo asset má nápis Festapp, který na marketing této značky nepřenášíme.
- Videa mají poloprůhledné ovládání přes obraz; při viditelnosti se přehrávají opakovaně. Toto výslovně nahrazuje původní požadavek na zastavení po dokončení. Ruční pauza, jediný aktivní klip a reduced-motion zůstávají závazné.
- Referenční doprovodný odstavec je odstraněn, pozice carouselu je dostupná screenreaderu. Výrazné tlačítko všech akcí je uprostřed pod kartami.
- Produktová média používají existující šablonu sálu; editor ukazuje levou paletu a skutečná gesta bez složitého pravého inspectoru. Formulář má viditelné akce; vstupenky odlišné skutečné šablony; skenování spojuje QR vstupenku s vlastním telefonem.

## Pozorování reference

Ticketnow byl prohlédnut izolovaným headless agent-browserem; vlastní screenshoty jsou v `/tmp/festapp-hero-reference`. Referenční kompozice slouží jako inspirace jednoduchosti, žádná konkurenční média nejsou použita. Současná originální hlavička vstupenky.online byla porovnána se zdrojovým CSS a computed style (80 px výška,16 px okraje,40 px tlačítka).

Reprodukce úvodu a přehrávače: `automation/landing_capture/review/build_preview.py`. Media recipes: `automation/landing_capture/`. Finální ověření se zapisuje až po dokončení médií do nové galerie `airy-review`; předchozí evidence se nepřepisuje jako důkaz nové verze.

## Finální ověření

8 cílených testů prošlo (generátor, přehrávač, carousel, SEO); Vite build prošel. Po opravě mezery za mobilním zalomením byl generátor znovu ověřen. Finální statická QA prošla na320/390/768/1440px: bez přetékání, rozbitých obrázků a dekorativních šipek,1H1, axe0nálezů. Skutečné přehrání prokázalo native loop a trvalou ruční pauzu, při scrollu běžel nejvýše1klip. Reduced-motion skutečně emulován:0přehrávaných videí a0skrytých sekcí. Oba finální scroll záznamy dekódovány. Galerie obsahuje porovnání se zachovanými screenshoty předchozí verze.

Výstup: `/Users/miakh/Downloads/festapp-landing-review-2026-10-22/airy-review/index.html`; finální vstupní SHA a výsledky v `final-review.json`. 18mediálních exportů viz `media-validation-authentic.json`. Bez deploye, commitu a pushe. Task-owned browsery a servery ukončené.
