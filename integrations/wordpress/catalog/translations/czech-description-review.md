# Český popis doplňku vstupenky.online

Český překlad po nezávislé AI kritice a opravách. Stav odeslání a schválení zaznamenává publikační receipt. Nejde o lidskou jazykovou revizi.

## Krátký popis

Vložte prodejní formulář vstupenky.online do svého webu pomocí bloku nebo shortcode (zkráceného zápisu). Akce a objednávky spravujete ve službě.

## Popis

Doplněk propojí Váš web s českou službou vstupenky.online. Potřebujete účet pořadatele a uložený, zveřejněný formulář v této službě. Doplněk přidává jeden blok pro editor Gutenberg, jeden shortcode a průvodce nastavením v nabídce Nastavení &gt; vstupenky.online. WooCommerce ani API klíče nejsou potřeba. Doplněk je zdarma. Externí služba má vlastní ceny pro pořadatele a podmínky. Aktuální nabídku najdete na https://vstupenky.online/. Poplatky za službu se neplatí přes WordPress.

Ve vstupenky.online vytvořte a uložte formulář. Zkopírujte jeho veřejnou adresu, vložte blok vstupenky.online a adresu do něj zadejte. Stránku zveřejněte. Používejte pouze https://vstupenky.online/form/saved-slug bez parametrů a fragmentů. Editor zobrazuje nastavení bloku, nikoli vzdálenou administraci.

Shortcode:
[vstupenky_online url="https://vstupenky.online/form/saved-slug" title="Vstupenky na naši akci"]

Pevná výška:
[vstupenky_online url="https://vstupenky.online/form/saved-slug" mode="fixed" height="800"]

Zachování vzhledu formuláře pro toto vložení:
[vstupenky_online url="https://vstupenky.online/form/saved-slug" inherit_style="false"]

U každého bloku můžete zapnout Přizpůsobit vzhled webu. Pro zachování vzhledu formuláře nastavte v jeho shortcode inherit_style="false". Po změně stránku uložte a zveřejněte. Sdílený pomocný skript /embed.js se načítá v obou režimech výšky. Vlastní písma musí umožňovat načítání z jiné domény. Plánek sálu si zachovává vlastní vzhled.

Pevnou a výchozí výšku lze nastavit od 240 do 4000 pixelů. V automatickém režimu se výška přizpůsobuje obsahu. Automatický režim využívá stávající pomocný skript služby. Samostatný odkaz na formulář je dostupný i bez tohoto skriptu. Na jedné stránce může být více formulářů. Nastavení akcí, dostupnost vstupenek, zpracování objednávek, platby, doručení vstupenek a odbavení zajišťuje vstupenky.online. Doplněk neimplementuje platební bránu. Platební metody ve vloženém formuláři a kompatibilitu prohlížečů je nutné ověřit pro konkrétní akci. Fungování karetních bran a přechodů do bankovních aplikací není zaručeno.

### Externí služba a ochrana soukromí

Na zveřejněné stránce s nastaveným formulářem se prohlížeč návštěvníka připojí k https://vstupenky.online a načte /form/ulozeny-odkaz?embed=1. V obou režimech výšky se také jednou pro každou stránku načte https://vstupenky.online/embed.js. Při připojení služba obdrží IP adresu návštěvníka, informace o prohlížeči a případnou adresu odkazující stránky povolenou pravidly webu. Údaje k nákupu zadává návštěvník přímo do vloženého rámce služby. Pomocný skript si s formulářem vyměňuje údaje o velikosti, viditelné oblasti a posunu stránky, volitelná omezená nastavení vzhledu a písem a zobrazované počty a ceny vstupenek. Kontaktní údaje zákazníků, identifikátory objednávek, platební pokyny, přihlašovací tajemství ani odeslané objednávky se WordPressu nepředávají.

