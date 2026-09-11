# Execution prompt: Offline funkcionalita

Implementuj plán `docs/archive/plans/2026-07-12_offline_funkcionalita_plan.md`.
Cíl: klíčové funkce appky použitelné bez signálu — **čistě klientská práce,
žádné SQL změny, žádný zásah do live DB**:

1. Základ: `ConnectivityService` (notifier + one-shot check) + `OfflineStrings`
   + `ExceptionHandler.isNetworkError`.
2. **R2.1** Přednášející & poradny čtou z existující speakers cache
   (`event_page.loadSpeakers` fallback, `counseling_picker` seed); sloty
   poraden zůstávají live-only.
3. **R2.2** Úklid offline: `toJson()` na `CleaningPlaceStatus`, cache pár
   v `OfflineDataService`, feature-gatovaný krok v `SynchroService`
   (vlastní try/catch!), fallback na stránce úklidu + barvy pinů na mapě.
   Cachovat jen veřejné stavy + `fetchedAt` — ne per-user flagy, ne reporty.
4. **R2.4** Feedback: cache „už jsem odeslal" per event (patří do
   `clearUserData`), oprava lživého offline stavu widgetu.
5. **R3 čitelná degradace** (fronta se NEDĚLÁ): jednotná offline hláška u
   4 zápisů — sign-in/out řeš uvnitř `DbEvents` (pokryje 5 call-sites vč.
   poraden), úklid v `cleaning_report_flow`, feedback v `_errorMessage`+`_remove`.
6. **R4** `lastSyncedAt` na konci syncu + `OfflineBanner` v
   `occasion_home_page` (body → Column).
7. **R5** odgatovat cache událostí (`synchro_service.dart:74`) — pozor na
   latentní `occasionId!` pád.
8. i18n: 5 klíčů `Offline.*` (cs+en + byte-identická kopie do
   `web_client/public/assets/translations/`).

**R1 (offline mapový podklad) se NEŘEŠÍ** — je vědomě mimo tento plán.

Nejdřív si přečti: `docs/architecture/ai_context.md`, **celý plán** a
`docs/architecture/SERVICES.md` (OfflineDataService/SynchroService).

Závazné:
- Postupuj po fázích 1→9 přesně podle plánu; rozhodnutí ✅ jsou daná, neptej se.
- Nic „navíc nevylepšuj" — sekce „Mimo rozsah" v plánu je zákaz, ne nápad.
- Prerekvizity z hlavičky plánu: před začátkem ověř `git status` — na větvi
  může být rozpracovaná cizí práce, commituj **jen své soubory**; čísla řádků
  v plánu platí pro stav před plánem `mista_uklid_architektura` (pokud už
  běžel, dohledej místa grepem podle názvů funkcí).
- Offline chování testuj reálně: web přes DevTools „Offline" throttling,
  ověř skutečný typ síťové výjimky supabase klienta, než napíšeš
  `isNetworkError`.
- Testy: `./automation/test_all.sh` bez nových failur (2 baseline DB failury
  známé), `fvm flutter analyze` čisté. Žádné nové DB testy (nejsou SQL změny).
- Vždy `fvm`; běh přes `fvm flutter run -d web-server --web-port 8080`
  (nikdy `-d chrome`).
- Po fázích 1-8 **zastav a nech uživatele zkontrolovat localhost:8080**
  (akceptační checklist = plán fáze 9 bod 3: letadlový průchod program /
  přednášející+poradny / úklid+mapa / ubytování / skupina, 4 zápisy s offline
  hláškou, banner; online regrese). Nasazení (fáze 9 bod 4 — VERSION bump,
  `deploy_direct.sh`, žádný `git push`, anglická commit message) proveď až
  po jeho odsouhlasení.
