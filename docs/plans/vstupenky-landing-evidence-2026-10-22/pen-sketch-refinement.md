# Rychle kreslený půdorys, střídání motivů a oprava telefonu

Nové zadání16:48: viditelně vedená rychlá čára, plné vybarvení, smazání a další motiv; skutečné sály, kruhové židle, oprava obřího telefonu a bílých artefaktů scanneru.

`automation/release/organizers/hero-plan.json` je uložený skutečný read-only dokument posledního nativně sestaveného sálu:18stolů včetně většího kruhového a112židlí. Reprodukční `automation/landing_capture/review/build_hero_sketch.py` z něj generuje zjednodušený dekorativní půdorys: skutečné polohy stolů/židlí, židle záměrně vykreslené kruhovými obrysy. Pravá část je zvětšený dekorativní detail kulatého stolu. Další motivy jsou symbolická vstupenka/QR a skeleton formuláře, nikoli tvrzení o skutečně provozovaném checkoutu.

`motion.js` vede drobný hrot po skutečných SVG cestách podle jejich délky. Jeden motiv:2.8s kreslení,0.5s plné vyplnění,1.6s držení,0.7s zpětné smazání,0.4s pauza. Střídají se tři motivy. Při reduced-motion zůstává první vybarvený půdorys statický. Žádná nová runtime knihovna; původní inspirační referenceVivus viz předchozí evidence.

Telefon v sekci výběru míst má max330px šířky i na desktopu, vlastnívideo přirozený poměr stran a výšku nejvýše700px. Předtím desktop roztažení portrait MP4 na plnou šířku vedlo k extrémní výšce. Video/data se kvůli této opravě nemění.

Scanner symboly byly znovu vykreslené přímo na navy v původním HTML, nikoli přebarvením světlého antialiasingu. Hladké SVG circle/check/cross a skutečnáFutura. Zdrojový skutečný accept/rejectfeed zůstal zachovaný; viz `scanner-svg-proof.json`. Čtyři výstupy dekódované, rozměry a délky zachované.

Hlavní titulek zůstává uživatelem zvolený „Vstupenky pro Vaši akci.“. Hlavní vysvětlení nově obsahuje důležitou výhodu: „Vlastní plánek. QR platby bez transakčních poplatků.“; odbavení telefonem je pod tlačítky. Bez deploye, commitu a pushe.

## Finální ověření

8cílených Node testů a Vitebuild prošly. Po opravě světových souřadnic židlí (parent transform) znovu prošel generátor a skutečná statickáQA na320/390/768/1440px. Axe0nálezů, žádné přetékání,3skutečně pozorované motivy ve native timeline včetněholdfill a přechodů. Telefon na desktopu nepřekračuje330px a760pxvýšku. Ručnípauza/loop/reducedmotion PASS. Nahraný18s skutečnýcyklus hero-motion.webm a oba scrollzáznamy plně dekódované. Po scannerfix byly také manifestem používanéWebP postery znovu vyexportovány z nových čistýchJPG a vizuálněprohlédnuty, aby neobsahovaly staré artefakty. Finální SHA/receipt v sketch-review/final-review.json. Vlastníbrowsery zavřené, bezdeploye/commitu/pushe.