Služba může využívat svůj backend, soubory, úložiště a poskytovatele plateb. Před zveřejněním se seznamte s jejími informacemi o soukromí a potřebami svého webu. Doplněk netvrdí, že služba nepoužívá soubory cookie. Doplněk pro WordPress nepřidává analytiku ani sledovací pixely. Externí služba má vlastní pravidla ochrany soukromí popsaná ve svých zásadách. Volitelné přizpůsobení vzhledu načítá adresy písem webu do vloženého rámce služby. Aktivace, nápověda doplňku ani úpravy v editoru vzdálený formulář nenačítají. WordPress ukládá veřejnou adresu a nastavení zobrazení, nikoli objednávky zákazníků, hesla pořadatelů nebo API klíče služby. Doplněk neprovádí HTTP požadavky ze serveru.

Služba: https://vstupenky.online/
Podmínky: https://vstupenky.online/terms/
Ochrana soukromí: https://vstupenky.online/privacy/
Volby soukromí: https://vstupenky.online/privacy/choices/
Podpora: https://vstupenky.online/support/
Kontakt: info@festapp.net

### Zdrojový kód

Všechny zdrojové soubory PHP, JavaScriptu a CSS jsou součástí doplňku v neminifikované podobě. JavaScript využívá editorové závislosti poskytované WordPressem. Není potřeba kompilace ani přibalený React. Zdrojový kód a protokol externího /embed.js spravuje služba nezávisle na tomto doplňku.

## Instalace

1. V nabídce Pluginy &gt; Instalace pluginů &gt; Nahrát plugin nahrajte vstupenky-online-1.0.4.zip a doplněk aktivujte.

2. V seznamu doplňků klikněte na Začít nebo otevřete Nastavení &gt; vstupenky.online. Přečtěte si tři kroky nastavení a informace o službě a ochraně soukromí.

3. Uložte formulář ve svém účtu pořadatele, zkopírujte jeho veřejnou adresu, vložte blok nebo shortcode a stránku zveřejněte.

4. Zkontrolujte zveřejněnou stránku, včetně mobilního zobrazení a samostatného odkazu na formulář.

## Časté dotazy

### Mohu spravovat objednávky ve WordPressu?

Ne. Akce a objednávky spravujete po přihlášení do vstupenky.online.

### Potřebuje návštěvník účet ve WordPressu?

Ne. Veřejný formulář se zobrazuje ve vloženém rámci služby. Případné požadavky konkrétní akce určuje služba.

### Proč byla moje adresa odmítnuta?

Použijte přesnou veřejnou adresu uloženého formuláře na https://vstupenky.online. Jiné domény, osobní odkazy, fragmenty, parametry adresy a adresy administrace nejsou povolené. Vývojové adresy vyžadují výslovné místní nastavení WordPressu a nelze je zadat do atributů bloku.

### Co když bezpečnostní pravidla mého webu blokují vložení formuláře?

Povolte https://vstupenky.online v direktivě frame-src a pro pomocný skript také v script-src. Nepřidávejte neověřené omezení iframe sandbox. Podle potřeby použijte pevnou výšku nebo samostatný odkaz. Pokud výsledek nákupu není jistý, nákup automaticky neopakujte. Nejprve se obraťte na pořadatele.

### Co se stane po deaktivaci nebo odstranění doplňku?

Doplněk nevytváří vlastní databázové tabulky ani globální nastavení a nezakládá vzdálené objednávky. Při aktivaci, deaktivaci ani odinstalaci neprovádí zápisy do služby. Objednávky ve službě zůstávají zachované. Po deaktivaci se může na stránce zobrazit nezpracovaný shortcode. Blok nebo shortcode odstraňte nebo nahraďte běžným veřejným odkazem.

## Popisky screenshotů

1. Průvodce nastavením a informace o službě.

2. Nastavení bloku Gutenberg bez vzdálené administrace.

3. Zveřejněný formulář se samostatným záložním odkazem.

4. Dva formuláře na stránce v mobilním zobrazení (Chrome, nikoli Safari).

5. Výběr míst ve vloženém formuláři.

## Přehled změn

### 1.0.4

Nastavení vzhledu pro jednotlivé bloky a shortcode prostřednictvím sdíleného rozhraní pro vkládání formulářů.

### 1.0.3

Sjednocení údaje o nejnižší podporované hlavní verzi WordPressu.

### 1.0.2

Odkaz na nabídku služby vede přímo na její kanonickou domovskou stránku.

### 1.0.1

Upřesnění, že nastavení vzhledu ve WordPressu místně přepisuje nastavení vzhledu z aplikace.
