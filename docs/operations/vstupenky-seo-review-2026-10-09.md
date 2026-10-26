# SEO a favicon vstupenky.online

Kontrola veřejného nasazení: 9. října 2026. Jde o audit, nikoli nasazenou opravu.

## Výsledek

Technický základ existuje: hlavní stránka vrací HTTP 200, povoluje indexaci, má správný canonical na HTTPS doménu, description, Open Graph a WebSite JSON-LD. Veřejný robots.txt neblokuje procházení; dynamická sitemap.xml obsahuje stránky akcí. Dvě vzorkované stránky akcí mají vlastní serverově doplněný název a canonical.

Hlavní stránka je katalog akcí. Název stránky, WebSite, H1 i manifest používají Festapp. Popis je obecný: „Platforma pro správu akcí, programu a vstupenek.“ Pro vyhledávání zaměřené na prodej vstupenek a registrace je vhodné doplnit jasný obsah vysvětlující službu a sjednotit značku podle rozhodnutí provozovatele.

## Nálezy

| Priorita | Nález | Doporučení |
| --- | --- | --- |
| Vysoká | Karty akcí jsou `div` s `onclick`; po načtení katalogu nebyl nalezen žádný `a[href]`. | Nabídnout skutečné odkazy na odpovídající veřejné stránky akcí a zachovat současné dialogové chování. |
| Střední | Deklarovaný favicon je staré „fa“ na tmavém pozadí. Stejný obsah má `/favicon.ico` i `/web-assets/favicon-D3FZdTM-.ico`; shoduje se se soubory obou klientů. PWA ikona je také „fa“. | Rozhodnout cílovou značku, sjednotit grafiku a odkazovat na stabilní veřejnou URL ikony. Aktuální ICO má obraz 48 x 48; velikost není prokázanou příčinou problému. |
| Střední | Flutter šablona deklaruje `/favicon-96x96.png` a `/favicon.svg`, ale tyto veřejné URL vracejí HTML s HTTP 200 místo obrázku. | Odstranit neplatné deklarace nebo dodat skutečné obrázky. Hlavní JS stránka na ně neodkazuje. |
| Střední | Sitemap generuje u všech položek dnešní `lastmod`, nikoli skutečný okamžik změny obsahu. | Použít doložený čas změny nebo `lastmod` vynechat. Nezaměňovat stáří termínu akce se stářím aktualizace stránky. |
| Střední | Neexistující cesta `/__seo_missing_page_20261009__` vrací HTTP 200 s Flutter HTML. | Pro skutečně neexistující veřejné stránky vracet odpovídající 404 při zachování platných SPA tras. |
| Nízká | Statický shell má `lang="en"` s českou description. Lokalizační služba po načtení nastavuje jazyk podle uživatele. | Statický jazyk odvodit od výchozího jazyka tenantu; zachovat následné přepínání. |
| Nízká | Robots.txt neuvádí URL sitemapy. | Přidat tenantem generovaný řádek `Sitemap: https://vstupenky.online/sitemap.xml`. |

Sitemap obsahuje i názvy URL s `copy`. Samotný název nedokazuje duplicitu ani to, že stránka má být skrytá; před filtrováním je nutné ověřit význam a publikaci příslušných akcí.

## Omezení

Automatické otevření Google Search skončilo kontrolou neobvyklého provozu. Kontrola byla ukončena bez obcházení CAPTCHA. Přesný favicon aktuálně zobrazený v uživatelově výsledku Googlu nebyl ověřen; doložen je favicon nabízený webem. Stav indexace, pozice a reálné Core Web Vitals nebyly zjišťovány v Search Console. Toto není kompletní obsahový nebo výkonnostní audit.

Ikonu hlavní stránky lze stáhnout a Google ji robots.txt neblokuje. Změna ikony na webu nezaručuje okamžitou změnu výsledků vyhledávání; Google uvádí nové procházení v řádu dnů až týdnů.

## Zdroje a místa opravy

- Veřejná stránka: https://vstupenky.online/
- Ikona: https://vstupenky.online/web-assets/favicon-D3FZdTM-.ico
- Sitemap: https://vstupenky.online/sitemap.xml
- `web_client/index.html`, `web/index.html`, `web_client/src/components/occasion/occasion_card.js`
- `automation/project.conf`, `automation/apply_config.sh`, `automation/cloudflare_build.sh`
- Google favicon: https://developers.google.com/search/docs/appearance/favicon-in-search
- Procházení odkazů: https://developers.google.com/search/docs/crawling-indexing/links-crawlable
- Přesnost lastmod: https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap

Případná oprava značky musí vycházet z tenantové konfigurace, aby ji další build nepřepsal. Audit neopravuje obsah jiných tenantů a neopravňuje k jejich publikaci.

## Navazující implementace

Provozovatel potvrdil, že grafika „fa“ je správná a potřebuje větší výřez. Značka této služby má být `vstupenky.online`. Opravy a výsledky místních kontrol jsou zaznamenány v [provedeném plánu](../plans/vstupenky-seo-2026-10-09.md). Původní audit výše popisuje veřejné nasazení před těmito úpravami; dosud se nezměnilo.
