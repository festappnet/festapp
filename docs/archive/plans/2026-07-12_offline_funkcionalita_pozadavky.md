# Požadavky: Offline funkcionalita (CSM Ostrava 2026)

> **Stav dokumentu:** návrh požadavků k odsouhlasení. Na jeho základě vznikne
> prováděcí plán. Sepsáno 2026-07-12 na základě analýzy větve
> `prod/csmostrava2026`.

## Motivace

Na místě konání (venkovní areál, tisíce lidí) bude mobilní signál slabý nebo
přetížený. Aplikace musí být použitelná i offline — **nejen mapa, ale všechny
klíčové funkce, hlavně ty nově přidané** (přednášející & poradny, úklidová
služba, trasy, ubytování, zpětná vazba).

---

## Jak offline funguje dnes (výchozí stav)

Ať jsou požadavky reálné, tady je, co už v kódu je:

- **Úložiště:** `sembast` (NoSQL, JSON) přes `OfflineDataService`.
- **Synchronizace:** `SynchroService.refreshOfflineData()` — běží při startu,
  přepnutí akce a po přihlášení. **Je jednosměrná (jen stahování).**
  **Neexistuje fronta odchozích změn** — jediná výjimka je „můj program".
- **Offline mapa (podklad):** ✅ hotová — stahování vektorových dlaždic
  (`.mbtiles`) + styl/sprity, `offline_map_helper.dart`. Podklad mapy funguje
  offline, když je balíček stažený.
- **Detekce připojení:** `connectivity_plus`, ale využitá jen na 3 místech
  (mapa, hra). Datová vrstva většinou jede „offline-first + try/catch".

### Co už offline ČTE (✅)

Program/harmonogram, detail události, můj program, místa a značky na mapě,
detail místa, info stránky, písničky, novinky, **trasy/GPX**, vlastní ubytování
uživatele, vyhledávání (hybridně).

### Co offline NEFUNGUJE (❌) — a jde hlavně o nové funkce

| Funkce | Problém |
|---|---|
| **Přednášející & Poradny (zobrazení)** | Data se už do cache stahují (`saveSpeakers`), ale detail události i výběr poradny volají **živé RPC** a offline sekci jen skryjí. |
| **Úklid — seznam/stav záchodů** | `DbCleaning` je záměrně „online-only", nic se necachuje. Offline barvy stavů zmizí. |
| **Ubytování — katalog služeb (admin)** | `getAllServices` je jen živé RPC. |
| **Zpětná vazba — čtení** | `DbEventFeedback` je celé online-only. |

### Průřezový nedostatek: žádné offline ZÁPISY

Každý zápis dnes potřebuje síť: **hlášení úklidu, rezervace poradny, přihlášení
na program, odeslání zpětné vazby**, tip ve hře, přesun místa. Fronta
odložených zápisů v aplikaci neexistuje.

### Platformní past

Offline seznam událostí se cachuje **jen na PWA/nativní appce**
(`isPwaInstalledOrNative()`). V obyčejném prohlížeči je program offline prázdný.

---

## Požadavky

Číslované, ať se na ně dá v plánu odkazovat. U každého je uvedena náročnost
podle výchozího stavu.

### R1 — Offline mapový podklad je připravený pro areál
- Vektorový podklad areálu Ostravy je stažitelný a použitelný bez signálu.
- **Stav:** mechanismus ✅ hotový. Zbývá ověřit/nakonfigurovat správný
  `offlineMapLayer` (URL balíčku + `forceOfflineMap`) pro tuto akci a otestovat
  na místě/emulaci bez sítě. **Náročnost: nízká (konfigurace + test).**

### R2 — Offline ČTENÍ všech spotřebitelských funkcí
Účastník i úklidová četa musí offline **vidět** aktuální (naposledy
stažená) data:

- **R2.1 Přednášející & Poradny** — offline zobrazit seznam přednášejících,
  jejich detail (foto, bio), oblasti poraden a dostupné sloty (naposledy
  stažené). *Data se už cachují — stačí přepnout `loadSpeakers` a
  `counseling_picker` na fallback z cache.* **Náročnost: nízká.**
- **R2.2 Úklid — seznam a stav záchodů** — offline zobrazit seznam/mapu
  záchodů s naposledy známým barevným stavem. *Vyžaduje novou cache stavu +
  doplnit do `SynchroService`.* **Náročnost: střední.**
- **R2.3 Ubytování — JEN vlastní** — offline vidět **svoje** ubytování
  (kde bydlím). ✅ *Toto už dnes offline funguje* (přes inventory bundle).
  **Adminský přehled „kdo kde bydlí" se offline NEDĚLÁ** (rozhodnutí uživatele).
  **Náročnost: nízká (ověřit, že to sedí).**
- **R2.4 Zpětná vazba — stav** — offline vědět, zda jsem už vazbu odeslal.
  **Náročnost: nízká–střední.**
