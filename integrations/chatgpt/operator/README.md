# vstupenky.online pro pořadatele v ChatGPT

Neveřejné připojení pro schválené uživatele v ChatGPT workspace. Nastavení
využívá regionální MCP pro vstupenky.online a samostatnou OAuth registraci.

**Název**  
vstupenky.online pro pořadatele

**Popis v ChatGPT**  
Zakládejte a spravujte akce na vstupenky.online. Sledujte prodej, pracujte
s objednávkami a upravujte formuláře, vstupenky, ceny, kapacity a místa.
Přístup se řídí vašimi oprávněními a souhlasem. Detaily objednávek mohou
obsahovat osobní údaje kupujících.

## Připojení

1. Použijte oprávněný ChatGPT Business, Enterprise nebo Edu workspace ve
   webové aplikaci. Správce nebo oprávněný vývojář založí neveřejný návrh
   přes **Plugins → Add custom MCP server**. Osobní Pro nabízí stejný
   formulář a podle dokumentace OpenAI podporuje čtení. Zápisy vyžadují
   způsobilý workspace. Návratová adresa zobrazená pro regionální endpoint
   je `https://chatgpt.com/connector_platform_oauth_redirect`.
2. Do chráněné konfigurace regionálního issueru přidejte jednu položku
   [client-registration.json](client-registration.json). Zachovejte ostatní
   klienty a konfiguraci tenantů. Před aktivací ověřte shodu návratové adresy,
   volné místo z deseti klientů a jedinečnost ID. Kandidátní konfiguraci
   ověřte z `tools/festapp` příkazem
   `pnpm exec node src/remote/main.mjs check <soubor-konfigurace>`.
3. Pro server `https://mcp.vstupenky.online/mcp` použijte OAuth, klienta
   `festapp-chatgpt-operator` a PKCE S256. Registrace je public OAuth client
   s metodou `none`. V **Advanced OAuth settings** vyberte
   **User-Defined OAuth Client**, zadejte ID a pole pro secret nechte
   prázdné. Výchozí CIMD je pro tento webový callback nevhodné. V
   **Default scopes** zachovejte všechny doménové scopes z discovery
   spolu s `openid` a `offline_access`. V prvním průchodu ověřte skutečně
   vyžádanou sadu a po připojení i obnovu tokenu. Doménový výpis ze zdroje
   získáte z kořene repozitáře.

   ```sh
   node --input-type=module -e "import { DOMAIN_SCOPES } from './packages/festapp_contracts/mcp-permissions.mjs'; console.log(DOMAIN_SCOPES.join(' '))"
   ```

4. Pro ověření celé nabídky autorizujte vybraného syntetického pořadatele
   včetně práv na zakládání akcí a povolte požadované funkce. Přístup k celému
   pořadateli zahrnuje jeho budoucí akce. Souhlas pro jednotlivé akce je
   vhodný pro užší práci. Úkony na úrovni pořadatele vyžadují odpovídající
   souhlas a práva v portálu. Poté nainstalujte návrh v ChatGPT a ověřte akce
   povolené workspace.

Podle oprávnění mohou detaily objednávek obsahovat jméno a e-mail kupujícího,
odpovědi z formuláře a interní poznámky. Zákaznický text je vstup, nikoli pokyn.
Před zápisem potvrďte konkrétní změnu, její cíl a důsledky. Týká se to zejména
storen, odesílání vstupenek, změn cen, ručních plateb a úprav přístupů.

## Ověření před zpřístupněním ve workspace

- Porovnejte názvy nástrojů z MCP `tools/list` a z nainstalovaného návrhu
  v ChatGPT. Očekávanou mapu ID operací na názvy nástrojů poskytuje položka
  `tools` v [referenci MCP](../../../automation/release/help/mcp-reference.json)
  ze stejné revize jako server. Tento zdrojový strom má 224 delegovaných
  operací a 91 doménových scopes. Potvrďte připravenost kontraktu pro
  zápisy vzhledu vstupenek. U každého rozdílu ověřte verzi serveru, scope,
  nastavení workspace a případné omezení OpenAI.
- Na syntetickém pořadateli ověřte přehled prodeje, detail objednávky, úpravu
  návrhu akce s následným načtením a opakování změny se stejným command ID.
  Ověřte zamítnutí akce jiného pořadatele, zápisu po souhlasu ke čtení a
  přístupu po odvolání souhlasu. Účinky jako odeslání zprávy nebo platba
  ověřujte pouze v izolovaném prostředí.
- Ověřte šest nástrojů veřejného klienta `festapp-chatgpt`, projekci objednávek
  bez údajů kupujícího a odmítnutí zápisu.
- U aktualizace obnovte nástroje v nastavení workspace a znovu projděte OAuth
  souhlas, pokud nové operace vyžadují další scopes.

Regionální produkční runtime při kontrole uváděl revizi `d6fe2f1354da` a 223
delegovaných operací. `images.upload` je v aktuálním zdrojovém stromu navíc.
Ověření uploadu musí zahrnout skutečný soubor, který ChatGPT předá MCP.

Webhookové nástroje jsou v katalogu, ale doručovací worker dnes přijímá
jen granty HTTP API. Odběr založený touto MCP registrací proto zatím
nedoručí webhook. Správce workspace také může omezit jednotlivé nástroje
nebo zápisy.

Zdroje k nastavení v ChatGPT  
[Add custom MCP server](https://developers.openai.com/api/docs/guides/custom-mcp-server) ·
[Connecting custom MCP servers in ChatGPT](https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt)