- **R2.5 Skupina — „od čí je skupina"** — běžný uživatel musí offline vidět
  **svou skupinu**: do které skupiny patří, kdo ji vede / čí je, členy.
  ✅ *Toto už dnes offline funguje.* Skupina uživatele (`eventUserGroup`) se
  cachuje uvnitř `UserInfoModel`; offline se v detailu skupinové události
  zobrazí název, popis, místo, **vedoucí/moderátor** (člen s `is_admin` = „čí
  je skupina") i seznam členů (`event_page.dart:1329–1337`).
  **Náročnost: žádná (ověřit na místě).**
  - *Drobná mezera (mimo zadání):* herní týmy / druhá skupina se necachují —
    offline prázdné. Netýká se běžného pohledu „moje skupina", neřešíme,
    dokud si to Julie nevyžádá.

### R3 — Offline ZÁPISY → ✅ ROZHODNUTO: čitelná degradace (var-D)
Chování akcí, které mění data, když není signál. Týká se: **hlášení úklidu,
rezervace poradny, přihlášení na program, odeslání zpětné vazby.**

**Zvoleno (2026-07-12): „Čitelná degradace" (R3-var-D)** — akce se offline
**nezadá**, ale UI to jasně řekne („Bez připojení nelze odeslat, zkus to prosím
u signálu") místo tiché chyby. Rychlé, bezpečné, žádné konflikty. **Fronta
odložených zápisů se NEDĚLÁ.**
- *Zamítnutá varianta (pro záznam):* „Fronta a synchronizace" — příliš velký
  nový mechanismus (konflikty slotů, pořadí, tokeny, duplicity).
- **Náročnost: nízká** (jen sjednotit chování + hlášky u zápisových akcí).

### R4 — Indikace offline stavu a stáří dat
- Viditelný indikátor „jsi offline".
- U cache dat naznačit stáří / „naposledy aktualizováno", ať uživatel ví, že
  stav (hlavně úklid) nemusí být aktuální.
- **Náročnost: nízká–střední.**

### R5 — Pokrytí platforem → ✅ ROZHODNUTO
- **Must-have: nainstalovaná PWA („na ploše") + nativní appka** (iOS/Android).
- **Obyčejný prohlížeč: ideál, ale ne nutnost** (nice-to-have). Pokud půjde
  levně přiohnout, uděláme; jinak v prohlížeči bereme online jako standard.
- Cílová skupina jsou **běžní uživatelé** — offline priorita je jejich vlastní
  pohled + **veřejné informace**, ne adminské přehledy.

### R6 — Ověření (akceptační kritéria)
- Testovací průchod v **letadlovém režimu** (nativní i PWA): projít program,
  detail události, přednášející/poradny, seznam+mapu záchodů, mapu s trasami,
  ubytování — vše se zobrazí.
- Zápisové akce se chovají podle zvolené R3 varianty (fronta vs. hláška).
- Regrese: online chování beze změny.

---

## Rozhodnutí (uzavřeno 2026-07-12)

1. **Offline zápisy → čitelná degradace (var-D).** Bez fronty. Viz R3.
2. **Platformy → PWA + nativní must-have; prohlížeč nice-to-have.** Viz R5.
3. **Offline čtení → v podstatě vše, pohledem běžného uživatele + veřejné info.**
   - Ubytování jen vlastní (ne adminský přehled). Viz R2.3.
   - **Přidán požadavek R2.5 — skupina** („od čí je skupina").

## Otevřené položky

Žádné — všechna rozhodnutí uzavřena, R2.5 (skupina) ověřeno jako již offline.

## Odhad rozsahu prací (na základě rozhodnutí)

Seřazeno od nejmenší práce:

| Požadavek | Práce |
|---|---|
| R2.5 skupina | **hotovo** — jen ověřit |
| R2.3 ubytování (vlastní) | **hotovo** — jen ověřit |
| R2.1 přednášející/poradny (čtení) | **malá** — fallback na cache (data se už stahují) |
| R3 zápisy — čitelná degradace | **malá** — sjednotit hlášky |
| R4 offline indikátor + stáří dat | **malá–střední** |
| R1 offline mapa areálu | **nízká** — konfigurace + test (mechanismus hotový) |
| R2.4 zpětná vazba (stav čtení) | **nízká–střední** — cache |
| R2.2 úklid — seznam/stav offline | **střední** — nová cache stavu + sync |
| R6 ověření (letadlový režim) | průběžně |

Tj. těžiště práce = **R2.2 (úklid offline čtení)** + drobnosti; velký rizikový
mechanismus (fronta zápisů) odpadl díky rozhodnutí R3.

Dalším krokem převedu tyto požadavky na fázovaný prováděcí plán (konkrétní
soubory, cache/RPC, testy, pořadí fází) ve stylu ostatních `docs/plans/`.
